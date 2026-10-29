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
var clash_match: ClashMatch = null
var _clash_bots: Array = [] ## ClashBotAI
var _clash_result_place: int = 0
var _clash_human_won: bool = false
var _clash_bot_send_cd: float = 0.0
## Online Clash (6-digit code): one of these runs, depending on this device's role.
var _net_host: ClashNetHost = null
var _net_client: ClashNetClient = null
## Shown in the match summary when an online match ends early (the host left).
var _online_end_note: String = ""

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
var _pan_mode: bool = false
## Command tower pay-per-use aim mode.
var _aim_ability_id: String = ""
var _aim_command_tower: Tower = null
## Clicked mob for inspect tooltip (name / HP / bounty).
var _inspected_enemy: Enemy = null
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
	wave_manager.tower_wrecked.connect(_on_clash_tower_wrecked)
	if Net.is_client():
		# The host's game spawns and moves enemies; this device only shows them.
		wave_manager.process_mode = Node.PROCESS_MODE_DISABLED

	_setup_clash_match()

	grid.tower_removed.connect(func(_c: Vector2i) -> void: wave_manager.repath_living_enemies())
	grid.tower_placed.connect(func(_c: Vector2i, t: Node) -> void:
		wave_manager.repath_living_enemies()
		_on_tower_placed_tutorial(t)
	)


func _setup_clash_match() -> void:
	_clash_bots.clear()
	if clash_match != null and is_instance_valid(clash_match):
		clash_match.queue_free()
	clash_match = null
	if not WaveScaler.is_clash_mode(Session.game_mode):
		return
	clash_match = ClashMatch.new()
	clash_match.name = "ClashMatch"
	add_child(clash_match)
	if _online():
		clash_match.setup_online(game_state, Net.seats, Net.my_seat())
		clash_match.player_eliminated.connect(_on_online_player_eliminated)
	else:
		clash_match.setup(game_state, Session.clash_player_count, Session.clash_bot_difficulties)
	wave_manager.set_clash_match(clash_match)
	build_system.set_clash_match(clash_match, clash_match.human_id)
	clash_match.match_over.connect(_on_clash_match_over)
	clash_match.players_changed.connect(_on_clash_players_changed)
	for p in clash_match.players:
		var cp := p as ClashPlayerState
		if cp == null or cp.is_human or cp.is_remote or Net.is_client():
			continue
		_add_clash_bot(cp.player_id)
	# GameState is the human wallet during play — seed it, then mirror into ClashPlayerState.
	game_state.gold = WaveScaler.clash_starting_gold()
	game_state.lives = WaveScaler.CLASH_STARTING_LIVES
	clash_match.sync_human_gold_from_game_state()


func _add_clash_bot(player_id: int) -> void:
	var bot := ClashBotAI.new()
	bot.setup(clash_match, grid, pathfinder, enemies, projectiles, traps, player_id)
	_clash_bots.append(bot)


## Online Clash match in progress on this device (host or joined player).
func _online() -> bool:
	return Net.in_match() and WaveScaler.is_clash_mode(Session.game_mode)


func _setup_online() -> void:
	if not _online() or clash_match == null:
		return
	Net.ended.connect(_on_online_session_ended)
	if Net.is_host():
		_net_host = ClashNetHost.new()
		_net_host.name = "ClashNetHost"
		add_child(_net_host)
		_net_host.setup(self)
		_net_host.bot_needed.connect(func(player_id: int) -> void:
			_add_clash_bot(player_id)
			_run_clash_bots()
		)
	else:
		_net_client = ClashNetClient.new()
		_net_client.name = "ClashNetClient"
		add_child(_net_client)
		_net_client.setup(self)
		_net_client.match_finished.connect(_on_online_match_finished)
	refresh_online_round_button()


## Online Clash: the Start Round / Skip Timer button. Joined players press it to
## say they're ready; the host can start once everyone is ready.
func refresh_online_round_button() -> void:
	if not _online() or wave_manager == null or game_state.is_game_over:
		return
	var between_waves := wave_manager.phase != WaveManager.Phase.WAVE
	if Net.is_client():
		if not between_waves:
			hud.set_skip_button_state("Wave running", true, "The host starts each round")
		elif Net.is_ready(Net.my_id):
			hud.set_skip_button_state("Ready ✓", false, "Tap to cancel Ready")
		else:
			hud.set_skip_button_state("Ready", false, "Tell the host you're ready for the next round")
		return
	if not between_waves or Net.guest_ids().is_empty():
		return
	var guests := Net.guest_ids().size()
	var ready := guests - Net.waiting_on_names().size()
	if ready < guests:
		var label := "Start Round" if wave_manager.phase == WaveManager.Phase.PREP else "Skip Timer"
		hud.set_skip_button_state(
			"%s (%d/%d ready)" % [label, ready, guests], false, "Waits for every player to press Ready"
		)


