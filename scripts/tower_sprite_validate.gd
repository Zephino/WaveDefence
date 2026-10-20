extends SceneTree

## Headless tower sheet validator.
## Usage: godot --headless --path . -s res://scripts/tower_sprite_validate.gd
## Exit code 0 = OK, 1 = incompatible sheets.

func _init() -> void:
	var ts = preload("res://scripts/tower_sprites.gd")
	var errors: PackedStringArray = ts.validate_assets()
	if errors.is_empty():
		print("TOWER_SPRITE_VALIDATE_OK")
		quit(0)
		return
	print("TOWER_SPRITE_VALIDATE_FAIL")
	for e in errors:
		print(" - ", e)
	quit(1)
