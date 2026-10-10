class_name GameGrid
extends Node2D

const COLS := 22
const ROWS := 15
const TILE_SIZE := 40
const SIEGE_COLS := 32
const SIEGE_ROWS := 32
## Share of buildable cells turned into permanent rocks on random maps.
const RANDOM_BLOCK_RATIO := 0.14
const RANDOM_GEN_ATTEMPTS := 40
const SIEGE_GEN_ATTEMPTS := 40

enum Tile { BUILDABLE, BLOCKED, SPAWN, EXIT }

signal tower_placed(cell: Vector2i, tower: Node)
signal tower_removed(cell: Vector2i)

var cols: int = COLS
var rows: int = ROWS
var tiles: Array = []
var towers: Dictionary = {} # Vector2i -> Tower
var spawn_cell: Vector2i = Vector2i(0, ROWS / 2)
var exit_cell: Vector2i = Vector2i(COLS - 1, ROWS / 2)
var hover_cell: Vector2i = Vector2i(-1, -1)
var hover_valid: bool = false
var show_hover: bool = false
var path_preview: PackedVector2Array = PackedVector2Array()
var is_random_layout: bool = false
var is_siege_layout: bool = false
## Seed actually used for the last generated random/siege layout (-1 if classic corridor).
var last_layout_seed: int = -1


func tile_px() -> int:
	return GameLayout.tile_size()


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
	for y in rows:
		var row: Array = []
		for x in cols:
			row.append(Tile.BUILDABLE)
		tiles.append(row)


func _init_classic_tiles() -> void:
	cols = COLS
	rows = ROWS
	_blank_buildable_grid()
	spawn_cell = Vector2i(0, rows / 2)
	exit_cell = Vector2i(cols - 1, rows / 2)
	tiles[spawn_cell.y][spawn_cell.x] = Tile.SPAWN
	tiles[exit_cell.y][exit_cell.x] = Tile.EXIT
	is_random_layout = false
	is_siege_layout = false
	last_layout_seed = -1


func reset(classic: bool = true, seed_value: int = -1) -> void:
	_clear_tower_nodes()
	path_preview.clear()
	if classic:
		_init_classic_tiles()
	else:
		generate_random_layout(seed_value)
	queue_redraw()


func reset_siege(seed_value: int = -1) -> void:
	_clear_tower_nodes()
	path_preview.clear()
	generate_siege_layout(seed_value)
	queue_redraw()


## Random spawn/exit on opposite short edges + scattered permanent blocked cells.
## Guarantees a spawn→exit path exists.
func generate_random_layout(seed_value: int = -1) -> bool:
	cols = COLS
	rows = ROWS
	is_siege_layout = false
	var used_seed := seed_value if seed_value >= 0 else WaveScaler.roll_seed()
	last_layout_seed = used_seed
	var rng := RandomNumberGenerator.new()
	rng.seed = used_seed

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
	last_layout_seed = used_seed
	queue_redraw()
	return false


## Center exit, outer-rim spawn, larger board. Guarantees a spawn→exit path.
func generate_siege_layout(seed_value: int = -1) -> bool:
	cols = SIEGE_COLS
	rows = SIEGE_ROWS
	is_random_layout = false
	var rng := RandomNumberGenerator.new()
	if seed_value >= 0:
		rng.seed = seed_value
	else:
		rng.randomize()

	for _attempt in SIEGE_GEN_ATTEMPTS:
		_blank_buildable_grid()
		exit_cell = Vector2i(cols / 2, rows / 2)
		spawn_cell = _random_rim_cell(rng, Vector2i(-1, -1))
		tiles[spawn_cell.y][spawn_cell.x] = Tile.SPAWN
		tiles[exit_cell.y][exit_cell.x] = Tile.EXIT
		if _layout_has_path():
			is_siege_layout = true
			queue_redraw()
			return true

	_blank_buildable_grid()
	exit_cell = Vector2i(cols / 2, rows / 2)
	spawn_cell = Vector2i(0, rows / 2)
	tiles[spawn_cell.y][spawn_cell.x] = Tile.SPAWN
	tiles[exit_cell.y][exit_cell.x] = Tile.EXIT
	is_siege_layout = true
	queue_redraw()
	return false


## Move SPAWN to a new rim cell; keep towers/rocks/exit. Returns false if none valid.
func relocate_rim_spawn(pathfinder: Pathfinder, exclude: Vector2i = Vector2i(-999, -999)) -> bool:
	if not is_siege_layout:
		return false
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var old_spawn := spawn_cell
	if exclude == Vector2i(-999, -999):
		exclude = old_spawn
	var candidates := _rim_cells()
	candidates.shuffle()
	for cell in candidates:
		if cell == exclude or cell == exit_cell:
			continue
		if towers.has(cell) or get_tile(cell) == Tile.BLOCKED:
			continue
		_set_spawn_cell(cell)
		pathfinder.sync_region()
		pathfinder.rebuild()
		if pathfinder.has_path():
			queue_redraw()
			return true
	_set_spawn_cell(old_spawn)
	pathfinder.sync_region()
	pathfinder.rebuild()
	queue_redraw()
	return false


func _set_spawn_cell(cell: Vector2i) -> void:
	if in_bounds(spawn_cell) and get_tile(spawn_cell) == Tile.SPAWN:
		tiles[spawn_cell.y][spawn_cell.x] = Tile.BUILDABLE
	spawn_cell = cell
	tiles[spawn_cell.y][spawn_cell.x] = Tile.SPAWN


