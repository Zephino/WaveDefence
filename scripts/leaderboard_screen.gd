extends Control

var list_host: VBoxContainer
var seed_detail_label: Label
var status_label: Label
var title_label: Label
var source_label: Label
var entry_box: VBoxContainer
var name_input: LineEdit
var submit_button: Button
var diff_buttons: Dictionary = {}
var mode_buttons: Dictionary = {}
var wave_score: int = -1
var view_difficulty: int = WaveScaler.Difficulty.MEDIUM
var score_difficulty: int = WaveScaler.Difficulty.MEDIUM
var view_mode: int = WaveScaler.GameMode.CLASSIC
var score_mode: int = WaveScaler.GameMode.CLASSIC
var can_enter: bool = false
var _leaving: bool = false
var _seed_popup: AcceptDialog
var _board_popup: AcceptDialog
var _board_preview: TextureRect


func _ready() -> void:
	wave_score = Session.pending_wave_score
	var debug_used := Session.pending_debug_used
	score_difficulty = Session.pending_difficulty
	view_difficulty = score_difficulty
	score_mode = Session.pending_game_mode
	view_mode = score_mode
	can_enter = (
		wave_score > 0
		and not debug_used
		and LeaderboardStore.qualifies(wave_score, score_difficulty, score_mode)
	)
	_build_ui()
	_refresh_mode_buttons()
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
		and LeaderboardStore.qualifies(wave_score, score_difficulty, score_mode)
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

	var mode_row := HBoxContainer.new()
	mode_row.add_theme_constant_override("separation", 8)
	mode_row.alignment = BoxContainer.ALIGNMENT_CENTER
	root.add_child(mode_row)
	var tab_h := 44.0 if GameLayout.use_touch_ui() else 34.0
	for mode in [
		WaveScaler.GameMode.CLASSIC,
		WaveScaler.GameMode.RANDOM,
		WaveScaler.GameMode.SIEGE,
		WaveScaler.GameMode.CLASH,
	]:
		var mbtn := Button.new()
		mbtn.text = WaveScaler.mode_label(mode)
		mbtn.focus_mode = Control.FOCUS_NONE
		mbtn.custom_minimum_size = Vector2(110, tab_h)
		mbtn.pressed.connect(_on_mode_tab.bind(mode))
		mode_row.add_child(mbtn)
		mode_buttons[mode] = mbtn

	var diff_row := HBoxContainer.new()
	diff_row.add_theme_constant_override("separation", 8)
	diff_row.alignment = BoxContainer.ALIGNMENT_CENTER
	root.add_child(diff_row)
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

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(580, 280)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)

	list_host = VBoxContainer.new()
	list_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_host.add_theme_constant_override("separation", 4)
	scroll.add_child(list_host)

	seed_detail_label = Label.new()
	seed_detail_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	seed_detail_label.modulate = Color(0.65, 0.72, 0.78)
	seed_detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	seed_detail_label.visible = false
	root.add_child(seed_detail_label)

	_seed_popup = AcceptDialog.new()
	_seed_popup.title = "Map seeds"
	_seed_popup.dialog_text = ""
	_seed_popup.ok_button_text = "Close"
	add_child(_seed_popup)

	_board_popup = AcceptDialog.new()
	_board_popup.title = "Board at game over"
	_board_popup.ok_button_text = "Close"
	_board_preview = TextureRect.new()
	_board_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_board_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_board_preview.custom_minimum_size = Vector2(420, 280)
	_board_popup.add_child(_board_preview)
	add_child(_board_popup)

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
	name_input.placeholder_text = "Player"
	name_input.text_submitted.connect(func(_t: String) -> void: _on_submit())
	name_row.add_child(name_input)
	InputSanitize.bind_line_edit(name_input, "name")

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


func _on_mode_tab(mode: int) -> void:
	view_mode = mode
	_refresh_mode_buttons()
	_refresh_list()
	_refresh_entry_visibility()


func _on_diff_tab(diff: int) -> void:
	view_difficulty = diff
	_refresh_diff_buttons()
	_refresh_list()
	_refresh_entry_visibility()


func _refresh_mode_buttons() -> void:
	for mode in mode_buttons.keys():
		var btn: Button = mode_buttons[mode]
		btn.modulate = Color(1.2, 1.15, 0.7) if int(mode) == view_mode else Color.WHITE


func _refresh_diff_buttons() -> void:
	for diff in diff_buttons.keys():
		var btn: Button = diff_buttons[diff]
		btn.modulate = Color(1.2, 1.15, 0.7) if int(diff) == view_difficulty else Color.WHITE


