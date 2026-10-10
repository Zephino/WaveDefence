class_name Tower
extends Node2D

const _AttackFx := preload("res://scripts/attack_fx.gd")

var tower_id: String = "gunner"
var def: Dictionary = {}
var fire_cooldown: float = 0.0
var enemy_container: Node
var projectile_container: Node
var selected: bool = false
var upgrade_level: int = 0
var final_element: String = ""
## Gold spent on upgrades (not base purchase); used for sell refund.
var gold_invested: int = 0
## Command ability id → remaining cooldown seconds.
var ability_cooldowns: Dictionary = {}
var buff_fire_mult: float = 1.0
var buff_time: float = 0.0
## Aim direction for elemental tower “front” / nozzle drawing.
var _aim_dir: Vector2 = Vector2.RIGHT
const SELECT_COLOR := Color(0.35, 0.95, 0.45)
const SELECT_COLOR_SOFT := Color(0.35, 0.95, 0.45, 0.35)


func setup(p_id: String, p_enemies: Node, p_projectiles: Node) -> void:
	tower_id = p_id
	enemy_container = p_enemies
	projectile_container = p_projectiles
	upgrade_level = 0
	final_element = ""
	gold_invested = 0
	_refresh_combat_def()
	queue_redraw()


func _refresh_combat_def() -> void:
	def = TowerData.combat_def(tower_id, upgrade_level, final_element)


func can_stat_upgrade() -> bool:
	return TowerData.can_upgrade_tower(self)


func can_final_upgrade() -> bool:
	return TowerData.can_apply_final(self)


func next_stat_upgrade_cost() -> int:
	return TowerData.stat_upgrade_cost(tower_id, upgrade_level)


func final_upgrade_cost() -> int:
	return TowerData.final_upgrade_cost(tower_id)


func apply_stat_upgrade() -> bool:
	if not can_stat_upgrade():
		return false
	var cost := next_stat_upgrade_cost()
	upgrade_level += 1
	gold_invested += cost
	_refresh_combat_def()
	queue_redraw()
	return true


func apply_final_element(element_id: String) -> bool:
	if not can_final_upgrade():
		return false
	if not TowerData.is_final_element(element_id):
		return false
	var cost := final_upgrade_cost()
	final_element = element_id
	gold_invested += cost
	_refresh_combat_def()
	queue_redraw()
	return true


func _process(delta: float) -> void:
	if bool(def.get("is_wall", false)):
		return
	if bool(def.get("is_command", false)):
		_tick_ability_cooldowns(delta)
		queue_redraw()
		return
	if buff_time > 0.0:
		buff_time -= delta
		if buff_time <= 0.0:
			buff_time = 0.0
			buff_fire_mult = 1.0
	fire_cooldown = maxf(fire_cooldown - delta, 0.0)
	if fire_cooldown <= 0.0:
		var target := _find_target()
		if target:
			_fire_at(target)
			var rate := maxf(float(def.get("fire_rate", 1.0)) * maxf(buff_fire_mult, 0.05), 0.05)
			fire_cooldown = 1.0 / rate
	queue_redraw()


func _tick_ability_cooldowns(delta: float) -> void:
	if ability_cooldowns.is_empty():
		return
	var keys := ability_cooldowns.keys()
	for key in keys:
		var left := float(ability_cooldowns[key]) - delta
		if left <= 0.0:
			ability_cooldowns.erase(key)
		else:
			ability_cooldowns[key] = left


func ability_cooldown_left(ability_id: String) -> float:
	return maxf(float(ability_cooldowns.get(ability_id, 0.0)), 0.0)


func start_ability_cooldown(ability_id: String, seconds: float) -> void:
	ability_cooldowns[ability_id] = maxf(seconds, 0.0)


func apply_fire_buff(mult: float, duration: float) -> void:
	if bool(def.get("is_wall", false)) or bool(def.get("is_command", false)):
		return
	buff_fire_mult = maxf(buff_fire_mult, mult)
	buff_time = maxf(buff_time, duration)
	queue_redraw()


func _find_target() -> Enemy:
	var range_px: float = float(def.get("range", 100.0))
	var prefer_bosses := TowerData.prefers_bosses(def)
	var best: Enemy = null
	var best_score := -INF
	for child in enemy_container.get_children():
		if child is Enemy:
			var e := child as Enemy
			if not TowerData.can_target_enemy(def, e):
				continue
			if global_position.distance_to(e.global_position) > range_px:
				continue
			# Prefer enemies further along the path; boss-hunters hard-prefer bosses.
			var progress := float(e.path_index)
			if e.path.size() > 0:
				var idx := mini(e.path_index, e.path.size() - 1)
				progress += 1.0 - clampf(e.global_position.distance_to(e.path[idx]) / 40.0, 0.0, 1.0)
			var score := progress
			if prefer_bosses and e.is_boss:
				score += 1000.0
			if score > best_score:
				best_score = score
				best = e
	return best


