class_name Enemy
extends Node2D

signal died(enemy: Enemy, bounty: int)
signal leaked(enemy: Enemy)
## Clash wrecker destroyed a defender tower/wall at this cell.
signal wrecked_at(cell: Vector2i)

var max_hp: float = 20.0
var hp: float = 20.0
var speed: float = 60.0
var bounty: int = 5
var is_boss: bool = false
var is_flying: bool = false
## Clash send: hunts and destroys defender towers/walls, then walks to exit.
var is_wrecker: bool = false
var _wreck_grid: GameGrid = null
var _wreck_pathfinder: Pathfinder = null
var _wreck_hunting: bool = false
## Wave this enemy belongs to (used so early-send leftovers don't inflate the new wave's kill % ).
var wave_index: int = 0
## Clash: defending player / lane (-1 = classic single board).
var defender_id: int = -1
var lane_id: int = -1
## Set during leaked if Clash overflowed this mob into the next lane.
var overflow_pending: bool = false
## Randomize-mode type id (empty in Classic monsters).
var monster_type: String = ""
## Element id → damage reduction 0..1 (burn / freeze / poison / lightning).
var element_resists: Dictionary = {}
var path: PackedVector2Array = PackedVector2Array()
var path_index: int = 0
var alive: bool = true

## Snake-boss chain: followers stay a fixed path-distance behind the previous segment.
var is_snake: bool = false
var snake_index: int = 0
var snake_prev: Enemy = null
var snake_spacing: float = 28.0
var path_dist: float = 0.0

var burn_time: float = 0.0
var burn_dps: float = 0.0
var poison_time: float = 0.0
var poison_dps: float = 0.0
var slow_time: float = 0.0
var slow_factor: float = 1.0
var mark_time: float = 0.0
var mark_damage_mult: float = 1.0

## Vortex aura: temporary circular detour around a tower.
var orbit_active: bool = false
var orbit_center: Vector2 = Vector2.ZERO
var orbit_radius: float = 48.0
var orbit_angle: float = 0.0
var orbit_laps: float = 1.0
var orbit_angle_traveled: float = 0.0
var orbit_immune_time: float = 0.0
var _orbit_immune_after: float = 1.5

var _radius: float = 10.0
var _base_color: Color = Color(0.85, 0.35, 0.35)


func setup(
	p_path: PackedVector2Array,
	p_hp: float,
	p_speed: float,
	p_bounty: int,
	p_boss: bool,
	p_flying: bool = false,
	p_wave_index: int = 0,
	p_monster_type: String = "",
	p_element_resists: Dictionary = {}
) -> void:
	path = p_path
	max_hp = p_hp
	hp = p_hp
	speed = p_speed
	bounty = p_bounty
	is_boss = p_boss
	is_flying = p_flying
	wave_index = p_wave_index
	monster_type = p_monster_type
	element_resists = p_element_resists.duplicate() if not p_element_resists.is_empty() else MonsterTypes.empty_resists()
	if is_flying:
		_radius = 15.0
		_base_color = Color(0.45, 0.7, 1.0)
	elif is_boss:
		_radius = 16.0
		_base_color = Color(0.75, 0.2, 0.55)
	else:
		_radius = 10.0
		_base_color = Color(0.85, 0.35, 0.35)
	if is_wrecker:
		_radius = 14.0
		_base_color = Color(0.95, 0.45, 0.12)
	if monster_type != "":
		_base_color = _base_color.lerp(MonsterTypes.tint_color(monster_type), 0.7)
	# Path points are grid-local (same space as this node's parent offset).
	if path.size() > 0:
		position = path[0]
		path_index = 1 if path.size() > 1 else 0
		path_dist = 0.0
	queue_redraw()


## Enable wrecker hunt (Clash send pack): smash lane structures, then exit.
func configure_wrecker(p_grid: GameGrid, p_pathfinder: Pathfinder = null) -> void:
	is_wrecker = true
	_wreck_grid = p_grid
	_wreck_pathfinder = p_pathfinder
	_wreck_hunting = true
	_radius = 14.0
	_base_color = Color(0.95, 0.45, 0.12)
	queue_redraw()
	refresh_wrecker_hunt()


