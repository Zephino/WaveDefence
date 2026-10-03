extends Control

var version_label: Label
var mode_buttons: Dictionary = {}
var selected_mode: int = WaveScaler.GameMode.CLASSIC


func _ready() -> void:
	selected_mode = Session.game_mode
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_ui()


func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.08, 0.1, 0.13)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var center_host := CenterContainer.new()
	center_host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center_host)

	var center := VBoxContainer.new()
	center.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_theme_constant_override("separation", 12)
	center_host.add_child(center)

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

	center.add_child(_spacer(8))

	var mode_label := Label.new()
	mode_label.text = "Choose mode"
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
	center.add_child(_menu_button("Quit", _on_quit))

	version_label = Label.new()
	version_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	version_label.modulate = Color(0.55, 0.6, 0.65)
	version_label.text = VersionInfo.label()
	center.add_child(_spacer(12))
	center.add_child(version_label)

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


func _refresh_mode_buttons() -> void:
	for mode in mode_buttons.keys():
		var btn: Button = mode_buttons[mode]
		btn.modulate = Color(1.2, 1.15, 0.7) if int(mode) == selected_mode else Color.WHITE


func _start_difficulty(difficulty: int) -> void:
	Session.go_game(difficulty, selected_mode)


func _on_leaderboard() -> void:
	Session.go_leaderboard(-1)


func _on_quit() -> void:
	Session.quit_game()
