class_name TowerSprites
extends RefCounted

## Data-driven tower sheet loader.
## Replace PNGs under res://assets/sprites/towers/ with the same filenames,
## frame size, and sheet layout — no GDScript changes required.
## Metadata comes from tower_<id>_frames.json (rows, fps, frame size, autotile).

const DIR := "res://assets/sprites/towers/"
const TOWER_IDS: PackedStringArray = [
	"wall", "gunner", "rapid", "cannon", "burn", "freeze",
	"poison", "lightning", "spike", "antiair", "gatling", "vortex", "command",
]

## Normalized gameplay anim names → possible JSON keys (first match wins).
const _ANIM_ALIASES := {
	"idle": ["idle"],
	"action": ["action", "shoot", "activate", "signal", "cast", "trigger"],
	"placement": ["placement"],
}

## id -> { meta, kind, frame_w, frame_h, anims: { name: { frames, fps, loop } }, wall_tiles }
static var _cache: Dictionary = {}
static var _failed: Dictionary = {}
static var _wall_tiles: Array = []


static func tower_ids() -> PackedStringArray:
	return TOWER_IDS


static func has_tower(tower_id: String) -> bool:
	if tower_id.is_empty() or _failed.has(tower_id):
		return false
	return _ensure(tower_id)


static func frame_size(tower_id: String, large_vortex: bool = false) -> Vector2:
	if large_vortex and tower_id == "vortex":
		if _ensure("vortex"):
			var entry: Dictionary = _cache["vortex"]
			var big: Dictionary = entry.get("vortex_3x3", {})
			if not big.is_empty():
				return Vector2(
					float(big.get("frame_w", 120)),
					float(big.get("frame_h", 120))
				)
		return Vector2(120, 120)
	if not _ensure(tower_id):
		return Vector2(40, 40)
	var e: Dictionary = _cache[tower_id]
	return Vector2(float(e.get("frame_w", 40)), float(e.get("frame_h", 40)))


## Texture for the given normalized anim at time seconds. Null if missing.
static func anim_texture(
	tower_id: String,
	anim: String,
	anim_time: float,
	large_vortex: bool = false
) -> Texture2D:
	if not _ensure(tower_id):
		return null
	var entry: Dictionary = _cache[tower_id]
	var anims: Dictionary = entry.get("anims", {})
	if large_vortex and tower_id == "vortex":
		anims = entry.get("anims_3x3", anims)
	var key := _resolve_anim_key(anims, anim)
	if key.is_empty():
		return null
	var clip: Dictionary = anims[key]
	var frames: Array = clip.get("frames", [])
	if frames.is_empty():
		return null
	var fps: float = maxf(float(clip.get("fps", 6.0)), 0.01)
	var loop: bool = bool(clip.get("loop", true))
	var idx: int
	if loop:
		idx = int(floor(anim_time * fps)) % frames.size()
	else:
		idx = mini(int(floor(anim_time * fps)), frames.size() - 1)
	if idx < 0:
		idx = 0
	return frames[idx] as Texture2D


static func anim_duration(tower_id: String, anim: String, large_vortex: bool = false) -> float:
	if not _ensure(tower_id):
		return 0.0
	var entry: Dictionary = _cache[tower_id]
	var anims: Dictionary = entry.get("anims", {})
	if large_vortex and tower_id == "vortex":
		anims = entry.get("anims_3x3", anims)
	var key := _resolve_anim_key(anims, anim)
	if key.is_empty():
		return 0.0
	var clip: Dictionary = anims[key]
	var frames: Array = clip.get("frames", [])
	var fps: float = maxf(float(clip.get("fps", 6.0)), 0.01)
	return float(frames.size()) / fps


static func anim_loops(tower_id: String, anim: String, large_vortex: bool = false) -> bool:
	if not _ensure(tower_id):
		return true
	var entry: Dictionary = _cache[tower_id]
	var anims: Dictionary = entry.get("anims", {})
	if large_vortex and tower_id == "vortex":
		anims = entry.get("anims_3x3", anims)
	var key := _resolve_anim_key(anims, anim)
	if key.is_empty():
		return true
	return bool(anims[key].get("loop", true))


