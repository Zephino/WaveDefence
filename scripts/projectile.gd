class_name Projectile
extends Node2D

const _EffectSprites := preload("res://scripts/effect_sprites.gd")

var target: Enemy
var speed: float = 320.0
var damage: float = 1.0
var splash_radius: float = 0.0
var effect: String = "none"
var effect_data: Dictionary = {}
var enemy_container: Node
var color: Color = Color.WHITE
var alive: bool = true
## Clash lane this shot can hit (-1 = any).
var lane_id: int = -1
## Visual-only tower id for projectile / impact sheets.
var tower_id: String = ""
var _anim_time: float = 0.0
var _flight_fx: String = ""
var _impact_fx: String = ""


func setup(
	p_target: Enemy,
	p_damage: float,
	p_splash: float,
	p_effect: String,
	p_effect_data: Dictionary,
	p_enemies: Node,
	p_color: Color,
	p_speed: float = 320.0,
	p_lane_id: int = -1,
	p_tower_id: String = ""
) -> void:
	target = p_target
	damage = p_damage
	splash_radius = p_splash
	effect = p_effect
	effect_data = p_effect_data
	enemy_container = p_enemies
	color = p_color
	speed = maxf(p_speed, 40.0)
	lane_id = p_lane_id
	tower_id = p_tower_id
	_flight_fx = _EffectSprites.projectile_for_tower(tower_id)
	_impact_fx = _EffectSprites.impact_for_tower(tower_id)
	_anim_time = 0.0


func _process(delta: float) -> void:
	if not alive:
		return
	_anim_time += delta
	if target == null or not is_instance_valid(target) or not target.alive:
		queue_free()
		return
	var prev_global := global_position
	var to_target := target.global_position - global_position
	var step := speed * delta
	if to_target.length() <= step:
		global_position = target.global_position
		if _hits_clash_divider(prev_global, global_position):
			_neutralize()
			return
		_impact()
	else:
		global_position += to_target.normalized() * step
		if _hits_clash_divider(prev_global, global_position):
			_neutralize()
			return
	queue_redraw()


## Instant hit (melee / point-blank). Safe to call after the projectile is in the tree.
func impact_now() -> void:
	if not alive:
		return
	_impact()


## Destroy the shot with no damage (Clash brown lane dividers).
func _neutralize() -> void:
	alive = false
	queue_free()


func _hits_clash_divider(from_global: Vector2, to_global: Vector2) -> bool:
	var g := _clash_grid()
	if g == null or not g.is_clash_layout:
		return false
	return g.segment_hits_blocked(from_global, to_global)


func _impact() -> void:
	alive = false
	_spawn_impact_fx()
	if effect == "lightning":
		_do_lightning(
			int(effect_data.get("chain_count", 3)),
			float(effect_data.get("chain_range", 90.0)),
			float(effect_data.get("chain_falloff", 0.7)),
			damage,
			true
		)
	elif splash_radius > 0.0:
		_damage_in_radius(global_position, splash_radius, damage, true)
	else:
		_apply_to_enemy(target, damage, true)
	_apply_bonus_chain()
	queue_free()


func _spawn_impact_fx() -> void:
	if _impact_fx.is_empty():
		return
	var host: Node = get_parent()
	if host == null:
		host = enemy_container
	var scale_extra := 1.0
	if _impact_fx == "fx_explosion" and splash_radius > 0.0:
		# 48px frame == 40px splash at scale 1; stretch to splash radius.
		scale_extra = splash_radius / 40.0
	_EffectSprites.spawn_flash(_impact_fx, global_position, host, 0.0, scale_extra)


func _do_lightning(chain_count: int, chain_range: float, falloff: float, start_dmg: float, apply_effects: bool) -> void:
	var hit: Array[Enemy] = []
	var current: Enemy = target
	var dmg := start_dmg
	var from_pos := global_position
	for i in chain_count:
		if current == null or not is_instance_valid(current) or not current.alive:
			break
		_apply_to_enemy(current, dmg, apply_effects)
		hit.append(current)
		_spawn_bolt(from_pos, current.global_position)
		from_pos = current.global_position
		dmg *= falloff
		current = _find_next_chain(from_pos, chain_range, hit)


