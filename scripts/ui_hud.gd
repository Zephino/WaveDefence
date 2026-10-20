class_name UIHud
extends CanvasLayer

const _WavePreview := preload("res://data/wave_preview.gd")

signal skip_timer_pressed
signal sell_pressed
signal deselect_pressed
signal upgrade_pressed
signal final_element_pressed(element_id: String)
signal command_ability_pressed(ability_id: String)
signal tower_type_selected(tower_id: String)
signal end_run_confirmed
signal multi_select_changed(enabled: bool)
signal pan_mode_changed(enabled: bool)
signal pause_pressed
signal clash_send_requested(target_id: int, pack_id: String)
signal clash_send_shop_upgrade_requested
signal portal_slide_pressed(which: String, dx: int)

var game_state: GameState
var clash_match: ClashMatch = null
var multi_select_enabled: bool = false
var pan_mode_enabled: bool = false
var _clash_status_label: Label
var _clash_send_box: VBoxContainer
var _clash_target_id: int = 1
var _clash_root: Control
var _hud_root: Control
var _towers_panel: PanelContainer
var _send_panel: PanelContainer
var _towers_toggle: Button
var _send_toggle: Button
var _actions_toggle: Button
var _towers_pin_btn: Button
var _send_pin_btn: Button
var _towers_open: bool = false
var _send_open: bool = false
var _actions_open: bool = false
var _towers_pinned: bool = false
var _send_pinned: bool = false
var _send_upgrade_btn: Button
var _towers_float_pos: Vector2 = Vector2(-1, -1)
var _send_float_pos: Vector2 = Vector2(-1, -1)
var _actions_float_pos: Vector2 = Vector2(-1, -1)
var _drag_shop: String = ""
var _drag_grab: Vector2 = Vector2.ZERO
var _towers_drag_bar: Control
var _send_drag_bar: Control
var _actions_drag_bar: Control
var _launcher_shell: PanelContainer
var _launcher_drag_bar: Control
var _launcher_body: VBoxContainer
var _launcher_hide_btn: Button
var _launcher_title: Label
var _launcher_float_pos: Vector2 = Vector2(-1, -1)
var _launcher_collapsed: bool = false

var gold_label: Label
var lives_label: Label
var wave_label: Label
var difficulty_label: Label
var mode_label: Label
var monsters_label: Label
var enemies_label: Label
var banner_label: Label
var version_label: Label
var status_label: Label
var timer_label: Label
var skip_button: Button
var sell_button: Button
var deselect_button: Button
var upgrade_button: Button
var multi_select_button: Button
var pan_mode_button: Button
var end_run_button: Button
var portal_slide_panel: PanelContainer
var portal_slide_box: VBoxContainer
var spawn_left_button: Button
var spawn_right_button: Button
var exit_left_button: Button
var exit_right_button: Button
var final_buttons: Dictionary = {}
var tower_buttons: Dictionary = {}
var ability_buttons: Dictionary = {}
var command_box: VBoxContainer
var board_tooltip: PanelContainer
var board_tooltip_label: Label
var _end_run_overlay: Control
var _tooltip_hide_at_msec: int = 0
var _command_tower: Tower = null
var _ability_was_on_cd: Dictionary = {}
var _shop_shell: PanelContainer
## Last wave the shop refreshed unlock announcements for (-1 = not yet).
var _last_shop_wave: int = -1
var _actions_shell: PanelContainer
var _top_bar: Control
var boss_hp_label: Label
var next_wave_brief_label: Label


func setup(p_state: GameState, version_text: String) -> void:
	game_state = p_state
	_build_ui(version_text)
	game_state.gold_changed.connect(_on_gold_changed)
	game_state.lives_changed.connect(_on_lives_changed)
	game_state.wave_changed.connect(_on_wave_changed)
	_on_gold_changed(game_state.gold)
	_on_lives_changed(game_state.lives)
	_on_wave_changed(game_state.wave)
	call_deferred("_clear_gui_focus")


func _build_ui(version_text: String) -> void:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	var top := HBoxContainer.new()
	top.position = Vector2(12, 8)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_theme_constant_override("separation", 18)
	root.add_child(top)

	gold_label = Label.new()
	lives_label = Label.new()
	wave_label = Label.new()
	difficulty_label = Label.new()
	difficulty_label.modulate = Color(0.72, 0.82, 0.95)
	mode_label = Label.new()
	mode_label.modulate = Color(0.78, 0.7, 0.9)
	monsters_label = Label.new()
	monsters_label.modulate = Color(0.85, 0.7, 0.65)
	banner_label = Label.new()
	banner_label.visible = false
	banner_label.modulate = Color(1.0, 0.82, 0.28)
	enemies_label = Label.new()
	enemies_label.modulate = Color(0.9, 0.75, 0.65)
	version_label = Label.new()
	version_label.text = "v%s" % version_text
	version_label.modulate = Color(0.7, 0.75, 0.8)
	top.add_child(gold_label)
	top.add_child(lives_label)
	top.add_child(wave_label)
	top.add_child(difficulty_label)
	top.add_child(mode_label)
	top.add_child(monsters_label)
	top.add_child(banner_label)
	top.add_child(enemies_label)
	top.add_child(version_label)
	_top_bar = top
	refresh_run_labels()
	update_enemies_remaining(0, 0, 0)

	# Status sits under the top bar only — never shares a row with Gold/Wave/banner.
	status_label = Label.new()
	status_label.position = Vector2(GameLayout.board_origin().x, 40)
	status_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	status_label.modulate = Color(0.75, 0.8, 0.85)
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.custom_minimum_size = Vector2(GameLayout.board_pixel_size().x, 0)
	root.add_child(status_label)

	next_wave_brief_label = Label.new()
	next_wave_brief_label.position = Vector2(GameLayout.board_origin().x, 58)
	next_wave_brief_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	next_wave_brief_label.modulate = Color(0.7, 0.78, 0.88)
	next_wave_brief_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	next_wave_brief_label.custom_minimum_size = Vector2(GameLayout.board_pixel_size().x, 0)
	root.add_child(next_wave_brief_label)

	boss_hp_label = Label.new()
	boss_hp_label.position = Vector2(640, 36)
	boss_hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	boss_hp_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	boss_hp_label.modulate = Color(1.0, 0.75, 0.85)
	boss_hp_label.visible = false
	root.add_child(boss_hp_label)

	_hud_root = root
	UserSettings.ensure_loaded()
	_towers_pinned = UserSettings.is_towers_shop_pinned()
	_send_pinned = UserSettings.is_send_shop_pinned()
	_towers_float_pos = UserSettings.get_towers_shop_pos()
	_send_float_pos = UserSettings.get_send_shop_pos()
	_launcher_float_pos = UserSettings.get_launcher_pos()
	_launcher_collapsed = UserSettings.is_launcher_collapsed()
	_towers_open = false
	_send_open = false
	_actions_open = false

	_build_launcher_panel(root)
	var action_parent := _make_actions_panel(root)
	_fill_actions_column(action_parent)

	_build_towers_shop_panel(root)
	_build_send_shop_panel(root)
	_apply_launcher_layout()
	_apply_towers_shop_layout()
	_apply_send_shop_layout()
	_apply_actions_layout()
	_build_portal_slide_bar(root)

	board_tooltip = PanelContainer.new()
	board_tooltip.visible = false
	board_tooltip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	board_tooltip.z_index = 50
	root.add_child(board_tooltip)
	board_tooltip_label = Label.new()
	board_tooltip_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	board_tooltip_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	board_tooltip_label.custom_minimum_size = Vector2(220, 0)
	board_tooltip.add_child(board_tooltip_label)

	_build_end_run_confirm(root)
	_build_clash_panel(root)

	highlight_tower("gunner")
	update_upgrade_buttons(false, 0, false, 0)


