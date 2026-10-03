class_name Pathfinder
extends RefCounted

var grid: GameGrid
var astar: AStarGrid2D


func _init(game_grid: GameGrid) -> void:
	grid = game_grid
	astar = AStarGrid2D.new()
	astar.region = Rect2i(0, 0, GameGrid.COLS, GameGrid.ROWS)
	astar.cell_size = Vector2(GameGrid.TILE_SIZE, GameGrid.TILE_SIZE)
	astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_MANHATTAN
	astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_MANHATTAN
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	astar.update()
	rebuild()


func rebuild() -> void:
	for y in GameGrid.ROWS:
		for x in GameGrid.COLS:
			var cell := Vector2i(x, y)
			astar.set_point_solid(cell, grid.is_blocked_for_path(cell))
	# Spawn and exit must remain walkable even if somehow marked.
	astar.set_point_solid(grid.spawn_cell, false)
	astar.set_point_solid(grid.exit_cell, false)


func has_path(extra_block: Vector2i = Vector2i(-1, -1)) -> bool:
	var blocked := false
	if extra_block != Vector2i(-1, -1) and grid.in_bounds(extra_block):
		blocked = not astar.is_point_solid(extra_block)
		if blocked:
			astar.set_point_solid(extra_block, true)
	var path := astar.get_id_path(grid.spawn_cell, grid.exit_cell)
	if blocked:
		astar.set_point_solid(extra_block, false)
	return path.size() > 0


func get_cell_path() -> Array[Vector2i]:
	var ids := astar.get_id_path(grid.spawn_cell, grid.exit_cell)
	var result: Array[Vector2i] = []
	for id in ids:
		result.append(id)
	return result


func get_world_path() -> PackedVector2Array:
	var cells := get_cell_path()
	var points := PackedVector2Array()
	for cell in cells:
		points.append(grid.cell_to_world_center(cell))
	return points


func would_block_path(cell: Vector2i) -> bool:
	if not grid.is_buildable(cell):
		return true
	return not has_path(cell)
