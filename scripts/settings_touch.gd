class_name SettingsTouch
extends RefCounted

## Makes settings sliders/toggles ignore vertical swipes so ScrollContainer can scroll.

const SWIPE_DEADZONE := 14.0


static func prepare_scroll(scroll: ScrollContainer) -> void:
	if scroll == null:
		return
	scroll.scroll_deadzone = int(SWIPE_DEADZONE)


static func wire_check(btn: BaseButton, on_toggled: Callable) -> void:
	btn.action_mode = BaseButton.ACTION_MODE_BUTTON_RELEASE
	btn.focus_mode = Control.FOCUS_NONE
	var state := {
		"press": Vector2.ZERO,
		"active": false,
		"swiping": false,
		"suppress": false,
	}
	btn.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventScreenTouch:
			var st := event as InputEventScreenTouch
			if st.pressed:
				state.press = st.position
				state.active = true
				state.swiping = false
			else:
				state.active = false
		elif event is InputEventMouseButton:
			var mb := event as InputEventMouseButton
			if mb.button_index != MOUSE_BUTTON_LEFT:
				return
			if mb.pressed:
				state.press = mb.position
				state.active = true
				state.swiping = false
			else:
				state.active = false
		elif state.active and event is InputEventScreenDrag:
			var drag := event as InputEventScreenDrag
			if _is_vertical_swipe(state.press, drag.position):
				state.swiping = true
				_scroll_parent(btn, -int(drag.relative.y))
				btn.accept_event()
		elif state.active and event is InputEventMouseMotion:
			var mm := event as InputEventMouseMotion
			if (mm.button_mask & MOUSE_BUTTON_MASK_LEFT) == 0:
				return
			if _is_vertical_swipe(state.press, mm.position):
				state.swiping = true
				_scroll_parent(btn, -int(mm.relative.y))
				btn.accept_event()
	)
	btn.toggled.connect(func(on: bool) -> void:
		if state.suppress:
			return
		if state.swiping:
			state.suppress = true
			btn.set_pressed_no_signal(not on)
			state.suppress = false
			state.swiping = false
			return
		if on_toggled.is_valid():
			on_toggled.call(on)
	)


static func wire_slider(slider: Range, on_changed: Callable) -> void:
	var state := {
		"press": Vector2.ZERO,
		"last": Vector2.ZERO,
		"committed": slider.value,
		"active": false,
		"scroll": false,
	}
	slider.focus_mode = Control.FOCUS_NONE
	slider.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventScreenTouch:
			var st := event as InputEventScreenTouch
			if st.pressed:
				state.press = st.position
				state.last = st.position
				state.committed = slider.value
				state.active = true
				state.scroll = false
			else:
				_finish_slider(slider, state, on_changed)
		elif event is InputEventMouseButton:
			var mb := event as InputEventMouseButton
			if mb.button_index != MOUSE_BUTTON_LEFT:
				return
			if mb.pressed:
				state.press = mb.position
				state.last = mb.position
				state.committed = slider.value
				state.active = true
				state.scroll = false
			else:
				_finish_slider(slider, state, on_changed)
		elif state.active and event is InputEventScreenDrag:
			var drag := event as InputEventScreenDrag
			state.last = drag.position
			if _mark_scroll_if_needed(slider, state, on_changed):
				_scroll_parent(slider, -int(drag.relative.y))
				slider.accept_event()
		elif state.active and event is InputEventMouseMotion:
			var mm := event as InputEventMouseMotion
			if (mm.button_mask & MOUSE_BUTTON_MASK_LEFT) == 0:
				return
			state.last = mm.position
			if _mark_scroll_if_needed(slider, state, on_changed):
				_scroll_parent(slider, -int(mm.relative.y))
				slider.accept_event()
	)
	slider.value_changed.connect(func(v: float) -> void:
		if state.scroll:
			return
		if state.active and _is_vertical_swipe(state.press, state.last):
			_mark_scroll_if_needed(slider, state, on_changed)
			return
		if on_changed.is_valid():
			on_changed.call(v)
	)


static func _finish_slider(slider: Range, state: Dictionary, _on_changed: Callable) -> void:
	if state.scroll:
		slider.set_value_no_signal(state.committed)
	else:
		state.committed = slider.value
	state.active = false
	state.scroll = false


static func _mark_scroll_if_needed(slider: Range, state: Dictionary, on_changed: Callable) -> bool:
	if state.scroll:
		return true
	if not _is_vertical_swipe(state.press, state.last):
		return false
	state.scroll = true
	slider.set_value_no_signal(state.committed)
	slider.release_focus()
	# Undo any live volume change that happened before the swipe was recognized.
	if on_changed.is_valid():
		on_changed.call(state.committed)
	return true


static func _is_vertical_swipe(press: Vector2, pos: Vector2) -> bool:
	var delta := pos - press
	return absf(delta.y) >= SWIPE_DEADZONE and absf(delta.y) >= absf(delta.x) * 0.85


static func _scroll_parent(from: Control, delta_y: int) -> void:
	if delta_y == 0:
		return
	var scroll := _find_scroll_parent(from)
	if scroll == null:
		return
	scroll.scroll_vertical = clampi(
		scroll.scroll_vertical + delta_y,
		0,
		maxi(scroll.get_v_scroll_bar().max_value - scroll.get_v_scroll_bar().page, 0)
	)


static func _find_scroll_parent(from: Control) -> ScrollContainer:
	var n: Node = from
	while n != null:
		if n is ScrollContainer:
			return n as ScrollContainer
		n = n.get_parent()
	return null
