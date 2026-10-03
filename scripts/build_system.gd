class_name BuildSystem
extends Node

signal selection_changed(tower_id: String)
signal selected_towers_changed(count: int, sell_total: int)
## upgrade_cost / final_cost are totals for all currently eligible selected towers.
signal selection_upgrade_changed(can_stat: bool, upgrade_cost: int, can_final: bool, final_cost: int)

var grid: GameGrid
var pathfinder: Pathfinder
var game_state: GameState
var enemy_container: Node
var projectile_container: Node

var selected_tower_id: String = "gunner"
var selected_towers: Array[Tower] = []
var placing_enabled: bool = true


func setup(p_grid: GameGrid, p_pathfinder: Pathfinder, p_state: GameState, p_enemies: Node, p_projectiles: Node) -> void:
	grid = p_grid
	pathfinder = p_pathfinder
	game_state = p_state
	enemy_container = p_enemies
	projectile_container = p_projectiles


## Select the shop tower type to place. Does not replace existing towers — sell first.
func select_tower_type(tower_id: String) -> void:
	selected_tower_id = tower_id
	selection_changed.emit(selected_tower_id)


## Returns the tower under the cursor, or null if none.
func update_hover(world_pos: Vector2) -> Tower:
	if grid == null or game_state.is_game_over:
		grid.set_hover(Vector2i(-1, -1), false, false)
		return null
	var cell := grid.world_to_cell(world_pos)
	var valid := can_place_at(cell)
	grid.set_hover(cell, valid, placing_enabled and grid.in_bounds(cell))
	if not grid.in_bounds(cell):
		return null
	var existing := grid.get_tower_at(cell)
	if existing and is_instance_valid(existing):
		return existing as Tower
	return null


func can_place_at(cell: Vector2i) -> bool:
	if game_state.is_game_over:
		return false
	if not grid.in_bounds(cell):
		return false
	if cell == grid.spawn_cell or cell == grid.exit_cell:
		return false
	var cost: int = int(TowerData.get_def(selected_tower_id)["cost"])
	if not game_state.can_afford(cost):
		return false

	var existing := grid.get_tower_at(cell)
	if existing:
		# Only real towers may replace walls. Never stack wall/tower on a tower.
		return _can_replace_wall(existing)

	if not grid.is_buildable(cell):
		return false
	if pathfinder.would_block_path(cell):
		return false
	return true


func try_place_at(world_pos: Vector2, additive_select: bool = false) -> bool:
	if game_state.is_game_over:
		return false
	var cell := grid.world_to_cell(world_pos)
	if not grid.in_bounds(cell):
		return false

	var existing := grid.get_tower_at(cell)
	if existing and not _can_replace_wall(existing):
		if additive_select:
			_toggle_selected(existing)
		else:
			_select_only(existing)
		return false

	if not can_place_at(cell):
		if not existing and not additive_select:
			_clear_placed_selection()
		return false

	var cost: int = int(TowerData.get_def(selected_tower_id)["cost"])
	if not game_state.spend_gold(cost):
		return false

	if existing and _can_replace_wall(existing):
		_replace_wall_with_tower(cell, existing)
		return true

	var tower := Tower.new()
	tower.setup(selected_tower_id, enemy_container, projectile_container)
	grid.place_tower(cell, tower)
	pathfinder.rebuild()
	_refresh_path_preview()
	# Placing should not leave the new tower (or prior selection) selected.
	_clear_placed_selection()
	return true


## Towers can be built on walls. Walls/towers cannot be built on towers (sell first).
func _can_replace_wall(existing: Tower) -> bool:
	if existing == null or not is_instance_valid(existing):
		return false
	return TowerData.is_wall(existing.tower_id) and not TowerData.is_wall(selected_tower_id)


func _replace_wall_with_tower(cell: Vector2i, wall: Tower) -> void:
	_replace_tower_at(cell, wall, selected_tower_id)
	pathfinder.rebuild()
	_refresh_path_preview()
	_clear_placed_selection()


func _replace_tower_at(cell: Vector2i, old_tower: Tower, new_tower_id: String) -> Tower:
	_remove_from_selection(old_tower)
	# Silent remove so pathfinding never sees an open hole mid-swap.
	var removed := grid.remove_tower_at(cell, false)
	if removed:
		removed.queue_free()
	var tower := Tower.new()
	tower.setup(new_tower_id, enemy_container, projectile_container)
	grid.place_tower(cell, tower)
	return tower


