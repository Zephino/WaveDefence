extends Node

## Procedural music + SFX. All synthesized — no external samples.

const _PA := preload("res://scripts/procedural_audio.gd")

enum MusicContext { NONE, MENU, GAME_STANDARD, GAME_SIEGE }

var _unlocked: bool = false
var _context: MusicContext = MusicContext.NONE
var _music_players: Array[AudioStreamPlayer] = []
var _sfx_player: AudioStreamPlayer
var _kill_sfx_cooldown: float = 0.0

var _loops: Dictionary = {}
var _sfx: Dictionary = {}

var _tension_smooth: float = 0.0
var _tension_timer: float = 0.0
var _boss_floor: float = 0.0
var _paused_duck: bool = false
var _enemies_node: Node2D = null
var _current_wave: int = 0
var _wave_is_boss: bool = false

const TENSION_INTERVAL := 0.05
const TENSION_LERP := 8.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_buses()
	_build_streams()
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


func _setup_buses() -> void:
	if AudioServer.bus_count <= 1:
		AudioServer.add_bus(1)
		AudioServer.set_bus_name(1, "Music")
		AudioServer.add_bus(2)
		AudioServer.set_bus_name(2, "SFX")
		AudioServer.set_bus_send(1, "Master")
		AudioServer.set_bus_send(2, "Master")


func _build_streams() -> void:
	_loops["menu"] = _PA.make_loop("menu", 20.0)
	_loops["calm"] = _PA.make_loop("game_calm", 28.0)
	_loops["intense"] = _PA.make_loop("game_intense", 26.0)
	_loops["siege_calm"] = _PA.make_loop("siege_calm", 30.0)
	_loops["siege_intense"] = _PA.make_loop("siege_intense", 28.0)
	_sfx["ui"] = _PA.make_ui_blip()
	_sfx["place"] = _PA.make_place_thud()
	_sfx["sell"] = _PA.make_sell_drop()
	_sfx["wave"] = _PA.make_wave_stinger()
	_sfx["boss"] = _PA.make_boss_stinger()
	_sfx["leak"] = _PA.make_leak_sfx()
	_sfx["kill"] = _PA.make_kill_tick()
	_sfx["game_over"] = _PA.make_game_over_sting()
	_sfx["unlock"] = _PA.make_unlock_fanfare()


func unlock() -> void:
	_unlocked = true


func _apply_volumes() -> void:
	var master := UserSettings.master_volume / 100.0
	var music := UserSettings.music_volume / 100.0 * master
	var sfx := UserSettings.sfx_volume / 100.0 * master
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Master"), linear_to_db(master))
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Music"), linear_to_db(music))
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("SFX"), linear_to_db(sfx))
	_update_music_mix()


func refresh_volumes() -> void:
	_apply_volumes()


func set_music_context(ctx: MusicContext) -> void:
	if not _unlocked and OS.has_feature("web"):
		return
	_context = ctx
	_tension_smooth = 0.0
	_boss_floor = 0.0
	match ctx:
		MusicContext.MENU:
			_play_loop_pair(_loops["menu"], null, 1.0, 0.0)
		MusicContext.GAME_STANDARD:
			_play_loop_pair(_loops["calm"], _loops["intense"], 1.0, 0.0)
		MusicContext.GAME_SIEGE:
			_play_loop_pair(_loops["siege_calm"], _loops["siege_intense"], 1.0, 0.0)
		_:
			_stop_music()


func _play_loop_pair(calm: AudioStream, intense: AudioStream, calm_vol: float, intense_vol: float) -> void:
	_music_players[0].stream = calm
	_music_players[1].stream = intense
	if not _music_players[0].playing:
		_music_players[0].play()
	if intense and not _music_players[1].playing:
		_music_players[1].play()
	_music_players[0].volume_db = linear_to_db(maxf(calm_vol, 0.001))
	if intense:
		_music_players[1].volume_db = linear_to_db(maxf(intense_vol, 0.001))


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
	if duck:
		AudioServer.set_bus_volume_db(
			AudioServer.get_bus_index("Music"),
			linear_to_db(UserSettings.music_volume / 100.0 * UserSettings.master_volume / 100.0 * 0.4)
		)
	else:
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
