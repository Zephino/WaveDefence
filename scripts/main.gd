extends Node2D

const _RangeOverlay := preload("res://scripts/range_overlay.gd")
const _PauseMenuOverlay := preload("res://scripts/pause_menu_overlay.gd")
const _RunSummaryOverlay := preload("res://scripts/run_summary_overlay.gd")
const _BoardScreenshot := preload("res://scripts/board_screenshot.gd")
const _WavePreview := preload("res://data/wave_preview.gd")
const _Achievements := preload("res://data/achievements.gd")
const _AchievementStore := preload("res://scripts/achievement_store.gd")
const _PlayerStats := preload("res://scripts/player_stats.gd")
const SoundHub := preload("res://scripts/sound_hub.gd")

var game_state: GameState
var grid: GameGrid
var pathfinder: Pathfinder
var build_system: BuildSystem
var wave_manager: WaveManager
var hud: UIHud
var debug_panel: DebugPanel

var enemies: Node2D
var projectiles: Node2D
var traps: Node2D
var map_offset: Vector2 = GameLayout.board_origin()
## Scroll into a larger map (Siege / oversized boards). World pos = map_offset - map_pan * map_zoom.
var map_pan: Vector2 = Vector2.ZERO
## 1.0 = native tile size; lower values shrink the board (wheel zoom on oversized maps).
var map_zoom: float = 1.0
const MAP_ZOOM_STEP := 0.1
var _map_camera: Camera2D

## Hold left mouse / finger to paint-place towers/walls across cells.
var _paint_holding: bool = false
var _paint_enabled: bool = false
var _last_paint_cell: Vector2i = Vector2i(-999, -999)
## Touch / mouse long-press on a tower toggles multi-select.
var _awaiting_tower_tap: bool = false
var _long_press_triggered: bool = false
var _press_start_pos: Vector2 = Vector2.ZERO
var _press_hold_time: float = 0.0
const LONG_PRESS_SEC := 0.45
const TAP_MOVE_PX := 18.0
var _touch_ui: bool = false
var _multi_select_mode: bool = false
## Command tower pay-per-use aim mode.
var _aim_ability_id: String = ""
var _aim_command_tower: Tower = null
## Board pan (Siege / large maps).
var _panning: bool = false
var _pan_last_screen: Vector2 = Vector2.ZERO
var _pan_moved: bool = false
var _range_overlay: Node2D
var _pause_menu: Control
var _game_paused: bool = false
var _tutorial_step: int = 0
var _pending_leaderboard_wave: int = -1


func _ready() -> void:
	UserSettings.ensure_loaded()
	_touch_ui = GameLayout.use_touch_ui()
	_setup_world()
	_setup_systems()
	_setup_ui()
	build_system.refresh_after_reset()


func _setup_world() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.08, 0.1, 0.13)
	bg.size = Vector2(1280, 720)
	bg.z_index = -10
	# Must ignore mouse or this fullscreen Control eats all map clicks.
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	grid = GameGrid.new()
	grid.name = "GameGrid"
	add_child(grid)
	_apply_run_map(false)

	enemies = Node2D.new()
	enemies.name = "Enemies"
	add_child(enemies)

	projectiles = Node2D.new()
	projectiles.name = "Projectiles"
	add_child(projectiles)

	traps = Node2D.new()
	traps.name = "CommandTraps"
	add_child(traps)

	_map_camera = Camera2D.new()
	_map_camera.name = "MapCamera"
	_map_camera.enabled = false
	add_child(_map_camera)
	_range_overlay = _RangeOverlay.new()
	_range_overlay.z_index = 5
	add_child(_range_overlay)
	_sync_world_positions()
	_update_map_camera()


func _setup_systems() -> void:
	game_state = GameState.new()
	game_state.name = "GameState"
	game_state.difficulty = Session.difficulty
	game_state.game_mode = Session.game_mode
	game_state.monster_mode = Session.monster_mode
	game_state.map_layout_mode = Session.map_layout_mode
	game_state.run_seed = Session.run_seed
	game_state.current_map_seed = Session.current_map_seed
	game_state.tutorial_run = Session.tutorial_active
	if game_state.tutorial_run:
		game_state.mark_debug_used()
	add_child(game_state)
	# Re-apply map now that GameState exists so sector/seed labels stay in sync.
	_apply_run_map(false)

	pathfinder = Pathfinder.new(grid)

	build_system = BuildSystem.new()
	build_system.name = "BuildSystem"
	add_child(build_system)
	build_system.setup(grid, pathfinder, game_state, enemies, projectiles)

	wave_manager = WaveManager.new()
	wave_manager.name = "WaveManager"
	add_child(wave_manager)
	wave_manager.setup(grid, pathfinder, game_state, enemies)
	wave_manager.wave_started.connect(_on_wave_started)
	wave_manager.wave_cleared.connect(_on_wave_cleared)
	wave_manager.map_rotate_requested.connect(_on_map_rotate_requested)
	wave_manager.spawn_rotate_requested.connect(_on_spawn_rotate_requested)

	grid.tower_removed.connect(func(_c: Vector2i) -> void: wave_manager.repath_living_enemies())
	grid.tower_placed.connect(func(_c: Vector2i, t: Node) -> void:
		wave_manager.repath_living_enemies()
		_on_tower_placed_tutorial(t)
	)


