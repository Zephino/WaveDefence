class_name AchievementStore
extends RefCounted

const SAVE_PATH := "user://achievements.cfg"
const SECTION := "unlocks"

static var _loaded: bool = false
static var _unlocked: Dictionary = {}  # id -> unix time


static func ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	_unlocked.clear()
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	var keys: PackedStringArray = cfg.get_section_keys(SECTION)
	for id in keys:
		_unlocked[id] = int(cfg.get_value(SECTION, id, 0))


static func is_unlocked(id: String) -> bool:
	ensure_loaded()
	return _unlocked.has(id)


static func unlock(id: String) -> bool:
	ensure_loaded()
	if _unlocked.has(id):
		return false
	_unlocked[id] = int(Time.get_unix_time_from_system())
	var cfg := ConfigFile.new()
	cfg.load(SAVE_PATH)
	cfg.set_value(SECTION, id, _unlocked[id])
	cfg.save(SAVE_PATH)
	return true


static func unlocked_ids() -> Array:
	ensure_loaded()
	return _unlocked.keys()