func setup_clash(p_match: ClashMatch) -> void:
	clash_match = p_match
	if _clash_root:
		_clash_root.visible = clash_match != null
	refresh_clash_panel()


func _build_clash_panel(root: Control) -> void:
	_clash_root = Control.new()
	_clash_root.visible = false
	_clash_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_clash_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(_clash_root)

	# Status only — ignore mouse so it never blocks lane clicks.
	_clash_status_label = Label.new()
	_clash_status_label.position = Vector2(GameLayout.board_origin().x, 76)
	_clash_status_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_clash_status_label.modulate = Color(0.8, 0.85, 0.7)
	_clash_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_clash_status_label.custom_minimum_size = Vector2(GameLayout.board_pixel_size().x, 0)
	_clash_root.add_child(_clash_status_label)


func refresh_clash_panel() -> void:
	if _clash_root == null:
		return
	var active := clash_match != null and game_state != null and WaveScaler.is_clash_mode(game_state.game_mode)
	_clash_root.visible = active
	_refresh_launcher_send_visibility()
	if not active:
		if _send_panel:
			_send_panel.visible = false
		_apply_send_shop_layout()
		return
	var parts: PackedStringArray = PackedStringArray()
	for p in clash_match.players:
		var cp := p as ClashPlayerState
		if cp == null:
			continue
		if not cp.alive:
			parts.append("%s: OUT" % cp.display_name)
		elif cp.cheater_healing:
			parts.append("%s L%d♥ $%d +%d/rnd" % [cp.display_name, cp.lives, cp.gold, cp.income_per_round])
		else:
			parts.append("%s L%d $%d +%d/rnd" % [cp.display_name, cp.lives, cp.gold, cp.income_per_round])
	if _clash_status_label:
		_clash_status_label.text = "  |  ".join(parts)
	_rebuild_clash_send_box()
	_apply_send_shop_layout()


func _rebuild_clash_send_box() -> void:
	if _clash_send_box == null or clash_match == null:
		return
	while _clash_send_box.get_child_count() > 0:
		var c := _clash_send_box.get_child(0)
		_clash_send_box.remove_child(c)
		c.queue_free()

	var shop_lv := clash_match.send_shop_level
	var lv_label := Label.new()
	lv_label.text = "Send shop Lv%d / %d (shared)" % [shop_lv, WaveScaler.CLASH_SEND_SHOP_MAX_LEVEL]
	lv_label.modulate = Color(0.85, 0.9, 0.55)
	lv_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_clash_send_box.add_child(lv_label)

	_send_upgrade_btn = Button.new()
	_send_upgrade_btn.focus_mode = Control.FOCUS_NONE
	_send_upgrade_btn.custom_minimum_size = Vector2(0, GameLayout.button_height(26.0))
	_send_upgrade_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if shop_lv >= WaveScaler.CLASH_SEND_SHOP_MAX_LEVEL:
		_send_upgrade_btn.text = "Send shop maxed"
		_send_upgrade_btn.disabled = true
		_send_upgrade_btn.tooltip_text = "All send packs unlocked"
	else:
		var up_cost := WaveScaler.clash_send_shop_upgrade_cost(shop_lv)
		_send_upgrade_btn.text = "Upgrade shop (%d)" % up_cost
		_send_upgrade_btn.disabled = game_state == null or not game_state.can_afford(up_cost)
		_send_upgrade_btn.tooltip_text = (
			"Unlock the next send-pack tier for %d gold. Higher packs grant larger +income/rnd."
			% up_cost
		)
		_send_upgrade_btn.pressed.connect(func() -> void:
			clash_send_shop_upgrade_requested.emit()
		)
	_clash_send_box.add_child(_send_upgrade_btn)

	var living := clash_match.living_opponents_of(clash_match.human_id)
	if living.is_empty():
		var none := Label.new()
		none.text = "No living opponents"
		none.modulate = Color(0.6, 0.65, 0.7)
		_clash_send_box.add_child(none)
		return
	# Keep target valid.
	var valid_ids: Array = []
	for p in living:
		valid_ids.append((p as ClashPlayerState).player_id)
	if not valid_ids.has(_clash_target_id):
		_clash_target_id = int(valid_ids[0])

	var target_row := HBoxContainer.new()
	target_row.add_theme_constant_override("separation", 3)
	_clash_send_box.add_child(target_row)
	for p in living:
		var cp := p as ClashPlayerState
		var tbtn := Button.new()
		tbtn.text = cp.display_name
		tbtn.focus_mode = Control.FOCUS_NONE
		tbtn.custom_minimum_size = Vector2(0, GameLayout.button_height(24.0))
		tbtn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var tid := cp.player_id
		tbtn.pressed.connect(func() -> void:
			_clash_target_id = tid
			refresh_clash_panel()
		)
		if tid == _clash_target_id:
			tbtn.modulate = Color(0.75, 1.0, 0.8)
		target_row.add_child(tbtn)

	for pack_id in WaveScaler.clash_send_packs_for_level(shop_lv):
		var pack := WaveScaler.clash_send_pack(str(pack_id))
		var cost: int = int(pack.get("cost", 0))
		var bump := WaveScaler.clash_send_income_bump(str(pack_id))
		var pbtn := Button.new()
		pbtn.text = "%s (%d)  +%d/rnd" % [str(pack.get("label", pack_id)), cost, bump]
		pbtn.focus_mode = Control.FOCUS_NONE
		pbtn.custom_minimum_size = Vector2(0, GameLayout.button_height(26.0))
		pbtn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		pbtn.disabled = game_state == null or not game_state.can_afford(cost)
		pbtn.tooltip_text = (
			"Send now (prep or during the round). Permanently raises your income by +%d/rnd."
			% bump
		)
		var pid := str(pack_id)
		pbtn.pressed.connect(func() -> void:
			clash_send_requested.emit(_clash_target_id, pid)
		)
		_clash_send_box.add_child(pbtn)


func _build_end_run_confirm(root: Control) -> void:
	_end_run_overlay = Control.new()
	_end_run_overlay.visible = false
	_end_run_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_end_run_overlay.z_index = 80
	_end_run_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(_end_run_overlay)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_end_run_overlay.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_end_run_overlay.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(420, 210)
	center.add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	panel.add_child(box)

	var pad_top := Control.new()
	pad_top.custom_minimum_size = Vector2(0, 8)
	pad_top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(pad_top)

	var title := Label.new()
	title.text = "End this run?"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 26)
	box.add_child(title)

	var body := Label.new()
	body.text = "Your wave score will be checked against the leaderboard.\nThis cannot be undone."
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.modulate = Color(0.8, 0.82, 0.86)
	box.add_child(body)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(row)

	var btn_h := GameLayout.button_height(40.0)
	var cancel := Button.new()
	cancel.text = "Cancel"
	cancel.focus_mode = Control.FOCUS_NONE
	cancel.custom_minimum_size = Vector2(140, btn_h)
	cancel.pressed.connect(hide_end_run_confirm)
	row.add_child(cancel)

	var confirm := Button.new()
	confirm.text = "End Run"
	confirm.focus_mode = Control.FOCUS_NONE
	confirm.custom_minimum_size = Vector2(140, btn_h)
	confirm.modulate = Color(1.15, 0.85, 0.75)
	confirm.pressed.connect(_on_end_run_confirmed)
	row.add_child(confirm)