func _on_online_player_eliminated(player_id: int) -> void:
	if clash_match == null or clash_match.finished or player_id != clash_match.human_id:
		return
	var me := clash_match.human()
	hud.set_status(
		"You're out (#%d). Watching until the match ends — leave anytime from the pause menu." % maxi(me.place, 2)
	)


## Joined player: the host says the match is over.
func _on_online_match_finished(winner_id: int) -> void:
	var me := clash_match.human()
	var won := me != null and winner_id == me.player_id
	clash_match.finished = true
	_on_clash_match_over(winner_id, won, 1 if won else maxi(me.place if me else 0, 2))
	if not game_state.is_game_over:
		game_state.is_game_over = true
		game_state.game_over.emit(game_state.highest_wave)


## The connection ended mid-match (host left, internet dropped…).
func _on_online_session_ended(reason: String) -> void:
	if reason.is_empty() or game_state == null or game_state.is_game_over:
		return
	_online_end_note = reason
	_clash_human_won = false
	_clash_result_place = 0
	game_state.is_game_over = true
	wave_manager.clear_enemies()
	hud.set_status(reason)
	call_deferred("_boot_clash_summary", maxi(game_state.wave, game_state.highest_wave))


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
	hud.pan_mode_changed.connect(func(on: bool) -> void:
		_pan_mode = on
		if on:
			hud.set_status("Pan mode — drag the map. Tap Pan again (or pick a tower) to place.")
	)
	build_system.selected_towers_changed.connect(_on_selected_towers_changed)
	build_system.selection_upgrade_changed.connect(hud.update_upgrade_buttons)
	hud.end_run_confirmed.connect(_on_end_run_confirmed)
	game_state.game_over.connect(_on_game_over_to_leaderboard)
	hud.pause_pressed.connect(_toggle_pause)
	hud.portal_slide_pressed.connect(_on_portal_slide_pressed)
	wave_manager.timer_updated.connect(_on_timer_updated)
	wave_manager.enemies_remaining_changed.connect(hud.update_enemies_remaining)
	wave_manager.skip_unlock_changed.connect(func(_u: bool) -> void: hud.set_skip_hint_ready())
	game_state.gold_changed.connect(func(_g: int) -> void: _refresh_portal_slide_ui())
	game_state.wave_changed.connect(func(_w: int) -> void: _refresh_portal_slide_ui())

	debug_panel = DebugPanel.new()
	add_child(debug_panel)
	debug_panel.debug_opened.connect(_mark_debug_used)
	debug_panel.add_gold_requested.connect(_debug_add_gold)
	debug_panel.add_lives_requested.connect(_debug_add_lives)
	debug_panel.set_wave_requested.connect(_debug_set_wave)
	debug_panel.send_wave_requested.connect(_debug_force_next_wave)
	debug_panel.clear_enemies_requested.connect(_debug_clear_enemies)
	debug_panel.spawn_on_self_requested.connect(_debug_spawn_on_self)
	debug_panel.god_mode_toggled.connect(_debug_god_mode)
	debug_panel.restart_requested.connect(restart_run)

	if clash_match != null:
		hud.setup_clash(clash_match)
		hud.clash_send_requested.connect(_on_clash_send_requested)
		hud.clash_send_shop_upgrade_requested.connect(_on_clash_send_shop_upgrade_requested)
	wave_manager.begin_run()
	hud.refresh_run_labels()
	_set_start_status()
	hud.update_timer(0.0, true, "prep")
	_refresh_portal_slide_ui()
	if clash_match != null:
		_run_clash_bots()
		hud.refresh_clash_panel()
	_setup_online()
	SoundHub.unlock()
	if WaveScaler.is_siege_mode(game_state.game_mode):
		SoundHub.set_music_context(SoundHub.MUSIC_GAME_SIEGE)
	else:
		SoundHub.set_music_context(SoundHub.MUSIC_GAME_STANDARD)
	if game_state.tutorial_run:
		_tutorial_step = 0
		_refresh_tutorial_status()


func _set_start_status() -> void:
	if _online() and Net.is_client():
		hud.set_status("Online Clash — build your lane, buy sends, then press Ready. The host starts each round.")
	elif _online():
		hud.set_status("Online Clash — build your lane (leftmost). Start Round once everyone is Ready.")
	elif WaveScaler.is_clash_mode(game_state.game_mode):
		hud.set_status("Clash — build your lane (leftmost), buy sends for opponents, then Start Round.")
	elif WaveScaler.is_random_mode(game_state.game_mode):
		hud.set_status(
			"Random map %d (seed %d) — build a path, then Start Round." % [
				game_state.map_sector,
				game_state.current_map_seed,
			]
		)
	elif WaveScaler.is_siege_mode(game_state.game_mode):
		hud.set_status("Siege — defend the center. Use Pan (or hold Space / RMB) to move the map. Start Round when ready.")
	elif WaveScaler.is_custom_layout(game_state.map_layout_mode):
		hud.set_status(
			"Classic custom map (seed %d) — fixed all run. Build, then Start Round." % game_state.current_map_seed
		)
	elif _touch_ui:
		hud.set_status("Touch: drag to place, Pan to move the map, long-press tower to multi-select.")
	else:
		hud.set_status("Build your maze, then press Start Round.")
	_refresh_pan_availability()