func _setup_ui() -> void:
	hud = UIHud.new()
	add_child(hud)
	hud.setup(game_state, VersionInfo.current())
	hud.skip_timer_pressed.connect(_on_skip_timer)
	hud.sell_pressed.connect(_on_sell_selected)
	hud.deselect_pressed.connect(_on_deselect)
	hud.upgrade_pressed.connect(_on_upgrade_selected)
	hud.final_element_pressed.connect(_on_final_element_selected)
	hud.command_ability_pressed.connect(_on_command_ability_pressed)
	hud.tower_type_selected.connect(_on_tower_type_selected)
	hud.multi_select_changed.connect(func(on: bool) -> void:
		_multi_select_mode = on
		hud.set_status("Multi-select %s." % ("ON — tap towers to add/remove" if on else "OFF"))
	)
	build_system.selected_towers_changed.connect(_on_selected_towers_changed)
	build_system.selection_upgrade_changed.connect(hud.update_upgrade_buttons)
	hud.end_run_confirmed.connect(_on_end_run_confirmed)
	game_state.game_over.connect(_on_game_over_to_leaderboard)
	hud.pause_pressed.connect(_toggle_pause)
	wave_manager.timer_updated.connect(hud.update_timer)
	wave_manager.enemies_remaining_changed.connect(hud.update_enemies_remaining)
	wave_manager.skip_unlock_changed.connect(func(_u: bool) -> void: hud.set_skip_hint_ready())

	debug_panel = DebugPanel.new()
	add_child(debug_panel)
	debug_panel.debug_opened.connect(_mark_debug_used)
	debug_panel.add_gold_requested.connect(_debug_add_gold)
	debug_panel.add_lives_requested.connect(_debug_add_lives)
	debug_panel.set_wave_requested.connect(_debug_set_wave)
	debug_panel.send_wave_requested.connect(_debug_force_next_wave)
	debug_panel.clear_enemies_requested.connect(_debug_clear_enemies)
	debug_panel.god_mode_toggled.connect(_debug_god_mode)
	debug_panel.restart_requested.connect(restart_run)

	wave_manager.begin_run()
	hud.refresh_run_labels()
	_set_start_status()
	hud.update_timer(0.0, true, "prep")
	SoundHub.unlock()
	if WaveScaler.is_siege_mode(game_state.game_mode):
		SoundHub.set_music_context(SoundHub.MUSIC_GAME_SIEGE)
	else:
		SoundHub.set_music_context(SoundHub.MUSIC_GAME_STANDARD)
	if game_state.tutorial_run:
		_tutorial_step = 0
		_refresh_tutorial_status()


func _set_start_status() -> void:
	if WaveScaler.is_random_mode(game_state.game_mode):
		hud.set_status(
			"Random map %d (seed %d) — build a path, then Start Round." % [
				game_state.map_sector,
				game_state.current_map_seed,
			]
		)
	elif WaveScaler.is_siege_mode(game_state.game_mode):
		hud.set_status("Siege — defend the center. Drag (RMB/middle/blocked cell) to pan. Start Round when ready.")
	elif WaveScaler.is_custom_layout(game_state.map_layout_mode):
		hud.set_status(
			"Classic custom map (seed %d) — fixed all run. Build, then Start Round." % game_state.current_map_seed
		)
	elif _touch_ui:
		hud.set_status("Touch: drag to place, long-press tower to multi-select, then Start Round.")
	else:
		hud.set_status("Build your maze, then press Start Round.")


func _process(delta: float) -> void:
	_update_range_ring()
	_update_boss_hp_bar()
	if game_state.is_game_over:
		_paint_holding = false
		_paint_enabled = false
		_awaiting_tower_tap = false
		_panning = false
		hud.hide_board_tower_tooltip()
		return
	hud.tick_tooltips()
	var mouse := get_global_mouse_position()
	var local_map := _screen_to_map(mouse)

	if _panning:
		if (
			Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE)
			or Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
			or Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
		):
			var delta_screen := mouse - _pan_last_screen
			if delta_screen.length_squared() > 0.5:
				_pan_moved = true
				map_pan -= delta_screen / maxf(map_zoom, 0.05)
				_clamp_map_pan()
				_sync_world_positions()
				_update_map_camera()
				_pan_last_screen = mouse
		else:
			_panning = false
		return

	if _awaiting_tower_tap and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_press_hold_time += delta
		if mouse.distance_to(_press_start_pos) > TAP_MOVE_PX:
			_awaiting_tower_tap = false
			# Drag on a wall/tower pans large maps instead of eating the press.
			if _map_needs_pan():
				_begin_pan(mouse)
		elif _press_hold_time >= LONG_PRESS_SEC:
			_long_press_triggered = true
			_awaiting_tower_tap = false
			build_system.try_place_at(local_map, true)
			hud.set_status("Multi-select: %d tower(s). Long-press or Multi: On." % build_system.selection_count())
			var tower := grid.get_tower_at(grid.world_to_cell(local_map))
			if tower:
				hud.show_touch_tower_info(tower as Tower)

	# Desktop hover tooltips; on touch, info is tap/long-press driven.
	if not _touch_ui:
		var hovered_tower := build_system.update_hover(local_map)
		if hovered_tower != null and _is_on_board_view(mouse) and not _paint_holding and not _awaiting_tower_tap:
			hud.show_board_tower_tooltip_for(hovered_tower, mouse)
		elif not hud.is_tooltip_pinned():
			hud.hide_board_tower_tooltip()
	else:
		build_system.update_hover(local_map)

	if _paint_holding and _paint_enabled and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		if not _is_additive_select():
			_paint_place_at(local_map, false)


func _is_additive_select() -> bool:
	return (
		_multi_select_mode
		or Input.is_key_pressed(KEY_CTRL)
		or Input.is_key_pressed(KEY_SHIFT)
	)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		_handle_key(event as InputEventKey)
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton:
		_handle_mouse(event as InputEventMouseButton)
	elif event is InputEventScreenTouch:
		# Prefer mouse emulation path; still mark touch UI if a screen appears mid-session.
		_touch_ui = true