## 16-tile fortress autotile. Bitmask: N=1, E=2, S=4, W=8.
static func wall_tile(neighbor_mask: int) -> Texture2D:
	_ensure_wall_autotile()
	if _wall_tiles.is_empty():
		return null
	var i := neighbor_mask & 15
	return _wall_tiles[i] as Texture2D


static func icon_texture(tower_id: String) -> Texture2D:
	var path := DIR + "tower_%s.png" % tower_id
	return _load_texture(path)


## Expected layout for replacement sheets (from frames.json / defaults).
static func expected_sheet_size(tower_id: String) -> Vector2i:
	if not _ensure(tower_id):
		return Vector2i(160, 80)
	var e: Dictionary = _cache[tower_id]
	return Vector2i(int(e.get("sheet_w", 160)), int(e.get("sheet_h", 80)))


static func expected_vortex_3x3_sheet_size() -> Vector2i:
	if _ensure("vortex"):
		var big: Dictionary = _cache["vortex"].get("vortex_3x3", {})
		if not big.is_empty():
			return Vector2i(int(big.get("sheet_w", 480)), int(big.get("sheet_h", 240)))
	return Vector2i(480, 240)


## Returns human-readable problems for incompatible replacement sheets.
static func validate_assets() -> PackedStringArray:
	var errors: PackedStringArray = []
	for id in TOWER_IDS:
		_cache.erase(id)
		_failed.erase(id)
		if not _ensure(id):
			errors.append("%s: missing sheet or frames.json under %s" % [id, DIR])
			continue
		var e: Dictionary = _cache[id]
		var sheet_path := str(e.get("sheet_path", ""))
		var tex := _load_texture(sheet_path)
		if tex == null:
			errors.append("%s: cannot load body sheet %s" % [id, sheet_path])
			continue
		var want_w := int(e.get("sheet_w", 160))
		var want_h := int(e.get("sheet_h", 80))
		if tex.get_width() != want_w or tex.get_height() != want_h:
			errors.append(
				"%s: sheet size %dx%d != expected %dx%d (from frames.json)" % [
					id, tex.get_width(), tex.get_height(), want_w, want_h
				]
			)
		var fw := int(e.get("frame_w", 40))
		var fh := int(e.get("frame_h", 40))
		var cols := int(e.get("columns", 4))
		var rows := int(e.get("rows", 2))
		if fw * cols != want_w or fh * rows != want_h:
			errors.append(
				"%s: frame_size %dx%d × %dx%d grid does not match sheet %dx%d" % [
					id, fw, fh, cols, rows, want_w, want_h
				]
			)
		var anims: Dictionary = e.get("anims", {})
		if _resolve_anim_key(anims, "idle").is_empty():
			errors.append("%s: missing idle animation in frames.json" % id)
		if id != "wall" and _resolve_anim_key(anims, "action").is_empty():
			errors.append("%s: missing action/shoot/activate animation" % id)
	# Wall autotile
	_wall_tiles.clear()
	_ensure_wall_autotile()
	if _wall_tiles.size() != 16:
		errors.append("wall autotile: expected 16 tiles from tower_wall_autotile_16.png")
	else:
		var at := _load_texture(DIR + "tower_wall_autotile_16.png")
		if at != null and (at.get_width() != 160 or at.get_height() != 160):
			errors.append(
				"wall autotile: size %dx%d != 160x160" % [at.get_width(), at.get_height()]
			)
	# Vortex 3×3
	if _ensure("vortex"):
		var big: Dictionary = _cache["vortex"].get("vortex_3x3", {})
		var big_path := str(big.get("sheet_path", DIR + "tower_vortex_3x3_sheet.png"))
		var big_tex := _load_texture(big_path)
		if big_tex == null:
			errors.append("vortex: missing tower_vortex_3x3_sheet.png")
		else:
			var ew := int(big.get("sheet_w", 480))
			var eh := int(big.get("sheet_h", 240))
			if big_tex.get_width() != ew or big_tex.get_height() != eh:
				errors.append(
					"vortex 3x3: sheet %dx%d != expected %dx%d" % [
						big_tex.get_width(), big_tex.get_height(), ew, eh
					]
				)
	return errors


