extends Control

const SELECT_BORDER := Color(0.32, 0.62, 0.4)
const SELECT_BG := Color(0.12, 0.16, 0.14)
const NORMAL_BG := Color(0.14, 0.16, 0.19)
const SELECT_FONT := Color(0.78, 0.88, 0.8)

var version_label: Label
var mode_buttons: Dictionary = {}
var monster_mode_buttons: Dictionary = {}
var selected_mode: int = WaveScaler.GameMode.CLASSIC
var selected_monster_mode: int = WaveScaler.MonsterMode.CLASSIC
var _large_controls_check: CheckButton
var _effects_check: CheckButton
var _center: VBoxContainer
var _touch_layout: bool = false
var _map_setup_overlay: Control
var _settings_overlay: Control
var _seed_overlay: Control
var _reopen_settings_after_rebuild: bool = false
var _setup_difficulty: int = WaveScaler.Difficulty.MEDIUM
var _setup_layout_mode: int = WaveScaler.MapLayoutMode.STANDARD
var _setup_seed_edit: LineEdit
var _setup_standard_btn: Button
var _setup_custom_btn: Button
var _setup_hint: Label
## View Seeds preview: 0 Classic Custom, 1 Random, 2 Siege.
var _seed_preview_kind: int = 0
var _seed_preview_buttons: Dictionary = {}
var _seed_view_edit: LineEdit
var _seed_resolved_label: Label
var _seed_status_label: Label
var _seed_viewport: SubViewport
var _seed_viewport_container: SubViewportContainer
var _seed_preview_grid: GameGrid
var _seed_preview_path: Pathfinder


func _ready() -> void:
	UserSettings.ensure_loaded()
	selected_mode = Session.game_mode
	selected_monster_mode = Session.monster_mode
	_setup_layout_mode = Session.map_layout_mode
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_ui()


func _build_ui() -> void:
	while get_child_count() > 0:
		var child := get_child(0)
		remove_child(child)
		child.free()

	var bg := ColorRect.new()
	bg.color = Color(0.08, 0.1, 0.13)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	_touch_layout = GameLayout.use_touch_ui() or (
		OS.has_feature("web") and GameLayout.is_mobile_device()
	) or UserSettings.is_large_controls()

	var host: Control
	if _touch_layout:
		var scroll := ScrollContainer.new()
		scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		add_child(scroll)
		var pad := MarginContainer.new()
		pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		pad.add_theme_constant_override("margin_left", 16)
		pad.add_theme_constant_override("margin_right", 16)
		pad.add_theme_constant_override("margin_top", 16)
		pad.add_theme_constant_override("margin_bottom", 24)
		scroll.add_child(pad)
		host = pad
	else:
		var center_host := CenterContainer.new()
		center_host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		center_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(center_host)
		host = center_host

	_center = VBoxContainer.new()
	_center.alignment = BoxContainer.ALIGNMENT_CENTER
	_center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_center.add_theme_constant_override("separation", 10 if _touch_layout else 12)
	host.add_child(_center)

	_build_header(_center)
	_build_map_monster_row(_center)
	_center.add_child(_spacer(8))
	_build_difficulty(_center)
	_center.add_child(_menu_button("Leaderboard", _on_leaderboard))
	_center.add_child(_menu_button("Settings", _show_settings_popup))
	_center.add_child(_menu_button("Quit", _on_quit))
	if _reopen_settings_after_rebuild:
		_reopen_settings_after_rebuild = false
		call_deferred("_show_settings_popup")

	_center.add_child(_spacer(8))
	var boards_label := Label.new()
	boards_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	boards_label.modulate = Color(0.5, 0.58, 0.62)
	boards_label.text = _boards_status_text()
	_center.add_child(boards_label)
	OnlineLeaderboard.boards_updated.connect(
		func(_ok: bool) -> void:
			boards_label.text = _boards_status_text()
	)


