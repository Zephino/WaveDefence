class_name PauseMenuOverlay
extends Control

const SettingsTouch := preload("res://scripts/settings_touch.gd")

signal resume_requested
signal quit_to_menu_requested
signal screenshot_requested

var _timeline: Label
var _timeline_text: String = ""
var _seed_clipboard: String = ""
var _root_box: VBoxContainer
var _settings_overlay: Control
var _music_mute_check: CheckButton
var _sfx_mute_check: CheckButton
var _updating_mute_ui: bool = false


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
	_root_box = VBoxContainer.new()
	_root_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_root_box.add_theme_constant_override("separation", 10)
	panel.add_child(_root_box)
	var title := Label.new()
	title.text = "Paused"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	_root_box.add_child(title)
	_timeline = Label.new()
	_timeline.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_timeline.custom_minimum_size = Vector2(420, 0)
	_timeline.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_timeline.modulate = Color(0.7, 0.78, 0.85)
	_timeline.tooltip_text = "Plain-English peek at the next waves (boss, faster, air, and so on)."
	_root_box.add_child(_timeline)
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
		_root_box.add_child(seed_label)
	_root_box.add_child(_btn("Resume", func() -> void: resume_requested.emit()))
	if not _seed_clipboard.is_empty():
		var copy_seed := Button.new()
		copy_seed.text = "Copy seed"
		copy_seed.custom_minimum_size = Vector2(280, 44)
		copy_seed.pressed.connect(func() -> void:
			DisplayServer.clipboard_set(_seed_clipboard)
			copy_seed.text = "Copied!"
			copy_seed.disabled = true
		)
		_root_box.add_child(copy_seed)
	_root_box.add_child(_btn("Settings", _show_settings))
	_root_box.add_child(_btn("Save maze image", func() -> void: screenshot_requested.emit()))
	_root_box.add_child(_btn("Quit to menu", func() -> void: quit_to_menu_requested.emit()))
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


func _show_settings() -> void:
	_hide_settings()
	_settings_overlay = Control.new()
	_settings_overlay.process_mode = Node.PROCESS_MODE_ALWAYS
	_settings_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_settings_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_settings_overlay)

	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.03, 0.05, 0.72)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_settings_overlay.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_settings_overlay.add_child(center)

	var panel := PanelContainer.new()
	center.add_child(panel)

	var vp_h := get_viewport().get_visible_rect().size.y
	if vp_h < 32.0:
		vp_h = GameLayout.VIEW_HEIGHT
	var scroll := ScrollContainer.new()
	SettingsTouch.prepare_scroll(scroll)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(340, minf(420.0, maxf(vp_h - 80.0, 220.0)))
	panel.add_child(scroll)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	box.custom_minimum_size = Vector2(320, 0)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(box)

	var title := Label.new()
	title.text = "Settings"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 22)
	box.add_child(title)

	box.add_child(_volume_row("Master volume", UserSettings.master_volume, func(v: int) -> void:
		UserSettings.set_master_volume(v)
		SoundHub.refresh_volumes()
	))
	box.add_child(_volume_row("Music volume", UserSettings.music_volume, func(v: int) -> void:
		UserSettings.set_music_volume(v)
		if v > 0 and UserSettings.is_music_muted():
			UserSettings.set_music_muted(false)
			_sync_mute_checks()
		SoundHub.refresh_volumes()
	))
	box.add_child(_volume_row("SFX volume", UserSettings.sfx_volume, func(v: int) -> void:
		UserSettings.set_sfx_volume(v)
		if v > 0 and UserSettings.is_sfx_muted():
			UserSettings.set_sfx_muted(false)
			_sync_mute_checks()
		SoundHub.refresh_volumes()
	))

	_music_mute_check = CheckButton.new()
	_music_mute_check.text = "Mute music"
	_music_mute_check.button_pressed = UserSettings.is_music_muted()
	_music_mute_check.custom_minimum_size = Vector2(300, 40)
	_music_mute_check.tooltip_text = "Silence music without changing the Music volume slider."
	SettingsTouch.wire_check(_music_mute_check, _on_mute_music_toggled)
	box.add_child(_music_mute_check)

	_sfx_mute_check = CheckButton.new()
	_sfx_mute_check.text = "Mute sounds"
	_sfx_mute_check.button_pressed = UserSettings.is_sfx_muted()
	_sfx_mute_check.custom_minimum_size = Vector2(300, 40)
	_sfx_mute_check.tooltip_text = "Silence SFX / UI clicks without changing the SFX volume slider."
	SettingsTouch.wire_check(_sfx_mute_check, _on_mute_sfx_toggled)
	box.add_child(_sfx_mute_check)

	box.add_child(_btn("Close", _hide_settings))


func _hide_settings() -> void:
	if _settings_overlay != null and is_instance_valid(_settings_overlay):
		_settings_overlay.queue_free()
	_settings_overlay = null
	_music_mute_check = null
	_sfx_mute_check = null


func _sync_mute_checks() -> void:
	_updating_mute_ui = true
	if _music_mute_check != null and is_instance_valid(_music_mute_check):
		_music_mute_check.set_pressed_no_signal(UserSettings.is_music_muted())
	if _sfx_mute_check != null and is_instance_valid(_sfx_mute_check):
		_sfx_mute_check.set_pressed_no_signal(UserSettings.is_sfx_muted())
	_updating_mute_ui = false


func _on_mute_music_toggled(on: bool) -> void:
	if _updating_mute_ui:
		return
	UserSettings.set_music_muted(on)
	SoundHub.refresh_volumes()


func _on_mute_sfx_toggled(on: bool) -> void:
	if _updating_mute_ui:
		return
	UserSettings.set_sfx_muted(on)
	SoundHub.refresh_volumes()


func _volume_row(label_text: String, value: int, cb: Callable) -> VBoxContainer:
	var col := VBoxContainer.new()
	var lab := Label.new()
	lab.text = "%s (%d%%)" % [label_text, value]
	col.add_child(lab)
	var slider := HSlider.new()
	slider.min_value = 0
	slider.max_value = 100
	slider.step = 5
	slider.value = value
	slider.custom_minimum_size = Vector2(300, 28)
	SettingsTouch.wire_slider(slider, func(v: float) -> void:
		lab.text = "%s (%d%%)" % [label_text, int(v)]
		cb.call(int(v))
	)
	col.add_child(slider)
	return col
