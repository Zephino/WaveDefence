class_name GameGrid
extends Node2D

const COLS := 22
const ROWS := 15
const TILE_SIZE := 40
const SIEGE_COLS := 32
const SIEGE_ROWS := 32
## Clash: buildable columns per lane (top→bottom path). Matches 7×15 maze sheets.
const CLASH_LANE_COLS := 7
const CLASH_ROWS := 15
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
var hover_footprint: int = 1
var path_preview: PackedVector2Array = PackedVector2Array()
var is_random_layout: bool = false
var is_siege_layout: bool = false
var is_clash_layout: bool = false
## Clash lane spawns / exits / column ranges (inclusive left..right).
var lane_spawns: Array = [] ## Array[Vector2i]
var lane_exits: Array = [] ## Array[Vector2i]
var lane_col_ranges: Array = [] ## Array[Vector2i] as (x0, x1)
## Seed actually used for the last generated random/siege layout (-1 if classic corridor).
var last_layout_seed: int = -1


func tile_px() -> int:
	return GameLayout.tile_size()


func _ready() -> void:
	_init_classic_tiles()
	queue_redraw()


func _clear_tower_nodes() -> void:
	var seen: Dictionary = {}
	for cell in towers.keys():
		var tower: Node = towers[cell]
		if is_instance_valid(tower) and not seen.has(tower):
			seen[tower] = true
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
	is_clash_layout = false
	lane_spawns.clear()
	lane_exits.clear()
	lane_col_ranges.clear()
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


func reset_clash(lane_count: int) -> void:
	_clear_tower_nodes()
	path_preview.clear()
	generate_clash_layout(lane_count)
	queue_redraw()


## Side-by-side vertical lanes: spawn top → exit bottom, wall dividers between.
func generate_clash_layout(lane_count: int) -> void:
	var n := clampi(lane_count, WaveScaler.CLASH_MIN_PLAYERS, WaveScaler.CLASH_MAX_PLAYERS)
	rows = CLASH_ROWS
	cols = n * CLASH_LANE_COLS + (n - 1)
	is_random_layout = false
	is_siege_layout = false
	is_clash_layout = true
	last_layout_seed = -1
	lane_spawns.clear()
	lane_exits.clear()
	lane_col_ranges.clear()
	_blank_buildable_grid()

	var x_cursor := 0
	for lane in n:
		var x0 := x_cursor
		var x1 := x_cursor + CLASH_LANE_COLS - 1
		lane_col_ranges.append(Vector2i(x0, x1))
		var mid_x := x0 + CLASH_LANE_COLS / 2
		var spawn := Vector2i(mid_x, 0)
		var exit_c := Vector2i(mid_x, rows - 1)
		lane_spawns.append(spawn)
		lane_exits.append(exit_c)
		tiles[spawn.y][spawn.x] = Tile.SPAWN
		tiles[exit_c.y][exit_c.x] = Tile.EXIT
		x_cursor = x1 + 1
		if lane < n - 1:
			for y in rows:
				tiles[y][x_cursor] = Tile.BLOCKED
			x_cursor += 1

	# Human lane is primary for classic path preview helpers.
	spawn_cell = lane_spawns[0] as Vector2i
	exit_cell = lane_exits[0] as Vector2i
	queue_redraw()


func clash_lane_count() -> int:
	return lane_spawns.size()


func lane_index_for_cell(cell: Vector2i) -> int:
	if not is_clash_layout:
		return -1
	for i in lane_col_ranges.size():
		var r: Vector2i = lane_col_ranges[i]
		if cell.x >= r.x and cell.x <= r.y:
			return i
	return -1


func lane_index_for_global(global_pos: Vector2) -> int:
	if not is_clash_layout:
		return -1
	return lane_index_for_cell(world_to_cell(to_local(global_pos)))


func is_clash_spawn_or_exit(cell: Vector2i) -> bool:
	if not is_clash_layout:
		return cell == spawn_cell or cell == exit_cell
	for s in lane_spawns:
		if cell == s:
			return true
	for e in lane_exits:
		if cell == e:
			return true
	return false


