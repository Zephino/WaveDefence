class_name GameLayout
extends RefCounted

## Shared layout so the HUD sidebar, board, and debug panel never overlap.

const VIEW_WIDTH := 1280
const VIEW_HEIGHT := 720
const SIDEBAR_LEFT := 8
const SIDEBAR_WIDTH := 176
const SIDEBAR_GAP := 12
const BOARD_TOP := 72
const DEBUG_GAP := 8


static func board_origin() -> Vector2:
	return Vector2(SIDEBAR_LEFT + SIDEBAR_WIDTH + SIDEBAR_GAP, BOARD_TOP)


static func board_pixel_size() -> Vector2:
	return Vector2(GameGrid.COLS * GameGrid.TILE_SIZE, GameGrid.ROWS * GameGrid.TILE_SIZE)


static func board_rect() -> Rect2:
	return Rect2(board_origin(), board_pixel_size())


static func sidebar_rect() -> Rect2:
	return Rect2(SIDEBAR_LEFT, BOARD_TOP - 8, SIDEBAR_WIDTH, VIEW_HEIGHT - (BOARD_TOP - 8) - 8)


## Right gutter beside the board (never overlaps playfield cells).
static func right_sidebar_rect() -> Rect2:
	var board := board_rect()
	var x := board.position.x + board.size.x + DEBUG_GAP
	var width := VIEW_WIDTH - x - DEBUG_GAP
	var y := BOARD_TOP - 8
	var height := VIEW_HEIGHT - y - 8
	return Rect2(x, y, maxf(width, 120.0), maxf(height, 200.0))


## Right gutter used by the debug panel (same strip as the touch action sidebar).
static func debug_panel_rect() -> Rect2:
	return right_sidebar_rect()


## True on phones/tablets or when a touchscreen is the practical input.
static func use_touch_ui() -> bool:
	if OS.has_feature("mobile") or OS.has_feature("android") or OS.has_feature("ios"):
		return true
	if DisplayServer.is_touchscreen_available():
		var size := DisplayServer.screen_get_size()
		# Treat small touchscreens as mobile UI even in the editor/desktop.
		return mini(size.x, size.y) > 0 and mini(size.x, size.y) <= 900
	return false


static func button_height(desktop_height: float) -> float:
	return desktop_height * 1.4 if use_touch_ui() else desktop_height


static func help_text() -> String:
	if use_touch_ui():
		return "Drag to paint place\nLong-press tower = multi-select\nMulti toggle / Deselect\nTap tower for info"
	return "Esc/right-click deselect\nCtrl/Shift multi-select\nUpgrade x3 then final\nF1 debug"
