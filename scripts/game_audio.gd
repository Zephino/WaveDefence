extends Node

## Original retro mixed-console loops (audio/music/*.wav) plus synthesized SFX.
## Loops are prebuilt so startup does not synthesize music.

const _PA := preload("res://scripts/procedural_audio.gd")
const _PM := preload("res://scripts/procedural_music.gd")

enum MusicContext { NONE, MENU, GAME_STANDARD, GAME_SIEGE }

const LOOP_PATHS_DESKTOP := {
	"menu": "res://audio/music/original_loop_01.wav",
	"calm": "res://audio/music/original_loop_02.wav",
	"intense": "res://audio/music/original_loop_03.wav",
	"siege_calm": "res://audio/music/original_loop_04.wav",
	"siege_intense": "res://audio/music/original_loop_05.wav",
}

## Lighter mono 22.05 kHz beds for browsers (autoplay + download size).
const LOOP_PATHS_WEB := {
	"menu": "res://audio/music/web_loop_01.wav",
	"calm": "res://audio/music/web_loop_02.wav",
	"intense": "res://audio/music/web_loop_03.wav",
	"siege_calm": "res://audio/music/web_loop_04.wav",
	"siege_intense": "res://audio/music/web_loop_05.wav",
}

## Raw RIFF copies (.bin) skip Godot's WAV importer, which often packs IMA-ADPCM that HTML5 cannot play.
const LOOP_PATHS_WEB_RAW := {
	"menu": "res://audio/music/web_pcm/web_loop_01.bin",
	"calm": "res://audio/music/web_pcm/web_loop_02.bin",
	"intense": "res://audio/music/web_pcm/web_loop_03.bin",
	"siege_calm": "res://audio/music/web_pcm/web_loop_04.bin",
	"siege_intense": "res://audio/music/web_pcm/web_loop_05.bin",
}

const PROCEDURAL_RECIPES := {
	"menu": "menu",
	"calm": "game_calm",
	"intense": "game_intense",
	"siege_calm": "siege_calm",
	"siege_intense": "siege_intense",
}

var _unlocked: bool = false
## Web only: true after a real click/tap/key. Menu _ready must not count as a gesture.
var _web_gesture: bool = false
var _web_retry_token: int = 0
var _web_unlock_cb: JavaScriptObject
var _context: MusicContext = MusicContext.NONE
var _music_players: Array[AudioStreamPlayer] = []
var _sfx_player: AudioStreamPlayer
var _kill_sfx_cooldown: float = 0.0

var _loops: Dictionary = {}
var _sfx: Dictionary = {}
var _pending_play: bool = false

var _tension_smooth: float = 0.0
var _tension_timer: float = 0.0
var _boss_floor: float = 0.0
var _paused_duck: bool = false
var _enemies_node: Node2D = null
var _current_wave: int = 0
var _wave_is_boss: bool = false
var _playback_token: int = 0

const TENSION_INTERVAL := 0.05
const TENSION_LERP := 8.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_buses()
	_build_sfx_only()
	_sfx_player = AudioStreamPlayer.new()
	_sfx_player.bus = "SFX"
	add_child(_sfx_player)
	for i in 4:
		var p := AudioStreamPlayer.new()
		p.bus = "Music"
		add_child(p)
		_music_players.append(p)
	UserSettings.ensure_loaded()
	_apply_volumes()
	_load_music_loops()
	set_process_input(OS.has_feature("web"))
	if OS.has_feature("web"):
		_bind_web_unlock_callback()


func _setup_buses() -> void:
	_ensure_named_bus("Music")
	_ensure_named_bus("SFX")


func _ensure_named_bus(bus_name: String) -> void:
	if AudioServer.get_bus_index(bus_name) >= 0:
		return
	var idx := AudioServer.bus_count
	AudioServer.add_bus(idx)
	AudioServer.set_bus_name(idx, bus_name)
	AudioServer.set_bus_send(idx, "Master")