func show_end_run_confirm() -> void:
	if game_state != null and game_state.is_game_over:
		return
	if _end_run_overlay:
		_end_run_overlay.visible = true
		_clear_gui_focus()


func hide_end_run_confirm() -> void:
	if _end_run_overlay:
		_end_run_overlay.visible = false
	_clear_gui_focus()


func _on_end_run_confirmed() -> void:
	hide_end_run_confirm()
	end_run_confirmed.emit()


func show_board_tower_tooltip_for(tower: Tower, screen_pos: Vector2) -> void:
	if board_tooltip == null:
		return
	if tower == null or not is_instance_valid(tower):
		board_tooltip.visible = false
		return
	board_tooltip_label.text = TowerData.tooltip_for_tower(tower)
	_place_board_tooltip(screen_pos)
	_tooltip_hide_at_msec = 0


func show_board_enemy_tooltip_for(enemy: Enemy, screen_pos: Vector2) -> void:
	if board_tooltip == null:
		return
	if enemy == null or not is_instance_valid(enemy) or not enemy.alive:
		board_tooltip.visible = false
		return
	board_tooltip_label.text = enemy.inspect_summary()
	_place_board_tooltip(screen_pos)
	# Main owns inspect pin (keeps HP live); do not auto-hide on timer.
	_tooltip_hide_at_msec = 0


func _place_board_tooltip(screen_pos: Vector2) -> void:
	board_tooltip.reset_size()
	var tip_size := board_tooltip.get_combined_minimum_size()
	var pos := screen_pos + Vector2(18, 18)
	var view := Vector2(GameLayout.VIEW_WIDTH, GameLayout.VIEW_HEIGHT)
	pos.x = minf(pos.x, view.x - tip_size.x - 8.0)
	pos.y = minf(pos.y, view.y - tip_size.y - 8.0)
	board_tooltip.position = pos
	board_tooltip.visible = true


## Touch-friendly inspect: pin tooltip near the board for a few seconds.
func show_touch_tower_info(tower: Tower) -> void:
	if tower == null or not is_instance_valid(tower):
		return
	var anchor := GameLayout.board_origin() + Vector2(12, 56)
	show_board_tower_tooltip_for(tower, anchor)
	_tooltip_hide_at_msec = Time.get_ticks_msec() + 2800


func hide_board_tower_tooltip() -> void:
	if board_tooltip:
		board_tooltip.visible = false
	_tooltip_hide_at_msec = 0


func tick_tooltips() -> void:
	if _tooltip_hide_at_msec > 0 and Time.get_ticks_msec() >= _tooltip_hide_at_msec:
		hide_board_tower_tooltip()


func is_tooltip_pinned() -> bool:
	return _tooltip_hide_at_msec > 0


func _toggle_multi_select() -> void:
	multi_select_enabled = not multi_select_enabled
	_refresh_multi_select_button()
	multi_select_changed.emit(multi_select_enabled)


func _refresh_multi_select_button() -> void:
	if multi_select_button == null:
		return
	multi_select_button.text = "Multi: On" if multi_select_enabled else "Multi: Off"
	multi_select_button.modulate = Color(1.15, 1.1, 0.7) if multi_select_enabled else Color.WHITE


func _toggle_pan_mode() -> void:
	set_pan_mode(not pan_mode_enabled)


func set_pan_mode(on: bool) -> void:
	if pan_mode_enabled == on:
		_refresh_pan_mode_button()
		return
	pan_mode_enabled = on
	_refresh_pan_mode_button()
	pan_mode_changed.emit(pan_mode_enabled)


func set_pan_available(available: bool) -> void:
	if pan_mode_button == null:
		return
	pan_mode_button.visible = available
	if not available and pan_mode_enabled:
		set_pan_mode(false)


func _refresh_pan_mode_button() -> void:
	if pan_mode_button == null:
		return
	pan_mode_button.text = "Pan: On" if pan_mode_enabled else "Pan: Off"
	pan_mode_button.modulate = Color(0.75, 1.15, 1.1) if pan_mode_enabled else Color.WHITE


func set_run_summary_presented(on: bool) -> void:
	if _top_bar:
		_top_bar.visible = not on
	if status_label:
		status_label.visible = not on
	if next_wave_brief_label:
		next_wave_brief_label.visible = not on
	if boss_hp_label:
		boss_hp_label.visible = not on and boss_hp_label.text != ""
	if _launcher_shell:
		_launcher_shell.visible = not on
	if on:
		if _actions_shell:
			_actions_shell.visible = false
		if _towers_panel:
			_towers_panel.visible = false
		if _send_panel:
			_send_panel.visible = false
	else:
		_apply_towers_shop_layout()
		_apply_send_shop_layout()
		_apply_actions_layout()
		_refresh_launcher_send_visibility()
	if _clash_root:
		_clash_root.visible = not on and clash_match != null
	hide_board_tower_tooltip()


func attach_run_summary(overlay: Control) -> void:
	set_run_summary_presented(true)
	_attach_fullscreen_overlay(overlay, 400)


func attach_pause_menu(overlay: Control) -> void:
	_attach_fullscreen_overlay(overlay, 350)


func _attach_fullscreen_overlay(overlay: Control, z: int) -> void:
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.offset_left = 0
	overlay.offset_top = 0
	overlay.offset_right = 0
	overlay.offset_bottom = 0
	overlay.z_index = z
	add_child(overlay)


func _make_actions_panel(root: Control) -> VBoxContainer:
	_actions_shell = PanelContainer.new()
	_actions_shell.visible = false
	_actions_shell.z_index = 26
	_actions_shell.mouse_filter = Control.MOUSE_FILTER_STOP
	_actions_shell.clip_contents = true
	_actions_shell.add_theme_stylebox_override("panel", _popup_panel_style())
	root.add_child(_actions_shell)

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_actions_shell.add_child(scroll)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 5)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(column)

	_actions_drag_bar = HBoxContainer.new()
	_actions_drag_bar.add_theme_constant_override("separation", 6)
	_actions_drag_bar.gui_input.connect(_on_actions_header_gui_input)
	column.add_child(_actions_drag_bar)
	var actions_title := Label.new()
	actions_title.text = "Actions"
	actions_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_actions_drag_bar.add_child(actions_title)
	var close_btn := Button.new()
	close_btn.text = "X"
	close_btn.focus_mode = Control.FOCUS_NONE
	close_btn.custom_minimum_size = Vector2(28, GameLayout.button_height(24.0))
	close_btn.tooltip_text = "Close actions"
	close_btn.pressed.connect(func() -> void:
		_actions_open = false
		_apply_actions_layout()
	)
	_actions_drag_bar.add_child(close_btn)
	return column


