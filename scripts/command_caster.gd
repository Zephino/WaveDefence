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


static func cast(
	ability_id: String,
	cell: Vector2i,
	grid: GameGrid,
	pathfinder: Pathfinder,
	enemy_container: Node,
	_projectile_container: Node
) -> Dictionary:
	var def := CommandAbilities.get_def(ability_id)
	if def.is_empty():
		return {"ok": false, "message": "Unknown ability."}
	if grid == null or not grid.in_bounds(cell):
		return {"ok": false, "message": "Pick a tile on the board."}
	var aim := CommandAbilities.aim_mode(ability_id)
	if aim == "path" and not _is_path_cell(pathfinder, cell):
		return {"ok": false, "message": "Pick a tile on the enemy path."}

	match ability_id:
		"airstrike":
			return _cast_airstrike(cell, grid, enemy_container, def)
		"supply":
			return _cast_supply(cell, grid, def)
		"barricade":
			return _cast_barricade(cell, grid, enemy_container, def)
		"flare":
			return _cast_flare(cell, grid, enemy_container, def)
		_:
			return {"ok": false, "message": "Unknown ability."}


static func _is_path_cell(pathfinder: Pathfinder, cell: Vector2i) -> bool:
	if pathfinder == null:
		return false
	for c in pathfinder.get_cell_path():
		if c == cell:
			return true
	return false


static func _cast_airstrike(cell: Vector2i, grid: GameGrid, enemy_container: Node, def: Dictionary) -> Dictionary:
	var cells := CommandAbilities.cross_cells(cell)
	var targets := enemies_on_cells(enemy_container, grid, cells)
	var dmg := float(def.get("damage", 140.0))
	var hit := 0
	for e in targets:
		# Bosses feel the full strike; creeps still take a solid chunk.
		var amount := dmg * (1.15 if e.is_boss else 1.0)
		e.take_damage(amount)
		hit += 1
	if hit <= 0:
		return {"ok": true, "message": "Air Strike missed — no enemies on that cross."}
	return {"ok": true, "message": "Air Strike hit %d enem%s!" % [hit, "y" if hit == 1 else "ies"]}


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
		return {"ok": true, "message": "Supply Drop landed — no towers in range to buff."}
	return {"ok": true, "message": "Supply Drop buffed %d tower%s." % [buffed, "" if buffed == 1 else "s"]}


static func _cast_barricade(cell: Vector2i, grid: GameGrid, enemy_container: Node, def: Dictionary) -> Dictionary:
	var cells: Array[Vector2i] = [cell]
	var targets := enemies_on_cells(enemy_container, grid, cells)
	var slow_f := float(def.get("slow_factor", 0.4))
	var slow_d := float(def.get("slow_duration", 3.0))
	var dps := float(def.get("dot_dps", 18.0))
	var dot_d := float(def.get("dot_duration", 3.0))
	var hit := 0
	for e in targets:
		if e.is_flying:
			continue
		e.apply_slow(slow_f, slow_d)
		e.apply_poison(dps, dot_d)
		hit += 1
	if hit <= 0:
		return {"ok": true, "message": "Barricade Spike — no ground enemies on that tile."}
	return {"ok": true, "message": "Barricade spiked %d ground enem%s." % [hit, "y" if hit == 1 else "ies"]}


static func _cast_flare(cell: Vector2i, grid: GameGrid, enemy_container: Node, def: Dictionary) -> Dictionary:
	var cells := CommandAbilities.cross_cells(cell)
	var targets := enemies_on_cells(enemy_container, grid, cells)
	var mult := float(def.get("mark_mult", 1.4))
	var duration := float(def.get("mark_duration", 4.0))
	var hit := 0
	for e in targets:
		e.apply_mark(mult, duration)
		hit += 1
	if hit <= 0:
		return {"ok": true, "message": "Recon Flare — no enemies marked."}
	return {"ok": true, "message": "Recon Flare marked %d enem%s." % [hit, "y" if hit == 1 else "ies"]}
