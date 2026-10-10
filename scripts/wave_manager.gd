class_name WaveManager
extends Node

const SoundHub := preload("res://scripts/sound_hub.gd")

signal wave_started(wave: int, banner: String)
signal wave_cleared(wave: int, kills: int, bonus_gold: int)
signal enemy_spawned(enemy: Enemy)
## Random mode: full clear of wave 25/50/… — main should rebuild the map (no auto-intermission).
signal map_rotate_requested(wave: int)
## Siege mode: relocate rim spawn after wave 5/10/… (towers stay).
signal spawn_rotate_requested(wave: int)
## mode: "prep" | "intermission" | "wave"
signal timer_updated(seconds_left: float, can_skip: bool, mode: String)
signal skip_unlock_changed(unlocked: bool)
## remaining = alive on map + still waiting to spawn (until the board clears).
signal enemies_remaining_changed(remaining: int, alive: int, queued: int)

enum Phase { PREP, INTERMISSION, WAVE }

## Cap alive + queued enemies. Early-send is blocked above this to prevent late-game freezes.
const MAX_BOARD_PRESSURE := 72

var grid: GameGrid
var pathfinder: Pathfinder
var game_state: GameState
var enemy_container: Node

var phase: Phase = Phase.PREP
var wave_active: bool = false
var spawning: bool = false
var spawn_queue: Array[Dictionary] = []
var spawn_timer: float = 0.0
var enemies_alive: int = 0
var kills_this_wave: int = 0
var enemies_this_wave_total: int = 0
## True once 25% of this wave's enemies have been killed (or after Start Round build timer).
var skip_unlocked: bool = false
var intermission_left: float = 0.0
## Gold awarded by the most recent early-send / timer skip (for UI status).
var last_early_send_bonus: int = 0
## If set, rotate the Random map once the board fully clears (survives early-send past 25/50…).
var pending_map_rotate_wave: int = 0
## Cached ground path; rebuilt only when towers change (not every spawn).
var _cached_ground_path: PackedVector2Array = PackedVector2Array()
var _path_dirty: bool = true
var _spawn_rng := RandomNumberGenerator.new()
## Current wave is a ground snake chain (random boss-wave variant).
var _wave_is_snake: bool = false
## Last spawned snake segment (used to link the next body piece).
var _snake_tail: Enemy = null
var game_paused: bool = false
var _leaks_this_wave: int = 0
var _flying_boss_wave_active: bool = false


func setup(p_grid: GameGrid, p_pathfinder: Pathfinder, p_state: GameState, p_enemies: Node) -> void:
	grid = p_grid
	pathfinder = p_pathfinder
	game_state = p_state
	enemy_container = p_enemies


func begin_run() -> void:
	clear_enemies()
	phase = Phase.PREP
	skip_unlocked = false
	intermission_left = 0.0
	last_early_send_bonus = 0
	pending_map_rotate_wave = 0
	_emit_timer()
	_emit_enemies_remaining()


func enemies_remaining() -> int:
	return enemies_alive + spawn_queue.size()


func board_pressure() -> int:
	return enemies_alive + spawn_queue.size()


func _emit_enemies_remaining() -> void:
	enemies_remaining_changed.emit(enemies_remaining(), enemies_alive, spawn_queue.size())


func invalidate_ground_path() -> void:
	_path_dirty = true


func _ensure_ground_path() -> PackedVector2Array:
	if _path_dirty or _cached_ground_path.size() < 2:
		pathfinder.rebuild()
		_cached_ground_path = pathfinder.get_world_path()
		_path_dirty = false
	return _cached_ground_path


func start_round() -> bool:
	## Player pressed Start Round after free-build prep.
	if phase != Phase.PREP or game_state.is_game_over:
		return false
	invalidate_ground_path()
	if _ensure_ground_path().size() < 2:
		return false
	_start_intermission(WaveScaler.INITIAL_BUILD_TIME, true)
	return true


func has_open_path() -> bool:
	return _ensure_ground_path().size() >= 2


