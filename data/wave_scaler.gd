class_name WaveScaler
extends RefCounted

## Endless wave formulas. Tune freely, then re-run (F5).

enum Difficulty { EASY, MEDIUM, HARD, CHEATER }
enum GameMode { CLASSIC, RANDOM, SIEGE, CLASH }
## Independent of map mode: Classic spawns (no resists) vs Randomize elemental types.
enum MonsterMode { CLASSIC, RANDOMIZE }
## Classic map setup: fixed corridor vs seeded random layout (fixed for the run).
enum MapLayoutMode { STANDARD, CUSTOM }

const STARTING_GOLD_EASY := 350
const STARTING_GOLD_MEDIUM := 200
const STARTING_GOLD_HARD := 100
## Default / Medium starting gold (kept for older call sites and smoke tests).
const STARTING_GOLD := STARTING_GOLD_MEDIUM
const STARTING_LIVES := 20
## After this wave number, pay to slide spawn/exit left/right on their row.
const PORTAL_SLIDE_UNLOCK_WAVE := 10
const PORTAL_SLIDE_COST := 200
## Random mode: new map after these wave clears (25, 50, 75…).
const MAP_ROTATE_EVERY := 25
## Siege mode: move outer-rim spawn after these wave clears (5, 10, 15…).
const SPAWN_ROTATE_EVERY := 5
## Gold granted on map rotate from kills earned on the previous map.
const MAP_ROTATE_GOLD_PER_KILL := 3


static func starting_gold_for(difficulty: int) -> int:
	match difficulty:
		Difficulty.EASY:
			return STARTING_GOLD_EASY
		Difficulty.HARD:
			return STARTING_GOLD_HARD
		_:
			return STARTING_GOLD_MEDIUM


static func difficulty_label(difficulty: int) -> String:
	match difficulty:
		Difficulty.EASY:
			return "Easy"
		Difficulty.HARD:
			return "Hard"
		Difficulty.CHEATER:
			return "Cheater"
		_:
			return "Medium"


static func is_cheater_bot(difficulty: int) -> bool:
	return difficulty == Difficulty.CHEATER


static func mode_label(mode: int) -> String:
	match mode:
		GameMode.RANDOM:
			return "Random"
		GameMode.SIEGE:
			return "Siege"
		GameMode.CLASH:
			return "Clash"
		_:
			return "Classic"


static func monster_mode_label(mode: int) -> String:
	match mode:
		MonsterMode.RANDOMIZE:
			return "Randomize"
		_:
			return "Classic"


static func is_random_mode(mode: int) -> bool:
	return mode == GameMode.RANDOM


static func is_siege_mode(mode: int) -> bool:
	return mode == GameMode.SIEGE


static func is_clash_mode(mode: int) -> bool:
	return mode == GameMode.CLASH


static func is_randomize_monsters(mode: int) -> bool:
	return mode == MonsterMode.RANDOMIZE


static func should_rotate_map_after_wave(mode: int, wave: int) -> bool:
	return is_random_mode(mode) and wave > 0 and wave % MAP_ROTATE_EVERY == 0


static func should_rotate_spawn_after_wave(mode: int, wave: int) -> bool:
	return is_siege_mode(mode) and wave > 0 and wave % SPAWN_ROTATE_EVERY == 0


static func is_custom_layout(layout_mode: int) -> bool:
	return layout_mode == MapLayoutMode.CUSTOM


## Parse a seed field. Empty → -1 (caller should roll). Digits → int. Other text → stable hash.
static func parse_seed_text(text: String) -> int:
	var t := text.strip_edges()
	if t.is_empty():
		return -1
	if t.is_valid_int():
		return maxi(absi(t.to_int()), 0)
	return absi(int(t.hash()))


static func roll_seed() -> int:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	return int(rng.randi() % 1_000_000_000)


## Resolve a user/empty seed into a concrete non-negative run seed.
static func resolve_run_seed(seed_or_neg: int) -> int:
	if seed_or_neg < 0:
		return roll_seed()
	return seed_or_neg