## Compact launcher under gold/lives: Towers / Send / Actions + always-visible Start/Skip.
## Drag the title bar to move; Hide collapses shop buttons (Start/Skip stay).
func _build_launcher_panel(root: Control) -> void:
	_launcher_shell = PanelContainer.new()
	_launcher_shell.z_index = 28
	_launcher_shell.mouse_filter = Control.MOUSE_FILTER_STOP
	_launcher_shell.add_theme_stylebox_override("panel", _popup_panel_style())
	root.add_child(_launcher_shell)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	_launcher_shell.add_child(column)

	_launcher_drag_bar = HBoxContainer.new()
	_launcher_drag_bar.add_theme_constant_override("separation", 6)
	_launcher_drag_bar.gui_input.connect(_on_launcher_header_gui_input)
	column.add_child(_launcher_drag_bar)

	_launcher_title = Label.new()
	_launcher_title.text = "Controls"
	_launcher_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_launcher_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_launcher_title.tooltip_text = "Drag to move"
	_launcher_drag_bar.add_child(_launcher_title)

	_launcher_hide_btn = Button.new()
	_launcher_hide_btn.focus_mode = Control.FOCUS_NONE
	_launcher_hide_btn.custom_minimum_size = Vector2(44, GameLayout.button_height(24.0))
	_launcher_hide_btn.pressed.connect(_toggle_launcher_collapsed)
	_launcher_drag_bar.add_child(_launcher_hide_btn)

	_launcher_body = VBoxContainer.new()
	_launcher_body.add_theme_constant_override("separation", 4)
	column.add_child(_launcher_body)

	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 4)
	_launcher_body.add_child(btn_row)

	var btn_h := GameLayout.button_height(26.0)
	_towers_toggle = Button.new()
	_towers_toggle.text = "Towers"
	_towers_toggle.focus_mode = Control.FOCUS_NONE
	_towers_toggle.custom_minimum_size = Vector2(64, btn_h)
	_towers_toggle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_towers_toggle.tooltip_text = "Open tower shop"
	_towers_toggle.pressed.connect(_toggle_towers_popup)
	btn_row.add_child(_towers_toggle)

	_send_toggle = Button.new()
	_send_toggle.text = "Send"
	_send_toggle.visible = false
	_send_toggle.focus_mode = Control.FOCUS_NONE
	_send_toggle.custom_minimum_size = Vector2(56, btn_h)
	_send_toggle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_send_toggle.tooltip_text = "Open Clash send shop"
	_send_toggle.pressed.connect(_toggle_send_popup)
	btn_row.add_child(_send_toggle)

	_actions_toggle = Button.new()
	_actions_toggle.text = "Actions"
	_actions_toggle.focus_mode = Control.FOCUS_NONE
	_actions_toggle.custom_minimum_size = Vector2(64, btn_h)
	_actions_toggle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_actions_toggle.tooltip_text = "Upgrade, sell, multi-select, pause…"
	_actions_toggle.pressed.connect(_toggle_actions_popup)
	btn_row.add_child(_actions_toggle)

	# Timer + Start/Skip stay outside the collapsible body so rounds remain one tap away.
	timer_label = Label.new()
	timer_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	timer_label.text = ""
	timer_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	timer_label.modulate = Color(0.85, 0.9, 0.7)
	column.add_child(timer_label)

	skip_button = _sidebar_button("Start Round", GameLayout.button_height(28.0))
	skip_button.disabled = false
	skip_button.tooltip_text = "Start the build timer, then waves begin"
	skip_button.pressed.connect(func() -> void: skip_timer_pressed.emit())
	column.add_child(skip_button)

	_launcher_shell.custom_minimum_size = Vector2(maxf(GameLayout.sidebar_width(), 200.0), 0)


func _popup_panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.16, 0.22, 0.94)
	style.border_color = Color(0.45, 0.85, 0.95, 0.95)
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	return style


func _build_towers_shop_panel(root: Control) -> void:
	_towers_panel = PanelContainer.new()
	_towers_panel.z_index = 26
	_towers_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_towers_panel.clip_contents = true
	_towers_panel.add_theme_stylebox_override("panel", _popup_panel_style())
	root.add_child(_towers_panel)
	_shop_shell = _towers_panel

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_towers_panel.add_child(scroll)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 5)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(column)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 4)
	header.mouse_filter = Control.MOUSE_FILTER_STOP
	header.tooltip_text = "Drag to move (when unpinned)"
	header.gui_input.connect(_on_towers_header_gui_input)
	column.add_child(header)
	_towers_drag_bar = header
	var shop_title := Label.new()
	shop_title.text = "Towers"
	shop_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	shop_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(shop_title)
	_towers_pin_btn = Button.new()
	_towers_pin_btn.focus_mode = Control.FOCUS_NONE
	_towers_pin_btn.custom_minimum_size = Vector2(52, GameLayout.button_height(24.0))
	_towers_pin_btn.pressed.connect(_toggle_towers_pin)
	header.add_child(_towers_pin_btn)
	var close_btn := Button.new()
	close_btn.text = "X"
	close_btn.focus_mode = Control.FOCUS_NONE
	close_btn.custom_minimum_size = Vector2(32, GameLayout.button_height(24.0))
	close_btn.pressed.connect(func() -> void:
		_towers_open = false
		_apply_towers_shop_layout()
	)
	header.add_child(close_btn)

	var tower_btn_h := GameLayout.button_height(26.0)
	for tower_id in TowerData.get_ids():
		var def := TowerData.get_def(tower_id)
		var btn := _sidebar_button("%s (%d)" % [def["display_name"], def["cost"]], tower_btn_h)
		btn.tooltip_text = TowerData.tooltip_for(tower_id)
		btn.pressed.connect(_on_tower_button.bind(tower_id))
		column.add_child(btn)
		tower_buttons[tower_id] = btn
	_refresh_shop_buttons()
	_refresh_towers_pin_button()


func _build_send_shop_panel(root: Control) -> void:
	_send_panel = PanelContainer.new()
	_send_panel.visible = false
	_send_panel.z_index = 26
	_send_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_send_panel.clip_contents = true
	_send_panel.add_theme_stylebox_override("panel", _popup_panel_style())
	root.add_child(_send_panel)

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_send_panel.add_child(scroll)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 5)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(column)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 4)
	header.mouse_filter = Control.MOUSE_FILTER_STOP
	header.tooltip_text = "Drag to move (when unpinned)"
	header.gui_input.connect(_on_send_header_gui_input)
	column.add_child(header)
	_send_drag_bar = header
	var send_title := Label.new()
	send_title.text = "Send"
	send_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	send_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	send_title.modulate = Color(0.85, 0.95, 0.7)
	header.add_child(send_title)
	_send_pin_btn = Button.new()
	_send_pin_btn.focus_mode = Control.FOCUS_NONE
	_send_pin_btn.custom_minimum_size = Vector2(52, GameLayout.button_height(24.0))
	_send_pin_btn.pressed.connect(_toggle_send_pin)
	header.add_child(_send_pin_btn)
	var close_btn := Button.new()
	close_btn.text = "X"
	close_btn.focus_mode = Control.FOCUS_NONE
	close_btn.custom_minimum_size = Vector2(32, GameLayout.button_height(24.0))
	close_btn.pressed.connect(func() -> void:
		_send_open = false
		_apply_send_shop_layout()
	)
	header.add_child(close_btn)

	_clash_send_box = VBoxContainer.new()
	_clash_send_box.add_theme_constant_override("separation", 4)
	_clash_send_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_clash_send_box.mouse_filter = Control.MOUSE_FILTER_STOP
	column.add_child(_clash_send_box)
	_refresh_send_pin_button()


func _toggle_towers_popup() -> void:
	if _towers_pinned:
		_towers_open = true
		_towers_panel.visible = true
		_apply_towers_shop_layout()
		return
	_towers_open = not _towers_open
	_apply_towers_shop_layout()


func _toggle_send_popup() -> void:
	if clash_match == null or game_state == null or not WaveScaler.is_clash_mode(game_state.game_mode):
		return
	if _send_pinned:
		_send_open = true
		_apply_send_shop_layout()
		return
	_send_open = not _send_open
	_apply_send_shop_layout()