func _build_header(parent: VBoxContainer) -> void:
	var header := HBoxContainer.new()
	header.alignment = BoxContainer.ALIGNMENT_CENTER
	header.add_theme_constant_override("separation", 16)
	parent.add_child(header)

	var title := Label.new()
	title.text = "WAVE DEFENCE"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 40)
	header.add_child(title)

	version_label = Label.new()
	version_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	version_label.modulate = Color(0.55, 0.6, 0.65)
	version_label.text = "ver: %s" % VersionInfo.current()
	version_label.add_theme_font_size_override("font_size", 18)
	header.add_child(version_label)


func _build_map_monster_row(parent: VBoxContainer) -> void:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 16)
	parent.add_child(row)

	var map_col := _choice_column("Map")
	row.add_child(map_col)
	map_col.add_child(_mode_button("Classic", WaveScaler.GameMode.CLASSIC))
	map_col.add_child(_mode_button("Random", WaveScaler.GameMode.RANDOM))
	map_col.add_child(_mode_button("Siege", WaveScaler.GameMode.SIEGE))
	_refresh_mode_buttons()

	var mon_col := _choice_column("Monsters")
	row.add_child(mon_col)
	mon_col.add_child(_monster_mode_button("Classic", WaveScaler.MonsterMode.CLASSIC))
	mon_col.add_child(_monster_mode_button("Randomize", WaveScaler.MonsterMode.RANDOMIZE))
	_refresh_monster_mode_buttons()


func _choice_column(title_text: String) -> VBoxContainer:
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 8)
	var label := Label.new()
	label.text = title_text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.modulate = Color(0.75, 0.8, 0.85)
	col.add_child(label)
	return col


func _build_difficulty(parent: VBoxContainer) -> void:
	var diff_label := Label.new()
	diff_label.text = "Difficulty"
	diff_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	diff_label.modulate = Color(0.75, 0.8, 0.85)
	parent.add_child(diff_label)

	parent.add_child(_menu_button(
		"Easy  (%d gold)" % WaveScaler.STARTING_GOLD_EASY,
		func() -> void: _start_difficulty(WaveScaler.Difficulty.EASY)
	))
	parent.add_child(_menu_button(
		"Medium  (%d gold)" % WaveScaler.STARTING_GOLD_MEDIUM,
		func() -> void: _start_difficulty(WaveScaler.Difficulty.MEDIUM)
	))
	parent.add_child(_menu_button(
		"Hard  (%d gold)" % WaveScaler.STARTING_GOLD_HARD,
		func() -> void: _start_difficulty(WaveScaler.Difficulty.HARD)
	))


func _boards_status_text() -> String:
	if not OnlineConfig.can_post():
		return "Leaderboards: Local (this device)"
	match OnlineLeaderboard.last_source:
		"global":
			return "Leaderboards: Global"
		"offline":
			return "Leaderboards: Local (offline)"
		_:
			return "Leaderboards: syncing…"


func _mode_button(text: String, mode: int) -> Button:
	var btn := _menu_button(text, func() -> void: _select_mode(mode), true)
	mode_buttons[mode] = btn
	return btn


func _monster_mode_button(text: String, mode: int) -> Button:
	var btn := _menu_button(text, func() -> void: _select_monster_mode(mode), true)
	monster_mode_buttons[mode] = btn
	return btn


func _menu_button_size(half_width: bool = false) -> Vector2:
	var h := GameLayout.button_height(44.0)
	var w := 420.0 if GameLayout.use_touch_ui() or UserSettings.is_large_controls() else 380.0
	if half_width:
		w = 200.0 if UserSettings.is_large_controls() or GameLayout.use_touch_ui() else 180.0
	return Vector2(w, h)


func _menu_button(text: String, cb: Callable, half_width: bool = false) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = _menu_button_size(half_width)
	btn.focus_mode = Control.FOCUS_NONE
	btn.pressed.connect(cb)
	return btn


func _spacer(height: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, height)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


func _select_mode(mode: int) -> void:
	selected_mode = mode
	Session.game_mode = mode
	_refresh_mode_buttons()