func _refresh_status(debug_used: bool = Session.pending_debug_used) -> void:
	var board_name := "%s / %s" % [
		WaveScaler.mode_label(score_mode),
		WaveScaler.difficulty_label(score_difficulty),
	]
	title_label.text = "LEADERBOARD"
	if debug_used and wave_score > 0:
		status_label.text = "Game over — wave %d (%s). Debug was used — not eligible." % [wave_score, board_name]
	elif can_enter:
		status_label.text = "Game over — wave %d qualifies on %s! Enter your name." % [wave_score, board_name]
	elif wave_score > 0:
		status_label.text = "Game over — wave %d (%s). Not enough for that board." % [wave_score, board_name]
	else:
		status_label.text = "Top runs by mode and difficulty. Showing %s / %s." % [
			WaveScaler.mode_label(view_mode),
			WaveScaler.difficulty_label(view_difficulty),
		]
	_refresh_entry_visibility()


func _refresh_entry_visibility() -> void:
	entry_box.visible = (
		can_enter
		and view_difficulty == score_difficulty
		and view_mode == score_mode
	)
	if entry_box.visible and name_input:
		name_input.grab_focus()


func _refresh_list() -> void:
	var mode_name := WaveScaler.mode_label(view_mode)
	var diff_name := WaveScaler.difficulty_label(view_difficulty)
	title_label.text = "%s · %s" % [mode_name.to_upper(), diff_name.to_upper()]
	if seed_detail_label:
		seed_detail_label.visible = false
		seed_detail_label.text = ""
	while list_host.get_child_count() > 0:
		var child := list_host.get_child(0)
		list_host.remove_child(child)
		child.free()

	var entries := LeaderboardStore.load_entries(view_difficulty, view_mode)
	if entries.is_empty():
		var empty := Label.new()
		empty.text = "No %s / %s scores yet. Survive waves to earn a spot." % [mode_name, diff_name]
		empty.modulate = Color(0.7, 0.75, 0.8)
		list_host.add_child(empty)
		return

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	list_host.add_child(header)
	header.add_child(_list_cell("#", 36))
	header.add_child(_list_cell("Name", 100))
	header.add_child(_list_cell("Wave", 50))
	if view_mode == WaveScaler.GameMode.CLASH:
		header.add_child(_list_cell("Match", 160))
	else:
		header.add_child(_list_cell("Seed", 120))
	header.add_child(_list_cell("Board", 70))

	for i in entries.size():
		var e: Dictionary = entries[i]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		list_host.add_child(row)
		row.add_child(_list_cell("%d." % (i + 1), 36))
		row.add_child(_list_cell(str(e["name"]), 100))
		row.add_child(_list_cell(str(int(e["wave"])), 50))
		if view_mode == WaveScaler.GameMode.CLASH:
			row.add_child(_make_clash_cell(
				int(e.get("clash_players", 0)),
				e.get("clash_bots", [])
			))
		else:
			row.add_child(_make_seed_cell(LeaderboardStore.normalize_seeds(e.get("seeds", []))))
		row.add_child(_make_board_cell(str(e.get("board_png", "")), str(e.get("name", ""))))


func _list_cell(text: String, width: float) -> Label:
	var label := Label.new()
	label.text = text
	label.custom_minimum_size = Vector2(width, 0)
	return label


func _make_seed_cell(seeds: Array) -> Control:
	var summary := LeaderboardStore.format_seeds_summary(seeds)
	if summary.is_empty():
		var none := Label.new()
		none.text = "—"
		none.modulate = Color(0.5, 0.55, 0.6)
		none.custom_minimum_size = Vector2(120, 0)
		return none
	if seeds.size() == 1:
		var one := Label.new()
		one.text = summary
		one.custom_minimum_size = Vector2(120, 0)
		one.tooltip_text = "Map seed: %d" % int(seeds[0])
		return one
	var btn := Button.new()
	btn.text = summary
	btn.focus_mode = Control.FOCUS_NONE
	btn.custom_minimum_size = Vector2(120, GameLayout.button_height(28.0))
	btn.tooltip_text = LeaderboardStore.format_seeds_detail(seeds) + "\n(Click to view)"
	btn.pressed.connect(_on_seeds_clicked.bind(seeds.duplicate()))
	return btn


func _make_clash_cell(players: int, bots) -> Control:
	var summary := LeaderboardStore.format_clash_summary(players, bots if typeof(bots) == TYPE_ARRAY else [])
	var label := Label.new()
	label.custom_minimum_size = Vector2(160, 0)
	if summary.is_empty():
		label.text = "—"
		label.modulate = Color(0.5, 0.55, 0.6)
	else:
		label.text = summary
		label.tooltip_text = summary
	return label