func _rim_cells() -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for x in cols:
		cells.append(Vector2i(x, 0))
		cells.append(Vector2i(x, rows - 1))
	for y in range(1, rows - 1):
		cells.append(Vector2i(0, y))
		cells.append(Vector2i(cols - 1, y))
	return cells


func _random_rim_cell(rng: RandomNumberGenerator, exclude: Vector2i) -> Vector2i:
	var cells := _rim_cells()
	if cells.is_empty():
		return Vector2i(0, rows / 2)
	for _try in 64:
		var cell: Vector2i = cells[rng.randi_range(0, cells.size() - 1)]
		if cell != exclude and cell != exit_cell:
			return cell
	return cells[0]


func _pick_random_spawn_exit(rng: RandomNumberGenerator) -> void:
	var flip := rng.randf() < 0.5
	var spawn_y := rng.randi_range(1, rows - 2)
	var exit_y := rng.randi_range(1, rows - 2)
	if flip:
		spawn_cell = Vector2i(cols - 1, spawn_y)
		exit_cell = Vector2i(0, exit_y)
	else:
		spawn_cell = Vector2i(0, spawn_y)
		exit_cell = Vector2i(cols - 1, exit_y)


func _scatter_blocked_cells(rng: RandomNumberGenerator) -> void:
	var total := cols * rows - 2
	var target := int(round(float(total) * RANDOM_BLOCK_RATIO))
	target = clampi(target, 8, total / 3)
	var placed := 0
	var guard := 0
	while placed < target and guard < total * 8:
		guard += 1
		var cell := Vector2i(rng.randi_range(0, cols - 1), rng.randi_range(0, rows - 1))
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
	var ts := tile_px()
	var astar := AStarGrid2D.new()
	astar.region = Rect2i(0, 0, cols, rows)
	astar.cell_size = Vector2(ts, ts)
	astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_MANHATTAN
	astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_MANHATTAN
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	astar.update()
	for y in rows:
		for x in cols:
			var cell := Vector2i(x, y)
			astar.set_point_solid(cell, get_tile(cell) == Tile.BLOCKED)
	astar.set_point_solid(spawn_cell, false)
	astar.set_point_solid(exit_cell, false)
	return astar.get_id_path(spawn_cell, exit_cell).size() > 0


func in_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < cols and cell.y < rows


func world_to_cell(world_pos: Vector2) -> Vector2i:
	var ts := float(tile_px())
	return Vector2i(int(floor(world_pos.x / ts)), int(floor(world_pos.y / ts)))


func cell_to_world_center(cell: Vector2i) -> Vector2:
	var ts := float(tile_px())
	return Vector2((cell.x + 0.5) * ts, (cell.y + 0.5) * ts)


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


func set_path_preview(points: PackedVector2Array) -> void:
	path_preview = points
	queue_redraw()


func _draw() -> void:
	var ts := tile_px()
	for y in rows:
		for x in cols:
			var cell := Vector2i(x, y)
			var rect := Rect2(x * ts, y * ts, ts, ts)
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
				draw_rect(rect.grow(-maxf(4.0, float(ts) * 0.2)), Color(0.28, 0.24, 0.2))
			draw_rect(rect, Color(0.1, 0.12, 0.16), false, 1.0)

	if path_preview.size() >= 2:
		draw_polyline(path_preview, Color(0.3, 0.85, 0.5, 0.55), 3.0, true)

	if show_hover and in_bounds(hover_cell):
		var hrect := Rect2(hover_cell.x * ts, hover_cell.y * ts, ts, ts)
		var hcolor := Color(0.3, 0.9, 0.4, 0.35) if hover_valid else Color(0.95, 0.25, 0.25, 0.4)
		draw_rect(hrect, hcolor)

	var map_w := cols * ts
	var map_h := rows * ts
	draw_rect(Rect2(0, 0, map_w, map_h), Color(0.35, 0.4, 0.5), false, 2.0)


func map_pixel_size() -> Vector2:
	var ts := tile_px()
	return Vector2(cols * ts, rows * ts)


## Curved air lane from spawn → exit (S / sine weave over the maze).
## phase_offset shifts the curve so stacked flyers don't share one line.
func build_air_s_path(phase_offset: float = 0.0, segments: int = 16) -> PackedVector2Array:
	var ts := float(tile_px())
	var start := cell_to_world_center(spawn_cell)
	var end := cell_to_world_center(exit_cell)
	var path := PackedVector2Array()
	path.append(start)
	var delta := end - start
	var amp := minf(float(mini(cols, rows)) * 0.25, 5.5) * ts
	var min_y := ts * 0.5
	var max_y := (float(rows) - 0.5) * ts
	var min_x := ts * 0.5
	var max_x := (float(cols) - 0.5) * ts
	var steps := maxi(segments, 4)
	# Prefer lateral weave relative to travel direction (works for rim→center).
	var perp := Vector2(-delta.y, delta.x).normalized()
	for i in range(1, steps):
		var t := float(i) / float(steps)
		var base := start.lerp(end, t)
		var offset := perp * (amp * sin(TAU * t + phase_offset))
		var p := base + offset
		path.append(Vector2(clampf(p.x, min_x, max_x), clampf(p.y, min_y, max_y)))
	path.append(end)
	return path
