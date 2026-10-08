class_name TowerData
extends RefCounted

## Tunable tower definitions. Change costs/stats here, then re-run (F5).

const SELL_REFUND_RATIO := 0.5
## Three stat upgrades, then one final elemental buff (keeps tower identity).
const MAX_STAT_UPGRADES := 3
## Final upgrade ids (UI labels: Fire / Ice / Poison / Lightning).
const FINAL_ELEMENTS := ["burn", "freeze", "poison", "lightning"]
const FINAL_ELEMENT_LABELS := {
	"burn": "Fire",
	"freeze": "Ice",
	"poison": "Poison",
	"lightning": "Lightning",
}
const FINAL_ELEMENT_COLORS := {
	"burn": Color(0.95, 0.4, 0.2),
	"freeze": Color(0.45, 0.85, 1.0),
	"poison": Color(0.4, 0.9, 0.4),
	"lightning": Color(0.95, 0.85, 0.25),
}
## Bonus strength when the final element differs from the tower's own effect.
const FINAL_BONUS_STRENGTH := 0.45

const TYPES := {
	"wall": {
		"display_name": "Wall",
		"blurb": "Cheap maze piece. Blocks the path. Build any real tower on top. Cannot cover an existing tower.",
		"cost": 5,
		"damage": 0.0,
		"range": 0.0,
		"fire_rate": 0.0,
		"splash_radius": 0.0,
		"color": Color(0.42, 0.4, 0.38),
		"effect": "wall",
		"is_wall": true,
	},
	"gunner": {
		"display_name": "Gunner",
		"blurb": "Reliable single-target shooter. Slight bonus damage vs flying enemies.",
		"cost": 40,
		"damage": 8.0,
		"range": 120.0,
		"fire_rate": 1.2,
		"splash_radius": 0.0,
		"color": Color(0.55, 0.62, 0.72),
		"effect": "none",
		"air_damage_mult": 1.25,
	},
	"rapid": {
		"display_name": "Rapid",
		"blurb": "Fast low-damage fire. Strong anti-air for chipping flyers.",
		"cost": 55,
		"damage": 4.0,
		"range": 100.0,
		"fire_rate": 3.0,
		"splash_radius": 0.0,
		"color": Color(0.75, 0.75, 0.35),
		"effect": "none",
		"air_damage_mult": 1.6,
	},
	"cannon": {
		"display_name": "Cannon",
		"blurb": "Boss hunter. Massive bonus damage vs bosses; prioritizes them in range. Weaker vs air and normal creeps.",
		"cost": 75,
		"damage": 20.0,
		"range": 125.0,
		"fire_rate": 0.5,
		"splash_radius": 40.0,
		"color": Color(0.55, 0.4, 0.3),
		"effect": "none",
		"air_damage_mult": 0.55,
		"boss_damage_mult": 2.4,
		"creep_damage_mult": 0.8,
		"prefer_bosses": true,
	},
	"burn": {
		"display_name": "Burn",
		"blurb": "Ignites enemies for damage over time. Better vs ground than air.",
		"cost": 50,
		"damage": 6.0,
		"range": 115.0,
		"fire_rate": 1.0,
		"splash_radius": 0.0,
		"color": Color(0.9, 0.35, 0.15),
		"effect": "burn",
		"burn_dps": 4.0,
		"burn_duration": 3.0,
		"air_damage_mult": 0.7,
	},
	"freeze": {
		"display_name": "Freeze",
		"blurb": "Slows enemies on hit. Solid air damage for locking down flyers.",
		"cost": 60,
		"damage": 4.0,
		"range": 125.0,
		"fire_rate": 0.9,
		"splash_radius": 0.0,
		"color": Color(0.4, 0.75, 0.95),
		"effect": "freeze",
		"slow_factor": 0.45,
		"slow_duration": 2.0,
		"air_damage_mult": 1.4,
	},
	"poison": {
		"display_name": "Poison",
		"blurb": "Poison DoT with light splash. Slightly weaker vs air.",
		"cost": 70,
		"damage": 3.0,
		"range": 105.0,
		"fire_rate": 1.1,
		"splash_radius": 40.0,
		"color": Color(0.35, 0.8, 0.35),
		"effect": "poison",
		"poison_dps": 3.0,
		"poison_duration": 4.0,
		"air_damage_mult": 0.85,
	},
	"lightning": {
		"display_name": "Lightning",
		"blurb": "Chains across nearby enemies. Strong vs air.",
		"cost": 80,
		"damage": 12.0,
		"range": 130.0,
		"fire_rate": 0.8,
		"splash_radius": 0.0,
		"color": Color(0.85, 0.75, 0.2),
		"effect": "lightning",
		"chain_count": 3,
		"chain_range": 90.0,
		"chain_falloff": 0.7,
		"air_damage_mult": 2.0,
	},
	"spike": {
		"display_name": "Spike",
		"blurb": "Melee ground spikes. High damage, very short range. Cannot hit flying enemies.",
		"cost": 45,
		"damage": 18.0,
		"range": 52.0,
		"fire_rate": 1.35,
		"splash_radius": 0.0,
		"color": Color(0.72, 0.55, 0.48),
		"effect": "none",
		"melee": true,
		"target_filter": "ground",
		"air_damage_mult": 0.0,
		"ground_damage_mult": 1.0,
	},
	"antiair": {
		"display_name": "Anti-Air",
		"blurb": "Flak turret. Only targets flying enemies. Long range, solid fire rate.",
		"cost": 65,
		"damage": 11.0,
		"range": 160.0,
		"fire_rate": 1.6,
		"splash_radius": 0.0,
		"color": Color(0.55, 0.7, 0.85),
		"effect": "none",
		"target_filter": "air",
		"air_damage_mult": 1.0,
		"ground_damage_mult": 0.0,
	},
	"gatling": {
		"display_name": "Gatling",
		"blurb": "Late-game special. Extreme fire rate shreds lanes. One tile — build other towers around it. Unlocks at wave 30.",
		"cost": 25000,
		"damage": 14.0,
		"range": 135.0,
		"fire_rate": 18.0,
		"splash_radius": 0.0,
		"color": Color(0.95, 0.55, 0.2),
		"effect": "none",
		"projectile_speed": 1100.0,
		"air_damage_mult": 1.2,
		"unlock_wave": 30,
	},
	"command": {
		"display_name": "Command",
		"blurb": "Support hub. Does not shoot. Click it, then buy an ability each time you want to use it (Air Strike, Supply Drop, Barricade, Flare).",
		"cost": 100,
		"damage": 0.0,
		"range": 0.0,
		"fire_rate": 0.0,
		"splash_radius": 0.0,
		"color": Color(0.55, 0.62, 0.38),
		"effect": "none",
		"is_command": true,
	},
}


