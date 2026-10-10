class_name GameLayout
extends RefCounted

## Shared layout so the HUD sidebar, board, and debug panel never overlap.

const VIEW_WIDTH := 1280
const VIEW_HEIGHT := 720
const SIDEBAR_LEFT := 8
const SIDEBAR_WIDTH := 176
const SIDEBAR_WIDTH_LARGE := 220
const SIDEBAR_GAP := 12
const BOARD_TOP := 72
const DEBUG_GAP := 8
const TILE_SIZE_DEFAULT := 40
const TILE_SIZE_LARGE_CONTROLS := 30
## Right actions column minimum width.
const RIGHT_SIDEBAR_MIN := 120
const RIGHT_SIDEBAR_LARGE_MIN := 160


static func tile_size() -> int:
	return TILE_SIZE_LARGE_CONTROLS if UserSettings.is_large_controls() else TILE_SIZE_DEFAULT


static func sidebar_width() -> float:
	return float(SIDEBAR_WIDTH_LARGE if UserSettings.is_large_controls() else SIDEBAR_WIDTH)


static func right_sidebar_min() -> float:
	return float(RIGHT_SIDEBAR_LARGE_MIN if UserSettings.is_large_controls() else RIGHT_SIDEBAR_MIN)


static func board_origin() -> Vector2:
	return Vector2(SIDEBAR_LEFT + sidebar_width() + SIDEBAR_GAP, BOARD_TOP)


## Visible play window between the sidebars (not necessarily the full map size).
static func board_view_size(map_size: Vector2 = Vector2.ZERO) -> Vector2:
	var origin := board_origin()
	var right_min := right_sidebar_min()
	var max_w := VIEW_WIDTH - origin.x - DEBUG_GAP - right_min - DEBUG_GAP
	var max_h := VIEW_HEIGHT - BOARD_TOP - 8
	if map_size == Vector2.ZERO:
		return Vector2(maxf(max_w, 200.0), maxf(max_h, 200.0))
	return Vector2(minf(map_size.x, max_w), minf(map_size.y, max_h))


static func board_pixel_size() -> Vector2:
	## Default classic footprint for HUD bootstrap before a grid exists.
	var map := Vector2(GameGrid.COLS * tile_size(), GameGrid.ROWS * tile_size())
	return board_view_size(map)


static func board_rect() -> Rect2:
	return Rect2(board_origin(), board_pixel_size())


static func board_rect_for_map(map_size: Vector2) -> Rect2:
	return Rect2(board_origin(), board_view_size(map_size))


static func sidebar_rect() -> Rect2:
	return Rect2(SIDEBAR_LEFT, BOARD_TOP - 8, sidebar_width(), VIEW_HEIGHT - (BOARD_TOP - 8) - 8)


## Right gutter beside the visible board window.
static func right_sidebar_rect() -> Rect2:
	var board := board_rect()
	var x := board.position.x + board.size.x + DEBUG_GAP
	var width := VIEW_WIDTH - x - DEBUG_GAP
	var y := BOARD_TOP - 8
	var height := VIEW_HEIGHT - y - 8
	return Rect2(x, y, maxf(width, right_sidebar_min()), maxf(height, 200.0))


static func right_sidebar_rect_for_map(map_size: Vector2) -> Rect2:
	var board := board_rect_for_map(map_size)
	var x := board.position.x + board.size.x + DEBUG_GAP
	var width := VIEW_WIDTH - x - DEBUG_GAP
	var y := BOARD_TOP - 8
	var height := VIEW_HEIGHT - y - 8
	return Rect2(x, y, maxf(width, right_sidebar_min()), maxf(height, 200.0))


## Floating debug overlay centered over the board (does not cover sidebars).
static func debug_panel_rect() -> Rect2:
	var board := board_rect()
	var width := 240.0
	var height := minf(board.size.y - 16.0, 440.0)
	var x := board.position.x + (board.size.x - width) * 0.5
	var y := board.position.y + 8.0
	return Rect2(x, y, width, height)


## Shop left + actions right (desktop and mobile).
static func use_dual_sidebars() -> bool:
	return true


## Cached web-mobile probe: -1 unknown, 0 no, 1 yes.
static var _web_mobile_cache: int = -1


## True for native mobile runtimes and mobile browsers (not desktop PCs).
static func is_mobile_device() -> bool:
	if OS.has_feature("android") or OS.has_feature("ios") or OS.has_feature("mobile"):
		return true
	if OS.has_feature("web"):
		if _is_web_mobile():
			return true
		# Fallbacks when the JS probe fails or returns an unexpected value.
		if DisplayServer.is_touchscreen_available():
			var size := DisplayServer.screen_get_size()
			if mini(size.x, size.y) > 0 and mini(size.x, size.y) <= 1100:
				return true
		var win := DisplayServer.window_get_size()
		if DisplayServer.is_touchscreen_available() and mini(win.x, win.y) <= 900:
			return true
	return false


static func _is_web_mobile() -> bool:
	if _web_mobile_cache >= 0:
		return _web_mobile_cache == 1
	var detected := false
	if OS.has_feature("web"):
		var result = JavaScriptBridge.eval(
			"""
			(function () {
				try {
					var ua = navigator.userAgent || navigator.vendor || '';
					var uaMobile = /Android|iPhone|iPad|iPod|Mobile|Tablet|webOS|BlackBerry|IEMobile|Opera Mini|CriOS|FxiOS/i.test(ua);
					var touch = (navigator.maxTouchPoints || 0) > 0 || 'ontouchstart' in window;
					var w = Math.min(window.innerWidth || 0, window.innerHeight || 0);
					var s = Math.min(screen.width || 0, screen.height || 0);
					var small = (w > 0 && w <= 1100) || (s > 0 && s <= 1100);
					var coarse = window.matchMedia && window.matchMedia('(pointer: coarse)').matches;
					var hoverNone = window.matchMedia && window.matchMedia('(hover: none)').matches;
					return (uaMobile || (touch && small) || (coarse && small) || (hoverNone && touch && small)) ? 1 : 0;
				} catch (e) {
					return 0;
				}
			})()
			""",
			true
		)
		var text := str(result).strip_edges().to_lower()
		detected = text == "1" or text == "true" or text == "1.0" or int(result) == 1
	_web_mobile_cache = 1 if detected else 0
	return detected


## True on phones/tablets or when a touchscreen is the practical input.
static func use_touch_ui() -> bool:
	if is_mobile_device():
		return true
	if DisplayServer.is_touchscreen_available():
		var size := DisplayServer.screen_get_size()
		# Treat small touchscreens as mobile UI even in the editor/desktop.
		return mini(size.x, size.y) > 0 and mini(size.x, size.y) <= 900
	return false


static func button_height(desktop_height: float) -> float:
	var h := desktop_height
	if use_touch_ui():
		h *= 1.4
	if UserSettings.is_large_controls():
		h *= 1.25
	return h


static func help_text() -> String:
	if use_touch_ui() or UserSettings.is_large_controls():
		return "Drag to paint place\nLong-press tower = multi-select\nMulti / Pan / Deselect\nTap tower for info\nPan: On = drag map only"
	return "Esc/right-click deselect\nCtrl/Shift multi-select\nUpgrade x3 then final\nF1/~ debug overlay\nPan: On or hold Space to drag map"