func _toggle_actions_popup() -> void:
	_actions_open = not _actions_open
	_apply_actions_layout()


func _refresh_launcher_send_visibility() -> void:
	if _send_toggle == null:
		return
	var clash_on := (
		clash_match != null
		and game_state != null
		and WaveScaler.is_clash_mode(game_state.game_mode)
	)
	var overlay_on := _end_run_overlay != null and _end_run_overlay.visible
	_send_toggle.visible = clash_on and not overlay_on


func _toggle_towers_pin() -> void:
	_towers_pinned = not _towers_pinned
	UserSettings.set_towers_shop_pinned(_towers_pinned)
	if _towers_pinned:
		_towers_open = true
	_refresh_towers_pin_button()
	_apply_towers_shop_layout()


func _toggle_send_pin() -> void:
	_send_pinned = not _send_pinned
	UserSettings.set_send_shop_pinned(_send_pinned)
	if _send_pinned:
		_send_open = true
	_refresh_send_pin_button()
	_apply_send_shop_layout()


func _refresh_towers_pin_button() -> void:
	if _towers_pin_btn == null:
		return
	_towers_pin_btn.text = "Unpin" if _towers_pinned else "Pin"
	_towers_pin_btn.tooltip_text = (
		"Dock towers on the left sidebar" if not _towers_pinned else "Float as a popup again"
	)


func _refresh_send_pin_button() -> void:
	if _send_pin_btn == null:
		return
	_send_pin_btn.text = "Unpin" if _send_pinned else "Pin"
	_send_pin_btn.tooltip_text = (
		"Dock sends in the right actions area" if not _send_pinned else "Float as a popup again"
	)


func _launcher_bottom_y() -> float:
	if _launcher_shell == null:
		return 34.0
	return _launcher_shell.position.y + maxf(_launcher_shell.size.y, 48.0) + 4.0


func _toggle_launcher_collapsed() -> void:
	_launcher_collapsed = not _launcher_collapsed
	UserSettings.set_launcher_collapsed(_launcher_collapsed)
	_apply_launcher_layout()


func _apply_launcher_layout() -> void:
	if _launcher_shell == null:
		return
	var default_pos := Vector2(GameLayout.SIDEBAR_LEFT, 34.0)
	if _launcher_float_pos.x >= 0.0:
		_launcher_shell.position = _clamp_shop_pos(_launcher_float_pos, _launcher_shell.size)
	else:
		_launcher_shell.position = default_pos
	if _launcher_body:
		_launcher_body.visible = not _launcher_collapsed
	if _launcher_title:
		_launcher_title.text = "Controls" if not _launcher_collapsed else "Controls ▸"
	if _launcher_hide_btn:
		_launcher_hide_btn.text = "Hide" if not _launcher_collapsed else "Show"
		_launcher_hide_btn.tooltip_text = (
			"Collapse Towers / Send / Actions (timer + Start Round stay)"
			if not _launcher_collapsed
			else "Expand shop buttons"
		)


func _apply_towers_shop_layout() -> void:
	if _towers_panel == null:
		return
	_refresh_towers_pin_button()
	if _towers_pinned:
		var rect := GameLayout.sidebar_rect()
		var top_y := maxf(rect.position.y, _launcher_bottom_y())
		var height := maxf(GameLayout.VIEW_HEIGHT - top_y - 8.0, 160.0)
		_towers_panel.position = Vector2(rect.position.x, top_y)
		_towers_panel.size = Vector2(rect.size.x, height)
		_towers_panel.custom_minimum_size = Vector2(rect.size.x, height)
		_towers_panel.visible = true
		_towers_open = true
	elif _towers_open:
		var w := GameLayout.sidebar_width()
		var h := minf(GameLayout.board_pixel_size().y - 48.0, 520.0)
		_towers_panel.size = Vector2(w, h)
		_towers_panel.custom_minimum_size = Vector2(w, h)
		if _towers_float_pos.x >= 0.0:
			_towers_panel.position = _clamp_shop_pos(_towers_float_pos, _towers_panel.size)
		else:
			var board := GameLayout.board_origin()
			_towers_panel.position = Vector2(board.x + 6.0, board.y + 8.0)
		_towers_panel.visible = true
	else:
		_towers_panel.visible = false
	if _towers_toggle:
		_towers_toggle.modulate = Color(0.75, 1.15, 1.1) if _towers_panel.visible else Color.WHITE


func _apply_send_shop_layout() -> void:
	if _send_panel == null:
		return
	_refresh_send_pin_button()
	var clash_on := (
		clash_match != null
		and game_state != null
		and WaveScaler.is_clash_mode(game_state.game_mode)
	)
	if not clash_on:
		_send_panel.visible = false
		_refresh_launcher_send_visibility()
		return
	_refresh_launcher_send_visibility()
	if _send_pinned:
		var rect := GameLayout.right_sidebar_rect()
		var h := minf(rect.size.y * 0.48, 340.0)
		_send_panel.position = rect.position
		_send_panel.size = Vector2(rect.size.x, h)
		_send_panel.custom_minimum_size = Vector2(rect.size.x, h)
		_send_panel.visible = true
		_send_open = true
	elif _send_open:
		var board_sz := GameLayout.board_pixel_size()
		var w := maxf(GameLayout.sidebar_width(), 200.0)
		var h := minf(board_sz.y - 48.0, 420.0)
		_send_panel.size = Vector2(w, h)
		_send_panel.custom_minimum_size = Vector2(w, h)
		if _send_float_pos.x >= 0.0:
			_send_panel.position = _clamp_shop_pos(_send_float_pos, _send_panel.size)
		else:
			var board := GameLayout.board_origin()
			_send_panel.position = Vector2(board.x + board_sz.x - w - 6.0, board.y + 8.0)
		_send_panel.visible = true
	else:
		_send_panel.visible = false
	if _send_toggle:
		_send_toggle.modulate = Color(0.75, 1.15, 1.1) if _send_panel.visible else Color.WHITE


func _apply_actions_layout() -> void:
	if _actions_shell == null:
		return
	if _actions_open:
		var w := maxf(GameLayout.right_sidebar_min(), 160.0)
		var h := minf(GameLayout.board_pixel_size().y - 24.0, 480.0)
		_actions_shell.size = Vector2(w, h)
		_actions_shell.custom_minimum_size = Vector2(w, h)
		if _actions_float_pos.x >= 0.0:
			_actions_shell.position = _clamp_shop_pos(_actions_float_pos, _actions_shell.size)
		else:
			var board := GameLayout.board_origin()
			var board_sz := GameLayout.board_pixel_size()
			_actions_shell.position = Vector2(board.x + board_sz.x - w - 6.0, board.y + 8.0)
		_actions_shell.visible = true
	else:
		_actions_shell.visible = false
	if _actions_toggle:
		_actions_toggle.modulate = Color(0.75, 1.15, 1.1) if _actions_shell.visible else Color.WHITE


func _clamp_shop_pos(pos: Vector2, size: Vector2) -> Vector2:
	var view := get_viewport().get_visible_rect().size if get_viewport() else Vector2(1280, 720)
	var max_x := maxf(view.x - size.x - 4.0, 4.0)
	var max_y := maxf(view.y - size.y - 4.0, 4.0)
	return Vector2(clampf(pos.x, 4.0, max_x), clampf(pos.y, 4.0, max_y))


func _on_towers_header_gui_input(event: InputEvent) -> void:
	_handle_shop_drag(event, "towers")