func _build_sfx_only() -> void:
	_sfx["ui"] = _PA.make_ui_blip()
	_sfx["place"] = _PA.make_place_thud()
	_sfx["sell"] = _PA.make_sell_drop()
	_sfx["wave"] = _PA.make_wave_stinger()
	_sfx["boss"] = _PA.make_boss_stinger()
	_sfx["leak"] = _PA.make_leak_sfx()
	_sfx["kill"] = _PA.make_kill_tick()
	_sfx["game_over"] = _PA.make_game_over_sting()
	_sfx["unlock"] = _PA.make_unlock_fanfare()


func _loop_paths() -> Dictionary:
	return LOOP_PATHS_WEB if OS.has_feature("web") else LOOP_PATHS_DESKTOP


func _load_music_loops() -> void:
	# Web plays the same beds through HTMLAudio (Godot's web mixer stays silent).
	if OS.has_feature("web"):
		return
	var paths := _loop_paths()
	for key in paths:
		var stream: AudioStreamWAV = null
		if OS.has_feature("web") and LOOP_PATHS_WEB_RAW.has(key):
			stream = _open_loop_from_file(String(LOOP_PATHS_WEB_RAW[key]))
		if stream == null:
			stream = _open_loop_bytes(String(paths[key]))
		if stream == null and OS.has_feature("web") and LOOP_PATHS_DESKTOP.has(key):
			stream = _open_loop_bytes(String(LOOP_PATHS_DESKTOP[key]))
		if stream == null and OS.has_feature("web") and PROCEDURAL_RECIPES.has(key):
			stream = _PM.make_track(String(PROCEDURAL_RECIPES[key]))
			if stream != null:
				_arm_loop(stream)
		if stream != null:
			_loops[key] = stream
		else:
			push_error("Failed to load music loop: %s" % String(paths[key]))


func _arm_loop(stream: AudioStreamWAV) -> void:
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	var frames := int(round(stream.get_length() * float(stream.mix_rate)))
	if frames <= 1:
		var frame_bytes := 4 if stream.stereo else 2
		if stream.format == AudioStreamWAV.FORMAT_8_BITS:
			frame_bytes = 2 if stream.stereo else 1
		frames = stream.data.size() / maxi(frame_bytes, 1)
	stream.loop_end = maxi(frames - 1, 1)


func _open_loop_bytes(path: String) -> AudioStreamWAV:
	# On web, prefer the imported sample (reliable in .pck). Desktop can use raw RIFF bytes.
	if OS.has_feature("web"):
		var web_stream := _open_loop_from_resource(path)
		if web_stream != null:
			return web_stream
		return _open_loop_from_file(path)
	var from_file := _open_loop_from_file(path)
	if from_file != null:
		return from_file
	return _open_loop_from_resource(path)


func _open_loop_from_resource(path: String) -> AudioStreamWAV:
	if not ResourceLoader.exists(path):
		return null
	var loaded: Variant = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REUSE)
	if loaded is AudioStreamWAV:
		var imported := loaded as AudioStreamWAV
		# duplicate() can drop sample bytes on HTML5; use the imported resource as-is.
		if imported.data.size() <= 0:
			return null
		if OS.has_feature("web") and imported.format != AudioStreamWAV.FORMAT_16_BITS and imported.format != AudioStreamWAV.FORMAT_8_BITS:
			return null
		_arm_loop(imported)
		return imported
	return null


func _open_loop_from_file(path: String) -> AudioStreamWAV:
	if not FileAccess.file_exists(path):
		return null
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return null
	var raw := file.get_buffer(file.get_length())
	return _wav_from_riff(raw)


