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

var burn_time: float = 0.0
var burn_dps: float = 0.0
var poison_time: float = 0.0
var poison_dps: float = 0.0
var slow_time: float = 0.0
var slow_factor: float = 1.0

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


func _move_along_path(delta: float) -> void:
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


func set_path(new_path: PackedVector2Array) -> void:
	# Flyers keep their air S-lane; maze edits do not repath them.
	if is_flying:
		return
	if new_path.is_empty():
		return
	path = new_path
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
	else:
		draw_circle(Vector2.ZERO, _radius, color)
		if is_boss:
			draw_arc(Vector2.ZERO, _radius + 3.0, 0.0, TAU, 24, Color(1, 0.85, 0.2), 2.0)
	# HP bar
	var bar_w := _radius * 2.2
	var ratio := clampf(hp / max_hp, 0.0, 1.0)
	draw_rect(Rect2(-bar_w * 0.5, -_radius - 8.0, bar_w, 3.0), Color(0.1, 0.1, 0.1))
	draw_rect(Rect2(-bar_w * 0.5, -_radius - 8.0, bar_w * ratio, 3.0), Color(0.2, 0.85, 0.3))