func get_lane_spawn(lane: int) -> Vector2i:
	if lane < 0 or lane >= lane_spawns.size():
		return spawn_cell
	return lane_spawns[lane] as Vector2i


func get_lane_exit(lane: int) -> Vector2i:
	if lane < 0 or lane >= lane_exits.size():
		return exit_cell
	return lane_exits[lane] as Vector2i


## Air path for a Clash lane (top→bottom weave within lane bounds).
func build_lane_air_s_path(lane: int, phase_offset: float = 0.0, segments: int = 16) -> PackedVector2Array:
	if not is_clash_layout or lane < 0 or lane >= lane_spawns.size():
		return build_air_s_path(phase_offset, segments)
	var ts := float(tile_px())
	var start := cell_to_world_center(get_lane_spawn(lane))
	var end := cell_to_world_center(get_lane_exit(lane))
	var r: Vector2i = lane_col_ranges[lane]
	var min_x := (float(r.x) + 0.5) * ts
	var max_x := (float(r.y) + 0.5) * ts
	var min_y := ts * 0.5
	var max_y := (float(rows) - 0.5) * ts
	var path := PackedVector2Array()
	path.append(start)
	var delta := end - start
	var amp := minf(float(CLASH_LANE_COLS) * 0.35, 2.5) * ts
	var steps := maxi(segments, 4)
	var perp := Vector2(-delta.y, delta.x).normalized()
	for i in range(1, steps):
		var t := float(i) / float(steps)
		var base := start.lerp(end, t)
		var offset := perp * (amp * sin(TAU * t + phase_offset))
		var p := base + offset
		path.append(Vector2(clampf(p.x, min_x, max_x), clampf(p.y, min_y, max_y)))
	path.append(end)
	return path


## Random spawn/exit on opposite short edges + scattered permanent blocked cells.
## Guarantees a spawn→exit path exists.
func generate_random_layout(seed_value: int = -1) -> bool:
	cols = COLS
	rows = ROWS
	is_siege_layout = false
	is_clash_layout = false
	lane_spawns.clear()
	lane_exits.clear()
	lane_col_ranges.clear()
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
	is_clash_layout = false
	lane_spawns.clear()
	lane_exits.clear()
	lane_col_ranges.clear()
	var used_seed := seed_value if seed_value >= 0 else WaveScaler.roll_seed()
	last_layout_seed = used_seed
	var rng := RandomNumberGenerator.new()
	rng.seed = used_seed

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
	last_layout_seed = used_seed
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


func _set_exit_cell(cell: Vector2i) -> void:
	if in_bounds(exit_cell) and get_tile(exit_cell) == Tile.EXIT:
		tiles[exit_cell.y][exit_cell.x] = Tile.BUILDABLE
	exit_cell = cell
	tiles[exit_cell.y][exit_cell.x] = Tile.EXIT


## Current spawn/exit for classic maps, or a Clash lane portal when `lane` is set.
func portal_cell(which: String, lane: int = -1) -> Vector2i:
	var is_spawn := which == "spawn"
	if is_clash_layout and lane >= 0 and lane < lane_spawns.size():
		return (lane_spawns[lane] if is_spawn else lane_exits[lane]) as Vector2i
	return spawn_cell if is_spawn else exit_cell


func _apply_portal_cell(which: String, cell: Vector2i, lane: int = -1) -> void:
	var is_spawn := which == "spawn"
	if is_clash_layout and lane >= 0 and lane < lane_spawns.size():
		var old: Vector2i = (lane_spawns[lane] if is_spawn else lane_exits[lane]) as Vector2i
		if is_spawn:
			if in_bounds(old) and get_tile(old) == Tile.SPAWN:
				tiles[old.y][old.x] = Tile.BUILDABLE
			lane_spawns[lane] = cell
			tiles[cell.y][cell.x] = Tile.SPAWN
			if lane == 0:
				spawn_cell = cell
		else:
			if in_bounds(old) and get_tile(old) == Tile.EXIT:
				tiles[old.y][old.x] = Tile.BUILDABLE
			lane_exits[lane] = cell
			tiles[cell.y][cell.x] = Tile.EXIT
			if lane == 0:
				exit_cell = cell
		return
	if is_spawn:
		_set_spawn_cell(cell)
	else:
		_set_exit_cell(cell)