func _select_monster_mode(mode: int) -> void:
	selected_monster_mode = mode
	Session.monster_mode = mode
	_refresh_monster_mode_buttons()


func _refresh_mode_buttons() -> void:
	for mode in mode_buttons.keys():
		var btn: Button = mode_buttons[mode]
		_apply_choice_style(btn, int(mode) == selected_mode)


func _refresh_monster_mode_buttons() -> void:
	for mode in monster_mode_buttons.keys():
		var btn: Button = monster_mode_buttons[mode]
		_apply_choice_style(btn, int(mode) == selected_monster_mode)


func _apply_choice_style(btn: Button, selected: bool) -> void:
	# Don't use modulate for selection — it washes out StyleBox borders on web.
	btn.modulate = Color.WHITE
	btn.add_theme_color_override(
		"font_color",
		SELECT_FONT if selected else Color(0.92, 0.94, 0.96)
	)
	btn.add_theme_color_override(
		"font_hover_color",
		SELECT_FONT.lightened(0.08) if selected else Color(1, 1, 1)
	)
	btn.add_theme_color_override(
		"font_pressed_color",
		SELECT_FONT.darkened(0.08) if selected else Color(0.85, 0.88, 0.9)
	)
	var box := StyleBoxFlat.new()
	box.bg_color = SELECT_BG if selected else NORMAL_BG
	box.set_border_width_all(3 if selected else 1)
	box.border_color = SELECT_BORDER if selected else Color(0.28, 0.32, 0.36)
	box.set_corner_radius_all(6)
	box.content_margin_left = 12
	box.content_margin_right = 12
	box.content_margin_top = 8
	box.content_margin_bottom = 8
	box.draw_center = true
	var hover := box.duplicate() as StyleBoxFlat
	hover.bg_color = box.bg_color.lightened(0.06)
	hover.border_color = SELECT_BORDER.lightened(0.08) if selected else Color(0.4, 0.45, 0.5)
	var pressed := box.duplicate() as StyleBoxFlat
	pressed.bg_color = box.bg_color.darkened(0.06)

	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		var sb: StyleBoxFlat = box if state == "normal" or state == "focus" or state == "disabled" else (hover if state == "hover" else pressed)
		btn.add_theme_stylebox_override(state, sb.duplicate() as StyleBoxFlat)


func _on_large_controls_toggled(on: bool) -> void:
	UserSettings.set_large_controls(on)
	# Rebuild so button sizes / scroll layout match immediately.
	_reopen_settings_after_rebuild = (
		_settings_overlay != null and is_instance_valid(_settings_overlay)
	)
	var had_setup := _map_setup_overlay != null and is_instance_valid(_map_setup_overlay)
	_hide_seed_browser()
	_hide_settings_popup()
	_map_setup_overlay = null
	mode_buttons.clear()
	monster_mode_buttons.clear()
	_build_ui()
	if had_setup:
		_show_map_setup(_setup_difficulty)


func _on_effects_toggled(on: bool) -> void:
	UserSettings.set_effects_enabled(on)


func _panel_style() -> StyleBoxFlat:
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.11, 0.13, 0.16)
	panel_style.set_border_width_all(2)
	panel_style.border_color = Color(0.28, 0.34, 0.4)
	panel_style.set_corner_radius_all(10)
	panel_style.content_margin_left = 20
	panel_style.content_margin_right = 20
	panel_style.content_margin_top = 16
	panel_style.content_margin_bottom = 16
	return panel_style


func _make_modal_overlay(z: int) -> Dictionary:
	var overlay := Control.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.z_index = z
	add_child(overlay)
	var dim := ColorRect.new()
	dim.color = Color(0.04, 0.05, 0.07, 0.82)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _panel_style())
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	return {"overlay": overlay, "box": box}