func can_send_wave() -> bool:
	if game_state.is_game_over or wave_active or spawning:
		return false
	return has_open_path()


func can_send_wave_early() -> bool:
	if game_state.is_game_over or phase != Phase.WAVE or not skip_unlocked:
		return false
	# Stacking early-sends with leftovers was freezing Classic around wave 50–60.
	if board_pressure() >= MAX_BOARD_PRESSURE:
		return false
	return has_open_path()


func can_skip_timer() -> bool:
	if game_state.is_game_over:
		return false
	if phase == Phase.INTERMISSION:
		return skip_unlocked and can_send_wave()
	if phase == Phase.WAVE:
		return can_send_wave_early()
	return false


func try_skip_timer() -> bool:
	if phase == Phase.WAVE:
		return send_wave_early()

	if phase != Phase.INTERMISSION or not skip_unlocked:
		return false
	if not can_send_wave():
		return false
	last_early_send_bonus = WaveScaler.early_send_bonus_from_timer(intermission_left)
	if last_early_send_bonus > 0:
		game_state.add_gold(last_early_send_bonus)
	return send_next_wave()


func send_next_wave() -> bool:
	if not can_send_wave():
		return false
	var world_path := _ensure_ground_path()
	if world_path.size() < 2:
		return false

	var wave := game_state.advance_wave()
	_spawn_rng.randomize()
	_snake_tail = null
	_wave_is_snake = WaveScaler.roll_snake_boss(wave, _spawn_rng)
	var banner := WaveScaler.boss_banner(wave, _wave_is_snake)
	_build_spawn_queue(wave)
	enemies_this_wave_total = spawn_queue.size()
	phase = Phase.WAVE
	wave_active = true
	spawning = true
	spawn_timer = 0.0
	kills_this_wave = 0
	_leaks_this_wave = 0
	_flying_boss_wave_active = wave > 0 and wave % 15 == 0
	skip_unlocked = false
	intermission_left = 0.0
	SoundHub.play_wave_start(WaveScaler.is_boss_wave(wave))
	SoundHub.set_gameplay_music_source(enemy_container as Node2D, wave, WaveScaler.is_boss_wave(wave))
	wave_started.emit(wave, banner)
	_emit_timer()
	_emit_enemies_remaining()
	return true


## Start the next wave immediately while living enemies stay on the map.
func send_wave_early() -> bool:
	if not can_send_wave_early():
		return false
	return _begin_overlapping_next_wave(true)


## Keep living enemies; drop unspawned leftovers; start the next wave's spawns immediately.
func _begin_overlapping_next_wave(award_bonuses: bool) -> bool:
	if award_bonuses and phase == Phase.WAVE and game_state.wave > 0:
		var finished_wave := game_state.wave
		var kills := kills_this_wave
		var clear_bonus := WaveScaler.wave_clear_bonus(kills, finished_wave)
		var early_bonus := WaveScaler.early_send_bonus_from_alive(finished_wave, enemies_alive)
		last_early_send_bonus = early_bonus
		if clear_bonus > 0:
			game_state.add_gold(clear_bonus)
		if early_bonus > 0:
			game_state.add_gold(early_bonus)
		wave_cleared.emit(finished_wave, kills, clear_bonus + early_bonus)
		if WaveScaler.should_rotate_map_after_wave(game_state.game_mode, finished_wave):
			pending_map_rotate_wave = finished_wave
		elif WaveScaler.should_rotate_spawn_after_wave(game_state.game_mode, finished_wave):
			spawn_rotate_requested.emit(finished_wave)
	else:
		last_early_send_bonus = 0

	# Keep living enemies on the board, but drop unspawned leftovers.
	# Re-appending leftovers each early-send stacked hundreds of entities by mid/late Classic.
	spawn_queue.clear()

	var wave := game_state.advance_wave()
	_spawn_rng.randomize()
	_snake_tail = null
	_wave_is_snake = WaveScaler.roll_snake_boss(wave, _spawn_rng)
	var banner := WaveScaler.boss_banner(wave, _wave_is_snake)
	_build_spawn_queue(wave)
	enemies_this_wave_total = spawn_queue.size()

	phase = Phase.WAVE
	wave_active = true
	spawning = true
	spawn_timer = 0.0
	kills_this_wave = 0
	_leaks_this_wave = 0
	_flying_boss_wave_active = wave > 0 and wave % 15 == 0
	skip_unlocked = false
	intermission_left = 0.0
	SoundHub.play_wave_start(WaveScaler.is_boss_wave(wave))
	SoundHub.set_gameplay_music_source(enemy_container as Node2D, wave, WaveScaler.is_boss_wave(wave))
	wave_started.emit(wave, banner)
	_emit_timer()
	_emit_enemies_remaining()
	return true