static func get_ids() -> Array:
	return ["wall", "gunner", "rapid", "cannon", "burn", "freeze", "poison", "lightning", "spike", "antiair", "gatling", "command"]


static func get_def(tower_id: String) -> Dictionary:
	return TYPES.get(tower_id, TYPES["gunner"])


static func is_wall(tower_id: String) -> bool:
	return bool(get_def(tower_id).get("is_wall", false))


static func is_command(tower_id: String) -> bool:
	return bool(get_def(tower_id).get("is_command", false))


## Wave number when the shop unlocks this tower (0 / missing = always available).
static func unlock_wave(tower_id: String) -> int:
	return int(get_def(tower_id).get("unlock_wave", 0))


static func is_unlocked(tower_id: String, current_wave: int) -> bool:
	var need := unlock_wave(tower_id)
	if need <= 0:
		return true
	return current_wave >= need


static func sell_value(tower_id: String) -> int:
	var def := get_def(tower_id)
	return int(floor(float(def["cost"]) * SELL_REFUND_RATIO))


static func sell_value_for_tower(tower: Tower) -> int:
	if tower == null:
		return 0
	var base_cost := int(get_def(tower.tower_id).get("cost", 0))
	return int(floor(float(base_cost + tower.gold_invested) * SELL_REFUND_RATIO))


