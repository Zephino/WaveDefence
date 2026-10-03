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
## Selected run difficulty (WaveScaler.Difficulty). Kept across Play Again.
var difficulty: int = WaveScaler.Difficulty.MEDIUM
## Classic (fixed map) or Random (shifting maps). Kept across Play Again.
var game_mode: int = WaveScaler.GameMode.CLASSIC

## Pending worldwide push (set when the player submits a name after a match).
var global_push_name: String = ""
var global_push_wave: int = -1
var global_push_difficulty: int = WaveScaler.Difficulty.MEDIUM
var global_push_needed: bool = false
var global_push_done: bool = false

## Web browsers block fullscreen until a tap; track that we already asked.
var _web_fullscreen_armed: bool = false
var _web_fullscreen_done: bool = false


func _ready() -> void:
	_apply_mobile_presentation()
	# Mobile web: wait for first tap/click to enter fullscreen (browser requirement).
	_web_fullscreen_armed = (
		OS.has_feature("web")
		and (GameLayout.is_mobile_device() or GameLayout.use_touch_ui())
	)
	set_process_input(_web_fullscreen_armed)


func _input(event: InputEvent) -> void:
	if not _web_fullscreen_armed or _web_fullscreen_done:
		return
	var pressed := false
	if event is InputEventScreenTouch:
		pressed = event.pressed
	elif event is InputEventMouseButton:
		pressed = event.pressed
	if not pressed:
		return
	_web_fullscreen_done = true
	_request_mobile_fullscreen()
	_js_lock_landscape()
	set_process_input(false)


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
	get_tree().change_scene_to_file(MENU_SCENE)


func go_game(selected_difficulty: int = -1, selected_mode: int = -1) -> void:
	if selected_difficulty >= 0:
		difficulty = selected_difficulty
	if selected_mode >= 0:
		game_mode = selected_mode
	pending_wave_score = -1
	pending_debug_used = false
	get_tree().change_scene_to_file(GAME_SCENE)


func go_leaderboard(wave_score: int = -1, debug_used: bool = false, run_difficulty: int = -1) -> void:
	pending_wave_score = wave_score
	pending_debug_used = debug_used and wave_score > 0
	if run_difficulty >= 0:
		pending_difficulty = run_difficulty
	elif wave_score > 0:
		pending_difficulty = difficulty
	else:
		pending_difficulty = difficulty
	get_tree().change_scene_to_file(LEADERBOARD_SCENE)


func quit_game() -> void:
	_release_mobile_presentation()
	get_tree().quit()


## Landscape + fullscreen on phones (native + mobile browsers). Desktop unchanged.
func _apply_mobile_presentation() -> void:
	if not GameLayout.is_mobile_device():
		return
	DisplayServer.screen_set_orientation(DisplayServer.SCREEN_SENSOR_LANDSCAPE)
	_js_lock_landscape()
	# Native apps can go fullscreen immediately; web needs a user gesture (see _input).
	if not OS.has_feature("web"):
		_request_mobile_fullscreen()


func _release_mobile_presentation() -> void:
	if not GameLayout.is_mobile_device():
		return
	DisplayServer.screen_set_orientation(DisplayServer.SCREEN_SENSOR)
	_js_unlock_orientation()
	if not OS.has_feature("web"):
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)


func _request_mobile_fullscreen() -> void:
	if not GameLayout.is_mobile_device():
		return
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	if OS.has_feature("web"):
		JavaScriptBridge.eval(
			"""
			(function () {
				try {
					var el = document.documentElement;
					var req = el.requestFullscreen || el.webkitRequestFullscreen || el.msRequestFullscreen;
					if (req) { req.call(el); }
				} catch (e) {}
			})()
			""",
			true
		)


func _js_lock_landscape() -> void:
	if not OS.has_feature("web"):
		return
	JavaScriptBridge.eval(
		"""
		(function () {
			try {
				if (screen.orientation && screen.orientation.lock) {
					screen.orientation.lock('landscape').catch(function () {});
				}
			} catch (e) {}
		})()
		""",
		true
	)


func _js_unlock_orientation() -> void:
	if not OS.has_feature("web"):
		return
	JavaScriptBridge.eval(
		"""
		(function () {
			try {
				if (screen.orientation && screen.orientation.unlock) {
					screen.orientation.unlock();
				}
			} catch (e) {}
		})()
		""",
		true
	)
