class_name WaveScaler
extends RefCounted

## Endless wave formulas. Tune freely, then re-run (F5).

enum Difficulty { EASY, MEDIUM, HARD }
enum GameMode { CLASSIC, RANDOM }

const STARTING_GOLD_EASY := 350
const STARTING_GOLD_MEDIUM := 200
const STARTING_GOLD_HARD := 100
## Default / Medium starting gold (kept for older call sites and smoke tests).
const STARTING_GOLD := STARTING_GOLD_MEDIUM
const STARTING_LIVES := 20
## Random mode: new map after these wave clears (25, 50, 75…).
const MAP_ROTATE_EVERY := 25
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
		_:
			return "Medium"


static func mode_label(mode: int) -> String:
	match mode:
		GameMode.RANDOM:
			return "Random"
		_:
			return "Classic"


static func is_random_mode(mode: int) -> bool:
	return mode == GameMode.RANDOM


static func should_rotate_map_after_wave(mode: int, wave: int) -> bool:
	return is_random_mode(mode) and wave > 0 and wave % MAP_ROTATE_EVERY == 0


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
	return creep_hp(wave) * 0.85


static func flying_creep_speed(wave: int) -> float:
	var cap := SPEED_WAVE_MAX_SPEED if is_speed_wave(wave) else 160.0
	return minf(creep_speed(wave) * 1.15, cap)


static func flying_creep_bounty(wave: int) -> int:
	return creep_bounty(wave) + 2


static func flying_boss_count(wave: int) -> int:
	if wave > 0 and wave % 15 == 0:
		return 1
	return 0


static func flying_boss_hp(wave: int) -> float:
	return creep_hp(wave) * 10.0


static func flying_boss_speed(wave: int) -> float:
	var base := minf(60.0 + wave * 1.5, 140.0)
	var speed := maxf(base * 0.7, 45.0)
	if is_speed_wave(wave):
		speed = minf(speed * 1.4, 150.0)
	return speed


static func flying_boss_bounty(wave: int) -> int:
	return creep_bounty(wave) * 18


static func spawn_interval(wave: int) -> float:
	var interval := maxf(0.55 - wave * 0.005, 0.2)
	if is_speed_wave(wave):
		interval = maxf(interval * SPEED_WAVE_SPAWN_MULT, 0.08)
	return interval


static func boss_banner(wave: int) -> String:
	var parts: PackedStringArray = PackedStringArray()
	if is_speed_wave(wave):
		parts.append("SPEED WAVE")
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