static func can_upgrade_tower(tower: Tower) -> bool:
	if tower == null or is_wall(tower.tower_id) or is_command(tower.tower_id):
		return false
	return tower.upgrade_level < MAX_STAT_UPGRADES


static func can_apply_final(tower: Tower) -> bool:
	if tower == null or is_wall(tower.tower_id) or is_command(tower.tower_id):
		return false
	return tower.upgrade_level >= MAX_STAT_UPGRADES and tower.final_element == ""


static func is_final_element(element_id: String) -> bool:
	return element_id in FINAL_ELEMENTS


static func final_element_label(element_id: String) -> String:
	return str(FINAL_ELEMENT_LABELS.get(element_id, element_id.capitalize()))


static func final_element_color(element_id: String) -> Color:
	return FINAL_ELEMENT_COLORS.get(element_id, Color(1, 1, 1))


## Gold to buy the next stat upgrade (from current level → level+1).
static func stat_upgrade_cost(tower_id: String, current_level: int) -> int:
	if current_level < 0 or current_level >= MAX_STAT_UPGRADES or is_wall(tower_id):
		return 0
	var base := int(get_def(tower_id).get("cost", 0))
	return maxi(int(round(float(base) * (0.45 + float(current_level) * 0.25))), 1)


static func final_upgrade_cost(tower_id: String) -> int:
	if is_wall(tower_id):
		return 0
	var base := int(get_def(tower_id).get("cost", 0))
	return maxi(int(round(float(base) * 1.25)), 1)


static func combat_def(tower_id: String, upgrade_level: int, final_element: String = "") -> Dictionary:
	var d: Dictionary = get_def(tower_id).duplicate(true)
	if bool(d.get("is_wall", false)) or bool(d.get("is_command", false)):
		return d
	var level := clampi(upgrade_level, 0, MAX_STAT_UPGRADES)
	for _i in level:
		d["damage"] = float(d.get("damage", 0.0)) * 1.18
		d["range"] = float(d.get("range", 0.0)) * 1.06
		d["fire_rate"] = float(d.get("fire_rate", 0.0)) * 1.08
		var splash := float(d.get("splash_radius", 0.0))
		if splash > 0.0:
			d["splash_radius"] = splash * 1.05
		if d.has("burn_dps"):
			d["burn_dps"] = float(d["burn_dps"]) * 1.12
		if d.has("poison_dps"):
			d["poison_dps"] = float(d["poison_dps"]) * 1.12
		if d.has("chain_count"):
			# Tiny chance to gain a chain link every other upgrade.
			pass
	if level >= 2 and d.has("chain_count"):
		d["chain_count"] = int(d["chain_count"]) + 1
	if final_element != "" and is_final_element(final_element):
		_apply_final_element(d, final_element)
	return d


## Adds a light elemental buff. Never replaces the tower's primary effect/color.
static func _apply_final_element(d: Dictionary, element_id: String) -> void:
	var src := get_def(element_id)
	var primary := str(d.get("effect", "none"))
	d["final_element"] = element_id
	match element_id:
		"burn":
			if primary == "burn":
				d["burn_dps"] = float(d.get("burn_dps", 4.0)) * 1.2
				d["burn_duration"] = float(d.get("burn_duration", 3.0)) * 1.1
			else:
				d["bonus_burn_dps"] = float(src.get("burn_dps", 4.0)) * FINAL_BONUS_STRENGTH
				d["bonus_burn_duration"] = float(src.get("burn_duration", 3.0)) * 0.8
		"freeze":
			if primary == "freeze":
				d["slow_factor"] = maxf(float(d.get("slow_factor", 0.45)) * 0.85, 0.3)
				d["slow_duration"] = float(d.get("slow_duration", 2.0)) * 1.15
			else:
				# Higher factor = milder slow.
				d["bonus_slow_factor"] = 0.72
				d["bonus_slow_duration"] = float(src.get("slow_duration", 2.0)) * 0.65
		"poison":
			if primary == "poison":
				d["poison_dps"] = float(d.get("poison_dps", 3.0)) * 1.2
				d["poison_duration"] = float(d.get("poison_duration", 4.0)) * 1.1
			else:
				d["bonus_poison_dps"] = float(src.get("poison_dps", 3.0)) * FINAL_BONUS_STRENGTH
				d["bonus_poison_duration"] = float(src.get("poison_duration", 4.0)) * 0.75
		"lightning":
			if primary == "lightning":
				d["chain_count"] = int(d.get("chain_count", 3)) + 1
				d["chain_range"] = float(d.get("chain_range", 90.0)) * 1.1
				d["air_damage_mult"] = float(d.get("air_damage_mult", 1.0)) * 1.1
			else:
				d["bonus_chain_count"] = 2
				d["bonus_chain_range"] = float(src.get("chain_range", 90.0)) * 0.75
				d["bonus_chain_falloff"] = float(src.get("chain_falloff", 0.7))
				d["air_damage_mult"] = float(d.get("air_damage_mult", 1.0)) * 1.15