func _handle_key(event: InputEventKey) -> void:
	match event.keycode:
		KEY_F1, KEY_QUOTELEFT:
			debug_panel.toggle()
		KEY_G:
			_debug_add_gold(1000)
		KEY_L:
			_debug_add_lives(5)
		KEY_N:
			_debug_force_next_wave()
		KEY_K:
			_debug_clear_enemies()
		KEY_U:
			_on_upgrade_selected()
		KEY_ESCAPE:
			if _game_paused:
				_resume_from_pause()
			elif not _aim_ability_id.is_empty() or build_system.selection_count() > 0:
				_on_deselect()
			else:
				_toggle_pause()
		KEY_R:
			restart_run()


func _handle_mouse(event: InputEventMouseButton) -> void:
	if game_state.is_game_over:
		return

	var screen := get_global_mouse_position()

	if event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		if event.pressed and _is_on_board_view(screen) and _map_allows_zoom():
			var next_z := map_zoom + MAP_ZOOM_STEP if event.button_index == MOUSE_BUTTON_WHEEL_UP else map_zoom - MAP_ZOOM_STEP
			_set_map_zoom(next_z, screen)
			get_viewport().set_input_as_handled()
		return

	if event.button_index == MOUSE_BUTTON_MIDDLE:
		if event.pressed and _map_needs_pan() and _is_on_board_view(screen):
			_begin_pan(screen)
			get_viewport().set_input_as_handled()
		elif not event.pressed:
			_panning = false
		return

	if event.button_index == MOUSE_BUTTON_RIGHT:
		if event.pressed:
			if _map_needs_pan() and _is_on_board_view(screen):
				_begin_pan(screen)
				get_viewport().set_input_as_handled()
				return
			var local_map := _screen_to_map(screen)
			if not _aim_ability_id.is_empty() or _is_on_map(local_map) or build_system.selection_count() > 0:
				_on_deselect()
				get_viewport().set_input_as_handled()
		else:
			if _panning:
				var was_drag := _pan_moved
				_panning = false
				if not was_drag:
					_on_deselect()
				get_viewport().set_input_as_handled()
		return

	if event.button_index != MOUSE_BUTTON_LEFT:
		return

	if not event.pressed:
		if _panning:
			_panning = false
		_finish_pointer_press()
		return

	if not _is_on_board_view(screen):
		# Tap outside the board clears selection on touch devices.
		if _touch_ui and (build_system.selection_count() > 0 or not _aim_ability_id.is_empty()):
			_on_deselect()
			get_viewport().set_input_as_handled()
		return
	get_viewport().set_input_as_handled()

	var local_map := _screen_to_map(screen)
	if not _aim_ability_id.is_empty():
		_resolve_command_aim(local_map)
		return

	# Pan from blocked / occupied cells when the map is larger than the view.
	if _map_needs_pan() and _can_start_pan_at(local_map) and not _is_additive_select():
		_begin_pan(screen)
		return

	var additive := event.ctrl_pressed or event.shift_pressed or _multi_select_mode
	_paint_holding = true
	_last_paint_cell = Vector2i(-999, -999)
	_press_start_pos = screen
	_press_hold_time = 0.0
	_long_press_triggered = false

	var cell := grid.world_to_cell(local_map)
	var existing = grid.get_tower_at(cell)

	# Tower press: wait for short-tap vs long-press (multi-select).
	if existing != null and not (TowerData.is_wall(existing.tower_id) and not TowerData.is_wall(build_system.selected_tower_id) and build_system.can_place_at(cell)):
		if additive:
			_paint_enabled = false
			_awaiting_tower_tap = false
			build_system.try_place_at(local_map, true)
			hud.set_status("Selection: %d tower(s)." % build_system.selection_count())
			hud.show_touch_tower_info(existing as Tower)
			return
		_awaiting_tower_tap = true
		_paint_enabled = false
		return

	_awaiting_tower_tap = false

	# Ctrl/Shift / Multi mode on empty = no paint.
	if additive:
		_paint_enabled = false
		return

	var placed := _paint_place_at(local_map, true)
	_paint_enabled = placed
	if not placed:
		var count := build_system.selection_count()
		if count > 0 and existing == null:
			# Empty failed cell while something is selected → deselect (touch-friendly).
			_on_deselect()
		elif not game_state.can_afford(int(TowerData.get_def(build_system.selected_tower_id)["cost"])):
			hud.set_status("Not enough gold.")
		elif pathfinder.would_block_path(cell):
			hud.set_status("Can't place there — would block the path.")
		else:
			hud.set_status("Can't place there.")


func _finish_pointer_press() -> void:
	var local_map := _screen_to_map(get_global_mouse_position())
	if _awaiting_tower_tap and not _long_press_triggered and _is_on_map(local_map):
		build_system.try_place_at(local_map, false)
		var cell := grid.world_to_cell(local_map)
		var tower = grid.get_tower_at(cell)
		var count := build_system.selection_count()
		if tower:
			hud.set_status("Selected %d. Long-press or Multi: On to multi-select." % maxi(count, 1))
			hud.show_touch_tower_info(tower as Tower)
	_awaiting_tower_tap = false
	_long_press_triggered = false
	_paint_holding = false
	_paint_enabled = false
	_last_paint_cell = Vector2i(-999, -999)
	_press_hold_time = 0.0


func _screen_to_map(screen: Vector2) -> Vector2:
	return (screen - map_offset) / maxf(map_zoom, 0.05) + map_pan