func _on_send_header_gui_input(event: InputEvent) -> void:
	_handle_shop_drag(event, "send")


func _on_actions_header_gui_input(event: InputEvent) -> void:
	_handle_shop_drag(event, "actions")


func _on_launcher_header_gui_input(event: InputEvent) -> void:
	_handle_shop_drag(event, "launcher")


func _handle_shop_drag(event: InputEvent, which: String) -> void:
	var pinned := false
	if which == "towers":
		pinned = _towers_pinned
	elif which == "send":
		pinned = _send_pinned
	var panel: Control = null
	match which:
		"towers":
			panel = _towers_panel
		"send":
			panel = _send_panel
		"actions":
			panel = _actions_shell
		"launcher":
			panel = _launcher_shell
	if pinned or panel == null or not panel.visible:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index != MOUSE_BUTTON_LEFT or not mb.pressed:
			return
		# Don't steal clicks from Pin/X — only drag from title/empty header space.
		var bar: Control = null
		match which:
			"towers":
				bar = _towers_drag_bar
			"send":
				bar = _send_drag_bar
			"actions":
				bar = _actions_drag_bar
			"launcher":
				bar = _launcher_drag_bar
		if bar != null:
			for child in bar.get_children():
				if child is BaseButton:
					var btn := child as BaseButton
					if btn.get_global_rect().has_point(mb.global_position):
						return
		_drag_shop = which
		_drag_grab = mb.global_position - panel.global_position


func _input(event: InputEvent) -> void:
	if _drag_shop == "":
		return
	var panel: Control = null
	match _drag_shop:
		"towers":
			panel = _towers_panel
		"send":
			panel = _send_panel
		"actions":
			panel = _actions_shell
		"launcher":
			panel = _launcher_shell
	if panel == null:
		_drag_shop = ""
		return
	if event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		var next := _clamp_shop_pos(mm.global_position - _drag_grab, panel.size)
		panel.position = next
		match _drag_shop:
			"towers":
				_towers_float_pos = next
			"send":
				_send_float_pos = next
			"actions":
				_actions_float_pos = next
			"launcher":
				_launcher_float_pos = next
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed:
			_persist_shop_float_pos(_drag_shop)
			_drag_shop = ""
			get_viewport().set_input_as_handled()


func _persist_shop_float_pos(which: String) -> void:
	if which == "towers":
		UserSettings.set_towers_shop_pos(_towers_float_pos)
	elif which == "send":
		UserSettings.set_send_shop_pos(_send_float_pos)
	elif which == "launcher":
		UserSettings.set_launcher_pos(_launcher_float_pos)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if (event as InputEventKey).keycode == KEY_ESCAPE:
			var closed := false
			if not _towers_pinned and _towers_open:
				_towers_open = false
				_apply_towers_shop_layout()
				closed = true
			if not _send_pinned and _send_open:
				_send_open = false
				_apply_send_shop_layout()
				closed = true
			if _actions_open:
				_actions_open = false
				_apply_actions_layout()
				closed = true
			if closed:
				get_viewport().set_input_as_handled()


func _fill_actions_column(sidebar: VBoxContainer) -> void:
	# Timer + Start/Skip live on the left launcher (always visible).
	var action_h := GameLayout.button_height(28.0)

	upgrade_button = _sidebar_button("Upgrade", action_h)
	upgrade_button.disabled = true
	upgrade_button.tooltip_text = "Select towers to upgrade (3 levels, then a final elemental buff)"
	upgrade_button.pressed.connect(func() -> void: upgrade_pressed.emit())
	sidebar.add_child(upgrade_button)

	command_box = VBoxContainer.new()
	command_box.visible = false
	command_box.add_theme_constant_override("separation", 4)
	sidebar.add_child(command_box)
	var cmd_title := Label.new()
	cmd_title.text = "Command abilities"
	cmd_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cmd_title.modulate = Color(0.85, 0.9, 0.55)
	command_box.add_child(cmd_title)
	var ability_h := GameLayout.button_height(26.0)
	for ability_id in CommandAbilities.get_ids():
		var adef := CommandAbilities.get_def(ability_id)
		var abtn := _sidebar_button(
			"%s (%d)" % [adef.get("display_name", ability_id), int(adef.get("cost", 0))],
			ability_h
		)
		abtn.tooltip_text = CommandAbilities.tooltip_for(ability_id)
		abtn.pressed.connect(func() -> void: command_ability_pressed.emit(ability_id))
		command_box.add_child(abtn)
		ability_buttons[ability_id] = abtn

	var final_row := HBoxContainer.new()
	final_row.add_theme_constant_override("separation", 3)
	final_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sidebar.add_child(final_row)
	var final_h := GameLayout.button_height(26.0)
	for element_id in TowerData.FINAL_ELEMENTS:
		var label := TowerData.final_element_label(element_id)
		var short := label.substr(0, 3)
		var fbtn := Button.new()
		fbtn.text = short
		fbtn.focus_mode = Control.FOCUS_NONE
		fbtn.custom_minimum_size = Vector2(0, final_h)
		fbtn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		fbtn.disabled = true
		fbtn.tooltip_text = "Final upgrade: %s" % label
		fbtn.pressed.connect(func() -> void: final_element_pressed.emit(element_id))
		final_row.add_child(fbtn)
		final_buttons[element_id] = fbtn

	sell_button = _sidebar_button("Sell Selected", action_h)
	sell_button.disabled = true
	sell_button.pressed.connect(func() -> void: sell_pressed.emit())
	sidebar.add_child(sell_button)

	multi_select_button = _sidebar_button("Multi: Off", GameLayout.button_height(26.0))
	multi_select_button.tooltip_text = "Toggle multi-select (touch-friendly Ctrl/Shift)"
	multi_select_button.pressed.connect(_toggle_multi_select)
	sidebar.add_child(multi_select_button)
	_refresh_multi_select_button()

	pan_mode_button = _sidebar_button("Pan: Off", GameLayout.button_height(26.0))
	pan_mode_button.tooltip_text = "Drag the map without placing towers (also hold Space on desktop)"
	pan_mode_button.pressed.connect(_toggle_pan_mode)
	pan_mode_button.visible = false
	sidebar.add_child(pan_mode_button)
	_refresh_pan_mode_button()

	deselect_button = _sidebar_button("Deselect", GameLayout.button_height(26.0))
	deselect_button.disabled = true
	deselect_button.tooltip_text = "Clear tower selection"
	deselect_button.pressed.connect(func() -> void: deselect_pressed.emit())
	sidebar.add_child(deselect_button)

	var pause_btn := _sidebar_button("Pause", action_h)
	pause_btn.pressed.connect(func() -> void: pause_pressed.emit())
	sidebar.add_child(pause_btn)

	end_run_button = _sidebar_button("End Run", action_h)
	end_run_button.tooltip_text = "End this run and check the leaderboard"
	end_run_button.pressed.connect(show_end_run_confirm)
	sidebar.add_child(end_run_button)


func _sidebar_button(text: String, height: float) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.focus_mode = Control.FOCUS_NONE
	btn.custom_minimum_size = Vector2(0, height)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.clip_text = true
	btn.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	return btn


func _portal_slide_button(text: String, height: float) -> Button:
	var btn := _sidebar_button(text, height)
	btn.tooltip_text = (
		"Pay %d gold to slide one cell left/right on the same row (unlocks after wave %d)."
		% [WaveScaler.PORTAL_SLIDE_COST, WaveScaler.PORTAL_SLIDE_UNLOCK_WAVE]
	)
	return btn


