class_name CommandCaster
extends RefCounted

## Places traps or fires instant Command abilities. Gold is spent only after a successful place.

const _CommandTrap := preload("res://scripts/command_trap.gd")


static func enemies_on_cells(enemy_container: Node, grid: GameGrid, cells: Array[Vector2i]) -> Array[Enemy]:
	return CommandAbilities.enemies_on_cells(enemy_container, grid, cells)


static func validate_aim(
	ability_id: String,
	cell: Vector2i,
	grid: GameGrid,
	pathfinder: Pathfinder
) -> Dictionary:
	var def := CommandAbilities.get_def(ability_id)
	if def.is_empty():
		return {"ok": false, "message": "Unknown ability."}
	if grid == null or not grid.in_bounds(cell):
		return {"ok": false, "message": "Pick a tile on the board."}
	var aim := CommandAbilities.aim_mode(ability_id)
	if aim == "path" and not _is_path_cell(pathfinder, cell):
		return {"ok": false, "message": "Pick a tile on the enemy path."}
	return {"ok": true, "message": "", "def": def}


## Place a trap or apply an instant ability. Returns ok + optional trap node.
static func place(
	ability_id: String,
	cell: Vector2i,
	grid: GameGrid,
	pathfinder: Pathfinder,
	enemy_container: Node,
	trap_container: Node
) -> Dictionary:
	var check := validate_aim(ability_id, cell, grid, pathfinder)
	if not bool(check.get("ok", false)):
		return check
	var def: Dictionary = check.get("def", {})
	if CommandAbilities.is_trap(ability_id):
		if trap_container == null:
			return {"ok": false, "message": "Trap layer missing."}
		if _cell_has_trap(trap_container, cell):
			return {"ok": false, "message": "A trap is already on that tile."}
		var trap = _CommandTrap.new()
		trap.setup(ability_id, cell, grid, enemy_container, def)
		trap_container.add_child(trap)
		return {
			"ok": true,
			"trap": trap,
			"message": "%s armed — waits for enemies." % CommandAbilities.display_name(ability_id),
		}
	# Instant (Supply Drop): only succeed if something is buffed.
	return _cast_supply(cell, grid, def)


static func _cell_has_trap(trap_container: Node, cell: Vector2i) -> bool:
	for child in trap_container.get_children():
		if child.has_method("is_active") and child.get("cell") == cell and child.is_active():
			return true
	return false


static func _is_path_cell(pathfinder: Pathfinder, cell: Vector2i) -> bool:
	if pathfinder == null:
		return false
	for c in pathfinder.get_cell_path():
		if c == cell:
			return true
	return false


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
		return {"ok": false, "message": "No towers in range — gold not spent."}
	return {"ok": true, "message": "Supply Drop buffed %d tower%s." % [buffed, "" if buffed == 1 else "s"]}
