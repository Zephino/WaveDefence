class_name PauseMenuOverlay
extends Control

signal resume_requested
signal quit_to_menu_requested
signal open_settings_requested
signal screenshot_requested

var _timeline: Label
var _timeline_text: String = ""
var _seed_clipboard: String = ""


func setup(timeline: String, seed_clipboard: String = "") -> void:
	_timeline_text = timeline
	_seed_clipboard = seed_clipboard
	if is_inside_tree():
		_apply_setup()


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0.05, 0.07, 0.1, 0.82)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var panel := PanelContainer.new()
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	var title := Label.new()
	title.text = "Paused"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	box.add_child(title)
	_timeline = Label.new()
	_timeline.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_timeline.custom_minimum_size = Vector2(420, 0)
	_timeline.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_timeline.modulate = Color(0.7, 0.78, 0.85)
	_timeline.tooltip_text = "Plain-English peek at the next waves (boss, faster, air, and so on)."
	box.add_child(_timeline)
	if not _seed_clipboard.is_empty():
		var seed_label := Label.new()
		seed_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		seed_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		seed_label.custom_minimum_size = Vector2(360, 0)
		seed_label.modulate = Color(0.72, 0.78, 0.85)
		if _seed_clipboard.contains(","):
			seed_label.text = "Map seeds: %s" % _seed_clipboard
		else:
			seed_label.text = "Map seed: %s" % _seed_clipboard
		seed_label.tooltip_text = "Paste into Classic → Custom layout to replay this map."
		box.add_child(seed_label)
	box.add_child(_btn("Resume", func() -> void: resume_requested.emit()))
	if not _seed_clipboard.is_empty():
		var copy_seed := Button.new()
		copy_seed.text = "Copy seed"
		copy_seed.custom_minimum_size = Vector2(280, 44)
		copy_seed.pressed.connect(func() -> void:
			DisplayServer.clipboard_set(_seed_clipboard)
			copy_seed.text = "Copied!"
			copy_seed.disabled = true
		)
		box.add_child(copy_seed)
	box.add_child(_btn("Settings", func() -> void: open_settings_requested.emit()))
	box.add_child(_btn("Save maze image", func() -> void: screenshot_requested.emit()))
	box.add_child(_btn("Quit to menu", func() -> void: quit_to_menu_requested.emit()))
	_apply_setup()


func set_timeline(text: String) -> void:
	setup(text, _seed_clipboard)


func _apply_setup() -> void:
	if _timeline:
		_timeline.text = ("Coming up: %s" % _timeline_text) if not _timeline_text.is_empty() else ""


func _btn(label: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = label
	b.custom_minimum_size = Vector2(280, 44)
	if cb.is_valid():
		b.pressed.connect(cb)
	return b
