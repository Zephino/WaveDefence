class_name GameGrid
extends Node2D

const COLS := 22
const ROWS := 15
const TILE_SIZE := 40
## Share of buildable cells turned into permanent rocks on random maps.
const RANDOM_BLOCK_RATIO := 0.14
const RANDOM_GEN_ATTEMPTS := 40

enum Tile { BUILDABLE, BLOCKED, SPAWN, EXIT }

signal tower_placed(cell: Vector2i, tower: Node)
signal tower_removed(cell: Vector2i)

var tiles: Array = []
var towers: Dictionary = {} # Vector2i -> Tower
var spawn_cell: Vector2i = Vector2i(0, ROWS / 2)
var exit_cell: Vector2i = Vector2i(COLS - 1, ROWS / 2)
var hover_cell: Vector2i = Vector2i(-1, -1)
var hover_valid: bool = false
var show_hover: bool = false
var aim_preview_cells: Array[Vector2i] = []
var aim_preview_valid: bool = false
var show_aim_preview: bool = false
var path_trap_overlay: Array = []
var path_preview: PackedVector2Array = PackedVector2Array()
var is_random_layout: bool = false


func _ready() -> void:
	_init_classic_tiles()
	queue_redraw()


func _clear_tower_nodes() -> void:
	for cell in towers.keys():
		var tower: Node = towers[cell]
		if is_instance_valid(tower):
			tower.queue_free()
	towers.clear()


func _blank_buildable_grid() -> void:
	tiles.clear()
	for y in ROWS:
		var row: Array = []
		for x in COLS:
			row.append(Tile.BUILDABLE)
		tiles.append(row)


func _init_classic_tiles() -> void:
	_blank_buildable_grid()
	spawn_cell = Vector2i(0, ROWS / 2)
	exit_cell = Vector2i(COLS - 1, ROWS / 2)
	tiles[spawn_cell.y][spawn_cell.x] = Tile.SPAWN
	tiles[exit_cell.y][exit_cell.x] = Tile.EXIT
	is_random_layout = false


func reset(classic: bool = true, seed_value: int = -1) -> void:
	_clear_tower_nodes()
	path_preview.clear()
	if classic:
		_init_classic_tiles()
	else:
		generate_random_layout(seed_value)
	queue_redraw()


## Random spawn/exit on opposite short edges + scattered permanent blocked cells.
## Guarantees a spawn→exit path exists.
func generate_random_layout(seed_value: int = -1) -> bool:
	var rng := RandomNumberGenerator.new()
	if seed_value >= 0:
		rng.seed = seed_value
	else:
		rng.randomize()

	for _attempt in RANDOM_GEN_ATTEMPTS:
		_blank_buildable_grid()
		_pick_random_spawn_exit(rng)
		_scatter_blocked_cells(rng)
		tiles[spawn_cell.y][spawn_cell.x] = Tile.SPAWN
		tiles[exit_cell.y][exit_cell.x] = Tile.EXIT
		if _layout_has_path():
			is_random_layout = true
			queue_redraw()
			return true

	# Fallback: open classic corridor if RNG fails repeatedly.
	_init_classic_tiles()
	is_random_layout = true
	queue_redraw()
	return false


func _pick_random_spawn_exit(rng: RandomNumberGenerator) -> void:
	var flip := rng.randf() < 0.5
	var spawn_y := rng.randi_range(1, ROWS - 2)
	var exit_y := rng.randi_range(1, ROWS - 2)
	if flip:
		spawn_cell = Vector2i(COLS - 1, spawn_y)
		exit_cell = Vector2i(0, exit_y)
	else:
		spawn_cell = Vector2i(0, spawn_y)
		exit_cell = Vector2i(COLS - 1, exit_y)


