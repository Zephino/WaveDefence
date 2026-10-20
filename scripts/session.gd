extends Node

## Autoload bridge for menu ↔ game ↔ leaderboard flow.

const MENU_SCENE := "res://scenes/menu.tscn"
const GAME_SCENE := "res://scenes/main.tscn"
const LEADERBOARD_SCENE := "res://scenes/leaderboard.tscn"

## Wave reached from a finished run. -1 means browse-only (no name entry).
var pending_wave_score: int = -1
## True when the finished run used debug tools (name entry blocked).
var pending_debug_used: bool = false
## Difficulty board for a pending score / leaderboard view.
var pending_difficulty: int = WaveScaler.Difficulty.MEDIUM
## Game mode board for a pending score / leaderboard view.
var pending_game_mode: int = WaveScaler.GameMode.CLASSIC
## Base64 PNG of the board at run end (attached on submit if they qualify).
var pending_board_png: String = ""
## Selected run difficulty (WaveScaler.Difficulty). Kept across Play Again.
var difficulty: int = WaveScaler.Difficulty.MEDIUM
## Classic / Random / Siege map mode. Kept across Play Again.
var game_mode: int = WaveScaler.GameMode.CLASSIC
## Classic (formula spawns) or Randomize (elemental monster types). Kept across Play Again.
var monster_mode: int = WaveScaler.MonsterMode.CLASSIC
## Classic: STANDARD corridor vs CUSTOM seeded layout. Random ignores (always generator).
var map_layout_mode: int = WaveScaler.MapLayoutMode.STANDARD
## Base seed for the run (Classic custom / Random). -1 until resolved at start.
var run_seed: int = -1
## Layout seed currently in play (shown in HUD; paste into Classic Custom to replay).
var current_map_seed: int = -1
## Last seed text typed on the map-setup screen (for Play Again convenience).
var map_seed_text: String = ""
## Guided tutorial practice run (leaderboard + achievements off).
var tutorial_active: bool = false
## Clash: total players including the human (2–4).
var clash_player_count: int = 2
## Clash: bot difficulties (WaveScaler.Difficulty), length = clash_player_count - 1.
var clash_bot_difficulties: Array = [WaveScaler.Difficulty.MEDIUM]

## Pending worldwide push (set when the player submits a name after a match).
var global_push_name: String = ""
var global_push_wave: int = -1
var global_push_difficulty: int = WaveScaler.Difficulty.MEDIUM
var global_push_game_mode: int = WaveScaler.GameMode.CLASSIC
var global_push_needed: bool = false
var global_push_done: bool = false
## Map seeds from the finished run (for leaderboard submit).
var pending_map_seeds: Array = []
## Seeds attached to the pending global push payload.
var global_push_seeds: Array = []
var global_push_board_png: String = ""

## True on mobile web (CSS landscape helper applies).
var _web_mobile_play: bool = false


func _ready() -> void:
	_web_mobile_play = (
		OS.has_feature("web")
		and (GameLayout.is_mobile_device() or GameLayout.use_touch_ui())
	)
	_apply_mobile_presentation()


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_WM_CLOSE_REQUEST:
			_release_mobile_presentation()
		NOTIFICATION_APPLICATION_RESUMED:
			_apply_mobile_presentation()
		NOTIFICATION_PREDELETE:
			_release_mobile_presentation()


func go_menu() -> void:
	pending_wave_score = -1
	pending_debug_used = false
	pending_board_png = ""
	tutorial_active = false
	get_tree().change_scene_to_file(MENU_SCENE)


func set_clash_setup(player_count: int, bot_difficulties: Array) -> void:
	clash_player_count = clampi(player_count, WaveScaler.CLASH_MIN_PLAYERS, WaveScaler.CLASH_MAX_PLAYERS)
	clash_bot_difficulties.clear()
	var bots_needed := clash_player_count - 1
	for i in bots_needed:
		var diff := WaveScaler.Difficulty.MEDIUM
		if i < bot_difficulties.size():
			diff = int(bot_difficulties[i])
		clash_bot_difficulties.append(diff)


func go_game(
	selected_difficulty: int = -1,
	selected_mode: int = -1,
	selected_monster_mode: int = -1,
	selected_layout_mode: int = -1,
	selected_run_seed: int = -2,
	selected_seed_text: String = "\u0001"
) -> void:
	if selected_difficulty >= 0:
		difficulty = selected_difficulty
	if selected_mode >= 0:
		game_mode = selected_mode
	if selected_monster_mode >= 0:
		monster_mode = selected_monster_mode
	if selected_layout_mode >= 0:
		map_layout_mode = selected_layout_mode
	# -2 means "leave unchanged" (Play Again); -1 means roll at game start.
	if selected_run_seed >= -1:
		run_seed = selected_run_seed
		current_map_seed = -1
	if selected_seed_text != "\u0001":
		map_seed_text = selected_seed_text
	pending_wave_score = -1
	pending_debug_used = false
	get_tree().change_scene_to_file(GAME_SCENE)