func _make_board_cell(board_png: String, player_name: String) -> Control:
	var png := LeaderboardStore.normalize_board_png(board_png)
	if png.is_empty():
		var none := Label.new()
		none.text = "—"
		none.modulate = Color(0.5, 0.55, 0.6)
		none.custom_minimum_size = Vector2(80, 0)
		return none
	var btn := Button.new()
	btn.text = "View"
	btn.focus_mode = Control.FOCUS_NONE
	btn.custom_minimum_size = Vector2(80, GameLayout.button_height(28.0))
	btn.tooltip_text = "See %s's board at game over" % player_name
	btn.pressed.connect(_on_board_clicked.bind(png, player_name))
	return btn


func _on_seeds_clicked(seeds: Array) -> void:
	var detail := LeaderboardStore.format_seeds_detail(seeds)
	if seed_detail_label:
		seed_detail_label.text = detail.replace("\n", "  ·  ")
		seed_detail_label.visible = true
	if _seed_popup:
		_seed_popup.dialog_text = detail
		_seed_popup.popup_centered()


func _on_board_clicked(board_png: String, player_name: String) -> void:
	var tex := BoardScreenshot.texture_from_b64(board_png)
	if tex == null or _board_popup == null:
		if status_label:
			status_label.text = "Could not load that board image."
		return
	_board_popup.title = "%s — board" % player_name
	_board_preview.texture = tex
	_board_popup.popup_centered()


func _on_submit() -> void:
	if not can_enter or Session.pending_debug_used:
		return
	if view_difficulty != score_difficulty or view_mode != score_mode:
		status_label.text = "Switch back to %s / %s to submit." % [
			WaveScaler.mode_label(score_mode),
			WaveScaler.difficulty_label(score_difficulty),
		]
		return
	if InputSanitize.looks_like_injection(name_input.text):
		status_label.text = "That name isn't allowed."
		name_input.text = InputSanitize.filter_name_typing(name_input.text)
		return
	var cleaned := LeaderboardStore.sanitize_name(name_input.text)
	if cleaned.is_empty():
		status_label.text = "Enter a valid name (letters, numbers, spaces)."
		return
	var seeds: Array = Session.pending_map_seeds.duplicate()
	var board_png := Session.pending_board_png
	var clash_players := Session.pending_clash_players if score_mode == WaveScaler.GameMode.CLASH else 0
	var clash_bots: Array = (
		Session.pending_clash_bots.duplicate() if score_mode == WaveScaler.GameMode.CLASH else []
	)
	LeaderboardStore.add_score(
		cleaned, wave_score, score_difficulty, seeds, score_mode, board_png, clash_players, clash_bots
	)
	can_enter = false
	entry_box.visible = false
	Session.pending_wave_score = -1
	Session.pending_debug_used = false
	Session.pending_map_seeds.clear()
	Session.pending_board_png = ""
	Session.pending_clash_players = 0
	Session.pending_clash_bots.clear()
	_refresh_list()
	var board_label := "%s / %s" % [
		WaveScaler.mode_label(score_mode),
		WaveScaler.difficulty_label(score_difficulty),
	]
	if OnlineConfig.can_post():
		OnlineLeaderboard.queue_pending_score(
			cleaned, wave_score, score_difficulty, seeds, score_mode, board_png, clash_players, clash_bots
		)
		if OnlineLeaderboard.is_online_likely():
			status_label.text = "Saved %s — wave %d (%s). Uploading…" % [
				cleaned,
				wave_score,
				board_label,
			]
			var ok := await OnlineLeaderboard.push_score(
				cleaned, wave_score, score_difficulty, seeds, score_mode, board_png, clash_players, clash_bots
			)
			if not is_inside_tree():
				return
			if ok:
				status_label.text = "Saved %s — wave %d (%s) on the global board." % [
					cleaned,
					wave_score,
					board_label,
				]
			else:
				status_label.text = "Saved %s locally — will upload when you’re back online." % cleaned
		else:
			status_label.text = "Saved %s locally — will upload when you’re back online." % cleaned
		_refresh_list()
		_refresh_source_label()
	else:
		status_label.text = "Saved %s — wave %d (%s) on this device." % [
			cleaned,
			wave_score,
			board_label,
		]


func _on_skip_entry() -> void:
	can_enter = false
	entry_box.visible = false
	Session.pending_wave_score = -1
	Session.pending_debug_used = false
	Session.pending_map_seeds.clear()
	Session.pending_board_png = ""
	Session.pending_clash_players = 0
	Session.pending_clash_bots.clear()
	OnlineLeaderboard.clear_pending()
	status_label.text = "Score discarded. Showing %s / %s." % [
		WaveScaler.mode_label(view_mode),
		WaveScaler.difficulty_label(view_difficulty),
	]
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