func _start_intermission(duration: float, allow_skip: bool) -> void:
	if game_state.is_game_over:
		return
	phase = Phase.INTERMISSION
	intermission_left = maxf(duration, 0.0)
	skip_unlocked = allow_skip
	_emit_timer()


func _emit_timer() -> void:
	match phase:
		Phase.PREP:
			timer_updated.emit(0.0, true, "prep")
		Phase.INTERMISSION:
			timer_updated.emit(intermission_left, can_skip_timer(), "intermission")
		Phase.WAVE:
			timer_updated.emit(0.0, can_skip_timer(), "wave")


func _build_spawn_queue(wave: int) -> void:
	spawn_queue.clear()
	# Fresh draws for monster types / resists (snake roll already happened in send_*).
	_spawn_rng.randomize()
	if _wave_is_snake:
		_build_snake_spawn_queue(wave)
		return
	var ground_left := WaveScaler.ground_creep_count(wave)
	var air_left := WaveScaler.flying_creep_count(wave)
	# Interleave ground and air creeps so late waves feel mixed, not batched.
	while ground_left > 0 or air_left > 0:
		if ground_left > 0:
			spawn_queue.append(_make_spawn_spec(
				wave,
				WaveScaler.creep_hp(wave),
				WaveScaler.creep_speed(wave),
				WaveScaler.creep_bounty(wave),
				false,
				false
			))
			ground_left -= 1
		if air_left > 0:
			spawn_queue.append(_make_spawn_spec(
				wave,
				WaveScaler.flying_creep_hp(wave),
				WaveScaler.flying_creep_speed(wave),
				WaveScaler.flying_creep_bounty(wave),
				false,
				true
			))
			air_left -= 1
	var bosses := WaveScaler.boss_count(wave)
	for i in bosses:
		spawn_queue.append(_make_spawn_spec(
			wave,
			WaveScaler.boss_hp(wave),
			WaveScaler.boss_speed(wave),
			WaveScaler.boss_bounty(wave),
			true,
			false
		))
	var flyers := WaveScaler.flying_boss_count(wave)
	for i in flyers:
		spawn_queue.append(_make_spawn_spec(
			wave,
			WaveScaler.flying_boss_hp(wave),
			WaveScaler.flying_boss_speed(wave),
			WaveScaler.flying_boss_bounty(wave),
			true,
			true
		))


func _build_snake_spawn_queue(wave: int) -> void:
	var count := WaveScaler.snake_segment_count(wave)
	for i in count:
		var is_head := i == 0
		var spec := _make_spawn_spec(
			wave,
			WaveScaler.snake_head_hp(wave) if is_head else WaveScaler.snake_body_hp(wave),
			WaveScaler.snake_speed(wave),
			WaveScaler.snake_head_bounty(wave) if is_head else WaveScaler.snake_body_bounty(wave),
			is_head,
			false
		)
		spec["snake"] = true
		spec["snake_index"] = i
		spawn_queue.append(spec)


