class_name UserSettings
extends RefCounted

## Persistent player preferences (main-menu Settings).

const SAVE_PATH := "user://settings.cfg"
const SECTION := "prefs"
const KEY_LARGE_CONTROLS := "large_controls"

static var _loaded: bool = false
static var large_controls: bool = false


static func ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var cfg := ConfigFile.new()
	var err := cfg.load(SAVE_PATH)
	if err != OK:
		large_controls = false
		return
	large_controls = bool(cfg.get_value(SECTION, KEY_LARGE_CONTROLS, false))


static func set_large_controls(enabled: bool) -> void:
	ensure_loaded()
	large_controls = enabled
	var cfg := ConfigFile.new()
	cfg.load(SAVE_PATH)  # keep other keys if present
	cfg.set_value(SECTION, KEY_LARGE_CONTROLS, large_controls)
	cfg.save(SAVE_PATH)


static func is_large_controls() -> bool:
	ensure_loaded()
	return large_controls
