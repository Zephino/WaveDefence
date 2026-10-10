class_name PauseMenuOverlay
extends Control

signal resume_requested
signal quit_to_menu_requested
signal open_settings_requested
signal screenshot_requested

var _timeline: Label


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
	add_child(center)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	center.add_child(box)
	var title := Label.new()
	title.text = "Paused"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	box.add_child(title)
	_timeline = Label.new()
	_timeline.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_timeline.custom_minimum_size = Vector2(360, 0)
	_timeline.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_timeline.modulate = Color(0.7, 0.78, 0.85)
	box.add_child(_timeline)
	box.add_child(_btn("Resume", func() -> void: resume_requested.emit()))
	box.add_child(_btn("Settings", func() -> void: open_settings_requested.emit()))
	box.add_child(_btn("Save maze image", func() -> void: screenshot_requested.emit()))
	box.add_child(_btn("Quit to menu", func() -> void: quit_to_menu_requested.emit()))


func set_timeline(text: String) -> void:
	if _timeline:
		_timeline.text = "Next waves: " + text


func _btn(label: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = label
	b.custom_minimum_size = Vector2(280, 44)
	b.pressed.connect(cb)
	return b
