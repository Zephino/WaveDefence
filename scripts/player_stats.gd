class_name PlayerStats
extends RefCounted

## Device-only personal bests (not run saves).

const SAVE_PATH := "user://stats.cfg"
const SECTION := "bests"

static var _loaded: bool = false
## difficulty int -> best wave
static var _best_wave: Dictionary = {}


static func ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	_best_wave.clear()
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	if not cfg.has_section_key(SECTION, "waves"):
		return
	var raw: Dictionary = cfg.get_value(SECTION, "waves", {})
	for k in raw.keys():
		_best_wave[int(k)] = int(raw[k])


static func _save() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SAVE_PATH)
	cfg.set_value(SECTION, "waves", _best_wave.duplicate())
	cfg.save(SAVE_PATH)


static func best_wave_for_difficulty(difficulty: int) -> int:
	ensure_loaded()
	return int(_best_wave.get(difficulty, 0))


static func try_update_best(difficulty: int, wave_reached: int) -> bool:
	ensure_loaded()
	var prev := best_wave_for_difficulty(difficulty)
	if wave_reached <= prev:
		return false
	_best_wave[difficulty] = wave_reached
	_save()
	return true