## Re-aim at the nearest lane structure, or the exit when the lane is clear.
func refresh_wrecker_hunt() -> void:
	if not is_wrecker or not alive or _wreck_grid == null:
		return
	if _smash_adjacent_structures():
		# Pathfinder/towers changed; aim again next tick.
		return
	var target := _nearest_smashable_cell()
	if target.x < 0:
		_wreck_hunting = false
		_path_wrecker_to_exit()
		return
	_wreck_hunting = true
	if _is_adjacent_to_cell(target) or _wreck_grid.world_to_cell(position) == target:
		_smash_adjacent_structures()
		return
	var approach := _best_approach_cell(target)
	if approach.x < 0:
		_wreck_hunting = false
		_path_wrecker_to_exit()
		return
	_path_wrecker_to_cell(approach)


func _wrecker_tick() -> void:
	if _smash_adjacent_structures():
		refresh_wrecker_hunt()
		return
	if _wreck_hunting and (path.is_empty() or path_index >= path.size()):
		refresh_wrecker_hunt()
	elif not _wreck_hunting and (path.is_empty() or path_index >= path.size()):
		_path_wrecker_to_exit()


func _path_wrecker_to_exit() -> void:
	if _wreck_grid == null or _wreck_pathfinder == null or lane_id < 0:
		return
	_path_wrecker_to_cell(_wreck_grid.get_lane_exit(lane_id))


func _path_wrecker_to_cell(goal: Vector2i) -> void:
	if _wreck_grid == null or _wreck_pathfinder == null:
		return
	var from := _wreck_grid.world_to_cell(position)
	if from == goal:
		path = PackedVector2Array([_wreck_grid.cell_to_world_center(goal)])
		path_index = 0
		return
	_wreck_pathfinder.rebuild()
	var world := _wreck_pathfinder.get_world_path_between(from, goal)
	if world.size() < 2:
		# Stand next to goal if blocked; smash tick will clear.
		path = PackedVector2Array([
			position,
			_wreck_grid.cell_to_world_center(goal),
		])
		path_index = 1
		return
	path = world
	path_index = 1 if path.size() > 1 else 0


func _nearest_smashable_cell() -> Vector2i:
	if _wreck_grid == null or lane_id < 0:
		return Vector2i(-1, -1)
	var here := _wreck_grid.world_to_cell(position)
	var best := Vector2i(-1, -1)
	var best_d := 1 << 30
	var seen: Dictionary = {}
	for cell in _wreck_grid.towers.keys():
		if _wreck_grid.lane_index_for_cell(cell) != lane_id:
			continue
		var node: Node = _wreck_grid.towers[cell]
		if node == null or not is_instance_valid(node) or not (node is Tower):
			continue
		if seen.has(node):
			continue
		seen[node] = true
		var anchor: Vector2i = node.get_meta("anchor_cell", cell)
		if not _cell_is_smashable(anchor):
			continue
		var d := absi(anchor.x - here.x) + absi(anchor.y - here.y)
		if d < best_d:
			best_d = d
			best = anchor
	return best


func _best_approach_cell(target: Vector2i) -> Vector2i:
	if _wreck_grid == null or _wreck_pathfinder == null:
		return Vector2i(-1, -1)
	var here := _wreck_grid.world_to_cell(position)
	var best := Vector2i(-1, -1)
	var best_d := 1 << 30
	var dirs: Array[Vector2i] = [
		Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
	]
	for d in dirs:
		var adj: Vector2i = target + d
		if not _wreck_grid.in_bounds(adj):
			continue
		if _wreck_grid.get_tower_at(adj) != null:
			continue
		var tile := _wreck_grid.get_tile(adj)
		if tile == GameGrid.Tile.BLOCKED:
			continue
		_wreck_pathfinder.rebuild()
		var probe := _wreck_pathfinder.get_cell_path_between(here, adj)
		if probe.is_empty() and here != adj:
			continue
		var dist := probe.size() if not probe.is_empty() else 0
		if here == adj:
			dist = 0
		if dist < best_d:
			best_d = dist
			best = adj
	return best


func _is_adjacent_to_cell(cell: Vector2i) -> bool:
	if _wreck_grid == null:
		return false
	var here := _wreck_grid.world_to_cell(position)
	return maxi(absi(here.x - cell.x), absi(here.y - cell.y)) == 1 and (
		here.x == cell.x or here.y == cell.y
	)


