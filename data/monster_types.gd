class_name MonsterTypes
extends RefCounted

## Randomize-mode monster roster and elemental resist growth.

const ELEMENTS := ["burn", "freeze", "poison", "lightning"]
## Slight resist strength (damage / effect reduction).
const RESIST_STRENGTH := 0.25
## Wave thresholds for how many resists each creep carries (Randomize only).
const RESISTS_AT_WAVE_2 := 16
const RESISTS_AT_WAVE_3 := 30
const RESISTS_AT_WAVE_4 := 50

const TYPES := {
	"ember": {
		"display_name": "Ember",
		"color": Color(0.95, 0.4, 0.2),
		"affinity": ["burn"],
		"flying_bias": 0.0,
	},
	"frost": {
		"display_name": "Frost",
		"color": Color(0.45, 0.8, 1.0),
		"affinity": ["freeze"],
		"flying_bias": 0.15,
	},
	"venom": {
		"display_name": "Venom",
		"color": Color(0.4, 0.85, 0.35),
		"affinity": ["poison"],
		"flying_bias": 0.0,
	},
	"spark": {
		"display_name": "Spark",
		"color": Color(0.95, 0.85, 0.25),
		"affinity": ["lightning"],
		"flying_bias": 0.35,
	},
	"brute": {
		"display_name": "Brute",
		"color": Color(0.7, 0.45, 0.55),
		"affinity": [],
		"flying_bias": 0.0,
	},
}


static func get_ids() -> Array:
	return ["ember", "frost", "venom", "spark", "brute"]


static func get_def(type_id: String) -> Dictionary:
	return TYPES.get(type_id, TYPES["brute"])


static func display_name(type_id: String) -> String:
	return str(get_def(type_id).get("display_name", type_id.capitalize()))


static func tint_color(type_id: String) -> Color:
	return get_def(type_id).get("color", Color(0.85, 0.35, 0.35))


## How many elemental resists a creep should have at this wave (1–4).
static func resist_slot_count(wave: int) -> int:
	if wave >= RESISTS_AT_WAVE_4:
		return 4
	if wave >= RESISTS_AT_WAVE_3:
		return 3
	if wave >= RESISTS_AT_WAVE_2:
		return 2
	return 1


## Pick a type for a spawn. Flying creeps slightly prefer spark/frost.
static func pick_type(rng: RandomNumberGenerator, flying: bool) -> String:
	var ids := get_ids()
	if not flying:
		return ids[rng.randi_range(0, ids.size() - 1)]
	var weights: Array[float] = []
	var total := 0.0
	for id in ids:
		var w := 1.0 + float(get_def(id).get("flying_bias", 0.0)) * 3.0
		weights.append(w)
		total += w
	var roll := rng.randf() * total
	var acc := 0.0
	for i in ids.size():
		acc += weights[i]
		if roll <= acc:
			return ids[i]
	return ids[ids.size() - 1]


## Build resist map for a type at a given wave. Affinity elements first, then random fill.
static func build_resists(type_id: String, wave: int, rng: RandomNumberGenerator) -> Dictionary:
	var slots := resist_slot_count(wave)
	var chosen: Array[String] = []
	var def := get_def(type_id)
	var affinity: Array = def.get("affinity", [])
	for el in affinity:
		var key := str(el)
		if key in ELEMENTS and key not in chosen:
			chosen.append(key)
			if chosen.size() >= slots:
				break
	var pool: Array[String] = []
	for el in ELEMENTS:
		if el not in chosen:
			pool.append(el)
	while chosen.size() < slots and not pool.is_empty():
		var idx := rng.randi_range(0, pool.size() - 1)
		chosen.append(pool[idx])
		pool.remove_at(idx)
	var resists := {}
	for el in ELEMENTS:
		resists[el] = RESIST_STRENGTH if el in chosen else 0.0
	return resists


static func empty_resists() -> Dictionary:
	var resists := {}
	for el in ELEMENTS:
		resists[el] = 0.0
	return resists