func _run_clash_bots() -> void:
	if clash_match == null or clash_match.finished:
		return
	var wave := maxi(game_state.wave, 1)
	for bot in _clash_bots:
		var ai := bot as ClashBotAI
		if ai != null:
			ai.run_prep_turn(wave)
	wave_manager.invalidate_ground_path()
	build_system.refresh_after_reset()
	if hud != null:
		hud.refresh_clash_panel()


func _on_clash_send_requested(target_id: int, pack_id: String) -> void:
	if clash_match == null or clash_match.finished:
		return
	if _net_client != null:
		_net_client.send_action(["send", target_id, pack_id])
		return
	if clash_match.try_send_pack(clash_match.human_id, target_id, pack_id):
		var pack := WaveScaler.clash_send_pack(pack_id)
		var bump := WaveScaler.clash_send_income_bump(pack_id)
		var rate := clash_match.human().income_per_round
		var n := 0
		if wave_manager.phase == WaveManager.Phase.WAVE:
			n = wave_manager.flush_pending_clash_sends()
		var dest := clash_match.get_player(target_id)
		var dest_name := dest.display_name if dest else "opponent"
		if n > 0:
			hud.set_status("Sent %s to %s now (+%d/rnd; income now +%d/rnd)." % [
				str(pack.get("label", pack_id)),
				dest_name,
				bump,
				rate,
			])
		else:
			hud.set_status("Queued %s to %s (+%d/rnd; income now +%d/rnd)." % [
				str(pack.get("label", pack_id)),
				dest_name,
				bump,
				rate,
			])
		hud.refresh_clash_panel()
	else:
		hud.set_status("Can't send that package.")


func _on_clash_send_shop_upgrade_requested() -> void:
	if clash_match == null or clash_match.finished:
		return
	if _net_client != null:
		_net_client.send_action(["shop"])
		return
	var before := clash_match.send_shop_level
	if clash_match.try_upgrade_send_shop(clash_match.human_id):
		var lv := clash_match.send_shop_level
		hud.set_status("Send shop upgraded to Lv%d for everyone." % lv)
		hud.refresh_clash_panel()
	else:
		var cost := WaveScaler.clash_send_shop_upgrade_cost(before)
		if before >= WaveScaler.CLASH_SEND_SHOP_MAX_LEVEL:
			hud.set_status("Send shop is already maxed.")
		elif cost > 0:
			hud.set_status("Need %d gold to upgrade the send shop." % cost)
		else:
			hud.set_status("Can't upgrade the send shop.")


func _run_clash_bot_sends() -> void:
	if clash_match == null or clash_match.finished:
		return
	var wave := maxi(game_state.wave, 1)
	for bot in _clash_bots:
		var ai := bot as ClashBotAI
		if ai != null:
			ai.run_send_turn(wave)
	wave_manager.flush_pending_clash_sends()
	if hud != null:
		hud.refresh_clash_panel()


## Wrecker smashed a cell — tell that lane's bot to patch walls/towers mid-wave.
func _on_clash_tower_wrecked(cell: Vector2i) -> void:
	if clash_match == null or clash_match.finished or grid == null:
		return
	var lane := grid.lane_index_for_cell(cell)
	if lane < 0:
		return
	var wave := maxi(game_state.wave, 1)
	var repaired := false
	for bot in _clash_bots:
		var ai := bot as ClashBotAI
		if ai == null:
			continue
		var p := clash_match.get_player(ai.player_id)
		if p == null or not p.alive or p.is_human or p.lane_index != lane:
			continue
		if ai.repair_lane(wave):
			repaired = true
		break
	if repaired:
		wave_manager.invalidate_ground_path()
		# Safety net: a mid-wave repair must never leave a lane sealed (sends would vanish).
		if not wave_manager.has_open_path():
			wave_manager.clear_path_blockers()
		build_system.refresh_after_reset()
		if hud != null:
			hud.refresh_clash_panel()


func _on_clash_players_changed() -> void:
	if hud != null:
		hud.refresh_clash_panel()


