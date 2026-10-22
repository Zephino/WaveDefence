class_name SettingsTouch
extends RefCounted

## Makes settings controls yield vertical swipes to ScrollContainer (mobile web).

const SWIPE_DEADZONE := 10.0
const WEB_SCROLL_GAIN := 1.45


static func prepare_scroll(scroll: ScrollContainer) -> void:
	if scroll == null:
		return
	scroll.scroll_deadzone = int(SWIPE_DEADZONE)
	scroll.mouse_filter = Control.MOUSE_FILTER_STOP
	_wire_drag_surface(scroll)
	if not scroll.get_meta("_wd_scroll_child_hook", false):
		scroll.set_meta("_wd_scroll_child_hook", true)
		scroll.child_entered_tree.connect(_on_scroll_child_entered.bind(scroll))


static func _on_scroll_child_entered(scroll: ScrollContainer, _n: Node) -> void:
	# Defer so the new child's children exist too.
	scroll.get_tree().create_timer(0.0).timeout.connect(func() -> void:
		if is_instance_valid(scroll):
			wire_scroll_tree(scroll)
	, CONNECT_ONE_SHOT)


## Walk a settings panel / scroll tree and enable finger-drag scrolling on surfaces.
static func wire_scroll_tree(root: Node) -> void:
	if root == null or not is_instance_valid(root):
		return
	if root is ScrollContainer:
		(root as ScrollContainer).scroll_deadzone = int(SWIPE_DEADZONE)
	if root is Control:
		_wire_drag_surface(root as Control)
	for child in root.get_children():
		wire_scroll_tree(child)


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
				_scroll_parent(btn, _scroll_delta(drag.relative.y))
				btn.accept_event()
		elif state.active and event is InputEventMouseMotion:
			var mm := event as InputEventMouseMotion
			if (mm.button_mask & MOUSE_BUTTON_MASK_LEFT) == 0:
				return
			if _is_vertical_swipe(state.press, mm.position):
				state.swiping = true
				_scroll_parent(btn, _scroll_delta(mm.relative.y))
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
				_scroll_parent(slider, _scroll_delta(drag.relative.y))
				slider.accept_event()
		elif state.active and event is InputEventMouseMotion:
			var mm := event as InputEventMouseMotion
			if (mm.button_mask & MOUSE_BUTTON_MASK_LEFT) == 0:
				return
			state.last = mm.position
			if _mark_scroll_if_needed(slider, state, on_changed):
				_scroll_parent(slider, _scroll_delta(mm.relative.y))
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


static func _wire_drag_surface(control: Control) -> void:
	# CheckButtons / sliders already have dedicated swipe handlers.
	if control is Range or control is CheckButton:
		return
	if control.get_meta("_wd_scroll_wired", false):
		return
	control.set_meta("_wd_scroll_wired", true)
	var state := {
		"press": Vector2.ZERO,
		"active": false,
		"swiping": false,
	}
	control.gui_input.connect(func(event: InputEvent) -> void:
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
				_scroll_parent(control, _scroll_delta(drag.relative.y))
				control.accept_event()
		elif state.active and event is InputEventMouseMotion:
			var mm := event as InputEventMouseMotion
			if (mm.button_mask & MOUSE_BUTTON_MASK_LEFT) == 0:
				return
			if _is_vertical_swipe(state.press, mm.position):
				state.swiping = true
				_scroll_parent(control, _scroll_delta(mm.relative.y))
				control.accept_event()
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
	if on_changed.is_valid():
		on_changed.call(state.committed)
	return true


static func _is_vertical_swipe(press: Vector2, pos: Vector2) -> bool:
	var delta := pos - press
	return absf(delta.y) >= SWIPE_DEADZONE and absf(delta.y) >= absf(delta.x) * 0.75


static func _scroll_delta(relative_y: float) -> int:
	var gain := WEB_SCROLL_GAIN if OS.get_name() == "Web" else 1.0
	return -int(relative_y * gain)


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
		# Surfaces that ARE the ScrollContainer.
		if n == from and from is ScrollContainer:
			return from as ScrollContainer
		n = n.get_parent()
	return null