func _wav_from_riff(raw: PackedByteArray) -> AudioStreamWAV:
	if raw.size() < 44:
		return null
	if raw.decode_u32(0) != 0x46464952: # "RIFF"
		return null
	var offset := 12
	var audio_format := 1
	var channels := 1
	var mix_rate := 22050
	var bits := 16
	var data := PackedByteArray()
	while offset + 8 <= raw.size():
		var chunk_id := raw.decode_u32(offset)
		var chunk_size := raw.decode_u32(offset + 4)
		var payload := offset + 8
		if payload + chunk_size > raw.size():
			break
		if chunk_id == 0x20746d66: # "fmt "
			audio_format = raw.decode_u16(payload)
			channels = raw.decode_u16(payload + 2)
			mix_rate = raw.decode_u32(payload + 4)
			bits = raw.decode_u16(payload + 14)
		elif chunk_id == 0x61746164: # "data"
			data = raw.slice(payload, payload + chunk_size)
			break
		offset = payload + chunk_size + (chunk_size & 1)
	if audio_format != 1 or data.is_empty():
		return null
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_8_BITS if bits == 8 else AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = mix_rate
	stream.stereo = channels == 2
	stream.data = data
	_arm_loop(stream)
	return stream


func _bind_web_unlock_callback() -> void:
	_web_unlock_cb = JavaScriptBridge.create_callback(_on_js_audio_unlock)
	var window := JavaScriptBridge.get_interface("window")
	if window != null:
		window.__wdGodotUnlock = _web_unlock_cb


func _on_js_audio_unlock(_args: Array) -> void:
	unlock()


func _process_web_unlock_flag() -> void:
	if _web_gesture or not OS.has_feature("web"):
		return
	var ready: bool = bool(JavaScriptBridge.eval("!!window.__wdAudioUnlocked", true))
	if ready:
		unlock()


func _input(event: InputEvent) -> void:
	if not OS.has_feature("web") or _web_gesture:
		return
	var pressed := false
	if event is InputEventMouseButton:
		pressed = (event as InputEventMouseButton).pressed
	elif event is InputEventScreenTouch:
		pressed = (event as InputEventScreenTouch).pressed
	elif event is InputEventKey:
		pressed = (event as InputEventKey).pressed
	if pressed:
		unlock()


func _notification(what: int) -> void:
	if not OS.has_feature("web"):
		return
	if what == NOTIFICATION_APPLICATION_FOCUS_IN or what == NOTIFICATION_WM_WINDOW_FOCUS_IN:
		if _web_gesture:
			_resume_web_audio_context()
			_try_play_context(true)


func unlock() -> void:
	_unlocked = true
	if OS.has_feature("web"):
		_web_gesture = true
		_resume_web_audio_context()
	# Browsers block autoplay until a gesture; every unlock must restart music.
	_pending_play = true
	_try_play_context(true)
	if OS.has_feature("web"):
		_schedule_web_retries()


func _schedule_web_retries() -> void:
	_web_retry_token += 1
	var token := _web_retry_token
	for delay in [0.08, 0.25, 0.6]:
		var timer := get_tree().create_timer(delay)
		timer.timeout.connect(func() -> void:
			if token != _web_retry_token:
				return
			_resume_web_audio_context()
			_try_play_context(true)
		, CONNECT_ONE_SHOT)


func _resume_web_audio_context() -> void:
	JavaScriptBridge.eval(
		"""
		(function () {
			try {
				if (window.WaveDefenceMobile && WaveDefenceMobile.unlockAudio) {
					WaveDefenceMobile.unlockAudio();
					return;
				}
				var Ctx = window.AudioContext || window.webkitAudioContext;
				if (!Ctx) return;
				if (!window.__wdAudioKick) {
					window.__wdAudioKick = new Ctx();
				}
				if (window.__wdAudioKick.state === 'suspended') {
					window.__wdAudioKick.resume();
				}
			} catch (e) {}
		})()
		""",
		true
	)


func _slider_db(percent: float) -> float:
	if percent <= 0.0:
		return -80.0
	return linear_to_db(percent / 100.0)


func _web_music_volume() -> float:
	var master := clampf(float(UserSettings.master_volume) / 100.0, 0.0, 1.0)
	var music := clampf(float(UserSettings.music_volume) / 100.0, 0.0, 1.0)
	var duck := 0.4 if _paused_duck else 1.0
	return master * music * duck


func _js_music(js: String) -> void:
	if not OS.has_feature("web"):
		return
	JavaScriptBridge.eval(js, true)