func _make_spawn_spec(
	wave: int,
	hp: float,
	speed: float,
	bounty: int,
	boss: bool,
	flying: bool
) -> Dictionary:
	var spec := {
		"hp": hp,
		"speed": speed,
		"bounty": bounty,
		"boss": boss,
		"flying": flying,
		"wave": wave,
		"counts_kill": true,
		"monster_type": "",
		"element_resists": MonsterTypes.empty_resists(),
		"snake": false,
		"snake_index": -1,
	}
	if game_state != null and WaveScaler.is_randomize_monsters(game_state.monster_mode):
		var type_id := MonsterTypes.pick_type(_spawn_rng, flying)
		spec["monster_type"] = type_id
		spec["element_resists"] = MonsterTypes.build_resists(type_id, wave, _spawn_rng)
	return spec


func _build_delta(delta: float) -> float:
	if phase != Phase.INTERMISSION:
		return delta
	return delta * UserSettings.get_build_speed_mult()


func _process(delta: float) -> void:
	if game_paused:
		return
	if game_state != null and game_state.is_game_over:
		return
	if phase == Phase.INTERMISSION:
		_process_intermission(_build_delta(delta))
	elif phase == Phase.WAVE and spawning:
		_process_spawning(delta)


func _process_intermission(delta: float) -> void:
	intermission_left = maxf(intermission_left - delta, 0.0)
	_emit_timer()
	if intermission_left <= 0.0:
		last_early_send_bonus = 0
		if not send_next_wave():
			# Path blocked — keep retrying on a short delay.
			intermission_left = 1.0
			_emit_timer()


func _process_spawning(delta: float) -> void:
	spawn_timer -= delta
	if spawn_timer > 0.0:
		return
	if spawn_queue.is_empty():
		spawning = false
		_check_wave_clear()
		return
	var spec: Dictionary = spawn_queue.pop_front()
	if not _spawn_enemy(spec):
		# Failed spawn (e.g. blocked path) — do not require a kill for this slot.
		if bool(spec.get("counts_kill", true)):
			enemies_this_wave_total = maxi(enemies_this_wave_total - 1, 0)
		_emit_enemies_remaining()
	if _wave_is_snake:
		spawn_timer = WaveScaler.snake_spawn_interval()
	else:
		spawn_timer = WaveScaler.spawn_interval(game_state.wave)


func _spawn_enemy(spec: Dictionary) -> bool:
	var flying := bool(spec.get("flying", false))
	var world_path: PackedVector2Array
	if flying:
		# Stagger phase so successive flyers weave on offset S lanes.
		var phase := float(enemies_alive % 4) * (PI * 0.35)
		if bool(spec.get("boss", false)):
			phase += 0.55
		world_path = grid.build_air_s_path(phase)
	else:
		world_path = _ensure_ground_path()
		if world_path.size() < 2:
			return false
	var enemy := Enemy.new()
	enemy_container.add_child(enemy)
	enemy.setup(
		world_path,
		float(spec["hp"]),
		float(spec["speed"]),
		int(spec["bounty"]),
		bool(spec["boss"]),
		flying,
		int(spec.get("wave", game_state.wave)),
		str(spec.get("monster_type", "")),
		spec.get("element_resists", MonsterTypes.empty_resists()) as Dictionary
	)
	if bool(spec.get("snake", false)):
		var prev: Enemy = _snake_tail
		if prev != null and not is_instance_valid(prev):
			prev = null
		enemy.configure_snake(int(spec.get("snake_index", 0)), prev, WaveScaler.SNAKE_SPACING)
		_snake_tail = enemy
	enemy.died.connect(_on_enemy_died)
	enemy.leaked.connect(_on_enemy_leaked)
	enemies_alive += 1
	enemy_spawned.emit(enemy)
	_emit_enemies_remaining()
	return true


func _on_enemy_died(enemy: Enemy, bounty: int) -> void:
	game_state.add_gold(bounty)
	game_state.register_kill()
	SoundHub.play_kill()
	if enemy.wave_index == game_state.wave:
		kills_this_wave += 1
		_update_skip_unlock()
	enemies_alive = maxi(enemies_alive - 1, 0)
	_emit_enemies_remaining()
	_check_wave_clear()