func _on_clash_match_over(winner_id: int, human_won: bool, place: int) -> void:
	_clash_human_won = human_won
	_clash_result_place = place
	if human_won:
		hud.set_status("Victory — last lane standing (wave %d)." % game_state.wave)
	else:
		hud.set_status("Defeated — place #%d (wave %d)." % [maxi(place, 2), game_state.wave])
	wave_manager.clear_enemies()


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
	if clash_match != null and not clash_match.finished and _net_client == null:
		clash_match.tick_cheater_heals(delta)
		if wave_manager != null and wave_manager.phase == WaveManager.Phase.WAVE:
			_clash_bot_send_cd -= delta
			if _clash_bot_send_cd <= 0.0:
				_clash_bot_send_cd = 2.4
				_run_clash_bot_sends()
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

	_refresh_inspected_enemy_tooltip(mouse)

	# Desktop hover tooltips; on touch, info is tap/long-press driven.
	if not _touch_ui:
		var hovered_tower := build_system.update_hover(local_map)
		if hovered_tower != null and _is_on_board_view(mouse) and not _paint_holding and not _awaiting_tower_tap:
			if _inspected_enemy == null:
				hud.show_board_tower_tooltip_for(hovered_tower, mouse)
		elif _inspected_enemy == null:
			var hover_mob := _find_enemy_at(local_map)
			if hover_mob != null and _is_on_board_view(mouse) and not _paint_holding and not _awaiting_tower_tap:
				hud.show_board_enemy_tooltip_for(hover_mob, mouse)
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
	if _online() and event.keycode in [KEY_F1, KEY_QUOTELEFT, KEY_G, KEY_L, KEY_N, KEY_K, KEY_R]:
		# Debug tools and restart would desync an online match.
		return
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
			elif (
				not _aim_ability_id.is_empty()
				or build_system.selection_count() > 0
				or build_system.placing_enabled
			):
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
		# Right-click always clears selection + stops placing (pan with middle mouse / Pan mode / Space).
		if event.pressed:
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

	# Pan mode / Space / blocked cells: move the camera without placing.
	if _map_needs_pan() and not _is_additive_select():
		if _pan_mode or _space_pan_held() or _can_start_pan_at(local_map):
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

	# Click a live mob to inspect (before empty-cell place). Towers still win on their cell.
	if existing == null:
		var clicked_mob := _find_enemy_at(local_map)
		if clicked_mob != null:
			_paint_holding = false
			_paint_enabled = false
			_awaiting_tower_tap = false
			_set_inspected_enemy(clicked_mob)
			hud.set_status("Inspecting %s." % clicked_mob.display_name())
			return

	# Existing piece: overbuild walls while a combat type is armed; otherwise select for sell.
	if existing != null:
		_clear_inspected_enemy()
		if additive:
			_paint_enabled = false
			_awaiting_tower_tap = false
			build_system.try_place_at(local_map, true)
			hud.set_status("Selection: %d tower(s)." % build_system.selection_count())
			hud.show_touch_tower_info(existing as Tower)
			return
		var wall_overbuild := (
			build_system.placing_enabled
			and TowerData.is_wall((existing as Tower).tower_id)
			and not TowerData.is_wall(build_system.selected_tower_id)
			and build_system.can_place_at(cell)
		)
		if wall_overbuild:
			_awaiting_tower_tap = false
			var overbuilt := _paint_place_at(local_map, true)
			_paint_enabled = overbuilt
			if not overbuilt and not game_state.can_afford(
				int(TowerData.get_def(build_system.selected_tower_id)["cost"])
			):
				hud.set_status("Not enough gold.")
			return
		_awaiting_tower_tap = true
		_paint_enabled = false
		return

	_awaiting_tower_tap = false
	_clear_inspected_enemy()

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
		elif _would_block_placement_path(cell):
			hud.set_status("Can't place there — would block the path.")
		else:
			hud.set_status("Can't place there.")


func _finish_pointer_press() -> void:
	var local_map := _screen_to_map(get_global_mouse_position())
	if _awaiting_tower_tap and not _long_press_triggered and _is_on_map(local_map):
		var cell := grid.world_to_cell(local_map)
		var before = grid.get_tower_at(cell)
		var was_wall := before != null and TowerData.is_wall((before as Tower).tower_id)
		build_system.try_place_at(local_map, false)
		var tower = grid.get_tower_at(cell)
		var count := build_system.selection_count()
		if count > 0 and tower:
			if was_wall and TowerData.is_wall((tower as Tower).tower_id):
				hud.set_status("Wall selected — Sell, or pick a combat tower and tap it to build over. Tap again to deselect.")
			else:
				hud.set_status("Selected %d. Tap again to deselect. Long-press / Multi for more." % maxi(count, 1))
			hud.show_touch_tower_info(tower as Tower)
		elif count == 0 and before != null:
			if was_wall and tower != null and not TowerData.is_wall((tower as Tower).tower_id):
				hud.set_status("Tower built over wall.")
			else:
				hud.set_status("Deselected — pick a tower type to place, or tap another piece.")
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


func _space_pan_held() -> bool:
	return Input.is_key_pressed(KEY_SPACE)


func _refresh_pan_availability() -> void:
	if hud == null:
		return
	hud.set_pan_available(_map_needs_pan())


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


## Pan so the board center (Siege exit) sits in the middle of the play view.
func _focus_camera_on_map_center() -> void:
	if grid == null or not _map_needs_pan():
		map_pan = Vector2.ZERO
		_clamp_map_pan()
		_sync_world_positions()
		_update_map_camera()
		return
	var mid := grid.map_pixel_size() * 0.5
	var visible := _visible_map_extent()
	map_pan = mid - visible * 0.5
	_clamp_map_pan()
	_sync_world_positions()
	_update_map_camera()


