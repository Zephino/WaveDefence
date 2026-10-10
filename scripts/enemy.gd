class_name Enemy
extends Node2D

signal died(enemy: Enemy, bounty: int)
signal leaked(enemy: Enemy)

var max_hp: float = 20.0
var hp: float = 20.0
var speed: float = 60.0
var bounty: int = 5
var is_boss: bool = false
var is_flying: bool = false
## Wave this enemy belongs to (used so early-send leftovers don't inflate the new wave's kill % ).
var wave_index: int = 0
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
	if monster_type != "":
		_base_color = _base_color.lerp(MonsterTypes.tint_color(monster_type), 0.7)
	# Path points are grid-local (same space as this node's parent offset).
	if path.size() > 0:
		position = path[0]
		path_index = 1 if path.size() > 1 else 0
		path_dist = 0.0
	queue_redraw()


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


func _move_along_path(delta: float) -> void:
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
		path_index += 1
		if path_index >= path.size():
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


func _leak() -> void:
	if not alive:
		return
	alive = false
	leaked.emit(self)
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