func _apply_bonus_chain() -> void:
	var bonus_count := int(effect_data.get("bonus_chain_count", 0))
	if bonus_count <= 0 or effect == "lightning":
		return
	if target == null or not is_instance_valid(target):
		return
	# Jump to nearby enemies only — primary target was already hit.
	var hit: Array[Enemy] = [target]
	var from_pos := target.global_position
	var chain_range := float(effect_data.get("bonus_chain_range", 90.0))
	var falloff := float(effect_data.get("bonus_chain_falloff", 0.7))
	var dmg := damage * 0.55
	var current := _find_next_chain(from_pos, chain_range, hit)
	for i in bonus_count:
		if current == null or not is_instance_valid(current) or not current.alive:
			break
		# Bonus chain is lightning-flavored even when the tower's primary effect is not.
		var chain_mult := TowerData.target_damage_mult(effect_data, current.is_flying, current.is_boss)
		if chain_mult > 0.0:
			current.take_damage(dmg * chain_mult * current.resist_mult("lightning"))
		hit.append(current)
		_spawn_bolt(from_pos, current.global_position)
		from_pos = current.global_position
		dmg *= falloff
		current = _find_next_chain(from_pos, chain_range, hit)


func _clash_grid() -> GameGrid:
	if enemy_container == null:
		return null
	var host := enemy_container.get_parent()
	if host == null:
		return null
	return host.get_node_or_null("GameGrid") as GameGrid


func _physical_lane(enemy: Enemy) -> int:
	var g := _clash_grid()
	if g == null:
		return -1
	return g.lane_index_for_global(enemy.global_position)


func _can_hit_lane(enemy: Enemy) -> bool:
	var g := _clash_grid()
	if g == null or not g.is_clash_layout or lane_id < 0:
		return TowerData.can_target_enemy(effect_data, enemy)
	return TowerData.can_target_enemy_in_lane(effect_data, enemy, lane_id, _physical_lane(enemy))


func _find_next_chain(from_pos: Vector2, chain_range: float, exclude: Array[Enemy]) -> Enemy:
	var best: Enemy = null
	var best_d := chain_range
	var g := _clash_grid()
	for child in enemy_container.get_children():
		if child is Enemy:
			var e := child as Enemy
			if not e.alive or e in exclude:
				continue
			if not _can_hit_lane(e):
				continue
			# Lightning can't jump across Clash brown dividers either.
			if g != null and g.is_clash_layout and g.segment_hits_blocked(from_pos, e.global_position):
				continue
			var d := from_pos.distance_to(e.global_position)
			if d <= best_d:
				best_d = d
				best = e
	return best


func _spawn_bolt(from_pos: Vector2, to_pos: Vector2) -> void:
	if not UserSettings.is_effects_enabled():
		return
	var host: Node = get_parent()
	if host == null:
		host = enemy_container
	var bolt := LightningBolt.new()
	host.add_child(bolt)
	bolt.setup(from_pos, to_pos)
	_EffectSprites.spawn_flash("fx_lightning_spark", to_pos, host, 0.0, 1.0)


func _damage_in_radius(center: Vector2, radius: float, dmg: float, apply_effects: bool) -> void:
	var g := _clash_grid()
	for child in enemy_container.get_children():
		if child is Enemy:
			var e := child as Enemy
			if e.alive and center.distance_to(e.global_position) <= radius:
				if not _can_hit_lane(e):
					continue
				if g != null and g.is_clash_layout and g.segment_hits_blocked(center, e.global_position):
					continue
				_apply_to_enemy(e, dmg, apply_effects)


