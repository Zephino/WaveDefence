class_name WaveSuggestionForm
extends CanvasLayer
## Anonymous player feedback, shown only from the main Hero selection screen.
## Sends to the Cloudflare Worker; no GitHub sign-in, email, or external tab.

signal closed

const MAX_TITLE := 100
const MAX_DESCRIPTION := 2000
const CATEGORY_IDS := [
  "tower", "enemy", "map", "clash", "balance", "gameplay", "ui", "other"
]
const CATEGORY_LABELS := [
  "Tower or weapon", "Enemy or boss", "Map or maze", "Clash mode",
  "Game balance", "Gameplay mechanic", "Interface or quality of life", "Other"
]

var _category: OptionButton
var _title_input: LineEdit
var _description: TextEdit
var _send: Button
var _status: Label
var _request: HTTPRequest
var _sending: bool = false
var _client_info: Dictionary = {}


func _ready() -> void:
  layer = 85
  process_mode = Node.PROCESS_MODE_ALWAYS
  _client_info = WaveSuggestionEnvironment.collect()
  _build()
  _request = HTTPRequest.new()
  _request.timeout = 20.0
  _request.request_completed.connect(_on_request_finished)
  add_child(_request)
  # Never dead-end the Send button just because an older web build has no URL.
  # The submit handler will explain what's missing, and players can retry.
  if not OnlineConfig.can_post():
    _status.text = "Suggestions are not available yet. The feedback service needs to be configured."
  _title_input.grab_focus.call_deferred()


func _build() -> void:
  var viewport_size: Vector2 = get_viewport().get_visible_rect().size
  var spacing: float = 18.0
  var touch: float = 52.0 if GameLayout.use_touch_ui() else 44.0
  var root := Control.new()
  root.set_anchors_preset(Control.PRESET_FULL_RECT)
  add_child(root)

  var dim := ColorRect.new()
  dim.color = Color(0.02, 0.02, 0.04, 0.9)
  dim.mouse_filter = Control.MOUSE_FILTER_STOP
  dim.set_anchors_preset(Control.PRESET_FULL_RECT)
  root.add_child(dim)

  # Scroll when necessary on small phone screens or with the touch keyboard.
  var scroll := ScrollContainer.new()
  scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, int(spacing))
  scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
  root.add_child(scroll)
  var center := CenterContainer.new()
  center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
  center.size_flags_vertical = Control.SIZE_EXPAND_FILL
  center.custom_minimum_size.y = maxf(viewport_size.y - spacing * 2.0, touch * 6.5)
  scroll.add_child(center)
  var panel := PanelContainer.new()
  panel.custom_minimum_size.x = minf(touch * 8.5, viewport_size.x - spacing * 2.0)
  center.add_child(panel)

  var margin := MarginContainer.new()
  for side: String in ["left", "top", "right", "bottom"]:
    margin.add_theme_constant_override("margin_" + side, int(spacing))
  panel.add_child(margin)
  var column := VBoxContainer.new()
  column.add_theme_constant_override("separation", int(spacing * 0.65))
  margin.add_child(column)

  var heading := Label.new()
  heading.text = "Suggest a Feature"
  heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
  column.add_child(heading)

  var explanation := Label.new()
  explanation.text = "Have an idea for Wave Defence? Send it directly to the developer without leaving the game."
  explanation.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
  column.add_child(explanation)

  var category_label := Label.new()
  category_label.text = "Category"
  column.add_child(category_label)
  _category = OptionButton.new()
  _category.custom_minimum_size.y = touch * 0.65
  for i: int in CATEGORY_IDS.size():
    _category.add_item(CATEGORY_LABELS[i], i)
  _category.select(0)
  column.add_child(_category)

  var title_label := Label.new()
  title_label.text = "Short title"
  column.add_child(title_label)
  _title_input = LineEdit.new()
  _title_input.placeholder_text = "What would you like added?"
  _title_input.max_length = MAX_TITLE
  _title_input.custom_minimum_size.y = touch * 0.65
  column.add_child(_title_input)

  var details_label := Label.new()
  details_label.text = "Your idea"
  column.add_child(details_label)
  _description = TextEdit.new()
  _description.placeholder_text = "Describe what you would like to see, and how it would work..."
  _description.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
  _description.custom_minimum_size.y = touch * 1.6
  _description.size_flags_vertical = Control.SIZE_EXPAND_FILL
  column.add_child(_description)

  var environment := Label.new()
  environment.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
  environment.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
  environment.text = "Auto-attached: version %s · %s · %s · %s" % [
    _client_info["game_version"],
    _client_info["device_type"],
    _client_info["platform"],
    _client_info["browser"],
  ]
  column.add_child(environment)

  var privacy := Label.new()
  privacy.text = "No account needed. Your suggestion and the general device details shown above will be public on GitHub. Do not include private information."
  privacy.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
  column.add_child(privacy)

  _status = Label.new()
  _status.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
  _status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
  column.add_child(_status)

  var actions := HBoxContainer.new()
  actions.add_theme_constant_override("separation", int(spacing))
  column.add_child(actions)
  var cancel := Button.new()
  cancel.text = "Close"
  cancel.custom_minimum_size = Vector2(touch * 2.5, touch * 0.7)
  cancel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
  cancel.pressed.connect(_close)
  actions.add_child(cancel)
  _send = Button.new()
  _send.text = "Send Suggestion"
  _send.custom_minimum_size = cancel.custom_minimum_size
  _send.size_flags_horizontal = Control.SIZE_EXPAND_FILL
  _send.pressed.connect(_submit)
  actions.add_child(_send)


