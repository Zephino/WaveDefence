class_name DebugPanel
extends CanvasLayer

signal add_gold_requested(amount: int)
signal add_lives_requested(amount: int)
signal set_wave_requested(wave: int)
signal send_wave_requested
signal clear_enemies_requested
signal god_mode_toggled(enabled: bool)
signal restart_requested
signal debug_opened

var panel: PanelContainer
var visible_panel: bool = false
var god_check: CheckButton


func _ready() -> void:
	layer = 20
	_build()
	hide_panel()


func _build() -> void:
	var rect := GameLayout.debug_panel_rect()
	panel = PanelContainer.new()
	panel.position = rect.position
	panel.size = rect.size
	panel.custom_minimum_size = rect.size
	panel.clip_contents = true
	# Dark overlay card over the board — leaves left/right sidebars free.
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.1, 0.13, 0.94)
	style.set_border_width_all(2)
	style.border_color = Color(0.45, 0.55, 0.4, 0.9)
	style.set_corner_radius_all(8)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(box)

	var title := Label.new()
	title.text = "Debug (F1 / ~)"
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(title)

	_add_button(box, "+1000 Gold", func() -> void: add_gold_requested.emit(1000))
	_add_button(box, "+5 Lives", func() -> void: add_lives_requested.emit(5))
	_add_button(box, "Jump Wave 10", func() -> void: set_wave_requested.emit(10))
	_add_button(box, "Jump Wave 15", func() -> void: set_wave_requested.emit(15))
	_add_button(box, "Jump Wave 50", func() -> void: set_wave_requested.emit(50))
	_add_button(box, "Force Next Wave", func() -> void: send_wave_requested.emit())
	_add_button(box, "Clear Enemies", func() -> void: clear_enemies_requested.emit())
	_add_button(box, "Restart Run", func() -> void: restart_requested.emit())

	god_check = CheckButton.new()
	god_check.text = "God Mode"
	god_check.tooltip_text = "No leak damage"
	god_check.toggled.connect(func(on: bool) -> void: god_mode_toggled.emit(on))
	box.add_child(god_check)

	var tip := Label.new()
	tip.text = "G gold  L lives\nN force  U upgrade\nK clear  R restart\nDebug = no leaderboard"
	tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tip.modulate = Color(0.75, 0.78, 0.82)
	box.add_child(tip)


func _add_button(parent: Node, text: String, cb: Callable) -> void:
	var btn := Button.new()
	btn.text = text
	btn.focus_mode = Control.FOCUS_NONE
	btn.clip_text = true
	btn.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.pressed.connect(cb)
	parent.add_child(btn)


func toggle() -> void:
	if visible_panel:
		hide_panel()
	else:
		show_panel()


func show_panel() -> void:
	visible_panel = true
	panel.visible = true
	debug_opened.emit()


func hide_panel() -> void:
	visible_panel = false
	panel.visible = false


func set_god_mode_ui(on: bool) -> void:
	if god_check:
		god_check.set_pressed_no_signal(on)
