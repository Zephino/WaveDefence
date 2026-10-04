extends Control

var list_label: Label
var status_label: Label
var title_label: Label
var source_label: Label
var entry_box: VBoxContainer
var name_input: LineEdit
var submit_button: Button
var diff_buttons: Dictionary = {}
var wave_score: int = -1
var view_difficulty: int = WaveScaler.Difficulty.MEDIUM
var score_difficulty: int = WaveScaler.Difficulty.MEDIUM
var can_enter: bool = false
var _leaving: bool = false


func _ready() -> void:
	wave_score = Session.pending_wave_score
	var debug_used := Session.pending_debug_used
	score_difficulty = Session.pending_difficulty
	view_difficulty = score_difficulty
	can_enter = (
		wave_score > 0
		and not debug_used
		and LeaderboardStore.qualifies(wave_score, score_difficulty)
	)
	_build_ui()
	_refresh_diff_buttons()
	_refresh_list()
	_refresh_status(debug_used)
	_refresh_source_label()
	if not OnlineLeaderboard.boards_updated.is_connected(_on_boards_updated):
		OnlineLeaderboard.boards_updated.connect(_on_boards_updated)
	# Pull worldwide boards when opening this screen (first install + later visits).
	OnlineLeaderboard.fetch_boards()


func _on_boards_updated(_ok: bool) -> void:
	if not is_inside_tree():
		return
	can_enter = (
		wave_score > 0
		and not Session.pending_debug_used
		and LeaderboardStore.qualifies(wave_score, score_difficulty)
		and not Session.global_push_done
		and Session.global_push_name.is_empty()
	)
	# If they already submitted locally this visit, keep entry hidden.
	if not Session.global_push_name.is_empty() or Session.global_push_done:
		can_enter = false
	_refresh_list()
	_refresh_entry_visibility()
	_refresh_source_label()


func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.08, 0.1, 0.13)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var root := VBoxContainer.new()
	root.position = Vector2(340, 40)
	root.custom_minimum_size = Vector2(600, 640)
	root.add_theme_constant_override("separation", 12)
	add_child(root)

	title_label = Label.new()
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.add_theme_font_size_override("font_size", 34)
	root.add_child(title_label)

	source_label = Label.new()
	source_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	source_label.modulate = Color(0.55, 0.65, 0.7)
	root.add_child(source_label)

	var diff_row := HBoxContainer.new()
	diff_row.add_theme_constant_override("separation", 8)
	diff_row.alignment = BoxContainer.ALIGNMENT_CENTER
	root.add_child(diff_row)
	var tab_h := 44.0 if GameLayout.use_touch_ui() else 34.0
	for diff in [WaveScaler.Difficulty.EASY, WaveScaler.Difficulty.MEDIUM, WaveScaler.Difficulty.HARD]:
		var btn := Button.new()
		btn.text = WaveScaler.difficulty_label(diff)
		btn.focus_mode = Control.FOCUS_NONE
		btn.custom_minimum_size = Vector2(120, tab_h)
		btn.pressed.connect(_on_diff_tab.bind(diff))
		diff_row.add_child(btn)
		diff_buttons[diff] = btn

	status_label = Label.new()
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.modulate = Color(0.85, 0.8, 0.45)
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(status_label)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(600, 300)
	root.add_child(panel)

	list_label = Label.new()
	list_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	panel.add_child(list_label)

	entry_box = VBoxContainer.new()
	entry_box.add_theme_constant_override("separation", 8)
	entry_box.visible = false
	root.add_child(entry_box)

	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 8)
	entry_box.add_child(name_row)

	var name_label := Label.new()
	name_label.text = "Name:"
	name_row.add_child(name_label)

	name_input = LineEdit.new()
	name_input.custom_minimum_size = Vector2(220, 32)
	name_input.max_length = LeaderboardStore.MAX_NAME_LENGTH
	name_input.placeholder_text = "Player"
	name_input.text_submitted.connect(func(_t: String) -> void: _on_submit())
	name_row.add_child(name_input)

	submit_button = Button.new()
	submit_button.text = "Submit Score"
	submit_button.pressed.connect(_on_submit)
	entry_box.add_child(submit_button)

	var skip_btn := Button.new()
	skip_btn.text = "Skip"
	skip_btn.pressed.connect(_on_skip_entry)
	entry_box.add_child(skip_btn)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 12)
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	root.add_child(buttons)

	var btn_h := 52.0 if GameLayout.use_touch_ui() else 40.0
	var btn_w := 180.0 if GameLayout.use_touch_ui() else 160.0
	var menu_btn := Button.new()
	menu_btn.text = "Main Menu"
	menu_btn.custom_minimum_size = Vector2(btn_w, btn_h)
	menu_btn.pressed.connect(func() -> void: _leave_to_menu())
	buttons.add_child(menu_btn)

	var play_btn := Button.new()
	play_btn.text = "Play Again"
	play_btn.custom_minimum_size = Vector2(btn_w, btn_h)
	play_btn.pressed.connect(func() -> void: _leave_to_game())
	buttons.add_child(play_btn)


