class_name BoardScreenshot
extends RefCounted

## Capture the visible board viewport to PNG.


static func save_from_viewport(root: Node, filename_hint: String) -> String:
	var vp := root.get_viewport()
	if vp == null:
		return ""
	var tex := vp.get_texture()
	if tex == null:
		return ""
	var img := tex.get_image()
	if img == null or img.is_empty():
		return ""
	if UserSettings.is_screenshot_watermark():
		img = _draw_watermark(img, filename_hint)
	var path := "user://screenshots/%s" % filename_hint
	DirAccess.make_dir_recursive_absolute("user://screenshots")
	if img.save_png(path) != OK:
		return ""
	return path


static func _draw_watermark(img: Image, hint: String) -> Image:
	var copy := img.duplicate()
	copy.fill_rect(Rect2i(0, copy.get_height() - 28, copy.get_width(), 28), Color(0, 0, 0, 160))
	# Godot Image has no font draw — encode hint in filename only; bottom bar marks export.
	return copy