func go_leaderboard(
	wave_score: int = -1,
	debug_used: bool = false,
	run_difficulty: int = -1,
	map_seeds: Array = [],
	run_mode: int = -1,
	board_png: String = "\u0001"
) -> void:
	pending_wave_score = wave_score
	pending_debug_used = debug_used and wave_score > 0
	pending_map_seeds = map_seeds.duplicate()
	if run_difficulty >= 0:
		pending_difficulty = run_difficulty
	elif wave_score > 0:
		pending_difficulty = difficulty
	else:
		pending_difficulty = difficulty
	if run_mode >= 0:
		pending_game_mode = run_mode
	elif wave_score > 0:
		pending_game_mode = game_mode
	else:
		pending_game_mode = game_mode
	# "\u0001" = leave pending_board_png unchanged (already snapped at game over).
	if board_png != "\u0001":
		pending_board_png = BoardScreenshot.sanitize_board_b64(board_png)
	get_tree().change_scene_to_file(LEADERBOARD_SCENE)


func quit_game() -> void:
	_release_mobile_presentation()
	if OS.has_feature("web"):
		# Exit fullscreen / CSS rotate and try to leave the page (history.back).
		_js_exit_play_mode()
		# Stop the engine after handing control back to the browser.
		get_tree().quit()
		return
	get_tree().quit()


## Landscape on phones. Web fullscreen is only via the Fullscreen menu button.
func _apply_mobile_presentation() -> void:
	if not GameLayout.is_mobile_device() and not _web_mobile_play:
		return
	DisplayServer.screen_set_orientation(DisplayServer.SCREEN_SENSOR_LANDSCAPE)
	if OS.has_feature("web"):
		_js_apply_css_landscape()
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)


func request_web_fullscreen() -> void:
	if not OS.has_feature("web"):
		return
	# Canvas/Godot clicks are not a trusted fullscreen gesture — ask the page
	# for a real HTML tap (modal / floating button) via promptFullscreen.
	JavaScriptBridge.eval(
		"""
		(function () {
			try {
				if (!window.WaveDefenceMobile) return;
				if (WaveDefenceMobile.promptFullscreen) {
					WaveDefenceMobile.promptFullscreen();
				} else if (WaveDefenceMobile.enterFullscreen) {
					WaveDefenceMobile.enterFullscreen();
				}
			} catch (e) {}
		})()
		""",
		true
	)


func request_web_install() -> void:
	if not OS.has_feature("web"):
		return
	JavaScriptBridge.eval(
		"""
		(function () {
			try {
				if (window.WaveDefenceMobile && WaveDefenceMobile.promptInstall) {
					WaveDefenceMobile.promptInstall();
				}
			} catch (e) {}
		})()
		""",
		true
	)


func request_web_update() -> void:
	if not OS.has_feature("web"):
		return
	JavaScriptBridge.eval(
		"""
		(function () {
			try {
				if (window.WaveDefenceMobile && WaveDefenceMobile.promptUpdateApp) {
					WaveDefenceMobile.promptUpdateApp();
				}
			} catch (e) {}
		})()
		""",
		true
	)


func _release_mobile_presentation() -> void:
	if not GameLayout.is_mobile_device() and not _web_mobile_play:
		return
	DisplayServer.screen_set_orientation(DisplayServer.SCREEN_SENSOR)
	if OS.has_feature("web"):
		return
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)


func _js_apply_css_landscape() -> void:
	if not OS.has_feature("web"):
		return
	JavaScriptBridge.eval(
		"""
		(function () {
			try {
				if (window.WaveDefenceMobile && WaveDefenceMobile.applyCssLandscape) {
					WaveDefenceMobile.applyCssLandscape();
				}
			} catch (e) {}
		})()
		""",
		true
	)


func _js_exit_play_mode() -> void:
	if not OS.has_feature("web"):
		return
	JavaScriptBridge.eval(
		"""
		(function () {
			try {
				if (window.WaveDefenceMobile && WaveDefenceMobile.exitPlayMode) {
					WaveDefenceMobile.exitPlayMode();
				}
			} catch (e) {}
		})()
		""",
		true
	)