func _apply_to_enemy(enemy: Enemy, dmg: float, apply_effects: bool) -> void:
	if enemy == null or not is_instance_valid(enemy) or not enemy.alive:
		return
	if not _can_hit_lane(enemy):
		return
	var mult := TowerData.target_damage_mult(effect_data, enemy.is_flying, enemy.is_boss)
	if mult <= 0.0:
		return
	var primary_el := _primary_element()
	var hit_mult := mult * enemy.resist_mult(primary_el)
	enemy.take_damage(dmg * hit_mult)
	if not apply_effects:
		return
	match effect:
		"burn":
			var r := enemy.resist_mult("burn")
			enemy.apply_burn(
				float(effect_data.get("burn_dps", 4.0)) * mult * r,
				float(effect_data.get("burn_duration", 3.0)) * r
			)
		"freeze":
			var r := enemy.resist_mult("freeze")
			# Resisted freeze: milder slow (higher factor) and shorter duration.
			var base_slow := float(effect_data.get("slow_factor", 0.45))
			var resisted_slow := lerpf(base_slow, 1.0, 1.0 - r)
			enemy.apply_slow(resisted_slow, float(effect_data.get("slow_duration", 2.0)) * r)
		"poison":
			var r := enemy.resist_mult("poison")
			enemy.apply_poison(
				float(effect_data.get("poison_dps", 3.0)) * mult * r,
				float(effect_data.get("poison_duration", 4.0)) * r
			)
	_apply_bonus_effects(enemy, mult)


func _primary_element() -> String:
	match effect:
		"burn", "freeze", "poison", "lightning":
			return effect
		_:
			return ""


func _apply_bonus_effects(enemy: Enemy, mult: float) -> void:
	if effect_data.has("bonus_burn_dps"):
		var r := enemy.resist_mult("burn")
		enemy.apply_burn(
			float(effect_data.get("bonus_burn_dps", 0.0)) * mult * r,
			float(effect_data.get("bonus_burn_duration", 0.0)) * r
		)
	if effect_data.has("bonus_slow_factor"):
		var r := enemy.resist_mult("freeze")
		var base_slow := float(effect_data.get("bonus_slow_factor", 0.72))
		var resisted_slow := lerpf(base_slow, 1.0, 1.0 - r)
		enemy.apply_slow(resisted_slow, float(effect_data.get("bonus_slow_duration", 0.0)) * r)
	if effect_data.has("bonus_poison_dps"):
		var r := enemy.resist_mult("poison")
		enemy.apply_poison(
			float(effect_data.get("bonus_poison_dps", 0.0)) * mult * r,
			float(effect_data.get("bonus_poison_duration", 0.0)) * r
		)


func _draw() -> void:
	var angle := 0.0
	if target != null and is_instance_valid(target):
		var dir := target.global_position - global_position
		if dir.length_squared() > 0.001:
			angle = dir.angle()
	if not _flight_fx.is_empty() and _EffectSprites.draw_effect(self, _flight_fx, _anim_time, angle, 1.0):
		return
	draw_circle(Vector2.ZERO, 4.0, color)


class LightningBolt extends Node2D:
	const _ES := preload("res://scripts/effect_sprites.gd")
	var from_pt := Vector2.ZERO
	var to_pt := Vector2.ZERO
	var life := 0.18
	var _anim_time: float = 0.0
	var _from_global := Vector2.ZERO
	var _to_global := Vector2.ZERO

	func setup(from_global: Vector2, to_global: Vector2) -> void:
		_from_global = from_global
		_to_global = to_global
		global_position = from_global
		from_pt = Vector2.ZERO
		to_pt = to_global - from_global
		z_index = 8

	func _process(delta: float) -> void:
		_anim_time += delta
		life -= delta
		if life <= 0.0:
			queue_free()
		queue_redraw()

	func _draw() -> void:
		var length := to_pt.length()
		var angle := to_pt.angle()
		# Tile gold bolt segments along the hop (64px authored length).
		if _ES.has_effect("fx_lightning_bolt") and length > 1.0:
			var seg_w := 64.0
			var sc := _ES.display_scale()
			var covered := 0.0
			while covered < length:
				var remain := length - covered
				var use_w := minf(seg_w, remain / maxf(sc, 0.001))
				draw_set_transform(Vector2.RIGHT.rotated(angle) * covered, angle, Vector2(sc, sc))
				var tex: Texture2D = _ES.anim_texture("fx_lightning_bolt", _anim_time)
				if tex != null:
					var sz: Vector2 = _ES.frame_size("fx_lightning_bolt")
					# Pivot is (0, 8) — left-center of the bolt segment.
					draw_texture_rect_region(
						tex,
						Rect2(0.0, -8.0, use_w, sz.y),
						Rect2(0, 0, use_w, sz.y)
					)
				draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
				covered += seg_w * sc
			return
		draw_line(from_pt, to_pt, Color(0.95, 0.9, 0.3, clampf(life / 0.18, 0.0, 1.0)), 2.5)