static func _resolve_anim_key(anims: Dictionary, normalized: String) -> String:
	var aliases: Array = _ANIM_ALIASES.get(normalized, [normalized])
	for a in aliases:
		if anims.has(str(a)):
			return str(a)
	return ""


static func _ensure(tower_id: String) -> bool:
	if _cache.has(tower_id):
		return true
	if _failed.has(tower_id):
		return false
	var meta_path := DIR + "tower_%s_frames.json" % tower_id
	var meta := _default_meta(tower_id)
	if FileAccess.file_exists(meta_path):
		var f := FileAccess.open(meta_path, FileAccess.READ)
		if f != null:
			var parsed = JSON.parse_string(f.get_as_text())
			if typeof(parsed) == TYPE_DICTIONARY:
				meta = parsed
	var body_sheet := str(meta.get("body_sheet", "tower_%s_sheet.png" % tower_id)).strip_edges()
	var sheet_path: String
	if body_sheet.begins_with("res://"):
		sheet_path = body_sheet
	elif body_sheet.is_empty():
		sheet_path = DIR + "tower_%s_sheet.png" % tower_id
	else:
		sheet_path = DIR + body_sheet.get_file()
	var sheet := _load_texture(sheet_path)
	if sheet == null:
		_failed[tower_id] = true
		return false
	var fw := _meta_frame_w(meta)
	var fh := _meta_frame_h(meta)
	var cols := int(meta.get("columns", 4))
	var rows := int(meta.get("rows", 2))
	var sheet_size = meta.get("sheet_size", [cols * fw, rows * fh])
	var sheet_w := int(sheet_size[0]) if typeof(sheet_size) == TYPE_ARRAY and sheet_size.size() > 0 else cols * fw
	var sheet_h := int(sheet_size[1]) if typeof(sheet_size) == TYPE_ARRAY and sheet_size.size() > 1 else rows * fh
	var anims := _build_anims(sheet, meta, fw, fh)
	var entry := {
		"meta": meta,
		"sheet_path": sheet_path,
		"frame_w": fw,
		"frame_h": fh,
		"columns": cols,
		"rows": rows,
		"sheet_w": sheet_w,
		"sheet_h": sheet_h,
		"anims": anims,
		"anims_3x3": {},
		"vortex_3x3": {},
	}
	if tower_id == "vortex":
		entry["vortex_3x3"] = _load_vortex_3x3(meta)
		entry["anims_3x3"] = entry["vortex_3x3"].get("anims", {})
	_cache[tower_id] = entry
	return true


static func _default_meta(tower_id: String) -> Dictionary:
	return {
		"name": tower_id,
		"frame_size": [40, 40],
		"columns": 4,
		"rows": 2,
		"sheet_size": [160, 80],
		"animations": {
			"idle": {"row": 0, "frame_count": 4, "fps": 6, "loop": true},
			"shoot": {"row": 1, "frame_count": 4, "fps": 10, "loop": false},
		},
		"body_sheet": "tower_%s_sheet.png" % tower_id,
	}


static func _meta_frame_w(meta: Dictionary) -> int:
	var fs = meta.get("frame_size", 40)
	if typeof(fs) == TYPE_ARRAY and fs.size() > 0:
		return int(fs[0])
	return int(fs)


static func _meta_frame_h(meta: Dictionary) -> int:
	var fs = meta.get("frame_size", 40)
	if typeof(fs) == TYPE_ARRAY and fs.size() > 1:
		return int(fs[1])
	if typeof(fs) == TYPE_ARRAY and fs.size() > 0:
		return int(fs[0])
	return int(fs)