func _is_on_board_view(screen: Vector2) -> bool:
	var local_view := screen - map_offset
	if local_view.x < 0.0 or local_view.y < 0.0:
		return false
	var view := GameLayout.board_view_size(grid.map_pixel_size())
	return local_view.x <= view.x and local_view.y <= view.y


func _is_on_map(local_map: Vector2) -> bool:
	if local_map.x < 0.0 or local_map.y < 0.0:
		return false
	var size := grid.map_pixel_size()
	return local_map.x <= size.x and local_map.y <= size.y


func _is_on_board(local_map: Vector2) -> bool:
	## Back-compat name: map-space bounds.
	return _is_on_map(local_map)


func _map_oversized_at_native() -> bool:
	if grid == null:
		return false
	var map_size := grid.map_pixel_size()
	var view := GameLayout.board_view_size(map_size)
	return map_size.x > view.x + 1.0 or map_size.y > view.y + 1.0


func _map_allows_zoom() -> bool:
	return map_zoom < 0.999 or _map_oversized_at_native()


func _min_map_zoom() -> float:
	if grid == null:
		return 1.0
	var map_size := grid.map_pixel_size()
	var view := GameLayout.board_view_size(map_size)
	if map_size.x <= 1.0 or map_size.y <= 1.0:
		return 1.0
	return minf(1.0, minf(view.x / map_size.x, view.y / map_size.y))


func _visible_map_extent() -> Vector2:
	var map_size := grid.map_pixel_size() if grid else Vector2.ZERO
	var view := GameLayout.board_view_size(map_size)
	return view / maxf(map_zoom, 0.05)


func _set_map_zoom(z: float, anchor_screen: Vector2) -> void:
	var old_z := maxf(map_zoom, 0.05)
	var new_z := clampf(z, _min_map_zoom(), 1.0)
	if is_equal_approx(old_z, new_z):
		return
	var local_view := anchor_screen - map_offset
	var map_pos := local_view / old_z + map_pan
	map_zoom = new_z
	map_pan = map_pos - local_view / maxf(new_z, 0.05)
	_clamp_map_pan()
	_sync_world_positions()
	_update_map_camera()


func _map_needs_pan() -> bool:
	if grid == null:
		return false
	var map_size := grid.map_pixel_size()
	var visible := _visible_map_extent()
	return map_size.x > visible.x + 1.0 or map_size.y > visible.y + 1.0


func _can_start_pan_at(local_map: Vector2) -> bool:
	## Immediate left-press pan only from non-buildable chrome (rocks / spawn / exit / off-map).
	## Walls and towers must not steal the press — place-over-wall and select need the click.
	if not _is_on_map(local_map):
		return true
	var cell := grid.world_to_cell(local_map)
	if not grid.in_bounds(cell):
		return true
	if cell == grid.spawn_cell or cell == grid.exit_cell:
		return true
	if grid.get_tile(cell) == GameGrid.Tile.BLOCKED:
		return true
	return false


func _begin_pan(screen: Vector2) -> void:
	_panning = true
	_pan_moved = false
	_pan_last_screen = screen
	_paint_holding = false
	_paint_enabled = false
	_awaiting_tower_tap = false


func _clamp_map_pan() -> void:
	var map_size := grid.map_pixel_size()
	var visible := _visible_map_extent()
	var max_pan := Vector2(maxf(0.0, map_size.x - visible.x), maxf(0.0, map_size.y - visible.y))
	map_pan.x = clampf(map_pan.x, 0.0, max_pan.x)
	map_pan.y = clampf(map_pan.y, 0.0, max_pan.y)


func _sync_world_positions() -> void:
	map_offset = GameLayout.board_origin()
	var world_pos := map_offset - map_pan * map_zoom
	var sc := Vector2(map_zoom, map_zoom)
	if grid:
		grid.position = world_pos
		grid.scale = sc
	if enemies:
		enemies.position = world_pos
		enemies.scale = sc
	if projectiles:
		projectiles.position = world_pos
		projectiles.scale = sc
	if traps:
		traps.position = world_pos
		traps.scale = sc


func _update_map_camera() -> void:
	if _map_camera == null:
		return
	# Keep Camera2D disabled — HUD is CanvasLayer; world pan/zoom uses offsets + scale.
	_map_camera.enabled = false
	var view := GameLayout.board_view_size(grid.map_pixel_size() if grid else Vector2.ZERO)
	_map_camera.position = map_offset + view * 0.5 + map_pan * map_zoom


func _focus_camera_on_spawn_exit() -> void:
	if grid == null or not _map_needs_pan():
		map_pan = Vector2.ZERO
		_clamp_map_pan()
		_sync_world_positions()
		_update_map_camera()
		return
	var mid := (grid.cell_to_world_center(grid.spawn_cell) + grid.cell_to_world_center(grid.exit_cell)) * 0.5
	var visible := _visible_map_extent()
	map_pan = mid - visible * 0.5
	_clamp_map_pan()
	_sync_world_positions()
	_update_map_camera()


func _paint_place_at(local_map: Vector2, show_status: bool) -> bool:
	if not _is_on_board(local_map):
		return false
	var cell := grid.world_to_cell(local_map)
	if cell == _last_paint_cell:
		return false
	var had_wall := false
	var existing = grid.get_tower_at(cell)
	if existing and TowerData.is_wall(existing.tower_id):
		had_wall = true
	if not build_system.can_place_at(cell):
		# Mark empty invalid cells so we don't spam attempts while held.
		if existing == null:
			_last_paint_cell = cell
		return false
	if build_system.try_place_at(local_map, false):
		_last_paint_cell = cell
		if show_status:
			if had_wall and not TowerData.is_wall(build_system.selected_tower_id):
				hud.set_status("Tower built over wall. Hold-drag to continue.")
			else:
				hud.set_status("Hold and drag to place more.")
		return true
	return false