func _record_wave_milestones(wave: int) -> void:
	if wave == 15 and game_state.gold >= 500:
		game_state.peak_gold_wave15 = true
	if _wave_is_snake and game_state.difficulty >= WaveScaler.Difficulty.MEDIUM and _leaks_this_wave == 0:
		game_state.snake_cleared_medium_plus = true
	if _flying_boss_wave_active:
		game_state.flying_boss_wave_leaks = _leaks_this_wave


func _on_enemy_leaked(_enemy: Enemy) -> void:
	_leaks_this_wave += 1
	SoundHub.play_leak()
	game_state.lose_life(1)
	enemies_alive = maxi(enemies_alive - 1, 0)
	_emit_enemies_remaining()
	_check_wave_clear()


func _update_skip_unlock() -> void:
	if enemies_this_wave_total <= 0 or skip_unlocked:
		return
	var needed := int(ceil(float(enemies_this_wave_total) * WaveScaler.SKIP_TIMER_KILL_RATIO))
	needed = maxi(needed, 1)
	if kills_this_wave >= needed:
		skip_unlocked = true
		skip_unlock_changed.emit(true)
		_emit_timer()


func _check_wave_clear() -> void:
	if spawning:
		return
	if enemies_alive <= 0 and spawn_queue.is_empty():
		wave_active = false
		var wave := game_state.wave
		var kills := kills_this_wave
		var bonus := WaveScaler.wave_clear_bonus(kills, wave)
		if bonus > 0:
			game_state.add_gold(bonus)
		_record_wave_milestones(wave)
		wave_cleared.emit(wave, kills, bonus)
		_emit_enemies_remaining()
		if game_state.is_game_over:
			return
		var rotate_wave := 0
		if pending_map_rotate_wave > 0:
			rotate_wave = pending_map_rotate_wave
			pending_map_rotate_wave = 0
		elif WaveScaler.should_rotate_map_after_wave(game_state.game_mode, wave):
			rotate_wave = wave
		if rotate_wave > 0:
			phase = Phase.PREP
			skip_unlocked = false
			intermission_left = 0.0
			_emit_timer()
			map_rotate_requested.emit(rotate_wave)
			return
		if WaveScaler.should_rotate_spawn_after_wave(game_state.game_mode, wave):
			spawn_rotate_requested.emit(wave)
		_start_intermission(WaveScaler.INTERMISSION_TIME, true)


func clear_enemies() -> void:
	for child in enemy_container.get_children():
		child.queue_free()
	enemies_alive = 0
	spawn_queue.clear()
	spawning = false
	wave_active = false
	kills_this_wave = 0
	enemies_this_wave_total = 0
	_wave_is_snake = false
	_snake_tail = null
	phase = Phase.PREP
	intermission_left = 0.0
	skip_unlocked = false
	last_early_send_bonus = 0
	_emit_enemies_remaining()


func jump_to_wave(wave_number: int) -> void:
	clear_enemies()
	game_state.set_wave(maxi(wave_number - 1, 0))
	force_intermission(3.0, true)


func force_intermission(duration: float = WaveScaler.INTERMISSION_TIME, allow_skip: bool = true) -> void:
	_start_intermission(duration, allow_skip)


## Debug: start the next wave immediately, ignoring timers and skip unlock.
## Does not clear living enemies — next-wave spawns overlap with whatever is already out.
func force_next_wave() -> bool:
	if game_state == null or game_state.is_game_over:
		return false
	if not has_open_path():
		return false
	# Anything still on the map / in the spawn queue → overlap like early send.
	if phase == Phase.WAVE or enemies_alive > 0 or spawning or not spawn_queue.is_empty():
		return _begin_overlapping_next_wave(false)
	# Idle prep / intermission with an empty board — just start the next wave.
	wave_active = false
	spawning = false
	intermission_left = 0.0
	skip_unlocked = true
	last_early_send_bonus = 0
	return send_next_wave()


func repath_living_enemies() -> void:
	invalidate_ground_path()
	var world_path := _ensure_ground_path()
	for child in enemy_container.get_children():
		if child is Enemy:
			(child as Enemy).set_path(world_path)