## Clash: keep the human (leftmost) lane in view — not the map midpoint over bot lanes.
func _focus_camera_on_human_lane() -> void:
	if grid == null or not grid.is_clash_layout:
		_focus_camera_on_map_center()
		return
	if not _map_needs_pan():
		map_pan = Vector2.ZERO
		_clamp_map_pan()
		_sync_world_positions()
		_update_map_camera()
		return
	var lane := 0
	if build_system != null:
		lane = build_system.human_lane
	elif _online():
		lane = maxi(Net.my_seat(), 0)
	var spawn := grid.get_lane_spawn(lane)
	var focus := grid.cell_to_world_center(spawn)
	# Bias a bit downward so more of the lane is visible under the top HUD.
	focus.y = grid.map_pixel_size().y * 0.45
	var visible := _visible_map_extent()
	map_pan = focus - visible * 0.5
	# Prefer showing lane x=0 at the left of the play view when it fits.
	var lane_left_px := 0.0
	if lane >= 0 and lane < grid.lane_col_ranges.size():
		lane_left_px = float((grid.lane_col_ranges[lane] as Vector2i).x) * float(grid.tile_px())
	map_pan.x = lane_left_px
	_clamp_map_pan()
	_sync_world_positions()
	_update_map_camera()


func _would_block_placement_path(cell: Vector2i) -> bool:
	if pathfinder == null or grid == null:
		return false
	if clash_match != null and grid.is_clash_layout:
		var lane := build_system.human_lane if build_system != null else 0
		return pathfinder.would_block_path_between(
			grid.get_lane_spawn(lane),
			grid.get_lane_exit(lane),
			cell
		)
	return pathfinder.would_block_path(cell)


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
	# Combat types may build over walls on tap or drag.
	if build_system.try_place_at(local_map, false, true):
		_last_paint_cell = cell
		if show_status:
			if had_wall and not TowerData.is_wall(build_system.selected_tower_id):
				hud.set_status("Tower built over wall. Hold-drag to continue.")
			else:
				hud.set_status("Hold and drag to place more.")
		return true
	return false


func _on_tower_type_selected(tower_id: String) -> void:
	if _pan_mode and hud != null:
		hud.set_pan_mode(false)
	build_system.select_tower_type(tower_id)
	hud.highlight_tower(tower_id)
	var def := TowerData.get_def(tower_id)
	var name := str(def.get("display_name", tower_id))
	hud.set_status("Placing %s. Right-click or re-tap a selected tower to deselect." % name)


## Joined player: anchor cells of the selected towers (the host acts on cells).
func _selected_cells() -> Array:
	var cells: Array = []
	for t in build_system.selected_towers:
		if is_instance_valid(t):
			cells.append(t.get_meta("anchor_cell", grid.world_to_cell(t.position)))
	return cells


func _on_sell_selected() -> void:
	if _net_client != null:
		if build_system.selection_count() == 0:
			hud.set_status("Nothing selected to sell.")
			return
		_net_client.send_action(["sell", _selected_cells()])
		build_system.clear_selection()
		return
	var count := build_system.selection_count()
	var refund := build_system.selection_sell_total()
	if build_system.sell_selected():
		hud.set_status("Sold %d tower(s) for %d gold." % [count, refund])
	else:
		hud.set_status("Nothing selected to sell.")


func _on_deselect() -> void:
	var had_aim := not _aim_ability_id.is_empty()
	var had_sel := build_system.selection_count() > 0
	var was_placing := build_system.placing_enabled
	var had_mob := _inspected_enemy != null
	_clear_command_aim()
	_clear_inspected_enemy()
	build_system.clear_selection()
	build_system.set_placing_enabled(false)
	if hud:
		hud.clear_tower_highlight()
	if had_aim:
		hud.set_status("Aim cancelled.")
	elif had_sel or was_placing:
		hud.set_status("Deselected — pick a tower type to place again.")
	elif had_mob:
		hud.set_status("Cleared mob inspect.")
	else:
		hud.set_status("Nothing selected.")


func _find_enemy_at(local_map: Vector2) -> Enemy:
	if enemies == null:
		return null
	var best: Enemy = null
	var best_d := INF
	for child in enemies.get_children():
		if not (child is Enemy):
			continue
		var e := child as Enemy
		if not e.alive:
			continue
		var d := e.position.distance_to(local_map)
		var reach := e.hit_radius() + float(grid.tile_px()) * 0.35
		if d <= reach and d < best_d:
			best_d = d
			best = e
	return best


func _set_inspected_enemy(enemy: Enemy) -> void:
	if _inspected_enemy != null and is_instance_valid(_inspected_enemy) and _inspected_enemy != enemy:
		_inspected_enemy.inspected = false
		_inspected_enemy.queue_redraw()
	_inspected_enemy = enemy
	if enemy != null and is_instance_valid(enemy):
		enemy.inspected = true
		enemy.queue_redraw()
		var screen := get_global_mouse_position()
		hud.show_board_enemy_tooltip_for(enemy, screen)