func _sync_web_music() -> void:
	if not OS.has_feature("web"):
		return
	var ctx_name := "menu"
	match _context:
		MusicContext.GAME_STANDARD:
			ctx_name = "standard"
		MusicContext.GAME_SIEGE:
			ctx_name = "siege"
		_:
			ctx_name = "menu"
	_js_music("if(window.WaveDefenceMobile){WaveDefenceMobile.musicSetVolume(%.4f);WaveDefenceMobile.musicSetContext('%s');}" % [_web_music_volume(), ctx_name])
	if ctx_name == "standard" or ctx_name == "siege":
		var floor_v := _boss_floor
		var intense_mix := clampf(floor_v + _tension_smooth * (1.0 - floor_v), 0.0, 1.0)
		_js_music("if(window.WaveDefenceMobile){WaveDefenceMobile.musicSetMix(%.4f,%.4f);}" % [1.0 - intense_mix, intense_mix])


func _apply_volumes() -> void:
	var master_idx := AudioServer.get_bus_index("Master")
	var music_idx := AudioServer.get_bus_index("Music")
	var sfx_idx := AudioServer.get_bus_index("SFX")
	if master_idx >= 0:
		AudioServer.set_bus_volume_db(master_idx, _slider_db(UserSettings.master_volume))
	if music_idx >= 0:
		var music_percent := UserSettings.music_volume * (0.4 if _paused_duck else 1.0)
		AudioServer.set_bus_volume_db(music_idx, _slider_db(music_percent))
	if sfx_idx >= 0:
		AudioServer.set_bus_volume_db(sfx_idx, _slider_db(UserSettings.sfx_volume))
	_sync_web_music()
	_update_music_mix()


func refresh_volumes() -> void:
	_apply_volumes()


func set_music_context(ctx: MusicContext) -> void:
	_context = ctx
	_tension_smooth = 0.0
	_boss_floor = 0.0
	_pending_play = true
	_try_play_context(false)


func _loop_ready(key: String) -> bool:
	return _loops.get(key) is AudioStreamWAV


func _try_play_context(force_restart: bool = false) -> void:
	if OS.has_feature("web") and not _web_gesture:
		return
	if OS.has_feature("web"):
		_sync_web_music()
		_pending_play = false
		return
	match _context:
		MusicContext.MENU:
			if not _loop_ready("menu"):
				return
			_play_loop_pair(_loops["menu"], null, 1.0, 0.0, force_restart)
			_pending_play = false
		MusicContext.GAME_STANDARD:
			if not _loop_ready("calm") or not _loop_ready("intense"):
				return
			_play_loop_pair(_loops["calm"], _loops["intense"], 1.0, 0.0, force_restart)
			_pending_play = false
		MusicContext.GAME_SIEGE:
			if not _loop_ready("siege_calm") or not _loop_ready("siege_intense"):
				return
			_play_loop_pair(_loops["siege_calm"], _loops["siege_intense"], 1.0, 0.0, force_restart)
			_pending_play = false
		_:
			_pending_play = false
	_playback_token += 1
	_confirm_playback(_playback_token)


func _confirm_playback(token: int) -> void:
	var timer := get_tree().create_timer(0.35)
	timer.timeout.connect(func() -> void:
		if token != _playback_token or _context == MusicContext.NONE:
			return
		if OS.has_feature("web") and not _web_gesture:
			return
		var player := _music_players[0]
		if player.stream == null:
			return
		if not player.playing or player.get_playback_position() < 0.02:
			player.play()
	, CONNECT_ONE_SHOT)


func _play_loop_pair(
	calm: AudioStream,
	intense: AudioStream,
	calm_vol: float,
	intense_vol: float,
	force_restart: bool = false
) -> void:
	if calm == null:
		return
	if force_restart or _music_players[0].stream != calm or not _music_players[0].playing:
		_music_players[0].stream = calm
		_music_players[0].play()
	_music_players[0].volume_db = linear_to_db(maxf(calm_vol, 0.001))
	if intense:
		if force_restart or _music_players[1].stream != intense or not _music_players[1].playing:
			_music_players[1].stream = intense
			_music_players[1].play()
		_music_players[1].volume_db = linear_to_db(maxf(intense_vol, 0.001))
	elif _music_players[1].playing or _music_players[1].stream != null:
		_music_players[1].stop()
		_music_players[1].stream = null