func _on_tower_type_selected(tower_id: String) -> void:
	build_system.select_tower_type(tower_id)
	var def := TowerData.get_def(tower_id)
	var name := str(def.get("display_name", tower_id))
	hud.set_status("Placing %s. Sell a tower before building over it." % name)


func _on_sell_selected() -> void:
	var count := build_system.selection_count()
	var refund := build_system.selection_sell_total()
	if build_system.sell_selected():
		hud.set_status("Sold %d tower(s) for %d gold." % [count, refund])
	else:
		hud.set_status("Nothing selected to sell.")


func _on_deselect() -> void:
	var had_aim := not _aim_ability_id.is_empty()
	_clear_command_aim()
	if build_system.selection_count() <= 0:
		hud.set_status("Aim cancelled." if had_aim else "Nothing selected.")
		return
	build_system.clear_selection()
	hud.set_status("Aim cancelled." if had_aim else "Selection cleared.")


func _on_selected_towers_changed(count: int, sell_total: int) -> void:
	hud.update_sell_button(count, sell_total)
	var cmd: Tower = null
	if count == 1 and build_system.selected_towers.size() == 1:
		var t: Tower = build_system.selected_towers[0]
		if is_instance_valid(t) and TowerData.is_command(t.tower_id):
			cmd = t
	hud.update_command_abilities(cmd)
	if not _aim_ability_id.is_empty():
		if cmd == null or cmd != _aim_command_tower:
			_clear_command_aim()


func _on_command_ability_pressed(ability_id: String) -> void:
	if game_state.is_game_over:
		return
	if build_system.selection_count() != 1:
		hud.set_status("Select a single Command tower first.")
		return
	var tower: Tower = build_system.selected_towers[0]
	if tower == null or not is_instance_valid(tower) or not TowerData.is_command(tower.tower_id):
		hud.set_status("Select a Command tower to use abilities.")
		return
	var def := CommandAbilities.get_def(ability_id)
	if def.is_empty():
		return
	var cost := CommandAbilities.cost(ability_id)
	if tower.ability_cooldown_left(ability_id) > 0.05:
		hud.set_status("%s is cooling down." % CommandAbilities.display_name(ability_id))
		return
	if not game_state.can_afford(cost):
		hud.set_status("Need %d gold for %s." % [cost, CommandAbilities.display_name(ability_id)])
		return
	_aim_ability_id = ability_id
	_aim_command_tower = tower
	var aim := CommandAbilities.aim_mode(ability_id)
	if CommandAbilities.is_trap(ability_id):
		hud.set_status(
			"Place %s trap (%dg) — click a %s. Esc/right-click cancels." % [
				CommandAbilities.display_name(ability_id),
				cost,
				"path tile" if aim == "path" else "board tile",
			]
		)
	elif aim == "path":
		hud.set_status(
			"Aim %s (%dg) — click a path tile. Esc/right-click cancels." % [
				CommandAbilities.display_name(ability_id),
				cost,
			]
		)
	else:
		hud.set_status(
			"Place %s (%dg) — click near your towers. Esc/right-click cancels." % [
				CommandAbilities.display_name(ability_id),
				cost,
			]
		)


func _resolve_command_aim(local_map: Vector2) -> void:
	var ability_id := _aim_ability_id
	var tower := _aim_command_tower
	if ability_id.is_empty() or tower == null or not is_instance_valid(tower):
		_clear_command_aim()
		hud.set_status("Ability aim cancelled.")
		return
	var cost := CommandAbilities.cost(ability_id)
	if tower.ability_cooldown_left(ability_id) > 0.05:
		_clear_command_aim()
		hud.set_status("%s is cooling down." % CommandAbilities.display_name(ability_id))
		return
	if not game_state.can_afford(cost):
		_clear_command_aim()
		hud.set_status("Need %d gold for %s." % [cost, CommandAbilities.display_name(ability_id)])
		return
	var cell := grid.world_to_cell(local_map)
	var result := CommandCaster.place(ability_id, cell, grid, pathfinder, enemies, traps)
	if not bool(result.get("ok", false)):
		hud.set_status(str(result.get("message", "Can't place there.")))
		return
	if not game_state.spend_gold(cost):
		# Roll back a just-created trap if gold somehow failed.
		var trap = result.get("trap", null)
		if trap != null and is_instance_valid(trap):
			trap.queue_free()
		_clear_command_aim()
		hud.set_status("Not enough gold.")
		return
	tower.start_ability_cooldown(ability_id, CommandAbilities.cooldown(ability_id))
	game_state.record_spend(cost)
	if ability_id == "supplydrop":
		game_state.supply_drop_used = true
	if ability_id == "airstrike":
		game_state.airstrike_trap_hit = true
	_clear_command_aim()
	hud.update_command_abilities(tower)
	hud.set_status("%s (-%d gold). %s" % [
		CommandAbilities.display_name(ability_id),
		cost,
		str(result.get("message", "")),
	])


func _clear_command_aim() -> void:
	_aim_ability_id = ""
	_aim_command_tower = null


func _on_upgrade_selected() -> void:
	var result := build_system.upgrade_selected()
	var upgraded: int = int(result.get("upgraded", 0))
	var spent: int = int(result.get("spent", 0))
	var failed: int = int(result.get("failed_afford", 0))
	if upgraded > 0:
		hud.set_status("Upgraded %d tower(s) (-%d gold).%s" % [
			upgraded,
			spent,
			" Not enough gold for %d." % failed if failed > 0 else "",
		])
	elif failed > 0:
		hud.set_status("Not enough gold to upgrade.")
	else:
		hud.set_status("Select towers under +3 to upgrade (walls can't upgrade).")