static func _build_anims(sheet: Texture2D, meta: Dictionary, fw: int, fh: int) -> Dictionary:
	var out := {}
	var anims_raw = meta.get("animations", {})
	if typeof(anims_raw) != TYPE_DICTIONARY:
		return out
	for anim_name in anims_raw.keys():
		var def: Dictionary = anims_raw[anim_name]
		if typeof(def) != TYPE_DICTIONARY:
			continue
		var row := int(def.get("row", 0))
		var count := int(def.get("frame_count", def.get("frames", 4)))
		count = maxi(count, 1)
		var fps := maxf(float(def.get("fps", 6.0)), 0.01)
		var loop := bool(def.get("loop", str(anim_name) == "idle"))
		var frames: Array = []
		for i in count:
			var at := AtlasTexture.new()
			at.atlas = sheet
			at.region = Rect2(i * fw, row * fh, fw, fh)
			frames.append(at)
		out[str(anim_name)] = {"frames": frames, "fps": fps, "loop": loop}
	return out


static func _load_vortex_3x3(meta: Dictionary) -> Dictionary:
	var spec: Dictionary = meta.get("vortex_3x3", {})
	var fw := int(spec.get("frame_width", 120))
	var fh := int(spec.get("frame_height", 120))
	var sheet_size = spec.get("sheet_size", [480, 240])
	var sheet_w := int(sheet_size[0]) if typeof(sheet_size) == TYPE_ARRAY else 480
	var sheet_h := int(sheet_size[1]) if typeof(sheet_size) == TYPE_ARRAY and sheet_size.size() > 1 else 240
	var sheet_path := DIR + "tower_vortex_3x3_sheet.png"
	var sheet := _load_texture(sheet_path)
	var anims := {}
	if sheet != null:
		var rows_map: Dictionary = spec.get("animation_rows", {"idle": 0, "activate": 1})
		for anim_name in rows_map.keys():
			var row := int(rows_map[anim_name])
			var frames: Array = []
			for i in 4:
				var at := AtlasTexture.new()
				at.atlas = sheet
				at.region = Rect2(i * fw, row * fh, fw, fh)
				frames.append(at)
			var loop := str(anim_name) == "idle"
			var fps := 6.0 if loop else 10.0
			# Prefer fps from main meta if present.
			var main_anims = meta.get("animations", {})
			if typeof(main_anims) == TYPE_DICTIONARY and main_anims.has(anim_name):
				fps = float(main_anims[anim_name].get("fps", fps))
			elif typeof(main_anims) == TYPE_DICTIONARY and anim_name == "activate" and main_anims.has("activate"):
				fps = float(main_anims["activate"].get("fps", fps))
			anims[str(anim_name)] = {"frames": frames, "fps": fps, "loop": loop}
	return {
		"frame_w": fw,
		"frame_h": fh,
		"sheet_w": sheet_w,
		"sheet_h": sheet_h,
		"sheet_path": sheet_path,
		"anims": anims,
	}


static func _ensure_wall_autotile() -> void:
	if not _wall_tiles.is_empty():
		return
	var path := DIR + "tower_wall_autotile_16.png"
	var atlas := _load_texture(path)
	if atlas == null:
		return
	for i in 16:
		var at := AtlasTexture.new()
		at.atlas = atlas
		at.region = Rect2((i % 4) * 40, int(i / 4) * 40, 40, 40)
		_wall_tiles.append(at)


static func _load_texture(path: String) -> Texture2D:
	if path.is_empty():
		return null
	if ResourceLoader.exists(path):
		var res = load(path)
		if res is Texture2D:
			return res as Texture2D
	if FileAccess.file_exists(path):
		var img := Image.load_from_file(ProjectSettings.globalize_path(path))
		if img != null and not img.is_empty():
			return ImageTexture.create_from_image(img)
	return null
