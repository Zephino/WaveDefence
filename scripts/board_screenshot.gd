class_name BoardScreenshot
extends RefCounted

## Capture the visible board viewport to PNG (file export or leaderboard embed).

const LEADERBOARD_MAX_EDGE := 360
const LEADERBOARD_MAX_B64 := 48000


static func save_from_viewport(root: Node, filename_hint: String) -> String:
	var img := _viewport_image(root)
	if img == null or img.is_empty():
		return ""
	if UserSettings.is_screenshot_watermark():
		img = _draw_watermark(img, filename_hint)
	var path := "user://screenshots/%s" % filename_hint
	DirAccess.make_dir_recursive_absolute("user://screenshots")
	if img.save_png(path) != OK:
		return ""
	return path


## Crop the board play area, downscale, return base64 PNG (empty if capture fails).
static func capture_board_b64(root: Node, max_edge: int = LEADERBOARD_MAX_EDGE) -> String:
	var img := capture_board_image(root, max_edge)
	if img == null or img.is_empty():
		return ""
	var bytes := img.save_png_to_buffer()
	if bytes.is_empty():
		return ""
	var b64 := Marshalls.raw_to_base64(bytes)
	if b64.length() > LEADERBOARD_MAX_B64:
		# Second pass: shrink harder.
		var w2 := maxi(int(img.get_width() * 0.6), 120)
		var h2 := maxi(int(img.get_height() * 0.6), 90)
		img.resize(w2, h2, Image.INTERPOLATE_BILINEAR)
		bytes = img.save_png_to_buffer()
		b64 = Marshalls.raw_to_base64(bytes)
	if b64.length() > LEADERBOARD_MAX_B64:
		return ""
	return b64


static func capture_board_image(root: Node, max_edge: int = LEADERBOARD_MAX_EDGE) -> Image:
	var full := _viewport_image(root)
	if full == null or full.is_empty():
		return null
	var crop := _board_crop_rect(full.get_size())
	var img := full.get_region(crop)
	if img == null or img.is_empty():
		return null
	var tw := img.get_width()
	var th := img.get_height()
	var edge := maxi(maxi(tw, th), 1)
	if edge > max_edge:
		var scale := float(max_edge) / float(edge)
		img.resize(
			maxi(int(round(float(tw) * scale)), 1),
			maxi(int(round(float(th) * scale)), 1),
			Image.INTERPOLATE_BILINEAR
		)
	return img


static func image_from_b64(b64: String) -> Image:
	var cleaned := sanitize_board_b64(b64)
	if cleaned.is_empty():
		return null
	var bytes := Marshalls.base64_to_raw(cleaned)
	if bytes.is_empty():
		return null
	var img := Image.new()
	if img.load_png_from_buffer(bytes) != OK:
		return null
	return img


static func texture_from_b64(b64: String) -> ImageTexture:
	var img := image_from_b64(b64)
	if img == null:
		return null
	return ImageTexture.create_from_image(img)


static func sanitize_board_b64(raw: String) -> String:
	var s := raw.strip_edges()
	if s.begins_with("data:image"):
		var comma := s.find(",")
		if comma >= 0:
			s = s.substr(comma + 1)
	if s.length() > LEADERBOARD_MAX_B64:
		return ""
	var out := ""
	for i in s.length():
		var ch := s[i]
		var code := ch.unicode_at(0)
		var ok := (
			(code >= 65 and code <= 90)
			or (code >= 97 and code <= 122)
			or (code >= 48 and code <= 57)
			or ch == "+"
			or ch == "/"
			or ch == "="
		)
		if ok:
			out += ch
	return out


static func _viewport_image(root: Node) -> Image:
	var vp := root.get_viewport()
	if vp == null:
		return null
	var tex := vp.get_texture()
	if tex == null:
		return null
	return tex.get_image()


static func _board_crop_rect(img_size: Vector2i) -> Rect2i:
	var origin := GameLayout.board_origin()
	var view := GameLayout.board_view_size()
	var x := clampi(int(origin.x), 0, maxi(img_size.x - 1, 0))
	var y := clampi(int(origin.y), 0, maxi(img_size.y - 1, 0))
	var w := clampi(int(view.x), 1, maxi(img_size.x - x, 1))
	var h := clampi(int(view.y), 1, maxi(img_size.y - y, 1))
	return Rect2i(x, y, w, h)


static func _draw_watermark(img: Image, hint: String) -> Image:
	var copy := img.duplicate()
	copy.fill_rect(Rect2i(0, copy.get_height() - 28, copy.get_width(), 28), Color(0, 0, 0, 160))
	# Godot Image has no font draw — encode hint in filename only; bottom bar marks export.
	return copy