func _unhandled_input(event: InputEvent) -> void:
  if event.is_action_pressed("ui_cancel") and not _sending:
    get_viewport().set_input_as_handled()
    _close()


func _submit() -> void:
  if _sending:
    return
  var title_text: String = _title_input.text.strip_edges()
  var description_text: String = _description.text.strip_edges()
  if title_text.length() < 5 or title_text.length() > MAX_TITLE:
    _status.text = "Please enter a title between 5 and 100 characters."
    _title_input.grab_focus()
    return
  if description_text.length() < 20 or description_text.length() > MAX_DESCRIPTION:
    _status.text = "Please describe your idea in 20 to 2000 characters."
    _description.grab_focus()
    return
  var endpoint: String = OnlineConfig.suggestion_url()
  if endpoint.is_empty():
    _status.text = "Suggestions are not available yet. The feedback service needs to be configured."
    return
  var data := {
    "category": CATEGORY_IDS[_category.selected],
    "title": title_text,
    "description": description_text,
    "client": _client_info,
    "website": ""
  }
  var headers := PackedStringArray(["Content-Type: application/json", "Accept: application/json"])
  _status.text = "Sending your suggestion..."
  _send.disabled = true
  _sending = true
  var err: Error = _request.request(endpoint, headers, HTTPClient.METHOD_POST, JSON.stringify(data))
  if err != OK:
    _sending = false
    _send.disabled = false
    _status.text = "Could not start the request (error %d). Please try again." % int(err)


func _on_request_finished(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
  _sending = false
  var response: Variant = JSON.parse_string(body.get_string_from_utf8())
  if result == HTTPRequest.RESULT_SUCCESS and code == 201 and response is Dictionary and response.get("accepted", false):
    _status.text = "Thank you! Your suggestion was sent to the developer."
    _title_input.editable = false
    _description.editable = false
    _category.disabled = true
    _send.disabled = true
    return
  _send.disabled = false
  if result != HTTPRequest.RESULT_SUCCESS:
    _status.text = "Network request failed (code %d). Please check your connection." % result
    return
  if code == 429:
    _status.text = "Daily suggestion limit reached. Please try again tomorrow."
    return
  # The Worker returns a safe, explanatory error for known GitHub failures.
  var reason: String = ""
  if response is Dictionary:
    reason = str(response.get("error", "")).strip_edges().left(250)
  if reason.is_empty():
    reason = "Unexpected server response. Check the Cloudflare Worker logs."
  _status.text = "Feedback service returned HTTP %d: %s" % [code, reason]


func _close() -> void:
  if _sending:
    return
  closed.emit()
  queue_free()
