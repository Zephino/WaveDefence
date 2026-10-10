extends RefCounted

## Cosmetic attack shots that travel from the tower toward a moving enemy.


static func try_spawn(
	effect: String,
	from_global: Vector2,
	to_global: Vector2,
	range_px: float,
	parent: Node,
	target: Node2D = null
) -> void:
	if parent == null or not UserSettings.is_effects_enabled():
		return
	if UserSettings.is_performance_mode():
		return
	var max_range := maxf(range_px, 8.0)
	match effect:
		"burn":
			var flame := FlameShot.new()
			flame.setup(from_global, to_global, max_range, target)
			parent.add_child(flame)
		"freeze":
			var ice := IceShot.new()
			ice.setup(from_global, to_global, max_range, target)
			parent.add_child(ice)
		"poison":
			var cloud := PoisonShot.new()
			cloud.setup(from_global, to_global, max_range, target)
			parent.add_child(cloud)
		_:
			pass


class TravelingShot extends Node2D:
	var _target: Node2D = null
	var _aim := Vector2.ZERO
	var _speed := 520.0
	var _life := 0.55
	var _max_life := 0.55
	var _max_range := 100.0
	var _from := Vector2.ZERO
	var _impacted := false
	var _trail: Array[Vector2] = []

	func setup(from_global: Vector2, to_global: Vector2, max_range: float, target: Node2D) -> void:
		_from = from_global
		global_position = from_global
		_aim = to_global
		_target = target
		_max_range = max_range
		var dist := from_global.distance_to(to_global)
		_speed = clampf(dist / 0.16, 280.0, 900.0)
		z_index = 8

	func _aim_point() -> Vector2:
		if _target != null and is_instance_valid(_target):
			return _target.global_position
		return _aim

	func _process(delta: float) -> void:
		if _impacted:
			_life -= delta
			if _life <= 0.0:
				queue_free()
			else:
				queue_redraw()
			return
		_life -= delta
		var dest := _aim_point()
		var to_target := dest - global_position
		var step := _speed * delta
		_trail.append(global_position)
		if _trail.size() > 8:
			_trail.pop_front()
		if to_target.length() <= step or _life <= 0.0 or _from.distance_to(global_position) >= _max_range:
			global_position = dest if to_target.length() <= step else global_position
			_impacted = true
			_life = 0.12
			_max_life = 0.12
			queue_redraw()
			return
		global_position += to_target.normalized() * step
		queue_redraw()

	func _draw_trail(color: Color, width: float) -> void:
		if _trail.size() < 2:
			return
		for i in range(1, _trail.size()):
			var a := float(i) / float(_trail.size())
			var p0: Vector2 = to_local(_trail[i - 1])
			var p1: Vector2 = to_local(_trail[i])
			var c := color
			c.a *= a * 0.7
			draw_line(p0, p1, c, width * a)


class FlameShot extends TravelingShot:
	func _draw() -> void:
		var a := clampf(_life / _max_life, 0.0, 1.0)
		_draw_trail(Color(1.0, 0.45, 0.1, 0.8), 4.0)
		if _impacted:
			draw_circle(Vector2.ZERO, 10.0 + (1.0 - a) * 8.0, Color(1.0, 0.4, 0.1, 0.45 * a))
			draw_circle(Vector2.ZERO, 5.0, Color(1.0, 0.85, 0.35, 0.7 * a))
			return
		var dir := (_aim_point() - global_position)
		if dir.length_squared() < 0.001:
			dir = Vector2.RIGHT
		else:
			dir = dir.normalized()
		var tip := dir * 14.0
		var side := Vector2(-dir.y, dir.x)
		var body := PackedVector2Array([
			-dir * 6.0 + side * 3.0,
			tip + side * 2.0,
			tip,
			tip - side * 2.0,
			-dir * 6.0 - side * 3.0,
		])
		draw_colored_polygon(body, Color(0.95, 0.35, 0.12, 0.85 * a))
		draw_circle(tip * 0.2, 3.5, Color(1.0, 0.85, 0.35, 0.9 * a))


class IceShot extends TravelingShot:
	func _draw() -> void:
		var a := clampf(_life / _max_life, 0.0, 1.0)
		_draw_trail(Color(0.7, 0.9, 1.0, 0.75), 3.0)
		if _impacted:
			for i in 5:
				var ang := float(i) * TAU / 5.0
				draw_line(Vector2.ZERO, Vector2.RIGHT.rotated(ang) * (8.0 + (1.0 - a) * 10.0), Color(0.85, 0.95, 1.0, 0.7 * a), 2.0)
			draw_circle(Vector2.ZERO, 4.0, Color(0.95, 1.0, 1.0, 0.8 * a))
			return
		var dir := (_aim_point() - global_position)
		if dir.length_squared() < 0.001:
			dir = Vector2.RIGHT
		else:
			dir = dir.normalized()
		var tip := dir * 16.0
		var side := Vector2(-dir.y, dir.x)
		draw_colored_polygon(PackedVector2Array([
			-dir * 4.0,
			tip * 0.45 + side * 5.0,
			tip,
			tip * 0.45 - side * 5.0,
		]), Color(0.65, 0.9, 1.0, 0.75 * a))
		draw_line(-dir * 3.0, tip, Color(0.95, 1.0, 1.0, 0.9 * a), 2.0)


class PoisonShot extends TravelingShot:
	func _draw() -> void:
		var a := clampf(_life / _max_life, 0.0, 1.0)
		_draw_trail(Color(0.4, 0.9, 0.35, 0.65), 5.0)
		if _impacted:
			draw_circle(Vector2.ZERO, 12.0 + (1.0 - a) * 10.0, Color(0.35, 0.85, 0.35, 0.3 * a))
			draw_circle(Vector2.ZERO, 6.0, Color(0.55, 0.95, 0.45, 0.45 * a))
			return
		draw_circle(Vector2.ZERO, 7.0, Color(0.35, 0.85, 0.35, 0.55 * a))
		draw_circle(Vector2(-3, -2), 4.0, Color(0.5, 0.95, 0.4, 0.4 * a))
		draw_circle(Vector2(3, 1), 3.5, Color(0.45, 0.9, 0.4, 0.4 * a))