func _stop_music() -> void:
	for p in _music_players:
		p.stop()
	if OS.has_feature("web"):
		_js_music("if(window.WaveDefenceMobile){WaveDefenceMobile.musicSetVolume(0);}")


func set_gameplay_music_source(enemies: Node2D, wave: int, boss_wave: bool) -> void:
	_enemies_node = enemies
	_current_wave = wave
	_wave_is_boss = boss_wave
	_boss_floor = 0.4 if boss_wave else 0.0


func set_paused_duck(duck: bool) -> void:
	_paused_duck = duck
	_apply_volumes()


func _process(delta: float) -> void:
	if OS.has_feature("web") and not _web_gesture:
		_process_web_unlock_flag()
	if _context != MusicContext.GAME_STANDARD and _context != MusicContext.GAME_SIEGE:
		return
	if _paused_duck:
		return
	_tension_timer += delta
	if _tension_timer >= TENSION_INTERVAL:
		_tension_timer = 0.0
		var raw := _max_enemy_path_progress()
		_tension_smooth = move_toward(_tension_smooth, raw, TENSION_LERP * TENSION_INTERVAL)
	_update_music_mix()


func _max_enemy_path_progress() -> float:
	if _enemies_node == null or not is_instance_valid(_enemies_node):
		return 0.0
	var best := 0.0
	for c in _enemies_node.get_children():
		if c is Enemy:
			var e := c as Enemy
			if not e.alive:
				continue
			best = maxf(best, e.path_progress())
	return best


func _update_music_mix() -> void:
	if _context != MusicContext.GAME_STANDARD and _context != MusicContext.GAME_SIEGE:
		return
	var floor_v := _boss_floor
	var intense_mix := clampf(floor_v + _tension_smooth * (1.0 - floor_v), 0.0, 1.0)
	var calm_vol := 1.0 - intense_mix
	var intense_vol := intense_mix
	if _paused_duck:
		calm_vol *= 0.4
		intense_vol *= 0.4
	if OS.has_feature("web"):
		_js_music("if(window.WaveDefenceMobile){WaveDefenceMobile.musicSetMix(%.4f,%.4f);}" % [calm_vol, intense_vol])
		return
	_music_players[0].volume_db = linear_to_db(maxf(calm_vol, 0.001))
	_music_players[1].volume_db = linear_to_db(maxf(intense_vol, 0.001))


func play_ui() -> void:
	if OS.has_feature("web"):
		_js_music("if(window.WaveDefenceMobile&&WaveDefenceMobile.playUiBlip){WaveDefenceMobile.playUiBlip();}")
	_play_sfx("ui")


func play_place() -> void:
	_play_sfx("place")


func play_sell() -> void:
	_play_sfx("sell")


func play_wave_start(boss: bool) -> void:
	_play_sfx("boss" if boss else "wave")


func play_leak() -> void:
	_play_sfx("leak")


func play_kill() -> void:
	if _kill_sfx_cooldown > 0.0:
		return
	_kill_sfx_cooldown = 0.06
	_play_sfx("kill")


func play_game_over() -> void:
	_play_sfx("game_over")


func play_achievement() -> void:
	_play_sfx("unlock")


func _play_sfx(key: String) -> void:
	if not _unlocked:
		return
	if not _sfx.has(key):
		return
	# First audible click is a trusted gesture — kick music if autoplay blocked it.
	if OS.has_feature("web") and (_music_players[0].stream == null or not _music_players[0].playing):
		_try_play_context(true)
	_sfx_player.stream = _sfx[key]
	_sfx_player.pitch_scale = randf_range(0.95, 1.05)
	_sfx_player.play()


func _physics_process(delta: float) -> void:
	if _kill_sfx_cooldown > 0.0:
		_kill_sfx_cooldown = maxf(_kill_sfx_cooldown - delta, 0.0)