## "any" (default), "ground", or "air".
static func target_filter(def: Dictionary) -> String:
	return str(def.get("target_filter", "any"))


static func can_target_enemy(def: Dictionary, enemy: Enemy) -> bool:
	if enemy == null or not is_instance_valid(enemy) or not enemy.alive:
		return false
	match target_filter(def):
		"ground":
			return not enemy.is_flying
		"air":
			return enemy.is_flying
		_:
			return true


## Multiplier vs air/ground and boss/creep. Defaults to 1.0 when unset.
static func target_damage_mult(def: Dictionary, is_flying: bool, is_boss: bool = false) -> float:
	match target_filter(def):
		"ground":
			if is_flying:
				return 0.0
		"air":
			if not is_flying:
				return 0.0
	var mult := 1.0
	if is_flying:
		mult *= float(def.get("air_damage_mult", 1.0))
	else:
		mult *= float(def.get("ground_damage_mult", 1.0))
	if is_boss:
		mult *= float(def.get("boss_damage_mult", 1.0))
	else:
		mult *= float(def.get("creep_damage_mult", 1.0))
	return mult


static func prefers_bosses(def: Dictionary) -> bool:
	return bool(def.get("prefer_bosses", false)) or float(def.get("boss_damage_mult", 1.0)) >= 1.5