func _refresh_source_label() -> void:
	if not OnlineConfig.can_post():
		source_label.text = "Local boards (global upload not set up yet)"
		return
	match OnlineLeaderboard.last_source:
		"global":
			source_label.text = "Global boards (online)"
		"offline":
			source_label.text = "Local boards (offline)"
		_:
			source_label.text = "Local boards"


func _on_diff_tab(diff: int) -> void:
	view_difficulty = diff
	_refresh_diff_buttons()
	_refresh_list()
	_refresh_entry_visibility()


func _refresh_diff_buttons() -> void:
	for diff in diff_buttons.keys():
		var btn: Button = diff_buttons[diff]
		btn.modulate = Color(1.2, 1.15, 0.7) if int(diff) == view_difficulty else Color.WHITE


func _refresh_status(debug_used: bool = Session.pending_debug_used) -> void:
	var diff_name := WaveScaler.difficulty_label(score_difficulty)
	title_label.text = "LEADERBOARD"
	if debug_used and wave_score > 0:
		status_label.text = "Game over — wave %d (%s). Debug was used — not eligible." % [wave_score, diff_name]
	elif can_enter:
		status_label.text = "Game over — wave %d qualifies on %s! Enter your name." % [wave_score, diff_name]
	elif wave_score > 0:
		status_label.text = "Game over — wave %d (%s). Not enough for that board." % [wave_score, diff_name]
	else:
		status_label.text = "Top runs by difficulty. Showing %s." % WaveScaler.difficulty_label(view_difficulty)
	_refresh_entry_visibility()


func _refresh_entry_visibility() -> void:
	entry_box.visible = can_enter and view_difficulty == score_difficulty
	if entry_box.visible and name_input:
		name_input.grab_focus()


func _refresh_list() -> void:
	var diff_name := WaveScaler.difficulty_label(view_difficulty)
	title_label.text = "%s LEADERBOARD" % diff_name.to_upper()
	var entries := LeaderboardStore.load_entries(view_difficulty)
	if entries.is_empty():
		list_label.text = "\n  No %s scores yet. Survive waves to earn a spot." % diff_name
		return
	var lines: PackedStringArray = PackedStringArray()
	lines.append("")
	for i in entries.size():
		var e: Dictionary = entries[i]
		lines.append("  %2d. %-12s   Wave %d" % [i + 1, str(e["name"]), int(e["wave"])])
	list_label.text = "\n".join(lines)


func _on_submit() -> void:
	if not can_enter or Session.pending_debug_used:
		return
	if view_difficulty != score_difficulty:
		status_label.text = "Switch back to the %s tab to submit." % WaveScaler.difficulty_label(score_difficulty)
		return
	var cleaned := LeaderboardStore.sanitize_name(name_input.text)
	if cleaned.is_empty():
		status_label.text = "Enter a valid name (letters, numbers, spaces)."
		return
	LeaderboardStore.add_score(cleaned, wave_score, score_difficulty)
	can_enter = false
	entry_box.visible = false
	Session.pending_wave_score = -1
	Session.pending_debug_used = false
	_refresh_list()
	if OnlineConfig.can_post():
		OnlineLeaderboard.queue_pending_score(cleaned, wave_score, score_difficulty)
		status_label.text = "Saved %s — wave %d (%s). Uploading…" % [
			cleaned,
			wave_score,
			WaveScaler.difficulty_label(score_difficulty),
		]
		var ok := await OnlineLeaderboard.push_score(cleaned, wave_score, score_difficulty)
		if not is_inside_tree():
			return
		if ok:
			status_label.text = "Saved %s — wave %d (%s) on the global board." % [
				cleaned,
				wave_score,
				WaveScaler.difficulty_label(score_difficulty),
			]
		else:
			status_label.text = "Saved %s locally — upload will retry when you leave." % cleaned
		_refresh_list()
		_refresh_source_label()
	else:
		status_label.text = "Saved %s — wave %d (%s) on this device." % [
			cleaned,
			wave_score,
			WaveScaler.difficulty_label(score_difficulty),
		]


func _on_skip_entry() -> void:
	can_enter = false
	entry_box.visible = false
	Session.pending_wave_score = -1
	Session.pending_debug_used = false
	OnlineLeaderboard.clear_pending()
	status_label.text = "Score discarded. Showing %s board." % WaveScaler.difficulty_label(view_difficulty)
	_refresh_list()


func _leave_to_menu() -> void:
	await _flush_before_leave()
	Session.go_menu()


func _leave_to_game() -> void:
	await _flush_before_leave()
	Session.go_game()


func _flush_before_leave() -> void:
	if _leaving:
		return
	_leaving = true
	# After a match, push at least once when leaving if we have a pending score and can POST.
	if Session.global_push_needed and not Session.global_push_done:
		status_label.text = "Uploading score…"
		await OnlineLeaderboard.flush_pending_if_online()
	elif OnlineConfig.can_post():
		await OnlineLeaderboard.flush_pending_if_online()