func _clear_inspected_enemy() -> void:
	if _inspected_enemy != null and is_instance_valid(_inspected_enemy):
		_inspected_enemy.inspected = false
		_inspected_enemy.queue_redraw()
	_inspected_enemy = null
	if hud and not hud.is_tooltip_pinned():
		hud.hide_board_tower_tooltip()
	elif hud:
		hud.hide_board_tower_tooltip()


func _refresh_inspected_enemy_tooltip(screen_pos: Vector2) -> void:
	if _inspected_enemy == null:
		return
	if not is_instance_valid(_inspected_enemy) or not _inspected_enemy.alive:
		_clear_inspected_enemy()
		return
	hud.show_board_enemy_tooltip_for(_inspected_enemy, screen_pos)


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
	if _net_client != null:
		_net_client.send_action(["cmd", tower.get_meta("anchor_cell", Vector2i.ZERO), ability_id, cell])
		_clear_command_aim()
		return
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
	tower.play_visual_action("action")
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
	if _net_client != null:
		_net_client.send_action(["upgrade", _selected_cells()])
		return
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
	if _net_client != null:
		_net_client.send_action(["final", _selected_cells(), element_id])
		return
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


func _on_timer_updated(seconds_left: float, can_skip: bool, mode: String) -> void:
	hud.update_timer(seconds_left, can_skip, mode)
	refresh_online_round_button()
	_refresh_portal_slide_ui()


func _portal_slide_lane() -> int:
	if clash_match != null and clash_match.human() != null:
		return clash_match.human().lane_index
	return build_system.human_lane if build_system != null else 0


func _portal_slides_unlocked() -> bool:
	if game_state == null or game_state.is_game_over:
		return false
	if game_state.wave < WaveScaler.PORTAL_SLIDE_UNLOCK_WAVE:
		return false
	if wave_manager == null:
		return false
	return wave_manager.phase != WaveManager.Phase.WAVE


func _refresh_portal_slide_ui() -> void:
	if hud == null or grid == null or build_system == null or build_system.pathfinder == null:
		return
	var unlocked := _portal_slides_unlocked()
	var can_afford := game_state != null and game_state.can_afford(WaveScaler.PORTAL_SLIDE_COST)
	if not unlocked:
		hud.refresh_portal_slides(false, false, false, false, false, false)
		return
	var lane := _portal_slide_lane()
	var pf: Pathfinder = build_system.pathfinder
	hud.refresh_portal_slides(
		true,
		can_afford,
		grid.can_slide_portal("spawn", -1, pf, lane),
		grid.can_slide_portal("spawn", 1, pf, lane),
		grid.can_slide_portal("exit", -1, pf, lane),
		grid.can_slide_portal("exit", 1, pf, lane)
	)


func _on_portal_slide_pressed(which: String, dx: int) -> void:
	if not _portal_slides_unlocked():
		hud.set_status("Portal moves unlock after wave %d." % WaveScaler.PORTAL_SLIDE_UNLOCK_WAVE)
		return
	if not game_state.can_afford(WaveScaler.PORTAL_SLIDE_COST):
		hud.set_status("Need %d gold to move a portal." % WaveScaler.PORTAL_SLIDE_COST)
		return
	if _net_client != null:
		_net_client.send_action(["portal", which, dx])
		return
	var lane := _portal_slide_lane()
	var pf: Pathfinder = build_system.pathfinder
	if not grid.can_slide_portal(which, dx, pf, lane):
		hud.set_status("Can't move that portal that way (edge, blocked, or would seal the path).")
		_refresh_portal_slide_ui()
		return
	if not game_state.spend_gold(WaveScaler.PORTAL_SLIDE_COST):
		hud.set_status("Need %d gold to move a portal." % WaveScaler.PORTAL_SLIDE_COST)
		return
	game_state.record_spend(WaveScaler.PORTAL_SLIDE_COST)
	if clash_match != null:
		clash_match.sync_human_gold_from_game_state()
	if not grid.try_slide_portal(which, dx, pf, lane):
		# Should be rare — refund if commit failed after the dry-run passed.
		game_state.add_gold(WaveScaler.PORTAL_SLIDE_COST)
		if clash_match != null:
			clash_match.sync_human_gold_from_game_state()
		hud.set_status("Portal move failed — gold refunded.")
		_refresh_portal_slide_ui()
		return
	build_system.rebuild_paths()
	_refresh_portal_slide_ui()
	var label := "Spawn" if which == "spawn" else "Exit"
	var dir := "left" if dx < 0 else "right"
	hud.set_status("%s moved %s (−%d gold)." % [label, dir, WaveScaler.PORTAL_SLIDE_COST])