func _cell_is_smashable(cell: Vector2i) -> bool:
	if _wreck_grid == null or not _wreck_grid.in_bounds(cell):
		return false
	var tile := _wreck_grid.get_tile(cell)
	if tile == GameGrid.Tile.SPAWN or tile == GameGrid.Tile.EXIT or tile == GameGrid.Tile.BLOCKED:
		return false
	var tower: Node = _wreck_grid.get_tower_at(cell)
	if tower == null or not (tower is Tower):
		return false
	var t := tower as Tower
	if lane_id >= 0 and t.lane_id >= 0 and t.lane_id != lane_id:
		return false
	return true


## Smash every smashable structure on/adjacent to the current cell. Returns true if any fell.
func _smash_adjacent_structures() -> bool:
	if not is_wrecker or _wreck_grid == null or not alive:
		return false
	var here := _wreck_grid.world_to_cell(position)
	var any := false
	var smash_dirs: Array[Vector2i] = [
		Vector2i.ZERO, Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
	]
	for d in smash_dirs:
		if _try_smash_cell(here + d):
			any = true
	return any


func _try_smash_cell(cell: Vector2i) -> bool:
	if not _cell_is_smashable(cell):
		return false
	var removed := _wreck_grid.remove_tower_at(cell)
	if removed == null:
		return false
	if is_instance_valid(removed):
		removed.queue_free()
	wrecked_at.emit(cell)
	return true


## Wire this enemy into a snake chain (call after setup).
func configure_snake(index: int, prev: Enemy, spacing: float = 28.0) -> void:
	is_snake = true
	snake_index = index
	snake_prev = prev
	snake_spacing = maxf(spacing, 12.0)
	path_dist = 0.0
	if index == 0:
		_radius = 15.0
		_base_color = Color(0.22, 0.78, 0.32)
	else:
		_radius = 11.0
		var shade := clampf(float(index) * 0.04, 0.0, 0.45)
		_base_color = Color(0.32, 0.68, 0.28).lerp(Color(0.16, 0.42, 0.2), shade)
	if monster_type != "":
		_base_color = _base_color.lerp(MonsterTypes.tint_color(monster_type), 0.4)
	queue_redraw()


## Damage multiplier after elemental resist (1.0 = full damage).
func resist_mult(element_id: String) -> float:
	if element_id.is_empty() or element_resists.is_empty():
		return 1.0
	var reduction := clampf(float(element_resists.get(element_id, 0.0)), 0.0, 0.9)
	return 1.0 - reduction


func resist_for(element_id: String) -> float:
	return clampf(float(element_resists.get(element_id, 0.0)), 0.0, 0.9)


func _process(delta: float) -> void:
	if not alive:
		return
	_tick_statuses(delta)
	if is_wrecker:
		_wrecker_tick()
	_move_along_path(delta)
	queue_redraw()


func _tick_statuses(delta: float) -> void:
	if burn_time > 0.0:
		burn_time -= delta
		take_damage(burn_dps * delta, false)
		if burn_time <= 0.0:
			burn_dps = 0.0
	if poison_time > 0.0:
		poison_time -= delta
		take_damage(poison_dps * delta, false)
		if poison_time <= 0.0:
			poison_dps = 0.0
	if slow_time > 0.0:
		slow_time -= delta
		if slow_time <= 0.0:
			slow_factor = 1.0
	if mark_time > 0.0:
		mark_time -= delta
		if mark_time <= 0.0:
			mark_time = 0.0
			mark_damage_mult = 1.0
	if orbit_immune_time > 0.0:
		orbit_immune_time = maxf(orbit_immune_time - delta, 0.0)


func try_begin_orbit(center: Vector2, radius: float, laps: float, immune_after: float = 1.5) -> bool:
	if not alive or is_flying or is_snake or is_wrecker or orbit_active:
		return false
	if orbit_immune_time > 0.0:
		return false
	orbit_active = true
	orbit_center = center
	orbit_radius = maxf(radius, 16.0)
	orbit_laps = maxf(laps, 0.25)
	orbit_angle_traveled = 0.0
	_orbit_immune_after = maxf(immune_after, 0.0)
	var offset := position - center
	if offset.length_squared() < 1.0:
		orbit_angle = 0.0
	else:
		orbit_angle = offset.angle()
	position = center + Vector2(cos(orbit_angle), sin(orbit_angle)) * orbit_radius
	queue_redraw()
	return true


func _end_orbit() -> void:
	if not orbit_active:
		return
	orbit_active = false
	orbit_immune_time = _orbit_immune_after
	orbit_angle_traveled = 0.0
	_snap_to_nearest_path()
	queue_redraw()