func _show_settings_popup() -> void:
	_hide_seed_browser()
	if _settings_overlay != null and is_instance_valid(_settings_overlay):
		_settings_overlay.queue_free()
	var modal := _make_modal_overlay(25)
	_settings_overlay = modal["overlay"]
	var box: VBoxContainer = modal["box"]

	var title := Label.new()
	title.text = "Settings"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 22)
	box.add_child(title)

	_large_controls_check = CheckButton.new()
	_large_controls_check.text = "Large Controls"
	_large_controls_check.button_pressed = UserSettings.is_large_controls()
	_large_controls_check.focus_mode = Control.FOCUS_NONE
	_large_controls_check.custom_minimum_size = Vector2(320, GameLayout.button_height(40.0))
	_large_controls_check.toggled.connect(_on_large_controls_toggled)
	box.add_child(_large_controls_check)

	_effects_check = CheckButton.new()
	_effects_check.text = "Effects"
	_effects_check.tooltip_text = "Tower attack visuals (flame, ice, poison cloud, lightning)."
	_effects_check.button_pressed = UserSettings.is_effects_enabled()
	_effects_check.focus_mode = Control.FOCUS_NONE
	_effects_check.custom_minimum_size = Vector2(320, GameLayout.button_height(40.0))
	_effects_check.toggled.connect(_on_effects_toggled)
	box.add_child(_effects_check)

	if OS.has_feature("web"):
		box.add_child(_menu_button("Fullscreen", _on_fullscreen, true))

	box.add_child(_menu_button("View Seeds", _show_seed_browser, true))
	box.add_child(_menu_button("Close", _hide_settings_popup, true))


func _hide_settings_popup() -> void:
	if _settings_overlay != null and is_instance_valid(_settings_overlay):
		_settings_overlay.queue_free()
	_settings_overlay = null
	_large_controls_check = null
	_effects_check = null


func _default_seed_preview_kind() -> int:
	if WaveScaler.is_siege_mode(selected_mode):
		return 2
	if WaveScaler.is_random_mode(selected_mode):
		return 1
	return 0


func _show_seed_browser() -> void:
	_hide_seed_browser()
	_seed_preview_kind = _default_seed_preview_kind()
	var modal := _make_modal_overlay(30)
	_seed_overlay = modal["overlay"]
	var box: VBoxContainer = modal["box"]

	var title := Label.new()
	title.text = "View Seeds"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 22)
	box.add_child(title)

	var hint := Label.new()
	hint.text = "Preview Classic Custom / Random / Siege layouts. Type a seed or Randomize."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size = Vector2(420, 0)
	hint.modulate = Color(0.7, 0.75, 0.8)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(hint)

	var type_label := Label.new()
	type_label.text = "Map type"
	type_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	type_label.modulate = Color(0.75, 0.8, 0.85)
	box.add_child(type_label)

	var type_row := HBoxContainer.new()
	type_row.alignment = BoxContainer.ALIGNMENT_CENTER
	type_row.add_theme_constant_override("separation", 8)
	box.add_child(type_row)
	_seed_preview_buttons.clear()
	for item in [
		{"kind": 0, "label": "Classic Custom"},
		{"kind": 1, "label": "Random"},
		{"kind": 2, "label": "Siege"},
	]:
		var kind: int = int(item["kind"])
		var btn := _menu_button(str(item["label"]), func() -> void:
			_seed_preview_kind = kind
			_refresh_seed_preview_buttons()
			_refresh_seed_preview()
		, true)
		btn.custom_minimum_size = Vector2(130, GameLayout.button_height(36.0))
		type_row.add_child(btn)
		_seed_preview_buttons[kind] = btn
	_refresh_seed_preview_buttons()

	var seed_label := Label.new()
	seed_label.text = "Seed"
	seed_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	seed_label.modulate = Color(0.75, 0.8, 0.85)
	box.add_child(seed_label)

	_seed_view_edit = LineEdit.new()
	_seed_view_edit.placeholder_text = "Type a seed or Randomize"
	_seed_view_edit.text = Session.map_seed_text
	_seed_view_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_seed_view_edit.custom_minimum_size = Vector2(420, GameLayout.button_height(40.0))
	_seed_view_edit.focus_mode = Control.FOCUS_CLICK
	_seed_view_edit.text_submitted.connect(func(_t: String) -> void: _refresh_seed_preview())
	box.add_child(_seed_view_edit)

	_seed_resolved_label = Label.new()
	_seed_resolved_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_seed_resolved_label.modulate = Color(0.55, 0.65, 0.7)
	box.add_child(_seed_resolved_label)

	var seed_actions := HBoxContainer.new()
	seed_actions.alignment = BoxContainer.ALIGNMENT_CENTER
	seed_actions.add_theme_constant_override("separation", 10)
	box.add_child(seed_actions)
	seed_actions.add_child(_menu_button("Randomize", _randomize_seed_preview, true))
	seed_actions.add_child(_menu_button("Preview", _refresh_seed_preview, true))

	_seed_viewport_container = SubViewportContainer.new()
	_seed_viewport_container.stretch = true
	_seed_viewport_container.custom_minimum_size = Vector2(420, 300)
	box.add_child(_seed_viewport_container)

	_seed_viewport = SubViewport.new()
	_seed_viewport.transparent_bg = true
	_seed_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_seed_viewport_container.add_child(_seed_viewport)

	_seed_preview_grid = GameGrid.new()
	_seed_preview_grid.name = "SeedPreviewGrid"
	_seed_viewport.add_child(_seed_preview_grid)
	_seed_preview_path = Pathfinder.new(_seed_preview_grid)

	_seed_status_label = Label.new()
	_seed_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_seed_status_label.modulate = Color(0.75, 0.85, 0.55)
	box.add_child(_seed_status_label)

	var bottom := HBoxContainer.new()
	bottom.alignment = BoxContainer.ALIGNMENT_CENTER
	bottom.add_theme_constant_override("separation", 12)
	box.add_child(bottom)
	bottom.add_child(_menu_button("Use seed", _use_seed_from_preview, true))
	bottom.add_child(_menu_button("Close", _hide_seed_browser, true))

	if _seed_view_edit.text.strip_edges() == "":
		_randomize_seed_preview()
	else:
		_refresh_seed_preview()


