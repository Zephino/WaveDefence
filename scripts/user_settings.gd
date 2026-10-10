class_name UserSettings
extends RefCounted

## Persistent player preferences (main-menu Settings).

const SAVE_PATH := "user://settings.cfg"
const SECTION := "prefs"
const KEY_LARGE_CONTROLS := "large_controls"
const KEY_EFFECTS := "effects_enabled"
const KEY_TUTORIAL_COMPLETED := "tutorial_completed"
const KEY_MASTER_VOLUME := "master_volume"
const KEY_MUSIC_VOLUME := "music_volume"
const KEY_SFX_VOLUME := "sfx_volume"
const KEY_MUSIC_MUTED := "music_muted"
const KEY_SFX_MUTED := "sfx_muted"
const KEY_BUILD_SPEED := "build_speed_mult"
const KEY_SHOW_TOWER_RANGE := "show_tower_range"
const KEY_HIGH_CONTRAST := "high_contrast"
const KEY_PERFORMANCE_MODE := "performance_mode"
const KEY_SHOW_ENEMY_HP := "show_enemy_hp_bars"
const KEY_SHOW_GRID_COORDS := "show_grid_coordinates"
const KEY_SCREENSHOT_WATERMARK := "screenshot_watermark"

static var _loaded: bool = false
static var large_controls: bool = false
static var effects_enabled: bool = true
static var tutorial_completed: bool = false
static var master_volume: int = 80
static var music_volume: int = 70
static var sfx_volume: int = 80
static var music_muted: bool = false
static var sfx_muted: bool = false
static var build_speed_mult: float = 1.0
static var show_tower_range: bool = true
static var high_contrast: bool = false
static var performance_mode: bool = false
static var show_enemy_hp_bars: bool = false
static var show_grid_coordinates: bool = false
static var screenshot_watermark: bool = true


static func ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var cfg := ConfigFile.new()
	var err := cfg.load(SAVE_PATH)
	if err != OK:
		_apply_defaults()
		return
	large_controls = bool(cfg.get_value(SECTION, KEY_LARGE_CONTROLS, false))
	effects_enabled = bool(cfg.get_value(SECTION, KEY_EFFECTS, true))
	tutorial_completed = bool(cfg.get_value(SECTION, KEY_TUTORIAL_COMPLETED, false))
	master_volume = int(cfg.get_value(SECTION, KEY_MASTER_VOLUME, 80))
	music_volume = int(cfg.get_value(SECTION, KEY_MUSIC_VOLUME, 70))
	sfx_volume = int(cfg.get_value(SECTION, KEY_SFX_VOLUME, 80))
	music_muted = bool(cfg.get_value(SECTION, KEY_MUSIC_MUTED, false))
	sfx_muted = bool(cfg.get_value(SECTION, KEY_SFX_MUTED, false))
	build_speed_mult = float(cfg.get_value(SECTION, KEY_BUILD_SPEED, 1.0))
	show_tower_range = bool(cfg.get_value(SECTION, KEY_SHOW_TOWER_RANGE, true))
	high_contrast = bool(cfg.get_value(SECTION, KEY_HIGH_CONTRAST, false))
	performance_mode = bool(cfg.get_value(SECTION, KEY_PERFORMANCE_MODE, false))
	show_enemy_hp_bars = bool(cfg.get_value(SECTION, KEY_SHOW_ENEMY_HP, false))
	show_grid_coordinates = bool(cfg.get_value(SECTION, KEY_SHOW_GRID_COORDS, false))
	screenshot_watermark = bool(cfg.get_value(SECTION, KEY_SCREENSHOT_WATERMARK, true))
	build_speed_mult = clampf(build_speed_mult, 1.0, 2.5)


static func _apply_defaults() -> void:
	large_controls = false
	effects_enabled = true
	tutorial_completed = false
	master_volume = 80
	music_volume = 70
	sfx_volume = 80
	music_muted = false
	sfx_muted = false
	build_speed_mult = 1.0
	show_tower_range = true
	high_contrast = false
	performance_mode = false
	show_enemy_hp_bars = false
	show_grid_coordinates = false
	screenshot_watermark = true