## Deterministic layout seed for Random map sector (1-based).
static func sector_seed(run_seed: int, map_sector: int) -> int:
	var sector := maxi(map_sector, 1)
	var mixed := run_seed * 10007 + sector * 9176 + 13
	return absi(int(mixed)) % 1_000_000_000


static func map_rotate_gold(difficulty: int, kills_on_map: int) -> int:
	var base := starting_gold_for(difficulty)
	var from_kills := maxi(kills_on_map, 0) * MAP_ROTATE_GOLD_PER_KILL
	return maxi(base, from_kills)


## Flat gold per kill awarded when the wave is fully cleared (tunable).
const WAVE_CLEAR_BONUS_PER_KILL := 4
## Auto-wave timers (seconds).
const INITIAL_BUILD_TIME := 20.0
const INTERMISSION_TIME := 12.0
## Fraction of wave enemies that must be killed before early-send / skip unlocks.
const SKIP_TIMER_KILL_RATIO := 0.25
## Gold for sending the next wave while enemies from the current wave remain.
const EARLY_SEND_BASE_GOLD := 12
const EARLY_SEND_GOLD_PER_ALIVE := 1
## Gold per second left when skipping the post-wave / build timer.
const EARLY_SEND_GOLD_PER_TIMER_SEC := 2
## After this wave, every wave mixes flying creeps with ground.
const MIXED_AIR_AFTER_WAVE := 20
## First wave that can spawn light flying scout creeps (before full mix).
const EARLY_AIR_SCOUT_WAVE := 8
## Flying share of creeps after the mix starts (ramps up, then caps).
const MIXED_AIR_RATIO_START := 0.18
const MIXED_AIR_RATIO_PER_WAVE := 0.01
const MIXED_AIR_RATIO_MAX := 0.4
## Super-speedy waves (glassier, much faster, denser spawns).
const SPEED_WAVE_FIRST := 7
const SPEED_WAVE_INTERVAL := 7
const SPEED_WAVE_SPEED_MULT := 2.2
const SPEED_WAVE_HP_MULT := 0.65
const SPEED_WAVE_SPAWN_MULT := 0.4
const SPEED_WAVE_MAX_SPEED := 230.0


static func is_speed_wave(wave: int) -> bool:
	return wave >= SPEED_WAVE_FIRST and wave % SPEED_WAVE_INTERVAL == 0


static func creep_count(wave: int) -> int:
	var count := mini(8 + wave, 40)
	# Speed waves pack a few extra runners.
	if is_speed_wave(wave):
		count = mini(count + 4, 44)
	return count


static func flying_creep_count(wave: int) -> int:
	if wave <= 0:
		return 0
	var total := creep_count(wave)
	# Full mix: every wave after the threshold includes air creeps.
	if wave > MIXED_AIR_AFTER_WAVE:
		var ratio := clampf(
			MIXED_AIR_RATIO_START + float(wave - MIXED_AIR_AFTER_WAVE) * MIXED_AIR_RATIO_PER_WAVE,
			MIXED_AIR_RATIO_START,
			MIXED_AIR_RATIO_MAX
		)
		return clampi(int(round(float(total) * ratio)), 1, total - 1)
	# Early scouts so air shows up well before wave 20 / 50.
	if wave >= EARLY_AIR_SCOUT_WAVE:
		if wave % 15 == 0:
			# Flying-boss waves also get a few air creeps in the pack.
			return clampi(2 + int(wave / 20), 2, total - 1)
		if wave % 5 == 0 or wave % 2 == 0:
			return 1
	return 0


static func ground_creep_count(wave: int) -> int:
	return creep_count(wave) - flying_creep_count(wave)


static func creep_hp(wave: int) -> float:
	var hp := 20.0 + wave * 8.0 + pow(float(wave), 1.35) * 2.0
	if is_speed_wave(wave):
		hp *= SPEED_WAVE_HP_MULT
	return hp


