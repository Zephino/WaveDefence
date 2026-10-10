class_name CommandAbilities
extends RefCounted

## Pay-on-place Command abilities. Combat traps arm on the path; Supply Drop buffs on place.

const ABILITIES := {
	"airstrike": {
		"display_name": "Air Strike",
		"blurb": "Place a path trap. Detonates once when an enemy enters the cross.",
		"cost": 80,
		"cooldown": 1.5,
		"aim": "path",
		"mode": "trap",
		"damage": 140.0,
	},
	"supply": {
		"display_name": "Supply Drop",
		"blurb": "Place near towers to buff fire rate. Gold only spends if at least one tower is buffed.",
		"cost": 50,
		"cooldown": 2.0,
		"aim": "any",
		"mode": "instant",
		"buff_mult": 1.55,
		"buff_duration": 5.0,
		"buff_radius_cells": 2,
	},
	"barricade": {
		"display_name": "Barricade Spike",
		"blurb": "Place a path trap. Ground creeps on that tile are slowed and take DoT for several seconds.",
		"cost": 45,
		"cooldown": 1.5,
		"aim": "path",
		"mode": "trap",
		"slow_factor": 0.4,
		"slow_duration": 3.0,
		"dot_dps": 18.0,
		"dot_duration": 3.0,
		"trap_duration": 8.0,
	},
	"flare": {
		"display_name": "Recon Flare",
		"blurb": "Place a path trap. Marks enemies on the cross when they walk into it.",
		"cost": 35,
		"cooldown": 1.5,
		"aim": "path",
		"mode": "trap",
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


static func place_mode(ability_id: String) -> String:
	return str(get_def(ability_id).get("mode", "trap"))


static func is_trap(ability_id: String) -> bool:
	return place_mode(ability_id) == "trap"


## Rich tooltip matching tower shop style.
static func tooltip_for(ability_id: String) -> String:
	var def := get_def(ability_id)
	if def.is_empty():
		return ""
	var lines: PackedStringArray = PackedStringArray()
	lines.append("%s — %d gold / use" % [display_name(ability_id), cost(ability_id)])
	var blurb := str(def.get("blurb", "")).strip_edges()
	if blurb != "":
		lines.append(blurb)
	lines.append("Aim: %s" % ("path tile" if aim_mode(ability_id) == "path" else "any board tile"))
	lines.append("Cooldown: %.1fs" % cooldown(ability_id))
	if is_trap(ability_id):
		lines.append("Trap: gold spent on place; effect waits for enemies (no wasted miss).")
	match ability_id:
		"airstrike":
			lines.append("Damage: %.0f (bosses ×1.15) on center + 4 sides" % float(def.get("damage", 140.0)))
		"supply":
			lines.append(
				"Fire rate ×%.2f for %.1fs within %d tiles" % [
					float(def.get("buff_mult", 1.55)),
					float(def.get("buff_duration", 5.0)),
					int(def.get("buff_radius_cells", 2)),
				]
			)
		"barricade":
			lines.append(
				"Ground slow ×%.2f + %.0f DoT for %.1fs; trap lasts %.1fs" % [
					float(def.get("slow_factor", 0.4)),
					float(def.get("dot_dps", 18.0)),
					float(def.get("dot_duration", 3.0)),
					float(def.get("trap_duration", 8.0)),
				]
			)
		"flare":
			lines.append(
				"Mark ×%.2f damage for %.1fs on center + 4 sides" % [
					float(def.get("mark_mult", 1.4)),
					float(def.get("mark_duration", 4.0)),
				]
			)
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


## Enemies whose feet are on any of the given cells.
static func enemies_on_cells(enemy_container: Node, grid: GameGrid, cells: Array[Vector2i]) -> Array[Enemy]:
	var hit: Array[Enemy] = []
	if enemy_container == null or grid == null:
		return hit
	var wanted := {}
	for c in cells:
		wanted[c] = true
	for child in enemy_container.get_children():
		if child is Enemy:
			var e := child as Enemy
			if not e.alive:
				continue
			var cell := grid.world_to_cell(e.position)
			if wanted.has(cell):
				hit.append(e)
	return hit
