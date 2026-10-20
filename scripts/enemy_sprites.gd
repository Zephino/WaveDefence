class_name EnemySprites
extends RefCounted

## Mob sprite sheets under res://assets/sprites/<id>/
## Supports *_ground_*, *_flier_*, and *_boss_* sheet naming.

const BASE_SPECIES: PackedStringArray = [
	"slime", "beetle", "spider", "crab", "crawler",
	"pillbug", "tortoise", "urchin", "mole", "scarab",
	"tick", "slug", "jelly", "armadillo", "roller",
]
const PLUS_SPECIES: PackedStringArray = [
	"slime_plus", "beetle_plus", "spider_plus", "crab_plus", "crawler_plus",
	"pillbug_plus", "tortoise_plus", "urchin_plus", "mole_plus", "scarab_plus",
	"tick_plus", "slug_plus", "jelly_plus", "armadillo_plus", "roller_plus",
]
const FLYING_SPECIES: PackedStringArray = [
	"bat", "wasp", "moth", "hornet", "dragonfly",
	"firefly", "hoverbot", "propeller", "stingray", "sky_jelly",
]
const FLYING_PLUS_SPECIES: PackedStringArray = [
	"bat_plus", "wasp_plus", "moth_plus", "hornet_plus", "dragonfly_plus",
	"firefly_plus", "hoverbot_plus", "propeller_plus", "stingray_plus", "sky_jelly_plus",
]
const BOSS_SPECIES: PackedStringArray = [
	"colossus_v2", "iron_maw_v2", "juggernaut_v2", "leviathan_v2", "overseer_v2",
]
const BOSS_PLUS_SPECIES: PackedStringArray = [
	"colossus_plus_v2", "iron_maw_plus_v2", "juggernaut_plus_v2",
	"leviathan_plus_v2", "overseer_plus_v2",
]
const WRECKER_SPECIES := "armadillo"
const SNAKE_SPECIES := "crawler"
const _SHEET_KINDS: PackedStringArray = ["ground", "flier", "boss"]

## species_id -> { sheet: Texture2D, walk: Array[AtlasTexture], fps: float, frame_w: int, frame_h: int }
static var _cache: Dictionary = {}
static var _failed: Dictionary = {}


static func pick_species(
	is_boss: bool,
	is_flying: bool,
	is_wrecker: bool,
	is_snake: bool,
	wave: int,
	rng: RandomNumberGenerator = null
) -> String:
	if is_wrecker:
		return WRECKER_SPECIES if not is_boss else "armadillo_plus"
	if is_snake:
		return SNAKE_SPECIES if not is_boss else "crawler_plus"
	if is_flying:
		var fly_pool: PackedStringArray = (
			FLYING_PLUS_SPECIES if is_boss or wave >= 20 else FLYING_SPECIES
		)
		return _pick_from(fly_pool, rng)
	if is_boss:
		var boss_pool: PackedStringArray = (
			BOSS_PLUS_SPECIES if wave >= 25 else BOSS_SPECIES
		)
		return _pick_from(boss_pool, rng)
	var pool: PackedStringArray = PLUS_SPECIES if wave >= 25 else BASE_SPECIES
	return _pick_from(pool, rng)


static func _pick_from(pool: PackedStringArray, rng: RandomNumberGenerator) -> String:
	if pool.is_empty():
		return "slime"
	if rng != null:
		return str(pool[rng.randi_range(0, pool.size() - 1)])
	return str(pool[int(Time.get_ticks_msec()) % pool.size()])


static func has_species(species_id: String) -> bool:
	if species_id.is_empty() or _failed.has(species_id):
		return false
	return _ensure(species_id)


static func walk_texture(species_id: String, anim_time: float) -> Texture2D:
	if not _ensure(species_id):
		return null
	var entry: Dictionary = _cache[species_id]
	var frames: Array = entry.get("walk", [])
	if frames.is_empty():
		return null
	var fps: float = float(entry.get("fps", 8.0))
	var idx := int(floor(anim_time * fps)) % frames.size()
	if idx < 0:
		idx = 0
	return frames[idx] as Texture2D


static func frame_size(species_id: String) -> Vector2:
	if not _ensure(species_id):
		return Vector2(40, 40)
	var entry: Dictionary = _cache[species_id]
	return Vector2(float(entry.get("frame_w", 40)), float(entry.get("frame_h", 40)))


static func _resolve_paths(species_id: String) -> Dictionary:
	for kind in _SHEET_KINDS:
		var sheet_path := "res://assets/sprites/%s/%s_%s_sheet.png" % [species_id, species_id, kind]
		var frames_path := "res://assets/sprites/%s/%s_%s_frames.json" % [species_id, species_id, kind]
		if ResourceLoader.exists(sheet_path) or FileAccess.file_exists(sheet_path):
			return {"sheet": sheet_path, "frames": frames_path, "kind": kind}
	return {}


static func _ensure(species_id: String) -> bool:
	if _cache.has(species_id):
		return true
	if _failed.has(species_id):
		return false
	var paths := _resolve_paths(species_id)
	if paths.is_empty():
		_failed[species_id] = true
		return false
	var sheet_path: String = str(paths["sheet"])
	var frames_path: String = str(paths["frames"])
	var sheet: Texture2D = null
	if ResourceLoader.exists(sheet_path):
		sheet = load(sheet_path) as Texture2D
	if sheet == null and FileAccess.file_exists(sheet_path):
		var img := Image.load_from_file(ProjectSettings.globalize_path(sheet_path))
		if img != null and not img.is_empty():
			sheet = ImageTexture.create_from_image(img)
	if sheet == null:
		_failed[species_id] = true
		return false
	var meta := {
		"frame_width": 40,
		"frame_height": 40,
		"animations": {"walk": {"row": 0, "frame_count": 4, "fps": 8}},
	}
	if FileAccess.file_exists(frames_path):
		var f := FileAccess.open(frames_path, FileAccess.READ)
		if f != null:
			var parsed = JSON.parse_string(f.get_as_text())
			if typeof(parsed) == TYPE_DICTIONARY:
				meta = parsed
	var fw := int(meta.get("frame_width", 40))
	var fh := int(meta.get("frame_height", 40))
	var walk_def: Dictionary = {}
	var anims = meta.get("animations", {})
	if typeof(anims) == TYPE_DICTIONARY and typeof(anims.get("walk", null)) == TYPE_DICTIONARY:
		walk_def = anims["walk"]
	var row := int(walk_def.get("row", 0))
	var count := maxi(int(walk_def.get("frame_count", 4)), 1)
	var fps := maxf(float(walk_def.get("fps", 8.0)), 1.0)
	var walk: Array = []
	for i in count:
		var at := AtlasTexture.new()
		at.atlas = sheet
		at.region = Rect2(i * fw, row * fh, fw, fh)
		walk.append(at)
	_cache[species_id] = {
		"sheet": sheet,
		"walk": walk,
		"fps": fps,
		"frame_w": fw,
		"frame_h": fh,
	}
	return true