func _refresh_seed_preview_buttons() -> void:
	for kind in _seed_preview_buttons.keys():
		var btn: Button = _seed_preview_buttons[kind]
		_apply_choice_style(btn, int(kind) == _seed_preview_kind)


func _resolved_preview_seed() -> int:
	var text := ""
	if _seed_view_edit:
		text = _seed_view_edit.text.strip_edges()
	var parsed := WaveScaler.parse_seed_text(text)
	if parsed < 0:
		return WaveScaler.roll_seed()
	return parsed


func _randomize_seed_preview() -> void:
	var rolled := WaveScaler.roll_seed()
	if _seed_view_edit:
		_seed_view_edit.text = str(rolled)
	_refresh_seed_preview()


func _refresh_seed_preview() -> void:
	if _seed_preview_grid == null or _seed_viewport == null:
		return
	var seed_val := _resolved_preview_seed()
	if _seed_view_edit and _seed_view_edit.text.strip_edges() == "":
		_seed_view_edit.text = str(seed_val)
	if _seed_preview_kind == 2:
		_seed_preview_grid.generate_siege_layout(seed_val)
	else:
		_seed_preview_grid.generate_random_layout(seed_val)
	_seed_preview_path = Pathfinder.new(_seed_preview_grid)
	_seed_preview_path.rebuild()
	_seed_preview_grid.set_path_preview(_seed_preview_path.get_world_path())
	_seed_preview_grid.queue_redraw()

	var map_size := _seed_preview_grid.map_pixel_size()
	_seed_viewport.size = Vector2i(maxi(int(map_size.x), 1), maxi(int(map_size.y), 1))
	var max_w := 420.0
	var max_h := 320.0
	var scale_f := minf(max_w / maxf(map_size.x, 1.0), max_h / maxf(map_size.y, 1.0))
	_seed_viewport_container.custom_minimum_size = Vector2(
		maxi(int(map_size.x * scale_f), 120),
		maxi(int(map_size.y * scale_f), 90)
	)
	var shown := _seed_preview_grid.last_layout_seed if _seed_preview_grid.last_layout_seed >= 0 else seed_val
	if _seed_resolved_label:
		_seed_resolved_label.text = "Resolved seed: %d" % shown
	if _seed_status_label:
		_seed_status_label.text = ""