## Hover text for shop buttons / placed-tower hints.
static func tooltip_for(tower_id: String, upgrade_level: int = 0, final_element: String = "") -> String:
	var def := combat_def(tower_id, upgrade_level, final_element)
	var base := get_def(tower_id)
	var lines: PackedStringArray = PackedStringArray()
	var title := str(base.get("display_name", tower_id))
	if upgrade_level > 0 or final_element != "":
		title += "  [+%d" % upgrade_level
		if final_element != "":
			title += "/%s" % final_element_label(final_element)
		title += "]"
	lines.append("%s — %d gold (sell %d)" % [
		title,
		int(base.get("cost", 0)),
		sell_value(tower_id),
	])
	var blurb := str(base.get("blurb", "")).strip_edges()
	if blurb != "":
		lines.append(blurb)
	var need_wave := unlock_wave(tower_id)
	if need_wave > 0:
		lines.append("Unlocks at wave %d" % need_wave)
	if bool(base.get("is_wall", false)) or bool(base.get("is_command", false)):
		if bool(base.get("is_command", false)):
			lines.append("No auto-fire. Select this tower, then buy an ability each use.")
		return "\n".join(lines)

	lines.append("Upgrades: %d/%d stat + final elemental buff" % [upgrade_level, MAX_STAT_UPGRADES])
	lines.append("Damage %.0f  |  Range %.0f  |  Rate %.1f/s" % [
		float(def.get("damage", 0.0)),
		float(def.get("range", 0.0)),
		float(def.get("fire_rate", 0.0)),
	])
	var splash := float(def.get("splash_radius", 0.0))
	if splash > 0.0:
		lines.append("Splash radius %.0f" % splash)
	if bool(def.get("melee", false)):
		lines.append("Melee (instant hit)")
	match target_filter(def):
		"ground":
			lines.append("Ground only — cannot hit air")
		"air":
			lines.append("Air only — cannot hit ground")

	match str(def.get("effect", "none")):
		"burn":
			lines.append("Burn %.0f DPS for %.1fs" % [
				float(def.get("burn_dps", 0.0)),
				float(def.get("burn_duration", 0.0)),
			])
		"freeze":
			lines.append("Slow to %.0f%% speed for %.1fs" % [
				float(def.get("slow_factor", 1.0)) * 100.0,
				float(def.get("slow_duration", 0.0)),
			])
		"poison":
			lines.append("Poison %.0f DPS for %.1fs" % [
				float(def.get("poison_dps", 0.0)),
				float(def.get("poison_duration", 0.0)),
			])
		"lightning":
			lines.append("Chains %d (range %.0f, %.0f%% falloff)" % [
				int(def.get("chain_count", 0)),
				float(def.get("chain_range", 0.0)),
				float(def.get("chain_falloff", 1.0)) * 100.0,
			])

	_append_final_buff_lines(lines, def)

	var air := float(def.get("air_damage_mult", 1.0))
	var ground := float(def.get("ground_damage_mult", 1.0))
	if not is_equal_approx(air, 1.0) or not is_equal_approx(ground, 1.0):
		lines.append("Air x%.2f  |  Ground x%.2f" % [air, ground])
	var boss := float(def.get("boss_damage_mult", 1.0))
	var creep := float(def.get("creep_damage_mult", 1.0))
	if not is_equal_approx(boss, 1.0) or not is_equal_approx(creep, 1.0):
		lines.append("Boss x%.2f  |  Creep x%.2f" % [boss, creep])
	if prefers_bosses(def):
		lines.append("Prioritizes bosses in range")
	if can_upgrade_tower_id(tower_id, upgrade_level):
		lines.append("Next upgrade: %d gold" % stat_upgrade_cost(tower_id, upgrade_level))
	elif upgrade_level >= MAX_STAT_UPGRADES and final_element == "":
		lines.append("Final ready: Fire / Ice / Poison / Lightning buff (%d gold)" % final_upgrade_cost(tower_id))
	return "\n".join(lines)


static func _append_final_buff_lines(lines: PackedStringArray, def: Dictionary) -> void:
	var fe := str(def.get("final_element", ""))
	if fe == "":
		return
	var label := final_element_label(fe)
	var primary := str(def.get("effect", "none"))
	if fe == primary:
		lines.append("%s final: strengthened %s" % [label, label.to_lower()])
		return
	if def.has("bonus_burn_dps"):
		lines.append("Fire buff: %.0f burn DPS for %.1fs" % [
			float(def.get("bonus_burn_dps", 0.0)),
			float(def.get("bonus_burn_duration", 0.0)),
		])
	if def.has("bonus_slow_factor"):
		lines.append("Ice buff: slow to %.0f%% for %.1fs" % [
			float(def.get("bonus_slow_factor", 1.0)) * 100.0,
			float(def.get("bonus_slow_duration", 0.0)),
		])
	if def.has("bonus_poison_dps"):
		lines.append("Poison buff: %.0f DPS for %.1fs" % [
			float(def.get("bonus_poison_dps", 0.0)),
			float(def.get("bonus_poison_duration", 0.0)),
		])
	if int(def.get("bonus_chain_count", 0)) > 0:
		lines.append("Lightning buff: chains %d" % int(def.get("bonus_chain_count", 0)))


static func can_upgrade_tower_id(tower_id: String, upgrade_level: int) -> bool:
	if is_wall(tower_id):
		return false
	return upgrade_level < MAX_STAT_UPGRADES


static func tooltip_for_tower(tower: Tower) -> String:
	if tower == null:
		return ""
	var text := tooltip_for(tower.tower_id, tower.upgrade_level, tower.final_element)
	if tower.gold_invested > 0:
		text += "\nInvested upgrades: %d gold (sell %d)" % [
			tower.gold_invested,
			sell_value_for_tower(tower),
		]
	return text
