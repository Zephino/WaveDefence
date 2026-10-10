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
	lives = maxi(lives - amount, 0)
	lives_changed.emit(lives)
	if lives <= 0:
		trigger_game_over()


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