func _use_seed_from_preview() -> void:
	var seed_val := _resolved_preview_seed()
	if _seed_preview_grid and _seed_preview_grid.last_layout_seed >= 0:
		seed_val = _seed_preview_grid.last_layout_seed
	Session.map_seed_text = str(seed_val)
	if _seed_view_edit:
		_seed_view_edit.text = Session.map_seed_text
	if _seed_status_label:
		_seed_status_label.text = "Seed saved for Map setup: %s" % Session.map_seed_text


func _hide_seed_browser() -> void:
	if _seed_overlay != null and is_instance_valid(_seed_overlay):
		_seed_overlay.queue_free()
	_seed_overlay = null
	_seed_view_edit = null
	_seed_resolved_label = null
	_seed_status_label = null
	_seed_viewport = null
	_seed_viewport_container = null
	_seed_preview_grid = null
	_seed_preview_path = null
	_seed_preview_buttons.clear()


func _start_difficulty(difficulty: int) -> void:
	if WaveScaler.is_siege_mode(selected_mode):
		Session.map_layout_mode = WaveScaler.MapLayoutMode.STANDARD
		Session.run_seed = -1
		Session.current_map_seed = -1
		Session.map_seed_text = ""
		Session.go_game(difficulty, selected_mode, selected_monster_mode)
		return
	_show_map_setup(difficulty)


func _show_map_setup(difficulty: int) -> void:
	_setup_difficulty = difficulty
	if _map_setup_overlay != null and is_instance_valid(_map_setup_overlay):
		_map_setup_overlay.queue_free()
	_map_setup_overlay = Control.new()
	_map_setup_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_map_setup_overlay.z_index = 20
	add_child(_map_setup_overlay)

	var dim := ColorRect.new()
	dim.color = Color(0.04, 0.05, 0.07, 0.82)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_map_setup_overlay.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_map_setup_overlay.add_child(center)

	var panel := PanelContainer.new()
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.11, 0.13, 0.16)
	panel_style.set_border_width_all(2)
	panel_style.border_color = Color(0.28, 0.34, 0.4)
	panel_style.set_corner_radius_all(10)
	panel_style.content_margin_left = 20
	panel_style.content_margin_right = 20
	panel_style.content_margin_top = 16
	panel_style.content_margin_bottom = 16
	panel.add_theme_stylebox_override("panel", panel_style)
	center.add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)

	var title := Label.new()
	title.text = "Map setup — %s / %s" % [
		WaveScaler.mode_label(selected_mode),
		WaveScaler.difficulty_label(difficulty),
	]
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 22)
	box.add_child(title)

	if WaveScaler.is_random_mode(selected_mode):
		_setup_layout_mode = WaveScaler.MapLayoutMode.CUSTOM
		var rnd_note := Label.new()
		rnd_note.text = "Random maps shift every %d waves. Optional seed makes the run reproducible." % WaveScaler.MAP_ROTATE_EVERY
		rnd_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		rnd_note.custom_minimum_size = Vector2(360, 0)
		rnd_note.modulate = Color(0.7, 0.75, 0.8)
		box.add_child(rnd_note)
	else:
		var layout_label := Label.new()
		layout_label.text = "Layout"
		layout_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		layout_label.modulate = Color(0.75, 0.8, 0.85)
		box.add_child(layout_label)

		var layout_row := HBoxContainer.new()
		layout_row.alignment = BoxContainer.ALIGNMENT_CENTER
		layout_row.add_theme_constant_override("separation", 10)
		box.add_child(layout_row)

		_setup_standard_btn = _menu_button("Standard", func() -> void:
			_setup_layout_mode = WaveScaler.MapLayoutMode.STANDARD
			_refresh_setup_layout_buttons()
			_update_setup_seed_enabled()
		, true)
		_setup_custom_btn = _menu_button("Custom layout", func() -> void:
			_setup_layout_mode = WaveScaler.MapLayoutMode.CUSTOM
			_refresh_setup_layout_buttons()
			_update_setup_seed_enabled()
		, true)
		layout_row.add_child(_setup_standard_btn)
		layout_row.add_child(_setup_custom_btn)
		_refresh_setup_layout_buttons()

	var seed_label := Label.new()
	seed_label.text = "Seed (optional)"
	seed_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	seed_label.modulate = Color(0.75, 0.8, 0.85)
	box.add_child(seed_label)

	_setup_seed_edit = LineEdit.new()
	_setup_seed_edit.placeholder_text = "Leave blank for a random seed"
	_setup_seed_edit.text = Session.map_seed_text
	_setup_seed_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_setup_seed_edit.custom_minimum_size = Vector2(360, GameLayout.button_height(40.0))
	_setup_seed_edit.focus_mode = Control.FOCUS_CLICK
	box.add_child(_setup_seed_edit)

	_setup_hint = Label.new()
	_setup_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_setup_hint.custom_minimum_size = Vector2(360, 0)
	_setup_hint.modulate = Color(0.55, 0.6, 0.65)
	_setup_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_setup_hint)
	_update_setup_seed_enabled()

	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	actions.add_theme_constant_override("separation", 12)
	box.add_child(actions)
	actions.add_child(_menu_button("Back", _hide_map_setup, true))
	actions.add_child(_menu_button("Start", _confirm_map_setup, true))