static func creep_speed(wave: int) -> float:
	var speed := minf(60.0 + wave * 1.5, 140.0)
	if is_speed_wave(wave):
		speed = minf(speed * SPEED_WAVE_SPEED_MULT, SPEED_WAVE_MAX_SPEED)
	return speed


static func creep_bounty(wave: int) -> int:
	var bounty := 5 + int(wave / 2)
	if is_speed_wave(wave):
		bounty += 1
	return bounty


static func boss_count(wave: int) -> int:
	if wave <= 0:
		return 0
	if wave % 50 == 0:
		return 2
	if wave % 10 == 0:
		return 1
	return 0


static func boss_hp(wave: int) -> float:
	return creep_hp(wave) * 12.0


static func boss_speed(wave: int) -> float:
	# Boss speed uses base creep pacing so speed waves don't make bosses absurd.
	var base := minf(60.0 + wave * 1.5, 140.0)
	var speed := maxf(base * 0.55, 35.0)
	if is_speed_wave(wave):
		speed = minf(speed * 1.35, 120.0)
	return speed


static func boss_bounty(wave: int) -> int:
	return creep_bounty(wave) * 15


static func flying_creep_hp(wave: int) -> float:
	# Glassier than ground — air already skips maze pathing.
	return creep_hp(wave) * 0.7


static func flying_creep_speed(wave: int) -> float:
	var cap := SPEED_WAVE_MAX_SPEED if is_speed_wave(wave) else 160.0
	return minf(creep_speed(wave) * 1.05, cap)


static func flying_creep_bounty(wave: int) -> int:
	return creep_bounty(wave) + 2


static func flying_boss_count(wave: int) -> int:
	if wave > 0 and wave % 15 == 0:
		return 1
	return 0


static func flying_boss_hp(wave: int) -> float:
	return creep_hp(wave) * 8.5


static func flying_boss_speed(wave: int) -> float:
	var base := minf(60.0 + wave * 1.5, 140.0)
	var speed := maxf(base * 0.65, 42.0)
	if is_speed_wave(wave):
		speed = minf(speed * 1.4, 150.0)
	return speed


static func flying_boss_bounty(wave: int) -> int:
	return creep_bounty(wave) * 18


## Chance a boss wave becomes a ground "snake" chain instead of the normal mix.
const SNAKE_BOSS_CHANCE := 0.35
## Spacing between snake segments along the path (world pixels).
const SNAKE_SPACING := 28.0
## How quickly segments pour out after the head (keeps the chain tight).
const SNAKE_SPAWN_INTERVAL := 0.07
const SNAKE_BODY_HP_MULT := 1.3
const SNAKE_HEAD_HP_MULT := 0.85
const SNAKE_SPEED_MULT := 0.9


static func is_boss_wave(wave: int) -> bool:
	return boss_count(wave) > 0 or flying_boss_count(wave) > 0


static func roll_snake_boss(wave: int, rng: RandomNumberGenerator) -> bool:
	if not is_boss_wave(wave) or rng == null:
		return false
	return rng.randf() < SNAKE_BOSS_CHANCE


## Every mob that would have been on the wave, as one ground chain.
static func snake_segment_count(wave: int) -> int:
	return creep_count(wave) + boss_count(wave) + flying_boss_count(wave)


static func snake_body_hp(wave: int) -> float:
	return creep_hp(wave) * SNAKE_BODY_HP_MULT


static func snake_head_hp(wave: int) -> float:
	# Head is still a tank, but slightly under a full ground boss so the long body carries the threat.
	return boss_hp(wave) * SNAKE_HEAD_HP_MULT


static func snake_speed(wave: int) -> float:
	return maxf(boss_speed(wave) * SNAKE_SPEED_MULT, 32.0)


static func snake_body_bounty(wave: int) -> int:
	return creep_bounty(wave) + 2


static func snake_head_bounty(wave: int) -> int:
	return boss_bounty(wave)


static func snake_spawn_interval() -> float:
	return SNAKE_SPAWN_INTERVAL