func _snap_to_nearest_path() -> void:
	if path.is_empty():
		return
	if is_snake:
		path_dist = _closest_path_dist(position)
		position = _position_at_path_dist(path_dist)
		return
	var best_i := 0
	var best_d := INF
	for i in path.size():
		var d := position.distance_squared_to(path[i])
		if d < best_d:
			best_d = d
			best_i = i
	path_index = mini(best_i + 1, path.size() - 1)


func _move_orbit(delta: float) -> void:
	var ang_speed := (speed * slow_factor) / maxf(orbit_radius, 1.0)
	var step := ang_speed * delta
	orbit_angle += step
	orbit_angle_traveled += step
	position = orbit_center + Vector2(cos(orbit_angle), sin(orbit_angle)) * orbit_radius
	if orbit_angle_traveled >= TAU * orbit_laps:
		_end_orbit()


func _move_along_path(delta: float) -> void:
	if orbit_active:
		_move_orbit(delta)
		return
	if is_snake:
		_move_snake(delta)
		return
	if path.is_empty() or path_index >= path.size():
		_leak()
		return
	var target := path[path_index]
	var current_speed := speed * slow_factor
	var step := current_speed * delta
	var to_target := target - position
	var dist := to_target.length()
	if dist <= step:
		position = target
		if is_wrecker:
			_smash_adjacent_structures()
		path_index += 1
		if path_index >= path.size():
			if is_wrecker and _wreck_hunting:
				refresh_wrecker_hunt()
			else:
				_leak()
	else:
		position += to_target.normalized() * step


func _move_snake(delta: float) -> void:
	if path.is_empty():
		_leak()
		return
	var total := _path_total_length()
	if total <= 0.0:
		_leak()
		return
	# Broken link → continue along the path as a free segment.
	if snake_prev != null and (not is_instance_valid(snake_prev) or not snake_prev.alive):
		snake_prev = null
	var step := speed * slow_factor * delta
	if snake_prev != null:
		var want := snake_prev.path_dist - snake_spacing
		if want <= 0.0:
			path_dist = 0.0
			position = path[0]
			return
		if path_dist < want:
			path_dist = minf(path_dist + step, want)
		else:
			path_dist = want
	else:
		path_dist += step
	if path_dist >= total:
		position = path[path.size() - 1]
		_leak()
		return
	position = _position_at_path_dist(path_dist)


func path_progress() -> float:
	var total := _path_total_length()
	if total <= 0.0:
		return 0.0
	return clampf(path_dist / total, 0.0, 1.0)


func _path_total_length() -> float:
	var total := 0.0
	for i in range(1, path.size()):
		total += path[i].distance_to(path[i - 1])
	return total


func _position_at_path_dist(dist: float) -> Vector2:
	if path.is_empty():
		return position
	if dist <= 0.0:
		return path[0]
	var remaining := dist
	for i in range(1, path.size()):
		var seg_len := path[i].distance_to(path[i - 1])
		if remaining <= seg_len:
			if seg_len <= 0.001:
				return path[i]
			return path[i - 1].lerp(path[i], remaining / seg_len)
		remaining -= seg_len
	return path[path.size() - 1]


func _closest_path_dist(pos: Vector2) -> float:
	if path.size() < 2:
		return 0.0
	var best_dist := 0.0
	var best_d2 := INF
	var walked := 0.0
	for i in range(1, path.size()):
		var a: Vector2 = path[i - 1]
		var b: Vector2 = path[i]
		var ab := b - a
		var ab_len2 := ab.length_squared()
		var t := 0.0
		if ab_len2 > 0.0001:
			t = clampf((pos - a).dot(ab) / ab_len2, 0.0, 1.0)
		var proj := a.lerp(b, t)
		var d2 := pos.distance_squared_to(proj)
		if d2 < best_d2:
			best_d2 = d2
			best_dist = walked + sqrt(ab_len2) * t
		walked += sqrt(ab_len2)
	return best_dist


func set_path(new_path: PackedVector2Array) -> void:
	# Flyers keep their air S-lane; maze edits do not repath them.
	if is_flying:
		return
	if new_path.is_empty():
		return
	path = new_path
	if is_snake:
		path_dist = _closest_path_dist(position)
		position = _position_at_path_dist(path_dist)
		return
	# Snap to nearest point index to avoid teleporting backward awkwardly.
	var best_i := 0
	var best_d := INF
	for i in path.size():
		var d := position.distance_squared_to(path[i])
		if d < best_d:
			best_d = d
			best_i = i
	path_index = mini(best_i + 1, path.size() - 1)