func _on_final_element_selected(element_id: String) -> void:
	var result := build_system.apply_final_selected(element_id)
	var applied: int = int(result.get("applied", 0))
	var spent: int = int(result.get("spent", 0))
	var failed: int = int(result.get("failed_afford", 0))
	var label := TowerData.final_element_label(element_id)
	if applied > 0:
		hud.set_status("Final %s on %d tower(s) (-%d gold).%s" % [
			label,
			applied,
			spent,
			" Not enough gold for %d." % failed if failed > 0 else "",
		])
	elif failed > 0:
		hud.set_status("Not enough gold for final %s." % label)
	else:
		hud.set_status("Need +3 upgrades before choosing a final elemental buff.")


func _on_skip_timer() -> void:
	if wave_manager.phase == WaveManager.Phase.PREP:
		if wave_manager.start_round():
			if game_state.tutorial_run and _tutorial_step == 2:
				_tutorial_step = 3
				_refresh_tutorial_status()
			hud.set_status("Round started — build timer running, then waves begin.")
		else:
			hud.set_status("Keep a path open from spawn to exit, then Start Round.")
		return
	if wave_manager.phase == WaveManager.Phase.WAVE:
		if wave_manager.try_skip_timer():
			var bonus := wave_manager.last_early_send_bonus
			if bonus > 0:
				hud.set_status("Early send — next wave incoming (+%d gold)." % bonus)
			else:
				hud.set_status("Early send — next wave incoming.")
		elif not wave_manager.skip_unlocked:
			hud.set_status("Kill 25% of enemies to unlock Send Next Wave.")
		elif not wave_manager.has_open_path():
			hud.set_status("Can't early-send — keep a path open spawn to exit.")
		else:
			hud.set_status("Can't early-send right now.")
		return
	if wave_manager.try_skip_timer():
		var bonus := wave_manager.last_early_send_bonus
		if bonus > 0:
			hud.set_status("Timer skipped — wave starting (+%d gold)." % bonus)
		else:
			hud.set_status("Timer skipped — wave starting.")
	elif wave_manager.phase == WaveManager.Phase.INTERMISSION:
		if not wave_manager.skip_unlocked:
			hud.set_status("Can't skip — unlock was not earned.")
		elif not wave_manager.can_send_wave():
			hud.set_status("Can't skip — keep a path open spawn to exit.")
		else:
			hud.set_status("Can't skip right now.")
	else:
		hud.set_status("No timer to skip right now.")


func _on_wave_started(wave: int, banner: String) -> void:
	hud.set_banner(banner)
	# Banner lives in the top bar; keep status short so text doesn't stack/overlap.
	hud.set_status("Wave %d started." % wave)


func _on_wave_cleared(wave: int, kills: int, bonus_gold: int) -> void:
	if game_state.tutorial_run and wave >= 1:
		_finish_tutorial()
		return
	hud.set_banner("")
	if WaveScaler.should_rotate_map_after_wave(game_state.game_mode, wave):
		# Full-clear rotate is handled by map_rotate_requested; early-send waits until the board empties.
		if wave_manager.pending_map_rotate_wave > 0:
			hud.set_status("Wave %d sector goal hit — clear the board for a new map." % wave)
		return
	if WaveScaler.should_rotate_spawn_after_wave(game_state.game_mode, wave):
		# Status set in _on_spawn_rotate_requested; keep a short clear line if rotate failed silently.
		return
	if bonus_gold > 0:
		hud.set_status("Wave %d cleared — %d kills, +%d bonus gold. Next wave on timer." % [wave, kills, bonus_gold])
	else:
		hud.set_status("Wave %d cleared — %d kills. Next wave on timer." % [wave, kills])


func _on_map_rotate_requested(wave: int) -> void:
	var kills_on_map := game_state.kills_this_map
	var carry_gold := WaveScaler.map_rotate_gold(game_state.difficulty, kills_on_map)
	for child in projectiles.get_children():
		child.queue_free()
	_clear_command_traps()
	wave_manager.clear_enemies()
	game_state.begin_next_map_sector(carry_gold)
	_apply_run_map(true)
	build_system.refresh_after_reset()
	build_system.select_tower_type("gunner")
	hud.highlight_tower("gunner")
	hud.set_banner("")
	hud.refresh_run_labels()
	wave_manager.begin_run()
	hud.update_timer(0.0, true, "prep")
	hud.set_status(
		"Map %d (seed %d) — wave %d sector cleared (%d kills → %d gold). Rebuild, then Start Round." % [
			game_state.map_sector,
			game_state.current_map_seed,
			wave,
			kills_on_map,
			carry_gold,
		]
	)


func _on_spawn_rotate_requested(wave: int) -> void:
	if grid == null or pathfinder == null:
		return
	var ok := grid.relocate_rim_spawn(pathfinder)
	wave_manager.invalidate_ground_path()
	wave_manager.repath_living_enemies()
	build_system.refresh_after_reset()
	_focus_camera_on_spawn_exit()
	if ok:
		hud.set_status("Wave %d cleared — entry moved to a new rim. Path must stay open to the center." % wave)
	else:
		hud.set_status("Wave %d cleared — could not move entry (path sealed). Sell towers to reopen." % wave)


