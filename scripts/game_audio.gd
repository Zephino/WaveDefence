extends Node

## Original NES-style loops (audio/music/*.wav) plus synthesized SFX.
## Loops are prebuilt so startup does not synthesize music.

const _PA := preload("res://scripts/procedural_audio.gd")

enum MusicContext { NONE, MENU, GAME_STANDARD, GAME_SIEGE }

const LOOP_PATHS := {
	"menu": "res://audio/music/original_loop_01.wav",
	"calm": "res://audio/music/original_loop_02.wav",
	"intense": "res://audio/music/original_loop_03.wav",
	"siege_calm": "res://audio/music/original_loop_04.wav",
	"siege_intense": "res://audio/music/original_loop_05.wav",
}

var _unlocked: bool = false
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


func _setup_buses() -> void:
	if AudioServer.bus_count <= 1:
		AudioServer.add_bus(1)
		AudioServer.set_bus_name(1, "Music")
		AudioServer.add_bus(2)
		AudioServer.set_bus_name(2, "SFX")
		AudioServer.set_bus_send(1, "Master")
		AudioServer.set_bus_send(2, "Master")


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


func _load_music_loops() -> void:
	for key in LOOP_PATHS:
		_loops[key] = _open_loop_bytes(String(LOOP_PATHS[key]))


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
	# Exported packs ship the imported AudioStreamWAV, not the raw .wav bytes.
	if ResourceLoader.exists(path):
		var loaded: Variant = ResourceLoader.load(path)
		if loaded is AudioStreamWAV:
			var imported := (loaded as AudioStreamWAV).duplicate() as AudioStreamWAV
			_arm_loop(imported)
			return imported
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("Music loop missing: %s" % path)
		return null
	var raw := file.get_buffer(file.get_length())
	if raw.size() < 44:
		return null
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = raw.decode_u32(24)
	stream.stereo = raw.decode_u16(22) == 2
	stream.data = raw.slice(44)
	_arm_loop(stream)
	return stream


func unlock() -> void:
	_unlocked = true
	if _pending_play:
		_try_play_context()


func _slider_db(percent: float) -> float:
	if percent <= 0.0:
		return -80.0
	return linear_to_db(percent / 100.0)


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
	_update_music_mix()


func refresh_volumes() -> void:
	_apply_volumes()


func set_music_context(ctx: MusicContext) -> void:
	if not _unlocked and OS.has_feature("web"):
		return
	_context = ctx
	_tension_smooth = 0.0
	_boss_floor = 0.0
	_pending_play = true
	_try_play_context()


func _try_play_context() -> void:
	if not _unlocked and OS.has_feature("web"):
		return
	match _context:
		MusicContext.MENU:
			if not _loops.has("menu"):
				return
			_play_loop_pair(_loops["menu"], null, 1.0, 0.0)
			_pending_play = false
		MusicContext.GAME_STANDARD:
			if not _loops.has("calm") or not _loops.has("intense"):
				return
			_play_loop_pair(_loops["calm"], _loops["intense"], 1.0, 0.0)
			_pending_play = false
		MusicContext.GAME_SIEGE:
			if not _loops.has("siege_calm") or not _loops.has("siege_intense"):
				return
			_play_loop_pair(_loops["siege_calm"], _loops["siege_intense"], 1.0, 0.0)
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
		var player := _music_players[0]
		if player.stream == null:
			return
		if not player.playing or player.get_playback_position() < 0.02:
			player.play()
	, CONNECT_ONE_SHOT)


func _play_loop_pair(calm: AudioStream, intense: AudioStream, calm_vol: float, intense_vol: float) -> void:
	if _music_players[0].stream != calm:
		_music_players[0].stream = calm
		_music_players[0].play()
	elif not _music_players[0].playing:
		_music_players[0].play()
	_music_players[0].volume_db = linear_to_db(maxf(calm_vol, 0.001))
	if intense:
		if _music_players[1].stream != intense:
			_music_players[1].stream = intense
			_music_players[1].play()
		elif not _music_players[1].playing:
			_music_players[1].play()
		_music_players[1].volume_db = linear_to_db(maxf(intense_vol, 0.001))
	elif _music_players[1].playing:
		_music_players[1].stop()
		_music_players[1].stream = null


func _stop_music() -> void:
	for p in _music_players:
		p.stop()


func set_gameplay_music_source(enemies: Node2D, wave: int, boss_wave: bool) -> void:
	_enemies_node = enemies
	_current_wave = wave
	_wave_is_boss = boss_wave
	_boss_floor = 0.4 if boss_wave else 0.0


func set_paused_duck(duck: bool) -> void:
	_paused_duck = duck
	_apply_volumes()


func _process(delta: float) -> void:
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
	_music_players[0].volume_db = linear_to_db(maxf(calm_vol, 0.001))
	_music_players[1].volume_db = linear_to_db(maxf(intense_vol, 0.001))


func play_ui() -> void:
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
	_sfx_player.stream = _sfx[key]
	_sfx_player.pitch_scale = randf_range(0.95, 1.05)
	_sfx_player.play()


func _physics_process(delta: float) -> void:
	if _kill_sfx_cooldown > 0.0:
		_kill_sfx_cooldown = maxf(_kill_sfx_cooldown - delta, 0.0)