## Floating bar on the map (not buried in the Actions list) for spawn/exit slides.
func _build_portal_slide_bar(root: Control) -> void:
	portal_slide_panel = PanelContainer.new()
	portal_slide_panel.visible = false
	portal_slide_panel.z_index = 25
	portal_slide_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var board := GameLayout.board_origin()
	portal_slide_panel.position = Vector2(board.x + 6.0, board.y + 6.0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.16, 0.22, 0.92)
	style.border_color = Color(0.45, 0.85, 0.95, 0.95)
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	portal_slide_panel.add_theme_stylebox_override("panel", style)
	root.add_child(portal_slide_panel)

	portal_slide_box = VBoxContainer.new()
	portal_slide_box.add_theme_constant_override("separation", 4)
	portal_slide_panel.add_child(portal_slide_box)

	var portal_title := Label.new()
	portal_title.text = "Move start / end  ·  %dg each" % WaveScaler.PORTAL_SLIDE_COST
	portal_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	portal_title.modulate = Color(0.75, 0.95, 1.0)
	portal_slide_box.add_child(portal_title)

	var slide_h := GameLayout.button_height(28.0)
	var spawn_row := HBoxContainer.new()
	spawn_row.add_theme_constant_override("separation", 4)
	portal_slide_box.add_child(spawn_row)
	spawn_left_button = _portal_slide_button("Start ◀", slide_h)
	spawn_left_button.pressed.connect(func() -> void: portal_slide_pressed.emit("spawn", -1))
	spawn_row.add_child(spawn_left_button)
	spawn_right_button = _portal_slide_button("Start ▶", slide_h)
	spawn_right_button.pressed.connect(func() -> void: portal_slide_pressed.emit("spawn", 1))
	spawn_row.add_child(spawn_right_button)

	var exit_row := HBoxContainer.new()
	exit_row.add_theme_constant_override("separation", 4)
	portal_slide_box.add_child(exit_row)
	exit_left_button = _portal_slide_button("End ◀", slide_h)
	exit_left_button.pressed.connect(func() -> void: portal_slide_pressed.emit("exit", -1))
	exit_row.add_child(exit_left_button)
	exit_right_button = _portal_slide_button("End ▶", slide_h)
	exit_right_button.pressed.connect(func() -> void: portal_slide_pressed.emit("exit", 1))
	exit_row.add_child(exit_right_button)


## Show spawn/exit slide controls when unlocked; enable each direction independently.
func refresh_portal_slides(
	unlocked: bool,
	can_afford: bool,
	can_spawn_left: bool,
	can_spawn_right: bool,
	can_exit_left: bool,
	can_exit_right: bool
) -> void:
	if portal_slide_panel == null:
		return
	portal_slide_panel.visible = unlocked
	if not unlocked:
		return
	if spawn_left_button:
		spawn_left_button.disabled = not (can_afford and can_spawn_left)
	if spawn_right_button:
		spawn_right_button.disabled = not (can_afford and can_spawn_right)
	if exit_left_button:
		exit_left_button.disabled = not (can_afford and can_exit_left)
	if exit_right_button:
		exit_right_button.disabled = not (can_afford and can_exit_right)


func _clear_gui_focus() -> void:
	var vp := get_viewport()
	if vp:
		vp.gui_release_focus()


func _on_tower_button(tower_id: String) -> void:
	if game_state != null and not TowerData.is_unlocked(tower_id, game_state.wave):
		var def := TowerData.get_def(tower_id)
		var cost := int(def.get("cost", 0))
		var need := TowerData.unlock_wave(tower_id)
		set_status(
			"%s unlocks at wave %d — %d gold" % [
				str(def.get("display_name", tower_id)),
				need,
				cost,
			]
		)
		return
	highlight_tower(tower_id)
	tower_type_selected.emit(tower_id)


func _refresh_shop_buttons() -> void:
	if tower_buttons.is_empty():
		return
	var wave := game_state.wave if game_state else 0
	var selected_id := ""
	for id in tower_buttons.keys():
		var existing: Button = tower_buttons[id]
		if existing.modulate.r > 1.1 and TowerData.is_unlocked(id, wave):
			selected_id = id
			break
	for tower_id in tower_buttons.keys():
		var btn: Button = tower_buttons[tower_id]
		var def := TowerData.get_def(tower_id)
		var unlocked := TowerData.is_unlocked(tower_id, wave)
		var cost := int(def.get("cost", 0))
		var name := str(def.get("display_name", tower_id))
		# Always show gold cost; locked towers also show which wave opens them.
		if unlocked:
			btn.text = "%s (%d)" % [name, cost]
			btn.disabled = false
			btn.tooltip_text = TowerData.tooltip_for(tower_id)
			btn.modulate = Color(1.2, 1.15, 0.7) if tower_id == selected_id else Color.WHITE
		else:
			var need := TowerData.unlock_wave(tower_id)
			btn.text = "%s (%d) · W%d" % [name, cost, need]
			btn.disabled = true
			btn.tooltip_text = "%s\nLocked — reach wave %d (%d gold)" % [
				TowerData.tooltip_for(tower_id),
				need,
				cost,
			]
			btn.modulate = Color(0.55, 0.55, 0.55)


func highlight_tower(tower_id: String) -> void:
	var wave := game_state.wave if game_state else 0
	for id in tower_buttons.keys():
		var btn: Button = tower_buttons[id]
		if not TowerData.is_unlocked(id, wave):
			btn.modulate = Color(0.55, 0.55, 0.55)
		else:
			btn.modulate = Color(1.2, 1.15, 0.7) if id == tower_id else Color.WHITE


func clear_tower_highlight() -> void:
	var wave := game_state.wave if game_state else 0
	for id in tower_buttons.keys():
		var btn: Button = tower_buttons[id]
		if not TowerData.is_unlocked(id, wave):
			btn.modulate = Color(0.55, 0.55, 0.55)
		else:
			btn.modulate = Color.WHITE


func set_banner(text: String) -> void:
	var cleaned := text.strip_edges()
	banner_label.text = cleaned
	banner_label.visible = cleaned != ""
	banner_label.tooltip_text = cleaned


func set_status(text: String) -> void:
	status_label.text = text


func set_next_wave_brief(text: String) -> void:
	if next_wave_brief_label:
		next_wave_brief_label.text = text


func update_boss_hp(name_text: String, ratio: float, visible: bool) -> void:
	if boss_hp_label == null:
		return
	boss_hp_label.visible = visible
	if not visible:
		return
	var pct := int(clampf(ratio, 0.0, 1.0) * 100.0)
	boss_hp_label.text = "%s  HP %d%%" % [name_text, pct]


func update_timer(seconds_left: float, can_skip: bool, mode: String) -> void:
	match mode:
		"prep":
			# Skip button already says Start Round — no redundant status line.
			timer_label.text = ""
			if game_state:
				set_next_wave_brief(_WavePreview.summary_line(1, game_state.game_mode, game_state.monster_mode))
			skip_button.text = "Start Round"
			skip_button.disabled = false
			skip_button.tooltip_text = "Start the build timer, then waves begin"
		"intermission":
			timer_label.text = "Next wave: %.1fs" % seconds_left
			if game_state:
				var nw := game_state.wave + 1
				set_next_wave_brief(_WavePreview.summary_line(nw, game_state.game_mode, game_state.monster_mode))
			skip_button.text = "Skip Timer"
			skip_button.disabled = not can_skip
			if can_skip:
				skip_button.tooltip_text = "Start the next wave now"
			else:
				skip_button.tooltip_text = "Path blocked or skip not available"
		_:
			timer_label.text = ""
			if can_skip:
				skip_button.text = "Send Next Wave"
				skip_button.disabled = false
				skip_button.tooltip_text = "Start the next wave now for bonus gold (alive enemies stay; unspawned leftovers are dropped)"
			else:
				skip_button.text = "Send Next Wave"
				skip_button.disabled = true
				skip_button.tooltip_text = "Kill 25% of enemies to unlock early send"