func sell_selected() -> bool:
	_prune_selection()
	if selected_towers.is_empty():
		return false
	var refund_total := 0
	var cells: Array[Vector2i] = []
	for tower in selected_towers:
		if not is_instance_valid(tower):
			continue
		cells.append(grid.world_to_cell(tower.position))
	selected_towers.clear()
	for cell in cells:
		var tower := grid.remove_tower_at(cell)
		if tower == null:
			continue
		refund_total += TowerData.sell_value_for_tower(tower as Tower)
		tower.queue_free()
	game_state.add_gold(refund_total)
	pathfinder.rebuild()
	_refresh_path_preview()
	_emit_selection()
	return refund_total > 0 or cells.size() > 0


## Upgrade every selected tower by one stat level (skips walls / maxed / unaffordable).
func upgrade_selected() -> Dictionary:
	_prune_selection()
	var upgraded := 0
	var failed_afford := 0
	var spent := 0
	for tower in selected_towers:
		if not is_instance_valid(tower) or not tower.can_stat_upgrade():
			continue
		var cost := tower.next_stat_upgrade_cost()
		if not game_state.can_afford(cost):
			failed_afford += 1
			continue
		if game_state.spend_gold(cost) and tower.apply_stat_upgrade():
			upgraded += 1
			spent += cost
		else:
			failed_afford += 1
	_emit_selection()
	return {"upgraded": upgraded, "failed_afford": failed_afford, "spent": spent}


## Apply a final elemental upgrade to every selected tower that is ready.
func apply_final_selected(element_id: String) -> Dictionary:
	_prune_selection()
	var applied := 0
	var failed_afford := 0
	var spent := 0
	if not TowerData.is_final_element(element_id):
		return {"applied": 0, "failed_afford": 0, "spent": 0}
	for tower in selected_towers:
		if not is_instance_valid(tower) or not tower.can_final_upgrade():
			continue
		var cost := tower.final_upgrade_cost()
		if not game_state.can_afford(cost):
			failed_afford += 1
			continue
		if game_state.spend_gold(cost) and tower.apply_final_element(element_id):
			applied += 1
			spent += cost
		else:
			failed_afford += 1
	_emit_selection()
	return {"applied": applied, "failed_afford": failed_afford, "spent": spent}


func clear_selection() -> void:
	_clear_placed_selection()


func selection_count() -> int:
	_prune_selection()
	return selected_towers.size()


func selection_sell_total() -> int:
	_prune_selection()
	var total := 0
	for tower in selected_towers:
		total += TowerData.sell_value_for_tower(tower)
	return total


func selection_upgrade_totals() -> Dictionary:
	_prune_selection()
	var upgrade_cost := 0
	var final_cost := 0
	var can_stat := false
	var can_final := false
	for tower in selected_towers:
		if not is_instance_valid(tower):
			continue
		if tower.can_stat_upgrade():
			can_stat = true
			upgrade_cost += tower.next_stat_upgrade_cost()
		if tower.can_final_upgrade():
			can_final = true
			final_cost += tower.final_upgrade_cost()
	return {
		"can_stat": can_stat,
		"upgrade_cost": upgrade_cost,
		"can_final": can_final,
		"final_cost": final_cost,
	}


func _select_only(tower: Tower) -> void:
	_clear_placed_selection(false)
	if tower and is_instance_valid(tower):
		selected_towers.append(tower)
		tower.set_selected(true)
	_emit_selection()


func _toggle_selected(tower: Tower) -> void:
	if tower == null or not is_instance_valid(tower):
		return
	if tower in selected_towers:
		_remove_from_selection(tower)
	else:
		selected_towers.append(tower)
		tower.set_selected(true)
	_emit_selection()


func _remove_from_selection(tower: Tower) -> void:
	var idx := selected_towers.find(tower)
	if idx >= 0:
		selected_towers.remove_at(idx)
	if is_instance_valid(tower):
		tower.set_selected(false)


func _clear_placed_selection(emit_change: bool = true) -> void:
	for tower in selected_towers:
		if is_instance_valid(tower):
			tower.set_selected(false)
	selected_towers.clear()
	if emit_change:
		_emit_selection()


func _prune_selection() -> void:
	var kept: Array[Tower] = []
	for tower in selected_towers:
		if is_instance_valid(tower):
			kept.append(tower)
	selected_towers = kept


func _emit_selection() -> void:
	selected_towers_changed.emit(selection_count(), selection_sell_total())
	var totals := selection_upgrade_totals()
	selection_upgrade_changed.emit(
		bool(totals["can_stat"]),
		int(totals["upgrade_cost"]),
		bool(totals["can_final"]),
		int(totals["final_cost"])
	)


func _refresh_path_preview() -> void:
	grid.set_path_preview(pathfinder.get_world_path())


func refresh_after_reset() -> void:
	selected_towers.clear()
	pathfinder.rebuild()
	_refresh_path_preview()
	_emit_selection()