func _apply_run_map(new_random: bool) -> void:
	if grid == null:
		return
	var mode := Session.game_mode if game_state == null else game_state.game_mode
	var layout_mode := Session.map_layout_mode if game_state == null else game_state.map_layout_mode
	if WaveScaler.is_siege_mode(mode):
		if new_random or not grid.is_siege_layout:
			grid.reset_siege()
		Session.current_map_seed = -1
	elif WaveScaler.is_random_mode(mode):
		if Session.run_seed < 0:
			Session.run_seed = WaveScaler.resolve_run_seed(-1)
		var sector := 1
		if game_state != null:
			sector = maxi(game_state.map_sector, 1)
		var layout_seed := WaveScaler.sector_seed(Session.run_seed, sector)
		if new_random or not grid.is_random_layout or grid.last_layout_seed != layout_seed:
			grid.reset(false, layout_seed)
		Session.current_map_seed = grid.last_layout_seed
	elif WaveScaler.is_custom_layout(layout_mode):
		if Session.run_seed < 0:
			Session.run_seed = WaveScaler.resolve_run_seed(-1)
		if new_random or not grid.is_random_layout or grid.last_layout_seed != Session.run_seed:
			grid.reset(false, Session.run_seed)
		Session.current_map_seed = grid.last_layout_seed
		Session.run_seed = Session.current_map_seed
	else:
		grid.reset(true)
		Session.current_map_seed = -1
	if game_state != null:
		game_state.set_map_seeds(Session.run_seed, Session.current_map_seed, layout_mode)
	if pathfinder != null:
		pathfinder.sync_region()
		pathfinder.rebuild()
	map_pan = Vector2.ZERO
	map_zoom = 1.0
	_sync_world_positions()
	if WaveScaler.is_siege_mode(mode):
		_focus_camera_on_spawn_exit()
	else:
		_update_map_camera()
	if hud != null:
		hud.refresh_run_labels()


func _mark_debug_used() -> void:
	game_state.mark_debug_used()
	hud.set_status("Debug used — this run can't be saved to the leaderboard.")


func _debug_add_gold(amount: int) -> void:
	_mark_debug_used()
	game_state.add_gold(amount)


func _debug_add_lives(amount: int) -> void:
	_mark_debug_used()
	game_state.lives += amount
	game_state.lives_changed.emit(game_state.lives)


func _debug_set_wave(wave_number: int) -> void:
	_mark_debug_used()
	wave_manager.jump_to_wave(wave_number)
	hud.set_banner("")
	hud.set_status("Jumped — next wave soon (skip available). Debug run: no leaderboard.")


func _debug_force_next_wave() -> void:
	_mark_debug_used()
	if wave_manager.force_next_wave():
		hud.set_status("Debug: forced next wave (no leaderboard this run).")
	else:
		hud.set_status("Debug: can't force wave — keep a path open spawn to exit.")


func _debug_clear_enemies() -> void:
	_mark_debug_used()
	wave_manager.clear_enemies()
	hud.set_banner("")
	wave_manager.force_intermission(WaveScaler.INTERMISSION_TIME, true)
	hud.set_status("Enemies cleared — intermission started. Debug run: no leaderboard.")


func _debug_god_mode(enabled: bool) -> void:
	_mark_debug_used()
	game_state.god_mode = enabled
	debug_panel.set_god_mode_ui(enabled)


func _on_end_run_confirmed() -> void:
	if game_state == null or game_state.is_game_over:
		return
	var wave_reached := maxi(game_state.wave, game_state.highest_wave)
	game_state.is_game_over = true
	wave_manager.clear_enemies()
	for child in projectiles.get_children():
		child.queue_free()
	if game_state.debug_used:
		hud.set_status("Run ended — debug used, leaderboard entry blocked.")
	else:
		hud.set_status("Run ended — checking leaderboard for wave %d..." % wave_reached)
	call_deferred("_boot_leaderboard", wave_reached)


func _on_game_over_to_leaderboard(wave_reached: int) -> void:
	if game_state.debug_used:
		hud.set_status("Game over — debug used, leaderboard entry blocked.")
	else:
		hud.set_status("Game over — loading leaderboard...")
	wave_manager.phase = WaveManager.Phase.PREP
	call_deferred("_boot_leaderboard", wave_reached)


func _boot_leaderboard(wave_reached: int) -> void:
	_pending_leaderboard_wave = wave_reached
	_show_run_summary(wave_reached)


func _show_run_summary(wave_reached: int) -> void:
	SoundHub.play_game_over()
	var new_best: bool = _PlayerStats.try_update_best(game_state.difficulty, wave_reached)
	var stats := game_state.run_stats_dictionary()
	for aid in _Achievements.check_run_end(game_state, stats):
		if _AchievementStore.unlock(aid):
			SoundHub.play_achievement()
	var coaching := {
		"new_best": new_best,
		"coaching_text": _RunSummaryOverlay.build_coaching_text(game_state),
		"screenshot_cb": _save_maze_screenshot,
	}
	if debug_panel:
		debug_panel.visible = false
	if build_system:
		build_system.clear_selection()
	if _range_overlay:
		_range_overlay.show_ring = false
		_range_overlay.queue_redraw()
	var summary: Control = _RunSummaryOverlay.new()
	summary.show_summary(game_state, coaching)
	hud.attach_run_summary(summary)
	summary.continued.connect(func() -> void:
		if game_state.tutorial_run:
			UserSettings.set_tutorial_completed(true)
			Session.tutorial_active = false
			Session.go_menu()
			return
		Session.go_leaderboard(
			wave_reached,
			game_state.debug_used or game_state.tutorial_run,
			game_state.difficulty,
			game_state.seeds_for_leaderboard()
		)
	)


func _toggle_pause() -> void:
	if game_state.is_game_over:
		return
	if _game_paused:
		_resume_from_pause()
	else:
		_open_pause_menu()