func _on_skip_timer() -> void:
	if _net_client != null:
		if wave_manager.phase == WaveManager.Phase.WAVE or game_state.is_game_over:
			return
		var now_ready := not Net.is_ready(Net.my_id)
		Net.set_ready(now_ready)
		refresh_online_round_button()
		hud.set_status("Ready — waiting for the host to start." if now_ready else "Not ready.")
		return
	if _online() and wave_manager.phase != WaveManager.Phase.WAVE and not Net.all_guests_ready():
		hud.set_status("Waiting for %s to press Ready." % ", ".join(Net.waiting_on_names()))
		return
	if wave_manager.phase == WaveManager.Phase.PREP:
		if wave_manager.start_round():
			if game_state.tutorial_run and _tutorial_step == 2:
				_tutorial_step = 3
				_refresh_tutorial_status()
			build_system.rebuild_paths()
			var fs: Dictionary = wave_manager.last_path_failsafe
			var removed := int(fs.get("removed", 0))
			var refunded := int(fs.get("refunded", 0))
			if removed > 0:
				hud.set_status(
					"Path was blocked — removed %d structures (+%d gold). Round started."
					% [removed, refunded]
				)
			else:
				hud.set_status("Round started — build timer running, then waves begin.")
		else:
			hud.set_status("Keep a path open from spawn to exit, then Start Round.")
		return
	if wave_manager.phase == WaveManager.Phase.WAVE:
		if wave_manager.try_skip_timer():
			build_system.rebuild_paths()
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
		build_system.rebuild_paths()
		var fs2: Dictionary = wave_manager.last_path_failsafe
		var removed2 := int(fs2.get("removed", 0))
		var refunded2 := int(fs2.get("refunded", 0))
		var bonus2 := wave_manager.last_early_send_bonus
		if removed2 > 0:
			hud.set_status(
				"Path was blocked — removed %d structures (+%d gold). Wave starting."
				% [removed2, refunded2]
			)
		elif bonus2 > 0:
			hud.set_status("Timer skipped — wave starting (+%d gold)." % bonus2)
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
	if clash_match != null:
		_clash_bot_send_cd = 0.6
	refresh_online_round_button()


func _on_wave_cleared(wave: int, kills: int, bonus_gold: int) -> void:
	if game_state.tutorial_run and wave >= 1:
		_finish_tutorial()
		return
	hud.set_banner("")
	if WaveScaler.is_clash_mode(game_state.game_mode):
		if clash_match != null and clash_match.finished:
			return
		_run_clash_bots()
		var rate := 0
		if clash_match != null and clash_match.human() != null:
			rate = clash_match.human().income_per_round
		if bonus_gold > 0:
			hud.set_status(
				"Wave %d cleared — +%d income (%d/rnd). Next round on timer — build and buy sends."
				% [wave, bonus_gold, rate]
			)
		else:
			hud.set_status("Wave %d cleared — next round on timer. Build and buy sends." % wave)
		hud.refresh_clash_panel()
		return
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
	_focus_camera_on_map_center()
	if ok:
		hud.set_status("Wave %d cleared — entry moved to a new rim. Path must stay open to the center." % wave)
	else:
		hud.set_status("Wave %d cleared — could not move entry (path sealed). Sell towers to reopen." % wave)


func _apply_run_map(new_random: bool) -> void:
	if grid == null:
		return
	var mode := Session.game_mode if game_state == null else game_state.game_mode
	var layout_mode := Session.map_layout_mode if game_state == null else game_state.map_layout_mode
	if WaveScaler.is_clash_mode(mode):
		var lanes := Session.clash_player_count
		if new_random or not grid.is_clash_layout or grid.clash_lane_count() != lanes:
			grid.reset_clash(lanes)
		Session.current_map_seed = -1
	elif WaveScaler.is_siege_mode(mode):
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
	if WaveScaler.is_clash_mode(mode):
		_focus_camera_on_human_lane()
	elif WaveScaler.is_siege_mode(mode):
		_focus_camera_on_map_center()
	else:
		_update_map_camera()
	_refresh_pan_availability()
	if hud != null:
		hud.refresh_run_labels()


func _mark_debug_used() -> void:
	game_state.mark_debug_used()
	hud.set_status("Debug used — this run can't be saved to the leaderboard.")


func _debug_add_gold(amount: int) -> void:
	_mark_debug_used()
	game_state.add_gold(amount)
	if clash_match != null:
		clash_match.sync_human_gold_from_game_state()


func _debug_add_lives(amount: int) -> void:
	_mark_debug_used()
	game_state.lives += amount
	game_state.lives_changed.emit(game_state.lives)
	if clash_match != null:
		var h := clash_match.human()
		if h != null:
			h.lives = game_state.lives
			clash_match.players_changed.emit()


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


func _debug_spawn_on_self(count: int, flying: bool, boss: bool) -> void:
	_mark_debug_used()
	var n := wave_manager.debug_spawn_on_self(count, flying, boss)
	if n <= 0:
		hud.set_status("Debug: couldn't spawn on self — keep a path open.")
		return
	var kind := "boss" if boss else ("flyer" if flying else "creep")
	hud.set_status("Debug: spawned %d %s on your path (no leaderboard)." % [n, kind])