func _fire_at(target: Enemy) -> void:
	var proj := Projectile.new()
	var effect: String = str(def.get("effect", "none"))
	var to_pos := target.global_position
	var aim := to_pos - global_position
	if aim.length_squared() > 0.001:
		_aim_dir = aim.normalized()
	proj.setup(
		target,
		float(def.get("damage", 1.0)),
		float(def.get("splash_radius", 0.0)),
		effect,
		def,
		enemy_container,
		def.get("color", Color.WHITE),
		float(def.get("projectile_speed", 320.0))
	)
	proj.global_position = global_position
	projectile_container.add_child(proj)
	if bool(def.get("melee", false)):
		proj.impact_now()
	if projectile_container != null:
		_AttackFx.try_spawn(
			effect,
			global_position,
			to_pos,
			float(def.get("range", 100.0)),
			projectile_container,
			target
		)


func set_selected(value: bool) -> void:
	selected = value
	queue_redraw()


func _draw() -> void:
	var color: Color = def.get("color", Color(0.6, 0.6, 0.6))
	if bool(def.get("is_wall", false)):
		draw_rect(Rect2(-18, -18, 36, 36), color)
		draw_rect(Rect2(-18, -18, 36, 36), Color(0.15, 0.14, 0.12), false, 2.0)
		draw_line(Vector2(-18, 0), Vector2(18, 0), Color(0.25, 0.23, 0.2), 1.5)
		draw_line(Vector2(0, -18), Vector2(0, 0), Color(0.25, 0.23, 0.2), 1.5)
		if selected:
			draw_rect(Rect2(-20, -20, 40, 40), SELECT_COLOR, false, 2.0)
			draw_arc(Vector2.ZERO, 24.0, 0.0, TAU, 40, SELECT_COLOR, 2.0)
		return
	draw_rect(Rect2(-14, -14, 28, 28), color)
	draw_rect(Rect2(-14, -14, 28, 28), Color(0.05, 0.05, 0.05), false, 2.0)
	if tower_id == "spike":
		draw_line(Vector2(-8, 8), Vector2(0, -10), Color(0.9, 0.85, 0.8), 2.0)
		draw_line(Vector2(0, 8), Vector2(6, -8), Color(0.9, 0.85, 0.8), 2.0)
		draw_line(Vector2(8, 8), Vector2(12, -4), Color(0.9, 0.85, 0.8), 2.0)
	elif tower_id == "antiair":
		draw_circle(Vector2(0, -2), 4.0, Color(0.85, 0.92, 1.0))
		draw_line(Vector2(-10, 6), Vector2(10, 6), Color(0.85, 0.92, 1.0), 2.0)
	elif tower_id == "gatling":
		draw_circle(Vector2(0, 0), 5.0, Color(0.2, 0.18, 0.16))
		draw_line(Vector2(-2, -2), Vector2(12, -6), Color(0.98, 0.75, 0.35), 2.2)
		draw_line(Vector2(-2, 0), Vector2(12, 0), Color(0.98, 0.75, 0.35), 2.2)
		draw_line(Vector2(-2, 2), Vector2(12, 6), Color(0.98, 0.75, 0.35), 2.2)
	elif tower_id == "command":
		draw_circle(Vector2.ZERO, 6.0, Color(0.9, 0.85, 0.35))
		draw_line(Vector2(0, -11), Vector2(0, 11), Color(0.95, 0.9, 0.55), 2.0)
		draw_line(Vector2(-11, 0), Vector2(11, 0), Color(0.95, 0.9, 0.55), 2.0)
	elif tower_id == "burn" or tower_id == "freeze":
		var nozzle := _aim_dir * 12.0
		var side := Vector2(-_aim_dir.y, _aim_dir.x) * 3.5
		var tip_color := Color(1.0, 0.55, 0.2) if tower_id == "burn" else Color(0.7, 0.9, 1.0)
		draw_line(-side, nozzle, tip_color, 2.0)
		draw_line(side, nozzle, tip_color, 2.0)
	# Upgrade pips along the bottom edge (Command / walls skip).
	if not bool(def.get("is_command", false)):
		for i in TowerData.MAX_STAT_UPGRADES:
			var pip_color := Color(0.95, 0.85, 0.35) if i < upgrade_level else Color(0.2, 0.2, 0.22)
			draw_rect(Rect2(-12 + i * 9, 10, 7, 3), pip_color)
	if buff_time > 0.0:
		draw_arc(Vector2.ZERO, 17.0, 0.0, TAU, 28, Color(0.55, 1.0, 0.55, 0.7), 2.0)
	if final_element != "":
		var accent := TowerData.final_element_color(final_element)
		draw_circle(Vector2(11, -11), 3.5, accent)
		draw_circle(Vector2(11, -11), 3.5, Color(0.05, 0.05, 0.05), false, 1.0)
	if selected:
		draw_arc(Vector2.ZERO, float(def.get("range", 100.0)), 0.0, TAU, 48, SELECT_COLOR_SOFT, 1.5)
		draw_rect(Rect2(-16, -16, 32, 32), SELECT_COLOR, false, 2.0)
		draw_arc(Vector2.ZERO, 20.0, 0.0, TAU, 40, SELECT_COLOR, 2.0)
