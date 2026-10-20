class_name EffectSprites
extends RefCounted

## Data-driven attack VFX under res://assets/sprites/effects/.
## Replace sheets + update effects_manifest.json — combat code stays unchanged.

const DIR := "res://assets/sprites/effects/"
const MANIFEST_PATH := DIR + "effects_manifest.json"

## tower_id -> in-flight projectile sheet name
const PROJECTILE_FOR_TOWER := {
	"gunner": "fx_tracer",
	"rapid": "fx_tracer",
	"gatling": "fx_tracer",
	"antiair": "fx_flak_shell",
	"cannon": "fx_cannon_shell",
	"burn": "fx_fireball",
	"freeze": "fx_ice_shard",
	"poison": "fx_poison_glob",
	"lightning": "fx_lightning_bolt",
}

## tower_id -> impact burst
const IMPACT_FOR_TOWER := {
	"gunner": "fx_hit_spark",
	"rapid": "fx_hit_spark",
	"gatling": "fx_hit_spark",
	"cannon": "fx_explosion",
	"burn": "fx_fire_burst",
	"freeze": "fx_frost_burst",
	"poison": "fx_poison_cloud",
	"lightning": "fx_lightning_spark",
	"antiair": "fx_flak_burst",
	"spike": "fx_spike_burst",
}

const MUZZLE_TOWERS := {
	"gunner": true,
	"rapid": true,
	"gatling": true,
	"cannon": true,
	"antiair": true,
}

## name -> { frames, fps, loop, frame_w, frame_h, pivot, sheet_w, sheet_h }
static var _cache: Dictionary = {}
static var _failed: Dictionary = {}
static var _manifest_loaded: bool = false


static func display_scale() -> float:
	return float(GameLayout.tile_size()) / 40.0


static func has_effect(effect_name: String) -> bool:
	if effect_name.is_empty() or _failed.has(effect_name):
		return false
	return _ensure(effect_name)


static func projectile_for_tower(tower_id: String) -> String:
	return str(PROJECTILE_FOR_TOWER.get(tower_id, ""))


static func impact_for_tower(tower_id: String) -> String:
	return str(IMPACT_FOR_TOWER.get(tower_id, ""))


static func uses_muzzle(tower_id: String) -> bool:
	return bool(MUZZLE_TOWERS.get(tower_id, false))


static func frame_size(effect_name: String) -> Vector2:
	if not _ensure(effect_name):
		return Vector2(16, 16)
	var e: Dictionary = _cache[effect_name]
	return Vector2(float(e.get("frame_w", 16)), float(e.get("frame_h", 16)))


static func pivot(effect_name: String) -> Vector2:
	if not _ensure(effect_name):
		return Vector2(8, 8)
	var e: Dictionary = _cache[effect_name]
	return e.get("pivot", Vector2(8, 8)) as Vector2


static func anim_duration(effect_name: String) -> float:
	if not _ensure(effect_name):
		return 0.0
	var e: Dictionary = _cache[effect_name]
	var frames: Array = e.get("frames", [])
	var fps: float = maxf(float(e.get("fps", 12.0)), 0.01)
	return float(frames.size()) / fps


static func anim_loops(effect_name: String) -> bool:
	if not _ensure(effect_name):
		return true
	return bool(_cache[effect_name].get("loop", true))


static func anim_texture(effect_name: String, anim_time: float) -> Texture2D:
	if not _ensure(effect_name):
		return null
	var e: Dictionary = _cache[effect_name]
	var frames: Array = e.get("frames", [])
	if frames.is_empty():
		return null
	var fps: float = maxf(float(e.get("fps", 12.0)), 0.01)
	var loop: bool = bool(e.get("loop", true))
	var idx: int
	if loop:
		idx = int(floor(anim_time * fps)) % frames.size()
	else:
		idx = mini(int(floor(anim_time * fps)), frames.size() - 1)
	if idx < 0:
		idx = 0
	return frames[idx] as Texture2D


## Draw a frame centered on pivot at local origin, facing `angle` (rad).
static func draw_effect(
	canvas: CanvasItem,
	effect_name: String,
	anim_time: float,
	angle: float = 0.0,
	extra_scale: float = 1.0
) -> bool:
	var tex := anim_texture(effect_name, anim_time)
	if tex == null or canvas == null:
		return false
	var sz := frame_size(effect_name)
	var piv := pivot(effect_name)
	var sc := display_scale() * extra_scale
	canvas.draw_set_transform(Vector2.ZERO, angle, Vector2(sc, sc))
	canvas.draw_texture_rect(tex, Rect2(-piv, sz), false)
	canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	return true


