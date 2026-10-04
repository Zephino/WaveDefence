extends Control

const SELECT_BORDER := Color(0.35, 0.95, 0.45)
const SELECT_BG := Color(0.16, 0.22, 0.18)
const NORMAL_BG := Color(0.14, 0.16, 0.19)

var version_label: Label
var mode_buttons: Dictionary = {}
var monster_mode_buttons: Dictionary = {}
var selected_mode: int = WaveScaler.GameMode.CLASSIC
var selected_monster_mode: int = WaveScaler.MonsterMode.CLASSIC


func _ready() -> void:
	selected_mode = Session.game_mode
	selected_monster_mode = Session.monster_mode
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_ui()


func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.08, 0.1, 0.13)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var touch_layout := GameLayout.use_touch_ui() or (
		OS.has_feature("web") and GameLayout.is_mobile_device()
	)

	var host: Control
	if touch_layout:
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

	var center := VBoxContainer.new()
	center.alignment = BoxContainer.ALIGNMENT_CENTER
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.add_theme_constant_override("separation", 10 if touch_layout else 12)
	host.add_child(center)

	var title := Label.new()
	title.text = "WAVE DEFENCE"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 40)
	center.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "Endless maze-builder tower defence"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.modulate = Color(0.7, 0.75, 0.8)
	center.add_child(subtitle)

	version_label = Label.new()
	version_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	version_label.modulate = Color(0.55, 0.6, 0.65)
	version_label.text = VersionInfo.label()
	center.add_child(version_label)

	center.add_child(_spacer(8))

	var mode_label := Label.new()
	mode_label.text = "Map"
	mode_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mode_label.modulate = Color(0.75, 0.8, 0.85)
	center.add_child(mode_label)

	center.add_child(_mode_button(
		"Classic — fixed map",
		WaveScaler.GameMode.CLASSIC
	))
	center.add_child(_mode_button(
		"Random — shifting maps every %d waves" % WaveScaler.MAP_ROTATE_EVERY,
		WaveScaler.GameMode.RANDOM
	))
	_refresh_mode_buttons()

	center.add_child(_spacer(6))

	var monster_label := Label.new()
	monster_label.text = "Monsters"
	monster_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	monster_label.modulate = Color(0.75, 0.8, 0.85)
	center.add_child(monster_label)

	center.add_child(_monster_mode_button(
		"Classic — standard wave mix",
		WaveScaler.MonsterMode.CLASSIC
	))
	center.add_child(_monster_mode_button(
		"Randomize — elemental resists (grow with waves)",
		WaveScaler.MonsterMode.RANDOMIZE
	))
	_refresh_monster_mode_buttons()

	center.add_child(_spacer(6))

	var diff_label := Label.new()
	diff_label.text = "Choose difficulty"
	diff_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	diff_label.modulate = Color(0.75, 0.8, 0.85)
	center.add_child(diff_label)

	center.add_child(_menu_button(
		"Easy  (%d gold)" % WaveScaler.STARTING_GOLD_EASY,
		func() -> void: _start_difficulty(WaveScaler.Difficulty.EASY)
	))
	center.add_child(_menu_button(
		"Medium  (%d gold)" % WaveScaler.STARTING_GOLD_MEDIUM,
		func() -> void: _start_difficulty(WaveScaler.Difficulty.MEDIUM)
	))
	center.add_child(_menu_button(
		"Hard  (%d gold)" % WaveScaler.STARTING_GOLD_HARD,
		func() -> void: _start_difficulty(WaveScaler.Difficulty.HARD)
	))
	center.add_child(_menu_button("Leaderboard", _on_leaderboard))
	if OS.has_feature("web"):
		center.add_child(_menu_button("Fullscreen", _on_fullscreen))
	center.add_child(_menu_button("Quit", _on_quit))

	center.add_child(_spacer(8))
	var boards_label := Label.new()
	boards_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	boards_label.modulate = Color(0.5, 0.58, 0.62)
	boards_label.text = _boards_status_text()
	center.add_child(boards_label)
	OnlineLeaderboard.boards_updated.connect(
		func(ok: bool) -> void:
			boards_label.text = "Leaderboards: Global" if ok else "Leaderboards: Local (offline)"
	)


func _boards_status_text() -> String:
	match OnlineLeaderboard.last_source:
		"global":
			return "Leaderboards: Global"
		"offline":
			return "Leaderboards: Local (offline)"
		_:
			return "Leaderboards: syncing…"


func _mode_button(text: String, mode: int) -> Button:
	var btn := _menu_button(text, func() -> void: _select_mode(mode))
	mode_buttons[mode] = btn
	return btn


func _monster_mode_button(text: String, mode: int) -> Button:
	var btn := _menu_button(text, func() -> void: _select_monster_mode(mode))
	monster_mode_buttons[mode] = btn
	return btn


func _menu_button(text: String, cb: Callable) -> Button:
	var btn := Button.new()
	btn.text = text
	var h := 52.0 if GameLayout.use_touch_ui() else 44.0
	var w := 420.0 if GameLayout.use_touch_ui() else 380.0
	btn.custom_minimum_size = Vector2(w, h)
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
		Color(0.75, 1.0, 0.8) if selected else Color(0.92, 0.94, 0.96)
	)
	btn.add_theme_color_override(
		"font_hover_color",
		Color(0.85, 1.0, 0.9) if selected else Color(1, 1, 1)
	)
	btn.add_theme_color_override(
		"font_pressed_color",
		Color(0.7, 0.95, 0.75) if selected else Color(0.85, 0.88, 0.9)
	)
	var box := StyleBoxFlat.new()
	box.bg_color = SELECT_BG if selected else NORMAL_BG
	box.set_border_width_all(4 if selected else 1)
	box.border_color = SELECT_BORDER if selected else Color(0.28, 0.32, 0.36)
	box.set_corner_radius_all(6)
	box.content_margin_left = 12
	box.content_margin_right = 12
	box.content_margin_top = 8
	box.content_margin_bottom = 8
	# Draw border outside the fill so it stays visible on dark themes.
	box.draw_center = true
	var hover := box.duplicate() as StyleBoxFlat
	hover.bg_color = box.bg_color.lightened(0.1)
	hover.border_color = SELECT_BORDER if selected else Color(0.4, 0.45, 0.5)
	var pressed := box.duplicate() as StyleBoxFlat
	pressed.bg_color = box.bg_color.darkened(0.08)
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		var sb: StyleBoxFlat = box if state == "normal" or state == "focus" or state == "disabled" else (hover if state == "hover" else pressed)
		btn.add_theme_stylebox_override(state, sb.duplicate() as StyleBoxFlat)


func _start_difficulty(difficulty: int) -> void:
	Session.go_game(difficulty, selected_mode, selected_monster_mode)


func _on_leaderboard() -> void:
	Session.go_leaderboard(-1)


func _on_fullscreen() -> void:
	Session.request_web_fullscreen()


func _on_quit() -> void:
	Session.quit_game()