func take_damage(amount: float, _from_hit: bool = true) -> void:
	if not alive or amount <= 0.0:
		return
	if mark_time > 0.0:
		amount *= maxf(mark_damage_mult, 1.0)
	hp -= amount
	if hp <= 0.0:
		_die()


func apply_burn(dps: float, duration: float) -> void:
	burn_dps = maxf(burn_dps, dps)
	burn_time = maxf(burn_time, duration)


func apply_poison(dps: float, duration: float) -> void:
	poison_dps = maxf(poison_dps, dps)
	poison_time = maxf(poison_time, duration)


func apply_slow(factor: float, duration: float) -> void:
	slow_factor = minf(slow_factor, factor)
	slow_time = maxf(slow_time, duration)


func apply_mark(mult: float, duration: float) -> void:
	mark_damage_mult = maxf(mark_damage_mult, mult)
	mark_time = maxf(mark_time, duration)
	queue_redraw()


func _die() -> void:
	if not alive:
		return
	alive = false
	died.emit(self, bounty)
	queue_free()


func start_overflow(new_path: PackedVector2Array, new_lane: int, new_defender: int) -> void:
	if new_path.size() < 2:
		return
	overflow_pending = true
	lane_id = new_lane
	defender_id = new_defender
	path = new_path
	path_index = 1
	path_dist = 0.0
	position = path[0]
	queue_redraw()


func _leak() -> void:
	if not alive:
		return
	leaked.emit(self)
	if overflow_pending:
		overflow_pending = false
		return
	alive = false
	queue_free()


func _draw() -> void:
	var color := _base_color
	if burn_time > 0.0:
		color = color.lerp(Color(1.0, 0.45, 0.1), 0.45)
	if poison_time > 0.0:
		color = color.lerp(Color(0.3, 0.9, 0.3), 0.35)
	if slow_time > 0.0:
		color = color.lerp(Color(0.4, 0.8, 1.0), 0.4)
	if mark_time > 0.0:
		color = color.lerp(Color(1.0, 0.95, 0.35), 0.45)
	if orbit_active:
		color = color.lerp(Color(0.65, 0.4, 0.95), 0.5)
	if is_flying:
		var wing := PackedVector2Array([
			Vector2(-_radius - 6.0, 0.0),
			Vector2(0.0, -_radius * 0.6),
			Vector2(_radius + 6.0, 0.0),
			Vector2(0.0, _radius * 0.6),
		])
		draw_colored_polygon(wing, color)
		draw_circle(Vector2.ZERO, _radius * 0.55, color.lightened(0.15))
		draw_arc(Vector2.ZERO, _radius + 4.0, 0.0, TAU, 24, Color(0.7, 0.9, 1.0), 2.0)
	elif is_snake:
		draw_circle(Vector2.ZERO, _radius, color)
		draw_circle(Vector2(-_radius * 0.35, 0.0), _radius * 0.72, color.darkened(0.12))
		if is_boss or snake_index == 0:
			draw_arc(Vector2.ZERO, _radius + 3.0, 0.0, TAU, 24, Color(0.85, 1.0, 0.35), 2.0)
			draw_circle(Vector2(_radius * 0.35, -_radius * 0.25), 2.2, Color(0.05, 0.08, 0.05))
			draw_circle(Vector2(_radius * 0.35, _radius * 0.25), 2.2, Color(0.05, 0.08, 0.05))
	else:
		draw_circle(Vector2.ZERO, _radius, color)
		if is_boss:
			draw_arc(Vector2.ZERO, _radius + 3.0, 0.0, TAU, 24, Color(1, 0.85, 0.2), 2.0)
	if UserSettings.is_show_enemy_hp_bars():
		var bar_w := _radius * 2.2
		var thick := 4.0 if is_boss else 3.0
		var ratio := clampf(hp / max_hp, 0.0, 1.0)
		draw_rect(Rect2(-bar_w * 0.5, -_radius - 8.0, bar_w, thick), Color(0.1, 0.1, 0.1))
		draw_rect(Rect2(-bar_w * 0.5, -_radius - 8.0, bar_w * ratio, thick), Color(0.2, 0.85, 0.3))
	if UserSettings.is_high_contrast() and monster_type != "":
		draw_arc(Vector2.ZERO, _radius + 5.0, 0.0, TAU, 12, Color.WHITE, 2.0)
