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


func _ready() -> void:
	_apply_play_orientation()


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_WM_CLOSE_REQUEST:
			_release_orientation()
		NOTIFICATION_APPLICATION_RESUMED:
			_apply_play_orientation()
		NOTIFICATION_PREDELETE:
			_release_orientation()


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
	_release_orientation()
	get_tree().quit()


func _is_mobile_runtime() -> bool:
	return OS.has_feature("mobile") or OS.has_feature("android") or OS.has_feature("ios")


## Keep the game in either landscape direction while active.
func _apply_play_orientation() -> void:
	if not _is_mobile_runtime():
		return
	DisplayServer.screen_set_orientation(DisplayServer.SCREEN_SENSOR_LANDSCAPE)


## Let the phone return to its normal orientation when the app is closed / backgrounded.
func _release_orientation() -> void:
	if not _is_mobile_runtime():
		return
	DisplayServer.screen_set_orientation(DisplayServer.SCREEN_SENSOR)
