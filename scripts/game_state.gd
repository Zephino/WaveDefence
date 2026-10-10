class_name GameState
extends Node

signal gold_changed(gold: int)
signal lives_changed(lives: int)
signal wave_changed(wave: int)
signal game_over(wave_reached: int)
signal restarted

var gold: int = WaveScaler.STARTING_GOLD
var lives: int = WaveScaler.STARTING_LIVES
var wave: int = 0
var difficulty: int = WaveScaler.Difficulty.MEDIUM
var game_mode: int = WaveScaler.GameMode.CLASSIC
var monster_mode: int = WaveScaler.MonsterMode.CLASSIC
var map_layout_mode: int = WaveScaler.MapLayoutMode.STANDARD
## Base seed for Classic custom / Random run.
var run_seed: int = -1
## Layout seed for the active map (HUD + Classic replay).
var current_map_seed: int = -1
## All map seeds used this run (Random sectors / Classic custom), in order.
var map_seeds_used: Array = []
var god_mode: bool = false
var is_game_over: bool = false
var highest_wave: int = 0
## Kills across the whole run (leaderboard / stats).
var total_kills: int = 0
## Kills since the current map was generated (Random-mode rotate payout).
var kills_this_map: int = 0
## 1-based Random-mode map index (Classic stays 1).
var map_sector: int = 1
## True if the debug menu / debug hotkeys were used this run (blocks leaderboard).
var debug_used: bool = false
## Tutorial practice run — no leaderboard / achievements.
var tutorial_run: bool = false

var total_leaks: int = 0
var leaks_per_wave: Dictionary = {}
var walls_placed: int = 0
var towers_placed: int = 0
var gold_spent_total: int = 0
var sell_refund_total: int = 0
var sell_count: int = 0
var run_gold_earned: int = 0
var peak_gold_wave15: bool = false
var gatling_placed: bool = false
var distinct_final_elements: Dictionary = {}
var snake_cleared_medium_plus: bool = false
var flying_boss_wave_leaks: int = -1
var supply_drop_used: bool = false
var airstrike_trap_hit: bool = false


func _ready() -> void:
	reset_run()


func reset_run(p_difficulty: int = -1, p_mode: int = -1, p_monster_mode: int = -1) -> void:
	if p_difficulty >= 0:
		difficulty = p_difficulty
	if p_mode >= 0:
		game_mode = p_mode
	if p_monster_mode >= 0:
		monster_mode = p_monster_mode
	gold = WaveScaler.starting_gold_for(difficulty)
	lives = WaveScaler.STARTING_LIVES
	wave = 0
	highest_wave = 0
	total_kills = 0
	kills_this_map = 0
	map_sector = 1
	map_seeds_used.clear()
	is_game_over = false
	god_mode = false
	debug_used = false
	tutorial_run = false
	total_leaks = 0
	leaks_per_wave.clear()
	walls_placed = 0
	towers_placed = 0
	gold_spent_total = 0
	sell_refund_total = 0
	sell_count = 0
	run_gold_earned = 0
	peak_gold_wave15 = false
	gatling_placed = false
	distinct_final_elements.clear()
	snake_cleared_medium_plus = false
	flying_boss_wave_leaks = -1
	supply_drop_used = false
	airstrike_trap_hit = false
	gold_changed.emit(gold)
	lives_changed.emit(lives)
	wave_changed.emit(wave)
	restarted.emit()


func set_map_seeds(p_run_seed: int, p_map_seed: int, p_layout_mode: int = -1) -> void:
	run_seed = p_run_seed
	current_map_seed = p_map_seed
	if p_layout_mode >= 0:
		map_layout_mode = p_layout_mode
	record_map_seed(p_map_seed)


func record_map_seed(seed_value: int) -> void:
	if seed_value < 0:
		return
	if not map_seeds_used.is_empty() and int(map_seeds_used[map_seeds_used.size() - 1]) == seed_value:
		return
	map_seeds_used.append(seed_value)


func seeds_for_leaderboard() -> Array:
	var out: Array = []
	for s in map_seeds_used:
		out.append(int(s))
	return out


func mark_debug_used() -> void:
	debug_used = true


func register_kill() -> void:
	total_kills += 1
	kills_this_map += 1


func begin_next_map_sector(carry_gold: int) -> void:
	map_sector += 1
	kills_this_map = 0
	lives = WaveScaler.STARTING_LIVES
	gold = maxi(carry_gold, 0)
	gold_changed.emit(gold)
	lives_changed.emit(lives)


func add_gold(amount: int) -> void:
	if amount == 0:
		return
	if amount > 0:
		run_gold_earned += amount
	gold += amount
	gold_changed.emit(gold)


func spend_gold(amount: int) -> bool:
	if gold < amount:
		return false
	gold -= amount
	gold_changed.emit(gold)
	return true


func can_afford(amount: int) -> bool:
	return gold >= amount


func lose_life(amount: int = 1) -> void:
	if is_game_over or god_mode:
		return
	total_leaks += amount
	var w := maxi(wave, 1)
	leaks_per_wave[w] = int(leaks_per_wave.get(w, 0)) + amount
	lives = maxi(lives - amount, 0)
	lives_changed.emit(lives)
	if lives <= 0:
		trigger_game_over()


func record_sell_refund(refund: int) -> void:
	sell_refund_total += refund
	sell_count += 1


func record_spend(amount: int) -> void:
	gold_spent_total += amount


func record_wall_placed() -> void:
	walls_placed += 1


func record_tower_placed(tower_id: String) -> void:
	towers_placed += 1
	if tower_id == "gatling":
		gatling_placed = true


func record_final_element(element: String) -> void:
	if element != "":
		distinct_final_elements[element] = true


func leaks_at_or_before(max_wave: int) -> int:
	var n := 0
	for k in leaks_per_wave.keys():
		if int(k) <= max_wave:
			n += int(leaks_per_wave[k])
	return n


func run_stats_dictionary() -> Dictionary:
	return {
		"tutorial": tutorial_run,
		"highest_wave": highest_wave,
		"total_leaks": total_leaks,
		"leaks_per_wave": leaks_per_wave.duplicate(),
		"leaks_at_or_before_wave": {"10": leaks_at_or_before(10), "20": leaks_at_or_before(20)},
		"total_kills": total_kills,
		"walls_placed": walls_placed,
		"towers_placed": towers_placed,
		"gold_spent": gold_spent_total,
		"sell_refund": sell_refund_total,
		"sell_count": sell_count,
		"run_gold_earned": run_gold_earned,
		"economy_king": peak_gold_wave15,
		"gatling_placed": gatling_placed,
		"distinct_final_elements": distinct_final_elements.size(),
		"snake_cleared_medium_plus": snake_cleared_medium_plus,
		"flying_boss_max_leaks_ok": flying_boss_wave_leaks >= 0 and flying_boss_wave_leaks <= 1,
		"commando_done": supply_drop_used and airstrike_trap_hit,
	}


func set_wave(value: int) -> void:
	wave = maxi(value, 0)
	highest_wave = maxi(highest_wave, wave)
	wave_changed.emit(wave)


func advance_wave() -> int:
	set_wave(wave + 1)
	return wave


func trigger_game_over() -> void:
	if is_game_over:
		return
	is_game_over = true
	highest_wave = maxi(highest_wave, wave)
	game_over.emit(wave)