static func spawn_interval(wave: int) -> float:
	var interval := maxf(0.55 - wave * 0.005, 0.2)
	if is_speed_wave(wave):
		interval = maxf(interval * SPEED_WAVE_SPAWN_MULT, 0.08)
	return interval


static func boss_banner(wave: int, is_snake: bool = false) -> String:
	var parts: PackedStringArray = PackedStringArray()
	if is_speed_wave(wave):
		parts.append("SPEED WAVE")
	if is_snake:
		parts.append("SNAKE")
		return " + ".join(parts)
	var bosses := boss_count(wave)
	if bosses >= 2:
		parts.append("DOUBLE BOSS")
	elif bosses == 1:
		parts.append("BOSS WAVE")
	if flying_boss_count(wave) > 0:
		parts.append("FLYING BOSS")
	elif flying_creep_count(wave) > 0 and not is_speed_wave(wave):
		parts.append("AIR MIX")
	elif flying_creep_count(wave) > 0 and is_speed_wave(wave):
		parts.append("AIR")
	return " + ".join(parts)


static func wave_clear_bonus(kills: int, wave: int) -> int:
	if kills <= 0:
		return 0
	# Scales lightly with wave so late clears stay rewarding.
	var per_kill := WAVE_CLEAR_BONUS_PER_KILL + int(wave / 10)
	return kills * per_kill


static func early_send_bonus_from_alive(wave: int, enemies_alive: int) -> int:
	var alive := maxi(enemies_alive, 0)
	return EARLY_SEND_BASE_GOLD + alive * EARLY_SEND_GOLD_PER_ALIVE + int(wave / 10)


static func early_send_bonus_from_timer(seconds_left: float) -> int:
	var secs := maxi(int(ceil(seconds_left)), 0)
	if secs <= 0:
		return 0
	return maxi(secs * EARLY_SEND_GOLD_PER_TIMER_SEC, EARLY_SEND_BASE_GOLD)


## --- Clash mode (lanes vs AI) ---
const CLASH_MIN_PLAYERS := 2
const CLASH_MAX_PLAYERS := 4
## Enough for a full 7×15 one-tile maze in walls (~55×5) plus a little send reserve.
const CLASH_STARTING_GOLD := 320
const CLASH_STARTING_LIVES := STARTING_LIVES
## Cheater bot: stacked on top of normal Clash start (endless-fight handicap).
const CLASH_CHEATER_EXTRA_GOLD := 500
const CLASH_CHEATER_EXTRA_LIVES := 100
## When lives drop to this, cheater slowly regenerates toward HEAL_TARGET.
const CLASH_CHEATER_HEAL_TRIGGER := 10
const CLASH_CHEATER_HEAL_TARGET := 50
## Seconds per +1 life while healing.
const CLASH_CHEATER_HEAL_INTERVAL := 2.5
const CLASH_BASE_INCOME := 10
## Fallback income bump if a pack omits income_bump.
const CLASH_SEND_INCOME_BUMP := 2
## Human send-shop levels (1–4). Bots ignore level gates.
const CLASH_SEND_SHOP_MAX_LEVEL := 4
## Cost to upgrade from level key → key+1.
const CLASH_SEND_SHOP_UPGRADE_COSTS := {1: 1500, 2: 5000, 3: 15000}
## Slightly lighter base packs so multi-lane boards stay readable.
const CLASH_CREEP_COUNT_MULT := 0.75