func _open_pause_menu() -> void:
	if _pause_menu != null and is_instance_valid(_pause_menu):
		return
	_game_paused = true
	wave_manager.game_paused = true
	get_tree().paused = true
	SoundHub.set_paused_duck(true)
	_pause_menu = _PauseMenuOverlay.new()
	_pause_menu.process_mode = Node.PROCESS_MODE_ALWAYS
	var next_w := game_state.wave + 1 if wave_manager.phase != WaveManager.Phase.WAVE else game_state.wave
	_pause_menu.setup(
		_WavePreview.timeline_text(next_w, 8, game_state.game_mode),
		_RunSummaryOverlay.seed_clipboard_text(game_state)
	)
	hud.attach_pause_menu(_pause_menu)
	_pause_menu.resume_requested.connect(_resume_from_pause)
	_pause_menu.quit_to_menu_requested.connect(_quit_to_menu_from_pause)
	_pause_menu.screenshot_requested.connect(_save_maze_screenshot)
	_pause_menu.open_settings_requested.connect(_open_pause_settings_stub)


func _resume_from_pause() -> void:
	_game_paused = false
	wave_manager.game_paused = false
	get_tree().paused = false
	SoundHub.set_paused_duck(false)
	if _pause_menu != null and is_instance_valid(_pause_menu):
		_pause_menu.queue_free()
	_pause_menu = null


func _quit_to_menu_from_pause() -> void:
	_resume_from_pause()
	Session.tutorial_active = false
	Session.go_menu()


func _open_pause_settings_stub() -> void:
	hud.set_status("Adjust settings from the main menu; pause keeps your run on screen.")


func _save_maze_screenshot() -> void:
	var seed_part := game_state.current_map_seed if game_state.current_map_seed >= 0 else 0
	var fname := "wave-defence-seed-%d-wave-%d.png" % [seed_part, game_state.wave]
	var path: String = _BoardScreenshot.save_from_viewport(self, fname)
	if path != "":
		hud.set_status("Saved maze image to %s" % path)
	else:
		hud.set_status("Could not save image.")


func _update_range_ring() -> void:
	if _range_overlay == null or grid == null:
		return
	if not UserSettings.is_show_tower_range():
		_range_overlay.show_ring = false
		_range_overlay.queue_redraw()
		return
	var range_px := 0.0
	var center := Vector2.ZERO
	var sel := build_system.selected_tower_id if build_system else ""
	if sel != "" and not TowerData.is_wall(sel):
		var def := TowerData.get_def(sel)
		range_px = float(def.get("range", 0)) * grid.tile_px()
		center = grid.cell_to_world_center(grid.hover_cell) if grid.in_bounds(grid.hover_cell) else Vector2.ZERO
	elif build_system.selection_count() == 1:
		for t in build_system.selected_towers:
			if is_instance_valid(t):
				var tdef := TowerData.get_def(t.tower_id)
				range_px = float(tdef.get("range", 0)) * grid.tile_px()
				center = t.position
				break
	_range_overlay.show_ring = range_px > 0.0
	_range_overlay.center = center
	_range_overlay.radius = range_px
	_range_overlay.queue_redraw()


func _update_boss_hp_bar() -> void:
	if hud == null or enemies == null:
		return
	var best: Enemy = null
	var best_prog := -1.0
	for c in enemies.get_children():
		if c is Enemy:
			var e := c as Enemy
			if not e.alive:
				continue
			if not e.is_boss and not (e.is_snake and e.snake_index == 0):
				continue
			var prog := e.path_progress()
			if best == null or prog > best_prog:
				best = e
				best_prog = prog
	if best == null:
		hud.update_boss_hp("", 0.0, false)
		return
	var name := "Snake" if best.is_snake else ("Flying boss" if best.is_flying else "Boss")
	hud.update_boss_hp(name, best.hp / maxf(best.max_hp, 1.0), true)


func _on_tower_placed_tutorial(t: Node) -> void:
	if not game_state.tutorial_run:
		return
	if not t is Tower:
		return
	var tower := t as Tower
	if _tutorial_step == 0 and TowerData.is_wall(tower.tower_id):
		_tutorial_step = 1
		_refresh_tutorial_status()
	elif _tutorial_step == 1 and not TowerData.is_wall(tower.tower_id):
		_tutorial_step = 2
		_refresh_tutorial_status()


func _refresh_tutorial_status() -> void:
	match _tutorial_step:
		0:
			hud.set_status("Tutorial: place a Wall on the path.")
		1:
			hud.set_status("Tutorial: place any combat tower on that wall.")
		2:
			hud.set_status("Tutorial: press Start Round.")
		_:
			hud.set_status("Tutorial: clear wave 1. Skip tutorial in the status area anytime.")


func _finish_tutorial() -> void:
	UserSettings.set_tutorial_completed(true)
	Session.tutorial_active = false
	game_state.is_game_over = true
	hud.set_status("Tutorial complete!")
	call_deferred("_show_run_summary", 1)


func _clear_command_traps() -> void:
	if traps == null:
		return
	for child in traps.get_children():
		child.queue_free()


func restart_run() -> void:
	for child in projectiles.get_children():
		child.queue_free()
	_clear_command_traps()
	game_state.reset_run(Session.difficulty, Session.game_mode, Session.monster_mode)
	game_state.map_layout_mode = Session.map_layout_mode
	game_state.run_seed = Session.run_seed
	game_state.current_map_seed = Session.current_map_seed
	_apply_run_map(true)
	build_system.refresh_after_reset()
	hud.set_banner("")
	hud.highlight_tower("gunner")
	build_system.select_tower_type("gunner")
	hud.refresh_run_labels()
	wave_manager.begin_run()
	_set_start_status()
	hud.update_timer(0.0, true, "prep")