func _scatter_blocked_cells(rng: RandomNumberGenerator) -> void:
	var total := COLS * ROWS - 2
	var target := int(round(float(total) * RANDOM_BLOCK_RATIO))
	target = clampi(target, 8, total / 3)
	var placed := 0
	var guard := 0
	while placed < target and guard < total * 8:
		guard += 1
		var cell := Vector2i(rng.randi_range(0, COLS - 1), rng.randi_range(0, ROWS - 1))
		if cell == spawn_cell or cell == exit_cell:
			continue
		if tiles[cell.y][cell.x] == Tile.BLOCKED:
			continue
		# Keep a clear column band near spawn/exit so the path isn't sealed.
		if abs(cell.x - spawn_cell.x) <= 1 or abs(cell.x - exit_cell.x) <= 1:
			if rng.randf() < 0.7:
				continue
		tiles[cell.y][cell.x] = Tile.BLOCKED
		placed += 1


func _layout_has_path() -> bool:
	var astar := AStarGrid2D.new()
	astar.region = Rect2i(0, 0, COLS, ROWS)
	astar.cell_size = Vector2(TILE_SIZE, TILE_SIZE)
	astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_MANHATTAN
	astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_MANHATTAN
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	astar.update()
	for y in ROWS:
		for x in COLS:
			var cell := Vector2i(x, y)
			astar.set_point_solid(cell, get_tile(cell) == Tile.BLOCKED)
	astar.set_point_solid(spawn_cell, false)
	astar.set_point_solid(exit_cell, false)
	return astar.get_id_path(spawn_cell, exit_cell).size() > 0


func in_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < COLS and cell.y < ROWS


func world_to_cell(world_pos: Vector2) -> Vector2i:
	return Vector2i(int(floor(world_pos.x / TILE_SIZE)), int(floor(world_pos.y / TILE_SIZE)))


func cell_to_world_center(cell: Vector2i) -> Vector2:
	return Vector2((cell.x + 0.5) * TILE_SIZE, (cell.y + 0.5) * TILE_SIZE)


func get_tile(cell: Vector2i) -> int:
	if not in_bounds(cell):
		return Tile.BLOCKED
	return tiles[cell.y][cell.x]


func is_terrain_blocked(cell: Vector2i) -> bool:
	return get_tile(cell) == Tile.BLOCKED


func is_buildable(cell: Vector2i) -> bool:
	if not in_bounds(cell):
		return false
	if cell == spawn_cell or cell == exit_cell:
		return false
	if towers.has(cell):
		return false
	return get_tile(cell) == Tile.BUILDABLE


func is_blocked_for_path(cell: Vector2i) -> bool:
	if not in_bounds(cell):
		return true
	if get_tile(cell) == Tile.BLOCKED:
		return true
	if towers.has(cell):
		return true
	return false


func place_tower(cell: Vector2i, tower: Node) -> void:
	towers[cell] = tower
	tower.position = cell_to_world_center(cell)
	add_child(tower)
	tower_placed.emit(cell, tower)
	queue_redraw()


func remove_tower_at(cell: Vector2i, notify: bool = true) -> Node:
	if not towers.has(cell):
		return null
	var tower: Node = towers[cell]
	towers.erase(cell)
	if notify:
		tower_removed.emit(cell)
	queue_redraw()
	return tower


func get_tower_at(cell: Vector2i) -> Node:
	return towers.get(cell, null)


func set_hover(cell: Vector2i, valid: bool, visible: bool) -> void:
	hover_cell = cell
	hover_valid = valid
	show_hover = visible
	queue_redraw()


func set_ability_aim_preview(cells: Array, valid: bool, visible: bool) -> void:
	aim_preview_cells.clear()
	for c in cells:
		if c is Vector2i:
			aim_preview_cells.append(c)
	aim_preview_valid = valid
	show_aim_preview = visible
	queue_redraw()


func clear_ability_aim_preview() -> void:
	show_aim_preview = false
	aim_preview_cells.clear()
	queue_redraw()


func set_path_trap_overlay(traps: Array) -> void:
	path_trap_overlay = traps
	queue_redraw()


func set_path_preview(points: PackedVector2Array) -> void:
	path_preview = points
	queue_redraw()


