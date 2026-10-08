class_name CommandCaster
extends RefCounted

## Executes Command tower pay-per-use abilities against the board.


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


static func affected_cells(ability_id: String, center: Vector2i) -> Array[Vector2i]:
	if CommandAbilities.places_trap(ability_id):
		if ability_id == "barricade":
			return [center]
		return CommandAbilities.cross_cells(center)
	if ability_id == "supply":
		return _supply_cells(center, int(CommandAbilities.get_def("supply").get("buff_radius_cells", 2)))
	return [center]


static func preview(
	ability_id: String,
	cell: Vector2i,
	grid: GameGrid,
	pathfinder: Pathfinder,
	traps: CommandTraps,
	enemy_container: Node
) -> Dictionary:
	var def := CommandAbilities.get_def(ability_id)
	if def.is_empty():
		return {"valid": false, "cells": [], "message": "Unknown ability."}
	if grid == null or not grid.in_bounds(cell):
		return {"valid": false, "cells": [], "message": "Pick a tile on the board."}
	var cells := affected_cells(ability_id, cell)
	var aim := CommandAbilities.aim_mode(ability_id)
	if aim == "path" and not _is_path_cell(pathfinder, cell):
		return {"valid": false, "cells": cells, "message": "Pick a tile on the enemy path."}
	if traps != null and CommandAbilities.places_trap(ability_id) and traps.overlaps_existing(ability_id, cell):
		return {"valid": false, "cells": cells, "message": "That path tile already has a trap."}
	if ability_id == "supply":
		var buffed := _count_supply_targets(cell, grid)
		if buffed <= 0:
			return {
				"valid": false,
				"cells": cells,
				"message": "Place near your towers — none in range to buff.",
			}
		return {
			"valid": true,
			"cells": cells,
			"message": "Supply Drop will buff %d tower%s." % [buffed, "" if buffed == 1 else "s"],
		}
	if CommandAbilities.places_trap(ability_id):
		var trap_name := CommandAbilities.display_name(ability_id)
		return {
			"valid": true,
			"cells": cells,
			"message": "Place %s trap — triggers when enemies cross." % trap_name,
		}
	return {"valid": false, "cells": cells, "message": "Can't aim there."}


static func cast(
	ability_id: String,
	cell: Vector2i,
	grid: GameGrid,
	pathfinder: Pathfinder,
	enemy_container: Node,
	_projectile_container: Node,
	traps: CommandTraps = null
) -> Dictionary:
	var preview_result := preview(ability_id, cell, grid, pathfinder, traps, enemy_container)
	if not bool(preview_result.get("valid", false)):
		return {"ok": false, "message": str(preview_result.get("message", "Can't aim there."))}

	if CommandAbilities.places_trap(ability_id):
		if traps == null:
			return {"ok": false, "message": "Traps unavailable."}
		traps.place(ability_id, cell)
		var name := CommandAbilities.display_name(ability_id)
		var dur := float(CommandAbilities.get_def(ability_id).get("trap_duration", 14.0))
		return {
			"ok": true,
			"message": "%s armed on path (%.0fs)." % [name, dur],
		}

	match ability_id:
		"supply":
			return _cast_supply(cell, grid, CommandAbilities.get_def(ability_id))
		_:
			return {"ok": false, "message": "Unknown ability."}


static func _is_path_cell(pathfinder: Pathfinder, cell: Vector2i) -> bool:
	if pathfinder == null:
		return false
	for c in pathfinder.get_cell_path():
		if c == cell:
			return true
	return false


static func _supply_cells(center: Vector2i, radius: int) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for y in range(center.y - radius, center.y + radius + 1):
		for x in range(center.x - radius, center.x + radius + 1):
			var c := Vector2i(x, y)
			if absi(c.x - center.x) + absi(c.y - center.y) <= radius:
				cells.append(c)
	return cells


static func _count_supply_targets(cell: Vector2i, grid: GameGrid) -> int:
	var def := CommandAbilities.get_def("supply")
	var radius := int(def.get("buff_radius_cells", 2))
	var buffed := 0
	for y in range(cell.y - radius, cell.y + radius + 1):
		for x in range(cell.x - radius, cell.x + radius + 1):
			var c := Vector2i(x, y)
			if not grid.in_bounds(c):
				continue
			if absi(c.x - cell.x) + absi(c.y - cell.y) > radius:
				continue
			var t = grid.get_tower_at(c)
			if t == null or not is_instance_valid(t):
				continue
			var tower := t as Tower
			if TowerData.is_wall(tower.tower_id) or TowerData.is_command(tower.tower_id):
				continue
			buffed += 1
	return buffed


static func _cast_supply(cell: Vector2i, grid: GameGrid, def: Dictionary) -> Dictionary:
	var radius := int(def.get("buff_radius_cells", 2))
	var mult := float(def.get("buff_mult", 1.5))
	var duration := float(def.get("buff_duration", 5.0))
	var buffed := 0
	for y in range(cell.y - radius, cell.y + radius + 1):
		for x in range(cell.x - radius, cell.x + radius + 1):
			var c := Vector2i(x, y)
			if not grid.in_bounds(c):
				continue
			if absi(c.x - cell.x) + absi(c.y - cell.y) > radius:
				continue
			var t = grid.get_tower_at(c)
			if t == null or not is_instance_valid(t):
				continue
			var tower := t as Tower
			if TowerData.is_wall(tower.tower_id) or TowerData.is_command(tower.tower_id):
				continue
			tower.apply_fire_buff(mult, duration)
			buffed += 1
	if buffed <= 0:
		return {"ok": false, "message": "Place near your towers — none in range to buff."}
	return {"ok": true, "message": "Supply Drop buffed %d tower%s." % [buffed, "" if buffed == 1 else "s"]}
