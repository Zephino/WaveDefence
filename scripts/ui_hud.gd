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
signal pause_pressed
signal copy_seed_pressed

var game_state: GameState
var multi_select_enabled: bool = false

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
var end_run_button: Button
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
var boss_hp_label: Label
var next_wave_brief_label: Label
var copy_seed_button: Button


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

	var dual_sides := GameLayout.use_dual_sidebars()
	# Left shop may scroll if the tower list grows; actions stay on the right.
	var left_box := _make_side_panel(root, GameLayout.sidebar_rect(), true)
	_fill_shop_column(left_box)

	var action_parent: VBoxContainer = left_box
	if dual_sides:
		action_parent = _make_side_panel(root, GameLayout.right_sidebar_rect(), false)
		var actions_title := Label.new()
		actions_title.text = "Actions"
		actions_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
		action_parent.add_child(actions_title)
	else:
		var spacer := Control.new()
		spacer.custom_minimum_size = Vector2(0, 4)
		spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		left_box.add_child(spacer)

	_fill_actions_column(action_parent)

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

	highlight_tower("gunner")
	update_upgrade_buttons(false, 0, false, 0)


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
	board_tooltip.reset_size()
	var tip_size := board_tooltip.get_combined_minimum_size()
	var pos := screen_pos + Vector2(18, 18)
	var view := Vector2(GameLayout.VIEW_WIDTH, GameLayout.VIEW_HEIGHT)
	pos.x = minf(pos.x, view.x - tip_size.x - 8.0)
	pos.y = minf(pos.y, view.y - tip_size.y - 8.0)
	board_tooltip.position = pos
	board_tooltip.visible = true
	_tooltip_hide_at_msec = 0


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


func _make_side_panel(root: Control, rect: Rect2, with_scroll: bool) -> VBoxContainer:
	var side_panel := PanelContainer.new()
	side_panel.position = rect.position
	side_panel.size = rect.size
	side_panel.custom_minimum_size = rect.size
	side_panel.clip_contents = true
	root.add_child(side_panel)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 5)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	if with_scroll:
		var scroll := ScrollContainer.new()
		scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		side_panel.add_child(scroll)
		scroll.add_child(column)
	else:
		side_panel.add_child(column)
	return column


func _fill_shop_column(sidebar: VBoxContainer) -> void:
	var shop_title := Label.new()
	shop_title.text = "Towers"
	shop_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sidebar.add_child(shop_title)

	var tower_btn_h := GameLayout.button_height(26.0)
	for tower_id in TowerData.get_ids():
		var def := TowerData.get_def(tower_id)
		var btn := _sidebar_button("%s (%d)" % [def["display_name"], def["cost"]], tower_btn_h)
		btn.tooltip_text = TowerData.tooltip_for(tower_id)
		btn.pressed.connect(_on_tower_button.bind(tower_id))
		sidebar.add_child(btn)
		tower_buttons[tower_id] = btn
	_refresh_shop_buttons()


func _fill_actions_column(sidebar: VBoxContainer) -> void:
	timer_label = Label.new()
	timer_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	timer_label.text = "Next wave: --"
	timer_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	timer_label.modulate = Color(0.85, 0.9, 0.7)
	sidebar.add_child(timer_label)

	var action_h := GameLayout.button_height(28.0)
	skip_button = _sidebar_button("Skip Timer", action_h)
	skip_button.disabled = true
	skip_button.tooltip_text = "Skip the countdown when unlocked"
	skip_button.pressed.connect(func() -> void: skip_timer_pressed.emit())
	sidebar.add_child(skip_button)

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

	deselect_button = _sidebar_button("Deselect", GameLayout.button_height(26.0))
	deselect_button.disabled = true
	deselect_button.tooltip_text = "Clear tower selection"
	deselect_button.pressed.connect(func() -> void: deselect_pressed.emit())
	sidebar.add_child(deselect_button)

	var pause_btn := _sidebar_button("Pause", action_h)
	pause_btn.pressed.connect(func() -> void: pause_pressed.emit())
	sidebar.add_child(pause_btn)

	copy_seed_button = _sidebar_button("Copy seed", GameLayout.button_height(26.0))
	copy_seed_button.visible = false
	copy_seed_button.pressed.connect(func() -> void: copy_seed_pressed.emit())
	sidebar.add_child(copy_seed_button)

	end_run_button = _sidebar_button("End Run", action_h)
	end_run_button.tooltip_text = "End this run and check the leaderboard"
	end_run_button.pressed.connect(show_end_run_confirm)
	sidebar.add_child(end_run_button)

	var help := Label.new()
	help.mouse_filter = Control.MOUSE_FILTER_IGNORE
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help.text = GameLayout.help_text()
	help.modulate = Color(0.6, 0.65, 0.7)
	sidebar.add_child(help)


func _sidebar_button(text: String, height: float) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.focus_mode = Control.FOCUS_NONE
	btn.custom_minimum_size = Vector2(0, height)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.clip_text = true
	btn.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	return btn


func _clear_gui_focus() -> void:
	var vp := get_viewport()
	if vp:
		vp.gui_release_focus()


func _on_tower_button(tower_id: String) -> void:
	if game_state != null and not TowerData.is_unlocked(tower_id, game_state.wave):
		set_status("Unlocks at wave %d" % TowerData.unlock_wave(tower_id))
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
		if unlocked:
			btn.text = "%s (%d)" % [name, cost]
			btn.disabled = false
			btn.tooltip_text = TowerData.tooltip_for(tower_id)
			btn.modulate = Color(1.2, 1.15, 0.7) if tower_id == selected_id else Color.WHITE
		else:
			var need := TowerData.unlock_wave(tower_id)
			btn.text = "%s (W%d)" % [name, need]
			btn.disabled = true
			btn.tooltip_text = "%s\nLocked — reach wave %d" % [TowerData.tooltip_for(tower_id), need]
			btn.modulate = Color(0.55, 0.55, 0.55)


func highlight_tower(tower_id: String) -> void:
	var wave := game_state.wave if game_state else 0
	for id in tower_buttons.keys():
		var btn: Button = tower_buttons[id]
		if not TowerData.is_unlocked(id, wave):
			btn.modulate = Color(0.55, 0.55, 0.55)
		else:
			btn.modulate = Color(1.2, 1.15, 0.7) if id == tower_id else Color.WHITE


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
			timer_label.text = "Build freely"
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
			timer_label.text = "Wave in progress"
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
			deselect_button.tooltip_text = "Clear %d selected tower(s) (Esc / right-click)" % count


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
		difficulty_label.text = WaveScaler.difficulty_label(game_state.difficulty)
	if copy_seed_button:
		copy_seed_button.visible = game_state.current_map_seed >= 0
	if mode_label:
		if WaveScaler.is_random_mode(game_state.game_mode):
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
		monsters_label.text = "Monsters: %s" % WaveScaler.monster_mode_label(game_state.monster_mode)
		if WaveScaler.is_randomize_monsters(game_state.monster_mode):
			monsters_label.tooltip_text = "Elemental resists grow with waves (all 4 by wave %d)" % MonsterTypes.RESISTS_AT_WAVE_4
		else:
			monsters_label.tooltip_text = "Standard wave mix — no elemental resists"


func _on_gold_changed(gold: int) -> void:
	gold_label.text = "Gold: %d" % gold
	_refresh_command_ability_buttons()


func _on_lives_changed(lives: int) -> void:
	lives_label.text = "Lives: %d" % lives


func _on_wave_changed(wave: int) -> void:
	wave_label.text = "Wave: %d" % wave
	_refresh_shop_buttons()