func _draw() -> void:
	for y in ROWS:
		for x in COLS:
			var cell := Vector2i(x, y)
			var rect := Rect2(x * TILE_SIZE, y * TILE_SIZE, TILE_SIZE, TILE_SIZE)
			var color := Color(0.18, 0.22, 0.28)
			if cell == spawn_cell:
				color = Color(0.2, 0.45, 0.25)
			elif cell == exit_cell:
				color = Color(0.45, 0.2, 0.2)
			elif get_tile(cell) == Tile.BLOCKED:
				color = Color(0.12, 0.11, 0.1)
			elif towers.has(cell):
				color = Color(0.16, 0.18, 0.22)
			draw_rect(rect, color)
			if get_tile(cell) == Tile.BLOCKED:
				draw_rect(rect.grow(-8), Color(0.28, 0.24, 0.2))
			draw_rect(rect, Color(0.1, 0.12, 0.16), false, 1.0)

	if path_preview.size() >= 2:
		draw_polyline(path_preview, Color(0.3, 0.85, 0.5, 0.55), 3.0, true)

	if show_hover and in_bounds(hover_cell) and not show_aim_preview:
		var hrect := Rect2(hover_cell.x * TILE_SIZE, hover_cell.y * TILE_SIZE, TILE_SIZE, TILE_SIZE)
		var hcolor := Color(0.3, 0.9, 0.4, 0.35) if hover_valid else Color(0.95, 0.25, 0.25, 0.4)
		draw_rect(hrect, hcolor)

	for trap in path_trap_overlay:
		if typeof(trap) != TYPE_DICTIONARY:
			continue
		var ability_id := str(trap.get("ability_id", ""))
		var cells: Array = trap.get("cells", [])
		var tint := Color(0.85, 0.35, 0.25, 0.32)
		match ability_id:
			"barricade":
				tint = Color(0.75, 0.45, 0.3, 0.38)
			"flare":
				tint = Color(0.95, 0.75, 0.25, 0.34)
			"airstrike":
				tint = Color(0.9, 0.3, 0.22, 0.34)
		for c_raw in cells:
			if c_raw is not Vector2i:
				continue
			var c: Vector2i = c_raw
			if not in_bounds(c):
				continue
			var trect := Rect2(c.x * TILE_SIZE, c.y * TILE_SIZE, TILE_SIZE, TILE_SIZE)
			draw_rect(trect, tint)
			draw_rect(trect, tint.lightened(0.35), false, 1.5)

	if show_aim_preview:
		var acolor := Color(0.35, 0.95, 0.55, 0.42) if aim_preview_valid else Color(0.95, 0.3, 0.25, 0.45)
		for c in aim_preview_cells:
			if not in_bounds(c):
				continue
			var arect := Rect2(c.x * TILE_SIZE, c.y * TILE_SIZE, TILE_SIZE, TILE_SIZE)
			draw_rect(arect, acolor)
			draw_rect(arect, acolor.lightened(0.25), false, 2.0)

	var map_w := COLS * TILE_SIZE
	var map_h := ROWS * TILE_SIZE
	draw_rect(Rect2(0, 0, map_w, map_h), Color(0.35, 0.4, 0.5), false, 2.0)


func map_pixel_size() -> Vector2:
	return Vector2(COLS * TILE_SIZE, ROWS * TILE_SIZE)


## Curved air lane from spawn → exit (S / sine weave over the maze).
## phase_offset shifts the curve so stacked flyers don't share one line.
func build_air_s_path(phase_offset: float = 0.0, segments: int = 16) -> PackedVector2Array:
	var start := cell_to_world_center(spawn_cell)
	var end := cell_to_world_center(exit_cell)
	var path := PackedVector2Array()
	path.append(start)
	var mid_y := (start.y + end.y) * 0.5
	# Amplitude keeps the S inside the board with a small margin.
	var amp := minf(float(ROWS) * 0.35, 5.5) * float(TILE_SIZE)
	var min_y := float(TILE_SIZE) * 0.5
	var max_y := (float(ROWS) - 0.5) * float(TILE_SIZE)
	var steps := maxi(segments, 4)
	for i in range(1, steps):
		var t := float(i) / float(steps)
		var x := lerpf(start.x, end.x, t)
		# One full sine cycle left→right reads as an S when traveling across.
		var y := mid_y + amp * sin(TAU * t + phase_offset)
		path.append(Vector2(x, clampf(y, min_y, max_y)))
	path.append(end)
	return path