func _refresh_setup_layout_buttons() -> void:
	if _setup_standard_btn:
		_apply_choice_style(_setup_standard_btn, _setup_layout_mode == WaveScaler.MapLayoutMode.STANDARD)
	if _setup_custom_btn:
		_apply_choice_style(_setup_custom_btn, _setup_layout_mode == WaveScaler.MapLayoutMode.CUSTOM)


func _update_setup_seed_enabled() -> void:
	if _setup_seed_edit == null:
		return
	var need_seed := (
		WaveScaler.is_random_mode(selected_mode)
		or _setup_layout_mode == WaveScaler.MapLayoutMode.CUSTOM
	)
	_setup_seed_edit.editable = need_seed
	_setup_seed_edit.modulate = Color.WHITE if need_seed else Color(0.5, 0.5, 0.5)
	if _setup_hint:
		if WaveScaler.is_random_mode(selected_mode):
			_setup_hint.text = "Same starting seed → same sector maps. HUD shows each map seed to replay in Classic → Custom."
		elif _setup_layout_mode == WaveScaler.MapLayoutMode.CUSTOM:
			_setup_hint.text = "Custom layout stays fixed all run. Paste a seed from Random HUD to replay that map."
		else:
			_setup_hint.text = "Standard uses the fixed left→right corridor (seed ignored)."


func _hide_map_setup() -> void:
	if _map_setup_overlay != null and is_instance_valid(_map_setup_overlay):
		_map_setup_overlay.queue_free()
	_map_setup_overlay = null


func _confirm_map_setup() -> void:
	var seed_text := ""
	if _setup_seed_edit:
		seed_text = _setup_seed_edit.text.strip_edges()
	var layout_mode := _setup_layout_mode
	if WaveScaler.is_random_mode(selected_mode):
		layout_mode = WaveScaler.MapLayoutMode.CUSTOM
	elif layout_mode == WaveScaler.MapLayoutMode.STANDARD:
		seed_text = ""
	var parsed := WaveScaler.parse_seed_text(seed_text)
	Session.go_game(
		_setup_difficulty,
		selected_mode,
		selected_monster_mode,
		layout_mode,
		parsed,
		seed_text
	)


func _on_leaderboard() -> void:
	Session.go_leaderboard(-1)


func _on_fullscreen() -> void:
	Session.request_web_fullscreen()


func _on_quit() -> void:
	Session.quit_game()
