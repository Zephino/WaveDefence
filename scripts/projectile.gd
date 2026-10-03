class_name Projectile
extends Node2D

var target: Enemy
var speed: float = 320.0
var damage: float = 1.0
var splash_radius: float = 0.0
var effect: String = "none"
var effect_data: Dictionary = {}
var enemy_container: Node
var color: Color = Color.WHITE
var alive: bool = true


func setup(
	p_target: Enemy,
	p_damage: float,
	p_splash: float,
	p_effect: String,
	p_effect_data: Dictionary,
	p_enemies: Node,
	p_color: Color,
	p_speed: float = 320.0
) -> void:
	target = p_target
	damage = p_damage
	splash_radius = p_splash
	effect = p_effect
	effect_data = p_effect_data
	enemy_container = p_enemies
	color = p_color
	speed = maxf(p_speed, 40.0)


func _process(delta: float) -> void:
	if not alive:
		return
	if target == null or not is_instance_valid(target) or not target.alive:
		queue_free()
		return
	var to_target := target.global_position - global_position
	var step := speed * delta
	if to_target.length() <= step:
		global_position = target.global_position
		_impact()
	else:
		global_position += to_target.normalized() * step
	queue_redraw()


## Instant hit (melee / point-blank). Safe to call after the projectile is in the tree.
func impact_now() -> void:
	if not alive:
		return
	_impact()


func _impact() -> void:
	alive = false
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
		_apply_to_enemy(current, dmg, false)
		hit.append(current)
		_spawn_bolt(from_pos, current.global_position)
		from_pos = current.global_position
		dmg *= falloff
		current = _find_next_chain(from_pos, chain_range, hit)


func _find_next_chain(from_pos: Vector2, chain_range: float, exclude: Array[Enemy]) -> Enemy:
	var best: Enemy = null
	var best_d := chain_range
	for child in enemy_container.get_children():
		if child is Enemy:
			var e := child as Enemy
			if not e.alive or e in exclude:
				continue
			if not TowerData.can_target_enemy(effect_data, e):
				continue
			var d := from_pos.distance_to(e.global_position)
			if d <= best_d:
				best_d = d
				best = e
	return best


func _spawn_bolt(from_pos: Vector2, to_pos: Vector2) -> void:
	var bolt := LightningBolt.new()
	bolt.setup(from_pos, to_pos)
	enemy_container.get_parent().add_child(bolt)


func _damage_in_radius(center: Vector2, radius: float, dmg: float, apply_effects: bool) -> void:
	for child in enemy_container.get_children():
		if child is Enemy:
			var e := child as Enemy
			if e.alive and center.distance_to(e.global_position) <= radius:
				_apply_to_enemy(e, dmg, apply_effects)


func _apply_to_enemy(enemy: Enemy, dmg: float, apply_effects: bool) -> void:
	if enemy == null or not is_instance_valid(enemy) or not enemy.alive:
		return
	if not TowerData.can_target_enemy(effect_data, enemy):
		return
	var mult := TowerData.target_damage_mult(effect_data, enemy.is_flying, enemy.is_boss)
	if mult <= 0.0:
		return
	enemy.take_damage(dmg * mult)
	if not apply_effects:
		return
	match effect:
		"burn":
			enemy.apply_burn(
				float(effect_data.get("burn_dps", 4.0)) * mult,
				float(effect_data.get("burn_duration", 3.0))
			)
		"freeze":
			enemy.apply_slow(float(effect_data.get("slow_factor", 0.45)), float(effect_data.get("slow_duration", 2.0)))
		"poison":
			enemy.apply_poison(
				float(effect_data.get("poison_dps", 3.0)) * mult,
				float(effect_data.get("poison_duration", 4.0))
			)
	_apply_bonus_effects(enemy, mult)


func _apply_bonus_effects(enemy: Enemy, mult: float) -> void:
	if effect_data.has("bonus_burn_dps"):
		enemy.apply_burn(
			float(effect_data.get("bonus_burn_dps", 0.0)) * mult,
			float(effect_data.get("bonus_burn_duration", 0.0))
		)
	if effect_data.has("bonus_slow_factor"):
		enemy.apply_slow(
			float(effect_data.get("bonus_slow_factor", 0.72)),
			float(effect_data.get("bonus_slow_duration", 0.0))
		)
	if effect_data.has("bonus_poison_dps"):
		enemy.apply_poison(
			float(effect_data.get("bonus_poison_dps", 0.0)) * mult,
			float(effect_data.get("bonus_poison_duration", 0.0))
		)


func _draw() -> void:
	draw_circle(Vector2.ZERO, 4.0, color)


class LightningBolt extends Node2D:
	var from_local := Vector2.ZERO
	var to_local := Vector2.ZERO
	var life := 0.15

	func setup(from_global: Vector2, to_global: Vector2) -> void:
		global_position = Vector2.ZERO
		from_local = from_global
		to_local = to_global

	func _process(delta: float) -> void:
		life -= delta
		if life <= 0.0:
			queue_free()
		queue_redraw()

	func _draw() -> void:
		draw_line(from_local, to_local, Color(0.95, 0.9, 0.3, clampf(life / 0.15, 0.0, 1.0)), 2.5)