## True if sliding `which` (`spawn`/`exit`) by `dx` (±1) on the same row would keep a path.
func can_slide_portal(which: String, dx: int, pathfinder: Pathfinder, lane: int = -1) -> bool:
	return _slide_portal(which, dx, pathfinder, lane, true)


## Commit a one-cell left/right portal slide on the same row. Returns false if illegal.
func try_slide_portal(which: String, dx: int, pathfinder: Pathfinder, lane: int = -1) -> bool:
	return _slide_portal(which, dx, pathfinder, lane, false)


func _slide_portal(
	which: String, dx: int, pathfinder: Pathfinder, lane: int, dry_run: bool
) -> bool:
	if which != "spawn" and which != "exit":
		return false
	if dx != -1 and dx != 1:
		return false
	if pathfinder == null:
		return false
	var current := portal_cell(which, lane)
	var other_which := "exit" if which == "spawn" else "spawn"
	var other := portal_cell(other_which, lane)
	var target := Vector2i(current.x + dx, current.y)
	if not in_bounds(target):
		return false
	if is_clash_layout and lane >= 0 and lane < lane_col_ranges.size():
		var r: Vector2i = lane_col_ranges[lane]
		if target.x < r.x or target.x > r.y:
			return false
	if target == other:
		return false
	if towers.has(target):
		return false
	if get_tile(target) == Tile.BLOCKED:
		return false
	# Don't land on a foreign Clash portal.
	if is_clash_layout and is_clash_spawn_or_exit(target) and target != current:
		return false

	_apply_portal_cell(which, target, lane)
	pathfinder.sync_region()
	pathfinder.rebuild()
	var ok := false
	if is_clash_layout and lane >= 0:
		ok = pathfinder.has_path_between(get_lane_spawn(lane), get_lane_exit(lane))
	else:
		ok = pathfinder.has_path()
	if not ok or dry_run:
		_apply_portal_cell(which, current, lane)
		pathfinder.sync_region()
		pathfinder.rebuild()
		if not ok:
			queue_redraw()
			return false
		return true
	queue_redraw()
	return true


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


## True when a world-space segment crosses any BLOCKED tile (Clash lane dividers).
func segment_hits_blocked(from_global: Vector2, to_global: Vector2) -> bool:
	var a := to_local(from_global)
	var b := to_local(to_global)
	var dist := a.distance_to(b)
	var step_px := maxf(float(tile_px()) * 0.25, 2.0)
	var steps := maxi(1, int(ceil(dist / step_px)))
	for i in range(steps + 1):
		var t := float(i) / float(steps)
		var p := a.lerp(b, t)
		if get_tile(world_to_cell(p)) == Tile.BLOCKED:
			return true
	return false


func is_buildable(cell: Vector2i) -> bool:
	if not in_bounds(cell):
		return false
	if is_clash_spawn_or_exit(cell):
		return false
	if towers.has(cell):
		return false
	return get_tile(cell) == Tile.BUILDABLE


func is_blocked_for_path(cell: Vector2i) -> bool:
	if not in_bounds(cell):
		return true
	if get_tile(cell) == Tile.BLOCKED:
		return true
	if not towers.has(cell):
		return false
	var node: Node = towers[cell]
	# Vortex-style lockdown: only the center blocks path; the 8 ring tiles stay walkable.
	if node is Tower and TowerData.path_blocks_center_only((node as Tower).tower_id):
		var anchor: Vector2i = node.get_meta("anchor_cell", world_to_cell(node.position))
		return cell == anchor
	return true


func is_map_corner_cell(cell: Vector2i) -> bool:
	return (cell.x == 0 or cell.x == cols - 1) and (cell.y == 0 or cell.y == rows - 1)


## True when any cell of a centered footprint sits on a map corner.
func footprint_touches_map_corner(center: Vector2i, size: int) -> bool:
	for c in TowerData.footprint_cells(center, size):
		if is_map_corner_cell(c):
			return true
	return false


