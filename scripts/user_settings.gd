class_name UserSettings
extends RefCounted

## Persistent player preferences (main-menu Settings).

const SAVE_PATH := "user://settings.cfg"
const SECTION := "prefs"
const KEY_LARGE_CONTROLS := "large_controls"
const KEY_EFFECTS := "effects_enabled"

static var _loaded: bool = false
static var large_controls: bool = false
static var effects_enabled: bool = true


static func ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var cfg := ConfigFile.new()
	var err := cfg.load(SAVE_PATH)
	if err != OK:
		large_controls = false
		effects_enabled = true
		return
	large_controls = bool(cfg.get_value(SECTION, KEY_LARGE_CONTROLS, false))
	effects_enabled = bool(cfg.get_value(SECTION, KEY_EFFECTS, true))


static func _save_prefs() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SAVE_PATH)  # keep other keys if present
	cfg.set_value(SECTION, KEY_LARGE_CONTROLS, large_controls)
	cfg.set_value(SECTION, KEY_EFFECTS, effects_enabled)
	cfg.save(SAVE_PATH)


static func set_large_controls(enabled: bool) -> void:
	ensure_loaded()
	large_controls = enabled
	_save_prefs()


static func is_large_controls() -> bool:
	ensure_loaded()
	return large_controls


static func set_effects_enabled(enabled: bool) -> void:
	ensure_loaded()
	effects_enabled = enabled
	_save_prefs()


static func is_effects_enabled() -> bool:
	ensure_loaded()
	return effects_enabled
