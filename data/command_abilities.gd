class_name CommandAbilities
extends RefCounted

## Pay-per-use abilities for the Command tower. Each cast costs gold again.

const ABILITIES := {
	"airstrike": {
		"display_name": "Air Strike",
		"blurb": "Arm a path cross. Strikes when enemies enter — you only pay if placement is valid.",
		"cost": 80,
		"cooldown": 1.5,
		"aim": "path",
		"trap": true,
		"trap_duration": 18.0,
		"damage": 140.0,
	},
	"supply": {
		"display_name": "Supply Drop",
		"blurb": "Drop supplies near your towers to boost fire rate. Must buff at least one tower.",
		"cost": 50,
		"cooldown": 2.0,
		"aim": "any",
		"buff_mult": 1.55,
		"buff_duration": 5.0,
		"buff_radius_cells": 2,
	},
	"barricade": {
		"display_name": "Barricade Spike",
		"blurb": "Place a spike trap on the path. Ground enemies crossing the tile are slowed and poisoned.",
		"cost": 45,
		"cooldown": 1.5,
		"aim": "path",
		"trap": true,
		"trap_duration": 16.0,
		"slow_factor": 0.4,
		"slow_duration": 3.0,
		"dot_dps": 18.0,
		"dot_duration": 3.0,
	},
	"flare": {
		"display_name": "Recon Flare",
		"blurb": "Arm a flare on a path cross. Marks enemies when they enter for bonus damage.",
		"cost": 35,
		"cooldown": 1.5,
		"aim": "path",
		"trap": true,
		"trap_duration": 18.0,
		"mark_mult": 1.4,
		"mark_duration": 4.0,
	},
}


static func get_ids() -> Array:
	return ["airstrike", "supply", "barricade", "flare"]


static func get_def(ability_id: String) -> Dictionary:
	return ABILITIES.get(ability_id, {})


static func display_name(ability_id: String) -> String:
	return str(get_def(ability_id).get("display_name", ability_id.capitalize()))


static func cost(ability_id: String) -> int:
	return int(get_def(ability_id).get("cost", 0))


static func cooldown(ability_id: String) -> float:
	return float(get_def(ability_id).get("cooldown", 1.0))


static func aim_mode(ability_id: String) -> String:
	return str(get_def(ability_id).get("aim", "path"))


static func places_trap(ability_id: String) -> bool:
	return bool(get_def(ability_id).get("trap", false))


static func trap_duration(ability_id: String) -> float:
	return float(get_def(ability_id).get("trap_duration", 14.0))


## Hover text for Command ability buttons (matches tower shop tooltips).
static func tooltip_for(ability_id: String) -> String:
	var def := get_def(ability_id)
	if def.is_empty():
		return ability_id
	var lines: PackedStringArray = PackedStringArray()
	lines.append("%s — %d gold per use" % [
		str(def.get("display_name", ability_id)),
		int(def.get("cost", 0)),
	])
	var blurb := str(def.get("blurb", "")).strip_edges()
	if blurb != "":
		lines.append(blurb)
	lines.append("Cooldown %.1fs after use" % float(def.get("cooldown", 1.0)))
	match ability_id:
		"airstrike":
			lines.append("Trap: path cross, %.0fs  |  Damage %.0f" % [
				trap_duration(ability_id),
				float(def.get("damage", 0.0)),
			])
			lines.append("Triggers once when enemies enter the cross")
		"barricade":
			lines.append("Trap: single path tile, %.0fs" % trap_duration(ability_id))
			lines.append("Slow to %.0f%% speed, poison %.0f DPS (ground only)" % [
				float(def.get("slow_factor", 1.0)) * 100.0,
				float(def.get("dot_dps", 0.0)),
			])
		"flare":
			lines.append("Trap: path cross, %.0fs  |  Mark x%.2f damage for %.1fs" % [
				trap_duration(ability_id),
				float(def.get("mark_mult", 1.0)),
				float(def.get("mark_duration", 0.0)),
			])
		"supply":
			lines.append("Instant buff: fire rate x%.2f for %.1fs" % [
				float(def.get("buff_mult", 1.0)),
				float(def.get("buff_duration", 0.0)),
			])
			lines.append("Radius %d cells (Manhattan) — must hit a tower" % int(def.get("buff_radius_cells", 2)))
	if places_trap(ability_id):
		lines.append("Click a path tile to place (like a trap). Gold only spent on valid placement.")
	else:
		lines.append("Click the board to aim. Gold only spent when the drop will buff towers.")
	return "\n".join(lines)


## Center cell plus four orthogonal neighbors (for Air Strike / Flare).
static func cross_cells(center: Vector2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = [
		center,
		center + Vector2i(0, -1),
		center + Vector2i(0, 1),
		center + Vector2i(-1, 0),
		center + Vector2i(1, 0),
	]
	return cells