static func _save_prefs() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SAVE_PATH)
	cfg.set_value(SECTION, KEY_LARGE_CONTROLS, large_controls)
	cfg.set_value(SECTION, KEY_EFFECTS, effects_enabled)
	cfg.set_value(SECTION, KEY_TUTORIAL_COMPLETED, tutorial_completed)
	cfg.set_value(SECTION, KEY_MASTER_VOLUME, master_volume)
	cfg.set_value(SECTION, KEY_MUSIC_VOLUME, music_volume)
	cfg.set_value(SECTION, KEY_SFX_VOLUME, sfx_volume)
	cfg.set_value(SECTION, KEY_MUSIC_MUTED, music_muted)
	cfg.set_value(SECTION, KEY_SFX_MUTED, sfx_muted)
	cfg.set_value(SECTION, KEY_BUILD_SPEED, build_speed_mult)
	cfg.set_value(SECTION, KEY_SHOW_TOWER_RANGE, show_tower_range)
	cfg.set_value(SECTION, KEY_HIGH_CONTRAST, high_contrast)
	cfg.set_value(SECTION, KEY_PERFORMANCE_MODE, performance_mode)
	cfg.set_value(SECTION, KEY_SHOW_ENEMY_HP, show_enemy_hp_bars)
	cfg.set_value(SECTION, KEY_SHOW_GRID_COORDS, show_grid_coordinates)
	cfg.set_value(SECTION, KEY_SCREENSHOT_WATERMARK, screenshot_watermark)
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


static func set_tutorial_completed(done: bool) -> void:
	ensure_loaded()
	tutorial_completed = done
	_save_prefs()


static func is_tutorial_completed() -> bool:
	ensure_loaded()
	return tutorial_completed


static func set_master_volume(v: int) -> void:
	ensure_loaded()
	master_volume = clampi(v, 0, 100)
	_save_prefs()


static func set_music_volume(v: int) -> void:
	ensure_loaded()
	music_volume = clampi(v, 0, 100)
	_save_prefs()


static func set_sfx_volume(v: int) -> void:
	ensure_loaded()
	sfx_volume = clampi(v, 0, 100)
	_save_prefs()


static func set_music_muted(on: bool) -> void:
	ensure_loaded()
	music_muted = on
	_save_prefs()


static func is_music_muted() -> bool:
	ensure_loaded()
	return music_muted


static func set_sfx_muted(on: bool) -> void:
	ensure_loaded()
	sfx_muted = on
	_save_prefs()


static func is_sfx_muted() -> bool:
	ensure_loaded()
	return sfx_muted


static func set_build_speed_mult(v: float) -> void:
	ensure_loaded()
	build_speed_mult = clampf(v, 1.0, 2.5)
	_save_prefs()


static func get_build_speed_mult() -> float:
	ensure_loaded()
	return build_speed_mult


static func set_show_tower_range(on: bool) -> void:
	ensure_loaded()
	show_tower_range = on
	_save_prefs()


static func is_show_tower_range() -> bool:
	ensure_loaded()
	return show_tower_range


static func set_high_contrast(on: bool) -> void:
	ensure_loaded()
	high_contrast = on
	_save_prefs()


static func is_high_contrast() -> bool:
	ensure_loaded()
	return high_contrast


static func set_performance_mode(on: bool) -> void:
	ensure_loaded()
	performance_mode = on
	_save_prefs()


static func is_performance_mode() -> bool:
	ensure_loaded()
	return performance_mode


static func set_show_enemy_hp_bars(on: bool) -> void:
	ensure_loaded()
	show_enemy_hp_bars = on
	_save_prefs()


static func is_show_enemy_hp_bars() -> bool:
	ensure_loaded()
	return show_enemy_hp_bars


static func set_show_grid_coordinates(on: bool) -> void:
	ensure_loaded()
	show_grid_coordinates = on
	_save_prefs()


static func is_show_grid_coordinates() -> bool:
	ensure_loaded()
	return show_grid_coordinates


static func set_screenshot_watermark(on: bool) -> void:
	ensure_loaded()
	screenshot_watermark = on
	_save_prefs()


static func is_screenshot_watermark() -> bool:
	ensure_loaded()
	return screenshot_watermark