## Send package ids → cost / creep count / permanent income bump (paid every round).
## min_shop_level gates human unlocks; bots may buy any pack.
const CLASH_SEND_PACKS := {
	"scout": {
		"label": "Scout x3", "cost": 40, "count": 3, "hp_mult": 0.7, "speed_mult": 1.15,
		"bounty_mult": 0.6, "income_bump": 2, "min_shop_level": 1,
	},
	"pack": {
		"label": "Pack x6", "cost": 80, "count": 6, "hp_mult": 1.0, "speed_mult": 1.0,
		"bounty_mult": 0.8, "income_bump": 4, "min_shop_level": 1,
	},
	"brute": {
		"label": "Brute x2", "cost": 120, "count": 2, "hp_mult": 2.2, "speed_mult": 0.85,
		"bounty_mult": 1.2, "income_bump": 6, "min_shop_level": 1,
	},
	"raid": {
		"label": "Raid x10", "cost": 200, "count": 10, "hp_mult": 1.1, "speed_mult": 1.05,
		"bounty_mult": 0.75, "income_bump": 10, "min_shop_level": 2,
	},
	"juggernaut": {
		"label": "Juggernaut x3", "cost": 280, "count": 3, "hp_mult": 3.0, "speed_mult": 0.75,
		"bounty_mult": 1.3, "income_bump": 12, "min_shop_level": 2,
	},
	"strikers": {
		"label": "Strikers x8", "cost": 220, "count": 8, "hp_mult": 0.85, "speed_mult": 1.35,
		"bounty_mult": 0.7, "income_bump": 11, "min_shop_level": 2,
	},
	"warlord": {
		"label": "Warlord x1", "cost": 450, "count": 1, "boss": true, "hp_mult": 1.0, "speed_mult": 1.0,
		"bounty_mult": 1.0, "income_bump": 18, "min_shop_level": 3,
	},
	"skirmisher": {
		"label": "Skirmisher x1", "cost": 300, "count": 1, "flying": true, "hp_mult": 1.2, "speed_mult": 1.1,
		"bounty_mult": 1.0, "income_bump": 14, "min_shop_level": 3,
	},
	"golem": {
		"label": "Golem x1", "cost": 400, "count": 1, "hp_mult": 4.5, "speed_mult": 0.65,
		"bounty_mult": 1.5, "income_bump": 16, "min_shop_level": 3,
	},
	"air_wing": {
		"label": "Air Wing x10", "cost": 900, "count": 10, "flying": true, "hp_mult": 1.0, "speed_mult": 1.0,
		"bounty_mult": 0.9, "income_bump": 28, "min_shop_level": 4,
	},
	"war_council": {
		"label": "War Council x3", "cost": 1200, "count": 3, "boss": true, "hp_mult": 1.0, "speed_mult": 1.0,
		"bounty_mult": 1.0, "income_bump": 35, "min_shop_level": 4,
	},
	"wrecker": {
		"label": "Wrecker x1", "cost": 1000, "count": 1, "wrecker": true, "hp_mult": 3.8, "speed_mult": 0.7,
		"bounty_mult": 1.4, "income_bump": 30, "min_shop_level": 4,
	},
}


static func clash_starting_gold() -> int:
	return CLASH_STARTING_GOLD


static func clash_send_pack_ids() -> Array:
	return CLASH_SEND_PACKS.keys()


static func clash_send_pack(pack_id: String) -> Dictionary:
	return CLASH_SEND_PACKS.get(pack_id, CLASH_SEND_PACKS["scout"])


## Pack ids unlocked at or below the given send-shop level.
static func clash_send_packs_for_level(level: int) -> Array:
	var out: Array = []
	var lv := clampi(level, 1, CLASH_SEND_SHOP_MAX_LEVEL)
	for id in clash_send_pack_ids():
		var pack := clash_send_pack(str(id))
		if int(pack.get("min_shop_level", 1)) <= lv:
			out.append(str(id))
	return out


## Gold to upgrade from `from_level` to from_level+1 (0 if maxed / invalid).
static func clash_send_shop_upgrade_cost(from_level: int) -> int:
	return int(CLASH_SEND_SHOP_UPGRADE_COSTS.get(from_level, 0))


## Permanent +gold/round from buying this pack (stacks for the rest of the match).
static func clash_send_income_bump(pack_id: String) -> int:
	var pack := clash_send_pack(pack_id)
	return maxi(int(pack.get("income_bump", CLASH_SEND_INCOME_BUMP)), 0)


static func clash_creep_count(wave: int) -> int:
	return maxi(int(round(float(creep_count(wave)) * CLASH_CREEP_COUNT_MULT)), 4)
