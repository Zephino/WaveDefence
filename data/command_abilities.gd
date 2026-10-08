class_name CommandAbilities
extends RefCounted

## Pay-per-use abilities for the Command tower. Each cast costs gold again.

const ABILITIES := {
	"airstrike": {
		"display_name": "Air Strike",
		"blurb": "Strike one path tile + four sides. High damage. Miss = wasted gold.",
		"cost": 80,
		"cooldown": 1.5,
		"aim": "path",
		"damage": 140.0,
	},
	"supply": {
		"display_name": "Supply Drop",
		"blurb": "Buff nearby towers' fire rate for a few seconds.",
		"cost": 50,
		"cooldown": 2.0,
		"aim": "any",
		"buff_mult": 1.55,
		"buff_duration": 5.0,
		"buff_radius_cells": 2,
	},
	"barricade": {
		"display_name": "Barricade Spike",
		"blurb": "Spike a path tile: ground creeps get slowed and DoT.",
		"cost": 45,
		"cooldown": 1.5,
		"aim": "path",
		"slow_factor": 0.4,
		"slow_duration": 3.0,
		"dot_dps": 18.0,
		"dot_duration": 3.0,
	},
	"flare": {
		"display_name": "Recon Flare",
		"blurb": "Mark enemies on a path cross so they take bonus damage briefly.",
		"cost": 35,
		"cooldown": 1.5,
		"aim": "path",
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
