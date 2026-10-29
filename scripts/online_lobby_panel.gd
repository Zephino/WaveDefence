class_name OnlineLobbyPanel
extends VBoxContainer
## Online Clash lobby (main menu). Join view: type a 6-digit code. Lobby view:
## the code, each lane (host, joined players, bots), and Ready / Start.
## The host can add and remove bots and set their difficulty; a friend who joins
## takes a new lane, or replaces a bot when all 4 lanes are taken.

signal close_requested

const DIFFS := [
	{"d": WaveScaler.Difficulty.EASY, "t": "Easy"},
	{"d": WaveScaler.Difficulty.MEDIUM, "t": "Medium"},
	{"d": WaveScaler.Difficulty.HARD, "t": "Hard"},
	{"d": WaveScaler.Difficulty.CHEATER, "t": "Cheater"},
]

## (text: String, cb: Callable, half_width: bool) -> Button, from the main menu.
var make_button: Callable
var _message: String = ""
var _code_edit: LineEdit


func setup(p_make_button: Callable, message: String = "") -> void:
	make_button = p_make_button
	_message = message
	add_theme_constant_override("separation", 10)
	Net.changed.connect(_rebuild)
	Net.ended.connect(_on_ended)
	_rebuild()


func _exit_tree() -> void:
	if Net.changed.is_connected(_rebuild):
		Net.changed.disconnect(_rebuild)
	if Net.ended.is_connected(_on_ended):
		Net.ended.disconnect(_on_ended)


func _rebuild() -> void:
	if not is_inside_tree() or Net.in_match():
		return
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_code_edit = null
	_title("Online Clash")
	if not _message.is_empty():
		_note(_message, Color(0.95, 0.75, 0.55))
	match Net.state:
		Net.State.OFF:
			_build_join()
		Net.State.CONNECTING:
			_note("Connecting…")
			_actions([make_button.call("Cancel", _leave, true)])
		_:
			_build_lobby()


func _build_join() -> void:
	_note("Type the 6-digit code from the host. To host, pick Clash on the menu and press Invite Friends.")
	_code_edit = LineEdit.new()
	_code_edit.placeholder_text = "123456"
	_code_edit.max_length = 6
	_code_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_code_edit.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_NUMBER
	_code_edit.custom_minimum_size = Vector2(200, GameLayout.button_height(40.0))
	_code_edit.add_theme_font_size_override("font_size", 24)
	_code_edit.text_submitted.connect(func(_t: String) -> void: _join())
	add_child(_code_edit)
	_actions([make_button.call("Back", _close, true), make_button.call("Join", _join, true)])


func _build_lobby() -> void:
	var code_label := _title("Code: %s %s" % [Net.code.substr(0, 3), Net.code.substr(3)])
	code_label.add_theme_font_size_override("font_size", 30)
	if Net.is_host():
		_note("Share this code. Friends take open lanes, or replace a bot when all 4 are taken.")
	for i in Net.seats.size():
		_seat_row(i, Net.seats[i] as Dictionary)
	if Net.is_host():
		var buttons: Array = []
		if Net.seats.size() < WaveScaler.CLASH_MAX_PLAYERS:
			buttons.append(make_button.call("+ Add bot", Net.add_bot, true))
		var start: Button = make_button.call("Start", Net.start_match, true)
		start.disabled = not Net.can_start()
		buttons.append(start)
		_actions(buttons)
		if not Net.all_guests_ready():
			_note("Waiting for %s to press Ready." % ", ".join(Net.waiting_on_names()))
		elif Net.guest_ids().is_empty():
			_note("No friends yet — you can start with bots, or wait for someone to join.")
	else:
		var ready := Net.is_ready(Net.my_id)
		_actions([make_button.call("Ready ✓" if ready else "Ready", func() -> void: Net.set_ready(not ready), true)])
		_note("The host starts the match once everyone is Ready.")
	_actions([make_button.call("Leave", _leave, true)])


func _seat_row(index: int, seat: Dictionary) -> void:
	var kind := str(seat.get("kind", ""))
	var id := int(seat.get("net_id", 0))
	var text := "Lane %d: %s" % [index + 1, str(seat.get("name", "?"))]
	if id == Net.my_id:
		text += " (you)"
	if kind == NetSession.SEAT_HUMAN:
		text += "  —  " + ("Ready ✓" if Net.is_ready(id) else "not ready")
	elif kind == NetSession.SEAT_BOT and not Net.is_host():
		text += "  (%s)" % _diff_name(int(seat.get("diff", 0)))
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 6)
	add_child(row)
	var label := Label.new()
	label.text = text
	label.custom_minimum_size = Vector2(220, 0)
	row.add_child(label)
	if kind != NetSession.SEAT_BOT or not Net.is_host():
		return
	for item in DIFFS:
		var diff: int = int(item["d"])
		var btn: Button = make_button.call(str(item["t"]), func() -> void: Net.set_bot_difficulty(index, diff), true)
		btn.custom_minimum_size = Vector2(72, GameLayout.button_height(30.0))
		btn.disabled = int(seat.get("diff", 0)) == diff
		row.add_child(btn)
	if Net.seats.size() > WaveScaler.CLASH_MIN_PLAYERS:
		var remove: Button = make_button.call("✕", func() -> void: Net.remove_bot(index), true)
		remove.custom_minimum_size = Vector2(40, GameLayout.button_height(30.0))
		remove.tooltip_text = "Remove this bot"
		row.add_child(remove)


func _diff_name(diff: int) -> String:
	for item in DIFFS:
		if int(item["d"]) == diff:
			return str(item["t"])
	return "Medium"


func _title(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 22)
	add_child(label)
	return label


func _note(text: String, color: Color = Color(0.7, 0.75, 0.8)) -> void:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.custom_minimum_size = Vector2(380, 0)
	label.modulate = color
	add_child(label)


func _actions(buttons: Array) -> void:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	add_child(row)
	for b in buttons:
		row.add_child(b)


func _join() -> void:
	if _code_edit == null:
		return
	var digits := _code_edit.text.strip_edges().replace(" ", "")
	if digits.length() != 6 or not digits.is_valid_int():
		_message = "Codes are 6 digits."
		_rebuild()
		return
	_message = ""
	Net.join_match(digits)


func _leave() -> void:
	_message = ""
	Net.leave()


func _close() -> void:
	close_requested.emit()


func _on_ended(reason: String) -> void:
	_message = reason
	_rebuild()