func _debug_god_mode(enabled: bool) -> void:
	_mark_debug_used()
	game_state.god_mode = enabled
	debug_panel.set_god_mode_ui(enabled)


func _on_end_run_confirmed() -> void:
	if game_state == null or game_state.is_game_over:
		return
	if _online():
		# Leaving: the host leaving ends the match for everyone; a joined player's lane goes to a bot.
		Net.leave()
		Session.go_menu()
		return
	var wave_reached := maxi(game_state.wave, game_state.highest_wave)
	game_state.is_game_over = true
	wave_manager.clear_enemies()
	for child in projectiles.get_children():
		child.queue_free()
	if WaveScaler.is_clash_mode(game_state.game_mode):
		_clash_human_won = false
		_clash_result_place = clash_match.living_count() + 1 if clash_match else 2
		hud.set_status("Clash ended early.")
		call_deferred("_boot_clash_summary", wave_reached)
		return
	if game_state.debug_used:
		hud.set_status("Run ended — debug used, leaderboard entry blocked.")
	else:
		hud.set_status("Run ended — checking leaderboard for wave %d..." % wave_reached)
	call_deferred("_boot_leaderboard", wave_reached)


func _on_game_over_to_leaderboard(wave_reached: int) -> void:
	wave_manager.phase = WaveManager.Phase.PREP
	_snap_board_for_leaderboard()
	if WaveScaler.is_clash_mode(game_state.game_mode):
		call_deferred("_boot_clash_summary", wave_reached)
		return
	if game_state.debug_used:
		hud.set_status("Game over — debug used, leaderboard entry blocked.")
	else:
		hud.set_status("Game over — loading leaderboard...")
	call_deferred("_boot_leaderboard", wave_reached)


func _snap_board_for_leaderboard() -> void:
	# Hide transient UI so the crop is mostly the maze.
	if debug_panel:
		debug_panel.visible = false
	if build_system:
		build_system.clear_selection()
	if _range_overlay:
		_range_overlay.show_ring = false
		_range_overlay.queue_redraw()
	if hud:
		hud.hide_end_run_confirm()
	Session.pending_board_png = _BoardScreenshot.capture_board_b64(self)


func _boot_clash_summary(wave_reached: int) -> void:
	SoundHub.play_game_over()
	var coaching := {
		"new_best": false,
		"coaching_text": _clash_summary_text(wave_reached),
		"screenshot_cb": _save_maze_screenshot,
	}
	if debug_panel:
		debug_panel.visible = false
	if build_system:
		build_system.clear_selection()
	var summary: Control = _RunSummaryOverlay.new()
	summary.show_summary(game_state, coaching)
	hud.attach_run_summary(summary)
	var online := _online() or not _online_end_note.is_empty()
	summary.continued.connect(func() -> void:
		if online:
			# Online matches aren't leaderboard runs (the host's device played every lane).
			Net.leave()
			Session.go_menu()
			return
		Session.go_leaderboard(
			wave_reached,
			game_state.debug_used or game_state.tutorial_run,
			game_state.difficulty,
			game_state.seeds_for_leaderboard(),
			game_state.game_mode
		)
	)


func _clash_summary_text(wave_reached: int) -> String:
	if not _online_end_note.is_empty():
		return "%s Match ended at wave %d." % [_online_end_note, wave_reached]
	if _clash_human_won:
		return "Clash victory! You were the last lane standing through wave %d." % wave_reached
	var place := maxi(_clash_result_place, 2)
	return "Clash defeat — finished #%d at wave %d. Send packs raise income; don't neglect your lane." % [
		place,
		wave_reached,
	]


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
			game_state.seeds_for_leaderboard(),
			game_state.game_mode
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
	# Online matches keep running for everyone else; the menu just opens on top.
	if not _online():
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
	if _online():
		Net.leave()
	Session.tutorial_active = false
	Session.go_menu()


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
	if _online():
		return
	for child in projectiles.get_children():
		child.queue_free()
	_clear_command_traps()
	game_state.reset_run(Session.difficulty, Session.game_mode, Session.monster_mode)
	game_state.map_layout_mode = Session.map_layout_mode
	game_state.run_seed = Session.run_seed
	game_state.current_map_seed = Session.current_map_seed
	_apply_run_map(true)
	_setup_clash_match()
	if clash_match != null:
		hud.setup_clash(clash_match)
	build_system.refresh_after_reset()
	hud.set_banner("")
	hud.highlight_tower("gunner")
	build_system.select_tower_type("gunner")
	hud.refresh_run_labels()
	wave_manager.begin_run()
	_set_start_status()
	hud.update_timer(0.0, true, "prep")
	if clash_match != null:
		_run_clash_bots()
		hud.refresh_clash_panel()
