class_name WebTextInput
extends RefCounted
## Typing on a phone in the web version (same fix as Mythriven): a browser game
## can't bring up the phone's keyboard by itself, so tapping a text box there
## opens the browser's own text box instead (it always shows the keyboard), and
## what's typed goes into the game's box. Does nothing on PC, in the apps, or in
## a desktop browser, where typing works as usual.


## Call once for each LineEdit. `question` is what the pop-up asks
## (the box's placeholder is used when empty).
static func attach(box: LineEdit, question: String = "") -> void:
	if not needed():
		return
	box.gui_input.connect(func(event: InputEvent) -> void: _on_input(box, question, event))


## True in a browser on a phone or tablet.
static func needed() -> bool:
	return OS.has_feature("web") and GameLayout.is_mobile_device()


## One pop-up per tap (on the finger lifting), never again straight after one closes.
static func _on_input(box: LineEdit, question: String, event: InputEvent) -> void:
	var lifted: bool = (event is InputEventMouseButton and not (event as InputEventMouseButton).pressed) \
			or (event is InputEventScreenTouch and not (event as InputEventScreenTouch).pressed)
	if not lifted or Time.get_ticks_msec() < int(box.get_meta("web_text_quiet_until", 0)):
		return
	box.accept_event()
	# A tap arrives as both a touch and a mouse click: ask only once.
	box.set_meta("web_text_quiet_until", Time.get_ticks_msec() + 100000)
	_ask.call_deferred(box, question)


static func _ask(box: LineEdit, question: String) -> void:
	if not is_instance_valid(box):
		return
	var text := question if question != "" else box.placeholder_text
	var answer: Variant = JavaScriptBridge.eval(
		"window.prompt(%s, %s)" % [JSON.stringify(text), JSON.stringify(box.text)], true
	)
	# The tap that opened it can echo back as the pop-up closes; ignore taps for a moment.
	box.set_meta("web_text_quiet_until", Time.get_ticks_msec() + 600)
	if not answer is String:
		return
	box.text = (answer as String).left(box.max_length) if box.max_length > 0 else answer
	box.text_changed.emit(box.text)