func footprint_in_bounds(center: Vector2i, size: int) -> bool:
	for c in TowerData.footprint_cells(center, size):
		if not in_bounds(c):
			return false
	return true


func is_footprint_buildable(center: Vector2i, size: int) -> bool:
	for c in TowerData.footprint_cells(center, size):
		if not is_buildable(c):
			return false
	return true


func place_tower(cell: Vector2i, tower: Node) -> void:
	var footprint := 1
	if tower is Tower:
		footprint = TowerData.footprint_size((tower as Tower).tower_id)
	for c in TowerData.footprint_cells(cell, footprint):
		towers[c] = tower
	tower.position = cell_to_world_center(cell)
	if tower is Tower:
		(tower as Tower).lane_id = lane_index_for_cell(cell)
		tower.set_meta("anchor_cell", cell)
	add_child(tower)
	tower_placed.emit(cell, tower)
	_refresh_wall_autotiles_around(cell, footprint)
	queue_redraw()


func remove_tower_at(cell: Vector2i, notify: bool = true) -> Node:
	if not towers.has(cell):
		return null
	var tower: Node = towers[cell]
	var to_clear: Array[Vector2i] = []
	for c in towers.keys():
		if towers[c] == tower:
			to_clear.append(c)
	for c in to_clear:
		towers.erase(c)
	if notify:
		tower_removed.emit(cell)
	for c in to_clear:
		_refresh_wall_autotiles_around(c, 1)
	queue_redraw()
	return tower


## Update 16-tile fortress bitmasks for walls near a changed cell.
func _refresh_wall_autotiles_around(cell: Vector2i, footprint: int = 1) -> void:
	var seen: Dictionary = {}
	var dirs: Array[Vector2i] = [
		Vector2i.ZERO, Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)
	]
	for c in TowerData.footprint_cells(cell, maxi(footprint, 1)):
		for d in dirs:
			var n: Vector2i = c + d
			if seen.has(n):
				continue
			seen[n] = true
			var t := get_tower_at(n) as Tower
			if t != null and is_instance_valid(t) and TowerData.is_wall(t.tower_id):
				t.refresh_wall_mask(self)


func get_tower_at(cell: Vector2i) -> Node:
	return towers.get(cell, null)


func set_hover(cell: Vector2i, valid: bool, visible: bool, footprint: int = 1) -> void:
	hover_cell = cell
	hover_valid = valid
	show_hover = visible
	hover_footprint = maxi(footprint, 1)
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
			var tile := get_tile(cell)
			if tile == Tile.SPAWN:
				color = Color(0.2, 0.45, 0.25)
			elif tile == Tile.EXIT:
				color = Color(0.45, 0.2, 0.2)
			elif tile == Tile.BLOCKED:
				color = Color(0.12, 0.11, 0.1)
			elif towers.has(cell):
				color = Color(0.16, 0.18, 0.22)
			draw_rect(rect, color)
			if get_tile(cell) == Tile.BLOCKED:
				draw_rect(rect.grow(-maxf(4.0, float(ts) * 0.2)), Color(0.28, 0.24, 0.2))
			draw_rect(rect, Color(0.1, 0.12, 0.16), false, 1.0)
			if UserSettings.is_show_grid_coordinates() and ts >= 14.0:
				var label := "%d,%d" % [x, y]
				draw_string(
					ThemeDB.fallback_font,
					Vector2(x * ts + 2.0, y * ts + ts * 0.45),
					label,
					HORIZONTAL_ALIGNMENT_LEFT,
					-1,
					maxi(8, int(ts * 0.22)),
					Color(0.55, 0.6, 0.68, 0.85)
				)

	if path_preview.size() >= 2:
		draw_polyline(path_preview, Color(0.3, 0.85, 0.5, 0.55), 3.0, true)

	if show_hover and in_bounds(hover_cell):
		var hcolor := Color(0.3, 0.9, 0.4, 0.35) if hover_valid else Color(0.95, 0.25, 0.25, 0.4)
		for c in TowerData.footprint_cells(hover_cell, hover_footprint):
			if not in_bounds(c):
				continue
			var hrect := Rect2(c.x * ts, c.y * ts, ts, ts)
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