func update_enemies_remaining(remaining: int, alive: int, queued: int) -> void:
	if enemies_label == null:
		return
	if remaining <= 0:
		enemies_label.text = "Left: --"
		enemies_label.tooltip_text = "Enemies left until the board clears"
		return
	enemies_label.text = "Left: %d" % remaining
	enemies_label.tooltip_text = "%d on map, %d still spawning" % [alive, queued]


func set_skip_hint_ready() -> void:
	status_label.text = "25% kills — Send Next Wave for bonus gold (next enemies start now)."


func update_sell_button(count: int, sell_total: int) -> void:
	if count <= 0:
		sell_button.text = "Sell Selected"
		sell_button.disabled = true
		sell_button.tooltip_text = "Select towers to sell"
		if deselect_button:
			deselect_button.disabled = true
	else:
		sell_button.text = "Sell x%d" % count
		sell_button.disabled = false
		sell_button.tooltip_text = "Refund about %d gold" % sell_total
		if deselect_button:
			deselect_button.disabled = false
			deselect_button.tooltip_text = "Clear selection and stop placing (Esc / right-click)"


func update_upgrade_buttons(can_stat: bool, upgrade_cost: int, can_final: bool, final_cost: int) -> void:
	if upgrade_button:
		upgrade_button.disabled = not can_stat
		if can_stat:
			upgrade_button.text = "Upgrade (%d)" % upgrade_cost
			upgrade_button.tooltip_text = "Upgrade selected towers by 1 level (%d gold total)" % upgrade_cost
		else:
			upgrade_button.text = "Upgrade"
			upgrade_button.tooltip_text = "Select towers under +3 to upgrade"
	for element_id in final_buttons.keys():
		var btn: Button = final_buttons[element_id]
		btn.disabled = not can_final
		var label := TowerData.final_element_label(element_id)
		if can_final:
			btn.tooltip_text = "Final %s upgrade (%d gold total)" % [label, final_cost]
		else:
			btn.tooltip_text = "Final %s — needs +3 upgrades first" % label


func update_command_abilities(tower: Tower) -> void:
	_command_tower = tower if tower != null and is_instance_valid(tower) and TowerData.is_command(tower.tower_id) else null
	if command_box == null:
		return
	command_box.visible = _command_tower != null
	_refresh_command_ability_buttons()


func _refresh_command_ability_buttons() -> void:
	if command_box == null or not command_box.visible or _command_tower == null:
		return
	if not is_instance_valid(_command_tower):
		command_box.visible = false
		_command_tower = null
		return
	for ability_id in ability_buttons.keys():
		var btn: Button = ability_buttons[ability_id]
		var adef := CommandAbilities.get_def(ability_id)
		var cost := int(adef.get("cost", 0))
		var name := str(adef.get("display_name", ability_id))
		var cd := _command_tower.ability_cooldown_left(ability_id)
		var tip := CommandAbilities.tooltip_for(ability_id)
		var was_cd := float(_ability_was_on_cd.get(ability_id, 0.0))
		if was_cd > 0.05 and cd <= 0.05 and not UserSettings.is_performance_mode():
			btn.modulate = Color(1.3, 1.25, 0.85)
			btn.create_tween().tween_property(btn, "modulate", Color.WHITE, 0.35)
		_ability_was_on_cd[ability_id] = cd
		if cd > 0.05:
			btn.text = "%s (%.1fs)" % [name, cd]
			btn.disabled = true
			btn.tooltip_text = "%s\n\nCooling down…" % tip
		else:
			btn.text = "%s (%d)" % [name, cost]
			btn.disabled = game_state == null or not game_state.can_afford(cost)
			btn.tooltip_text = tip


func _process(_delta: float) -> void:
	if command_box != null and command_box.visible:
		_refresh_command_ability_buttons()


func refresh_run_labels() -> void:
	if game_state == null:
		return
	if difficulty_label:
		if WaveScaler.is_clash_mode(game_state.game_mode):
			difficulty_label.text = "Clash"
		else:
			difficulty_label.text = WaveScaler.difficulty_label(game_state.difficulty)
	if mode_label:
		if WaveScaler.is_clash_mode(game_state.game_mode):
			var n := clash_match.player_count() if clash_match != null else 0
			mode_label.text = "Map: Clash (%d lanes)" % n
			mode_label.tooltip_text = "Last standing wins. Send packs raise income."
		elif WaveScaler.is_random_mode(game_state.game_mode):
			mode_label.text = "Map: Random M%d  Seed: %d" % [
				game_state.map_sector,
				game_state.current_map_seed,
			]
			mode_label.tooltip_text = "Paste this seed into Classic → Custom layout to replay this map."
		elif WaveScaler.is_siege_mode(game_state.game_mode):
			mode_label.text = "Map: Siege"
			mode_label.tooltip_text = ""
		elif WaveScaler.is_custom_layout(game_state.map_layout_mode):
			mode_label.text = "Map: Classic  Seed: %d" % game_state.current_map_seed
			mode_label.tooltip_text = "Custom layout — fixed for this run."
		else:
			mode_label.text = "Map: Classic"
			mode_label.tooltip_text = ""
	if monsters_label:
		if WaveScaler.is_clash_mode(game_state.game_mode):
			monsters_label.text = "Send + defend"
			monsters_label.tooltip_text = "Buy sends in prep; bots never gang up on you."
		else:
			monsters_label.text = "Monsters: %s" % WaveScaler.monster_mode_label(game_state.monster_mode)
			if WaveScaler.is_randomize_monsters(game_state.monster_mode):
				monsters_label.tooltip_text = "Elemental resists grow with waves (all 4 by wave %d)" % MonsterTypes.RESISTS_AT_WAVE_4
			else:
				monsters_label.tooltip_text = "Standard wave mix — no elemental resists"
	refresh_clash_panel()


func _on_gold_changed(gold: int) -> void:
	gold_label.text = "Gold: %d" % gold
	_refresh_command_ability_buttons()
	if clash_match != null:
		refresh_clash_panel()


func _on_lives_changed(lives: int) -> void:
	lives_label.text = "Lives: %d" % lives
	if clash_match != null:
		refresh_clash_panel()


func _on_wave_changed(wave: int) -> void:
	wave_label.text = "Wave: %d" % wave
	_refresh_shop_buttons()
	# Announce towers that just became available (Vortex @ 12, Gatling @ 30, …).
	var prev := _last_shop_wave
	_last_shop_wave = wave
	if prev < 0:
		return
	var unlocked_now: PackedStringArray = PackedStringArray()
	for tower_id in TowerData.get_ids():
		var need := TowerData.unlock_wave(tower_id)
		if need <= 0 or wave < need or prev >= need:
			continue
		var def := TowerData.get_def(tower_id)
		unlocked_now.append(
			"%s (%d gold)" % [str(def.get("display_name", tower_id)), int(def.get("cost", 0))]
		)
	if unlocked_now.size() > 0:
		set_status("Unlocked: %s" % ", ".join(unlocked_now))