## One-shot / looping sprite node parented under `parent` at global pos.
static func spawn_flash(
	effect_name: String,
	global_pos: Vector2,
	parent: Node,
	angle: float = 0.0,
	extra_scale: float = 1.0
) -> Node2D:
	if parent == null or not has_effect(effect_name):
		return null
	if not UserSettings.is_effects_enabled() or UserSettings.is_performance_mode():
		return null
	var flash_script: GDScript = load("res://scripts/effect_flash.gd") as GDScript
	if flash_script == null:
		return null
	var node: Node2D = flash_script.new() as Node2D
	parent.add_child(node)
	node.call("setup", effect_name, global_pos, angle, extra_scale)
	return node


static func validate_assets() -> PackedStringArray:
	var errors: PackedStringArray = []
	_load_manifest()
	if not FileAccess.file_exists(MANIFEST_PATH):
		errors.append("missing %s" % MANIFEST_PATH)
		return errors
	var raw := FileAccess.get_file_as_string(MANIFEST_PATH)
	var parsed = JSON.parse_string(raw)
	if typeof(parsed) != TYPE_DICTIONARY:
		errors.append("effects_manifest.json is not a dictionary")
		return errors
	var list = parsed.get("effects", [])
	if typeof(list) != TYPE_ARRAY:
		errors.append("effects_manifest.json missing effects array")
		return errors
	for item in list:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var name := str(item.get("name", ""))
		_cache.erase(name)
		_failed.erase(name)
		if not _ensure(name):
			errors.append("%s: failed to load sheet" % name)
			continue
		var e: Dictionary = _cache[name]
		var want_w := int(item.get("frame_width", 16)) * int(item.get("columns", 4))
		var want_h := int(item.get("frame_height", 16)) * int(item.get("rows", 1))
		var got_w := int(e.get("sheet_w", 0))
		var got_h := int(e.get("sheet_h", 0))
		if got_w != want_w or got_h != want_h:
			errors.append(
				"%s: sheet %dx%d != expected %dx%d" % [name, got_w, got_h, want_w, want_h]
			)
	return errors


static func _load_manifest() -> void:
	if _manifest_loaded:
		return
	_manifest_loaded = true
	if not FileAccess.file_exists(MANIFEST_PATH):
		return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST_PATH))
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	# Manifest is consulted per-effect in _ensure; flag only.


static func _ensure(effect_name: String) -> bool:
	if _cache.has(effect_name):
		return true
	if _failed.has(effect_name):
		return false
	_load_manifest()
	var meta := _meta_for(effect_name)
	if meta.is_empty():
		_failed[effect_name] = true
		return false
	var sheet_file := str(meta.get("sheet", "%s_sheet.png" % effect_name))
	var sheet_path := DIR + sheet_file.get_file()
	var sheet := _load_texture(sheet_path)
	if sheet == null:
		_failed[effect_name] = true
		return false
	var fw := int(meta.get("frame_width", 16))
	var fh := int(meta.get("frame_height", 16))
	var count := maxi(int(meta.get("frames", 4)), 1)
	var fps := maxf(float(meta.get("fps", 12.0)), 0.01)
	var loop := bool(meta.get("loop", true))
	var piv_raw = meta.get("pivot", [fw * 0.5, fh * 0.5])
	var piv := Vector2(float(fw) * 0.5, float(fh) * 0.5)
	if typeof(piv_raw) == TYPE_ARRAY and piv_raw.size() >= 2:
		piv = Vector2(float(piv_raw[0]), float(piv_raw[1]))
	var frames: Array = []
	for i in count:
		var at := AtlasTexture.new()
		at.atlas = sheet
		at.region = Rect2(i * fw, 0, fw, fh)
		frames.append(at)
	_cache[effect_name] = {
		"frames": frames,
		"fps": fps,
		"loop": loop,
		"frame_w": fw,
		"frame_h": fh,
		"pivot": piv,
		"sheet_w": sheet.get_width(),
		"sheet_h": sheet.get_height(),
	}
	return true


static func _meta_for(effect_name: String) -> Dictionary:
	if not FileAccess.file_exists(MANIFEST_PATH):
		return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST_PATH))
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	var list = parsed.get("effects", [])
	if typeof(list) != TYPE_ARRAY:
		return {}
	for item in list:
		if typeof(item) == TYPE_DICTIONARY and str(item.get("name", "")) == effect_name:
			return item
	return {}


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
