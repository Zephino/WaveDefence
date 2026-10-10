extends RefCounted

## Short cosmetic attack bursts for elemental towers (gated by UserSettings effects).


static func try_spawn(effect: String, from_global: Vector2, to_global: Vector2, range_px: float, parent: Node) -> void:
	if parent == null or not UserSettings.is_effects_enabled():
		return
	if UserSettings.is_performance_mode():
		return
	var max_range := maxf(range_px, 8.0)
	match effect:
		"burn":
			var flame := FlameBurst.new()
			flame.setup(from_global, to_global, max_range)
			parent.add_child(flame)
		"freeze":
			var ice := IceBurst.new()
			ice.setup(from_global, to_global, max_range)
			parent.add_child(ice)
		"poison":
			var cloud := PoisonCloud.new()
			cloud.setup(from_global, to_global, max_range)
			parent.add_child(cloud)
		_:
			pass


class FlameBurst extends Node2D:
	var _dir := Vector2.RIGHT
	var _len := 40.0
	var _life := 0.25
	var _max_life := 0.25

	func setup(from_global: Vector2, to_global: Vector2, max_range: float) -> void:
		global_position = from_global
		var seg: Dictionary = _aim(from_global, to_global, max_range)
		_dir = seg["dir"]
		_len = float(seg["len"])
		z_index = 8

	func _aim(from_global: Vector2, to_global: Vector2, max_range: float) -> Dictionary:
		var delta := to_global - from_global
		var dist := delta.length()
		if dist < 0.001:
			var fallback_len := minf(24.0, max_range)
			return {"dir": Vector2.RIGHT, "len": fallback_len}
		return {"dir": delta / dist, "len": minf(dist, max_range)}

	func _process(delta: float) -> void:
		_life -= delta
		if _life <= 0.0:
			queue_free()
			return
		queue_redraw()

	func _draw() -> void:
		var a := clampf(_life / _max_life, 0.0, 1.0)
		var tip := _dir * _len
		var side := Vector2(-_dir.y, _dir.x)
		var base_w := 5.0 + (1.0 - a) * 3.0
		var tip_w := 14.0 + (1.0 - a) * 6.0
		var outer := PackedVector2Array([
			side * base_w,
			tip + side * tip_w * 0.35,
			tip,
			tip - side * tip_w * 0.35,
			-side * base_w,
		])
		draw_colored_polygon(outer, Color(0.95, 0.35, 0.12, 0.55 * a))
		var mid := PackedVector2Array([
			side * (base_w * 0.45),
			tip * 0.92 + side * tip_w * 0.15,
			tip * 0.98,
			tip * 0.92 - side * tip_w * 0.15,
			-side * (base_w * 0.45),
		])
		draw_colored_polygon(mid, Color(1.0, 0.7, 0.2, 0.65 * a))
		draw_line(Vector2.ZERO, tip * 0.95, Color(1.0, 0.95, 0.7, 0.85 * a), 2.0)


class IceBurst extends Node2D:
	var _dir := Vector2.RIGHT
	var _len := 40.0
	var _life := 0.28
	var _max_life := 0.28
	var _shards: Array[Vector2] = []

	func setup(from_global: Vector2, to_global: Vector2, max_range: float) -> void:
		global_position = from_global
		var delta := to_global - from_global
		var dist := delta.length()
		if dist < 0.001:
			_dir = Vector2.RIGHT
			_len = minf(24.0, max_range)
		else:
			_dir = delta / dist
			_len = minf(dist, max_range)
		z_index = 8
		var side := Vector2(-_dir.y, _dir.x)
		_shards = [
			_dir.rotated(-0.22) * (_len * 0.92),
			_dir * _len,
			_dir.rotated(0.22) * (_len * 0.92),
			_dir.rotated(-0.12) * (_len * 0.7) + side * 4.0,
			_dir.rotated(0.12) * (_len * 0.7) - side * 4.0,
		]

	func _process(delta: float) -> void:
		_life -= delta
		if _life <= 0.0:
			queue_free()
			return
		queue_redraw()

	func _draw() -> void:
		var a := clampf(_life / _max_life, 0.0, 1.0)
		var side := Vector2(-_dir.y, _dir.x)
		var cone := PackedVector2Array([
			side * 3.0,
			_dir * _len + side * (_len * 0.12),
			_dir * _len - side * (_len * 0.12),
			-side * 3.0,
		])
		draw_colored_polygon(cone, Color(0.55, 0.85, 1.0, 0.28 * a))
		for shard in _shards:
			draw_line(Vector2.ZERO, shard, Color(0.85, 0.95, 1.0, 0.8 * a), 2.0)
			draw_circle(shard, 2.2, Color(0.95, 1.0, 1.0, 0.75 * a))


class PoisonCloud extends Node2D:
	var _dir := Vector2.RIGHT
	var _len := 40.0
	var _life := 0.35
	var _max_life := 0.35
	var _puffs: Array[Vector2] = []

	func setup(from_global: Vector2, to_global: Vector2, max_range: float) -> void:
		global_position = from_global
		var delta := to_global - from_global
		var dist := delta.length()
		if dist < 0.001:
			_dir = Vector2.RIGHT
			_len = minf(24.0, max_range)
		else:
			_dir = delta / dist
			_len = minf(dist, max_range)
		z_index = 8
		var side := Vector2(-_dir.y, _dir.x)
		_puffs = [
			_dir * (_len * 0.35),
			_dir * (_len * 0.62) + side * 6.0,
			_dir * (_len * 0.62) - side * 6.0,
			_dir * (_len * 0.88),
			_dir * _len,
		]

	func _process(delta: float) -> void:
		_life -= delta
		if _life <= 0.0:
			queue_free()
			return
		queue_redraw()

	func _draw() -> void:
		var a := clampf(_life / _max_life, 0.0, 1.0)
		var grow := 1.0 + (1.0 - a) * 0.45
		for i in _puffs.size():
			var p: Vector2 = _puffs[i]
			var r := (8.0 + float(i) * 2.5) * grow
			# Keep cloud within range from the tower origin.
			var reach := p.length() + r
			if reach > _len + 4.0:
				r = maxf(4.0, _len + 4.0 - p.length())
			draw_circle(p, r, Color(0.35, 0.85, 0.35, 0.22 * a))
			draw_circle(p, r * 0.55, Color(0.55, 0.95, 0.45, 0.28 * a))
