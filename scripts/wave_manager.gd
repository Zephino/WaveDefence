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
## Clash wrecker smashed a structure at this cell (after repath).
signal tower_wrecked(cell: Vector2i)

enum Phase { PREP, INTERMISSION, WAVE }

## Cap alive + queued enemies. Early-send is blocked above this to prevent late-game freezes.
const MAX_BOARD_PRESSURE := 72

var grid: GameGrid
var pathfinder: Pathfinder
var game_state: GameState
var enemy_container: Node
## Optional Clash match — multi-lane spawn / gold / lives.
var clash_match: ClashMatch = null

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
## Last path-block failsafe result: { removed: int, refunded: int }.
var last_path_failsafe: Dictionary = {"removed": 0, "refunded": 0}
## If set, rotate the Random map once the board fully clears (survives early-send past 25/50…).
var pending_map_rotate_wave: int = 0
## Cached ground path; rebuilt only when towers change (not every spawn).
var _cached_ground_path: PackedVector2Array = PackedVector2Array()
var _path_dirty: bool = true
## Clash: per-lane cached ground paths.
var _cached_lane_paths: Dictionary = {}
var _spawn_rng := RandomNumberGenerator.new()
## Current wave is a ground snake chain (random boss-wave variant).
var _wave_is_snake: bool = false
## Last spawned snake segment (used to link the next body piece).
var _snake_tail: Enemy = null
## Clash: last snake tail per lane.
var _snake_tails_by_lane: Dictionary = {}
var game_paused: bool = false
var _leaks_this_wave: int = 0
var _flying_boss_wave_active: bool = false


func setup(p_grid: GameGrid, p_pathfinder: Pathfinder, p_state: GameState, p_enemies: Node) -> void:
	grid = p_grid
	pathfinder = p_pathfinder
	game_state = p_state
	enemy_container = p_enemies


func set_clash_match(p_match: ClashMatch) -> void:
	clash_match = p_match


func _is_clash() -> bool:
	return clash_match != null and game_state != null and WaveScaler.is_clash_mode(game_state.game_mode)


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
	_cached_lane_paths.clear()


func _ensure_ground_path() -> PackedVector2Array:
	if _path_dirty or _cached_ground_path.size() < 2:
		pathfinder.rebuild()
		_cached_ground_path = pathfinder.get_world_path()
		_path_dirty = false
	return _cached_ground_path


func _ensure_lane_ground_path(lane: int) -> PackedVector2Array:
	if not _path_dirty and _cached_lane_paths.has(lane):
		var cached: PackedVector2Array = _cached_lane_paths[lane]
		if cached.size() >= 2:
			return cached
	pathfinder.rebuild()
	_path_dirty = false
	var spawn := grid.get_lane_spawn(lane)
	var exit_c := grid.get_lane_exit(lane)
	var path := pathfinder.get_world_path_between(spawn, exit_c)
	_cached_lane_paths[lane] = path
	return path


func start_round() -> bool:
	## Player pressed Start Round after free-build prep.
	if phase != Phase.PREP or game_state.is_game_over:
		return false
	last_path_failsafe = {"removed": 0, "refunded": 0}
	invalidate_ground_path()
	if not has_open_path():
		clear_path_blockers()
		if not has_open_path():
			return false
	_start_intermission(WaveScaler.INITIAL_BUILD_TIME, true)
	return true


func has_open_path() -> bool:
	if _is_clash():
		for p in clash_match.living_players():
			var cp := p as ClashPlayerState
			if _ensure_lane_ground_path(cp.lane_index).size() < 2:
				return false
		return clash_match.living_count() > 0
	return _ensure_ground_path().size() >= 2


## Remove player/bot-built path blockers until spawn→exit is open; refund sell value to owners.
## Does not remove terrain rocks. Returns { removed, refunded }.
func clear_path_blockers() -> Dictionary:
	last_path_failsafe = {"removed": 0, "refunded": 0}
	if grid == null or pathfinder == null or game_state == null:
		return last_path_failsafe
	invalidate_ground_path()
	pathfinder.rebuild()
	if has_open_path():
		return last_path_failsafe

	var removed := 0
	var refunded := 0
	var max_iters := maxi(grid.towers.size(), 1) + 8
	var guard := 0
	while not has_open_path() and guard < max_iters:
		guard += 1
		var tower := _pick_path_blocker_to_remove()
		if tower == null:
			break
		var refund := _refund_and_remove_tower(tower)
		removed += 1
		refunded += refund
		invalidate_ground_path()
		pathfinder.rebuild()

	last_path_failsafe = {"removed": removed, "refunded": refunded}
	return last_path_failsafe


func _unique_path_blocking_towers() -> Array[Tower]:
	var seen: Dictionary = {}
	var out: Array[Tower] = []
	if grid == null:
		return out
	for cell in grid.towers.keys():
		var node: Node = grid.towers[cell]
		if not (node is Tower) or not is_instance_valid(node):
			continue
		var tower := node as Tower
		if seen.has(tower):
			continue
		seen[tower] = true
		if _tower_blocks_any_path_cell(tower):
			out.append(tower)
	return out


func _tower_blocks_any_path_cell(tower: Tower) -> bool:
	for cell in grid.towers.keys():
		if grid.towers[cell] == tower and grid.is_blocked_for_path(cell):
			return true
	return false


func _blocked_lane_indices() -> Array[int]:
	var out: Array[int] = []
	if not _is_clash() or clash_match == null:
		return out
	for p in clash_match.living_players():
		var cp := p as ClashPlayerState
		if cp == null:
			continue
		if _ensure_lane_ground_path(cp.lane_index).size() < 2:
			out.append(cp.lane_index)
	return out


func _tower_on_blocked_lane(tower: Tower, blocked_lanes: Array[int]) -> bool:
	if blocked_lanes.is_empty():
		return true
	var lane := tower.lane_id
	if lane < 0 and grid != null:
		lane = grid.lane_index_for_cell(grid.world_to_cell(tower.position))
	return lane in blocked_lanes


func _would_open_path_if_removed(tower: Tower) -> bool:
	if tower == null or grid == null or pathfinder == null:
		return false
	var cells: Array[Vector2i] = []
	for c in grid.towers.keys():
		if grid.towers[c] == tower:
			cells.append(c)
	if cells.is_empty():
		return false
	var anchor: Vector2i = cells[0]
	if tower.has_meta("anchor_cell"):
		anchor = tower.get_meta("anchor_cell") as Vector2i
	var removed := grid.remove_tower_at(anchor, false)
	if removed == null:
		return false
	invalidate_ground_path()
	pathfinder.rebuild()
	var ok := has_open_path()
	for c in cells:
		grid.towers[c] = tower
	invalidate_ground_path()
	pathfinder.rebuild()
	return ok


func _pick_path_blocker_to_remove() -> Tower:
	var candidates := _unique_path_blocking_towers()
	if candidates.is_empty():
		return null
	var blocked_lanes := _blocked_lane_indices()
	var scoped: Array[Tower] = []
	for t in candidates:
		if _tower_on_blocked_lane(t, blocked_lanes):
			scoped.append(t)
	if scoped.is_empty():
		scoped = candidates

	for t in scoped:
		if _would_open_path_if_removed(t):
			return t
	for t in scoped:
		if TowerData.is_wall(t.tower_id):
			return t
	return scoped[0]


func _refund_and_remove_tower(tower: Tower) -> int:
	if tower == null or not is_instance_valid(tower) or grid == null:
		return 0
	var refund := TowerData.sell_value_for_tower(tower)
	var cell: Vector2i
	if tower.has_meta("anchor_cell"):
		cell = tower.get_meta("anchor_cell") as Vector2i
	else:
		cell = grid.world_to_cell(tower.position)
	var removed := grid.remove_tower_at(cell, true)
	if removed == null:
		return 0

	var owner_id := -1
	if tower.has_meta("clash_owner"):
		owner_id = int(tower.get_meta("clash_owner"))
	if _is_clash() and clash_match != null and owner_id >= 0:
		var cp := clash_match.get_player(owner_id)
		if cp != null and cp.is_human:
			game_state.add_gold(refund)
			game_state.record_sell_refund(refund)
			clash_match.sync_human_gold_from_game_state()
		elif cp != null:
			cp.add_gold(refund)
			clash_match.players_changed.emit()
		else:
			game_state.add_gold(refund)
			game_state.record_sell_refund(refund)
	else:
		game_state.add_gold(refund)
		game_state.record_sell_refund(refund)

	tower.queue_free()
	return refund


func can_send_wave() -> bool:
	if game_state.is_game_over or wave_active or spawning:
		return false
	if _is_clash() and clash_match.finished:
		return false
	return has_open_path()


func can_send_wave_early() -> bool:
	# Clash uses buy-sends instead of overlapping early waves.
	if _is_clash():
		return false
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
		if not has_open_path():
			clear_path_blockers()
		if not can_send_wave():
			return false
	last_early_send_bonus = WaveScaler.early_send_bonus_from_timer(intermission_left)
	if last_early_send_bonus > 0:
		game_state.add_gold(last_early_send_bonus)
	return send_next_wave()


func send_next_wave() -> bool:
	if not can_send_wave():
		return false
	if not _is_clash():
		var world_path := _ensure_ground_path()
		if world_path.size() < 2:
			return false

	var wave := game_state.advance_wave()
	_spawn_rng.randomize()
	_snake_tail = null
	_snake_tails_by_lane.clear()
	_wave_is_snake = false if _is_clash() else WaveScaler.roll_snake_boss(wave, _spawn_rng)
	var banner := WaveScaler.boss_banner(wave, _wave_is_snake)
	if _is_clash():
		_build_clash_spawn_queue(wave)
	else:
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


func _build_clash_spawn_queue(wave: int) -> void:
	spawn_queue.clear()
	_spawn_rng.randomize()
	for p in clash_match.living_players():
		var cp := p as ClashPlayerState
		var lane := cp.lane_index
		var defender := cp.player_id
		var count := WaveScaler.clash_creep_count(wave)
		var air_n := 0
		if wave >= WaveScaler.EARLY_AIR_SCOUT_WAVE:
			air_n = mini(1 + int(wave / 15), maxi(count / 4, 1))
		var ground_n := maxi(count - air_n, 1)
		for _i in ground_n:
			var spec := _make_spawn_spec(
				wave,
				WaveScaler.creep_hp(wave),
				WaveScaler.creep_speed(wave),
				WaveScaler.creep_bounty(wave),
				false,
				false
			)
			spec["lane_id"] = lane
			spec["defender_id"] = defender
			spawn_queue.append(spec)
		for _j in air_n:
			var air := _make_spawn_spec(
				wave,
				WaveScaler.flying_creep_hp(wave),
				WaveScaler.flying_creep_speed(wave),
				WaveScaler.flying_creep_bounty(wave),
				false,
				true
			)
			air["lane_id"] = lane
			air["defender_id"] = defender
			spawn_queue.append(air)
		if wave > 0 and wave % 10 == 0:
			var boss := _make_spawn_spec(
				wave,
				WaveScaler.boss_hp(wave) * 0.85,
				WaveScaler.boss_speed(wave),
				WaveScaler.boss_bounty(wave),
				true,
				false
			)
			boss["lane_id"] = lane
			boss["defender_id"] = defender
			spawn_queue.append(boss)
		for send in cp.take_incoming_sends():
			_append_clash_send_specs(wave, lane, defender, str(send.get("pack_id", "scout")))
	# Round-robin shuffle lightly so lanes interleave.
	_interleave_clash_queue()


func _append_clash_send_specs(wave: int, lane: int, defender: int, pack_id: String) -> void:
	var pack := WaveScaler.clash_send_pack(pack_id)
	var n: int = int(pack.get("count", 3))
	var hp_m: float = float(pack.get("hp_mult", 1.0))
	var sp_m: float = float(pack.get("speed_mult", 1.0))
	var bo_m: float = float(pack.get("bounty_mult", 0.8))
	var flying := bool(pack.get("flying", false))
	var boss := bool(pack.get("boss", false))
	var wrecker := bool(pack.get("wrecker", false))
	for _k in n:
		var base_hp: float
		var base_speed: float
		var base_bounty: int
		if boss and flying:
			base_hp = WaveScaler.flying_boss_hp(wave)
			base_speed = WaveScaler.flying_boss_speed(wave)
			base_bounty = WaveScaler.flying_boss_bounty(wave)
		elif boss:
			base_hp = WaveScaler.boss_hp(wave)
			base_speed = WaveScaler.boss_speed(wave)
			base_bounty = WaveScaler.boss_bounty(wave)
		elif flying:
			base_hp = WaveScaler.flying_creep_hp(wave)
			base_speed = WaveScaler.flying_creep_speed(wave)
			base_bounty = WaveScaler.flying_creep_bounty(wave)
		else:
			base_hp = WaveScaler.creep_hp(wave)
			base_speed = WaveScaler.creep_speed(wave)
			base_bounty = WaveScaler.creep_bounty(wave)
		var spec := _make_spawn_spec(
			wave,
			base_hp * hp_m,
			base_speed * sp_m,
			maxi(int(round(float(base_bounty) * bo_m)), 1),
			boss,
			flying
		)
		spec["lane_id"] = lane
		spec["defender_id"] = defender
		spec["sent"] = true
		spec["wrecker"] = wrecker
		spawn_queue.append(spec)


func _interleave_clash_queue() -> void:
	if spawn_queue.size() < 2:
		return
	var by_lane: Dictionary = {}
	for spec in spawn_queue:
		var lane := int(spec.get("lane_id", 0))
		if not by_lane.has(lane):
			by_lane[lane] = []
		(by_lane[lane] as Array).append(spec)
	spawn_queue.clear()
	var lanes: Array = by_lane.keys()
	lanes.sort()
	var remaining := true
	while remaining:
		remaining = false
		for lane in lanes:
			var arr: Array = by_lane[lane]
			if arr.is_empty():
				continue
			remaining = true
			spawn_queue.append(arr.pop_front())


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
	elif phase == Phase.WAVE and (spawning or not spawn_queue.is_empty()):
		spawning = true
		_process_spawning(delta)


func _process_intermission(delta: float) -> void:
	intermission_left = maxf(intermission_left - delta, 0.0)
	_emit_timer()
	if intermission_left <= 0.0:
		last_early_send_bonus = 0
		if not has_open_path():
			clear_path_blockers()
		if not send_next_wave():
			# Still blocked (e.g. only rocks) — keep retrying on a short delay.
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
	var lane_id := int(spec.get("lane_id", -1))
	var defender_id := int(spec.get("defender_id", -1))
	var world_path: PackedVector2Array
	if flying:
		# Stagger phase so successive flyers weave on offset S lanes.
		var phase_off := float(enemies_alive % 4) * (PI * 0.35)
		if bool(spec.get("boss", false)):
			phase_off += 0.55
		if _is_clash() and lane_id >= 0:
			world_path = grid.build_lane_air_s_path(lane_id, phase_off)
		else:
			world_path = grid.build_air_s_path(phase_off)
	else:
		if _is_clash() and lane_id >= 0:
			world_path = _ensure_lane_ground_path(lane_id)
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
	enemy.lane_id = lane_id
	enemy.defender_id = defender_id
	if bool(spec.get("wrecker", false)):
		enemy.configure_wrecker(grid, pathfinder)
		enemy.wrecked_at.connect(_on_wrecker_wrecked)
	if bool(spec.get("snake", false)):
		var prev: Enemy = _snake_tail
		if _is_clash() and lane_id >= 0:
			prev = _snake_tails_by_lane.get(lane_id, null)
		if prev != null and not is_instance_valid(prev):
			prev = null
		enemy.configure_snake(int(spec.get("snake_index", 0)), prev, WaveScaler.SNAKE_SPACING)
		_snake_tail = enemy
		if _is_clash() and lane_id >= 0:
			_snake_tails_by_lane[lane_id] = enemy
	enemy.died.connect(_on_enemy_died)
	enemy.leaked.connect(_on_enemy_leaked)
	enemies_alive += 1
	enemy_spawned.emit(enemy)
	_emit_enemies_remaining()
	return true


func _on_wrecker_wrecked(cell: Vector2i) -> void:
	invalidate_ground_path()
	repath_living_enemies()
	tower_wrecked.emit(cell)


func _on_enemy_died(enemy: Enemy, bounty: int) -> void:
	if _is_clash() and enemy.defender_id >= 0:
		clash_match.credit_kill(enemy.defender_id, bounty)
	else:
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
	if _is_clash():
		return
	if wave == 15 and game_state.gold >= 500:
		game_state.peak_gold_wave15 = true
	if _wave_is_snake and game_state.difficulty >= WaveScaler.Difficulty.MEDIUM and _leaks_this_wave == 0:
		game_state.snake_cleared_medium_plus = true
	if _flying_boss_wave_active:
		game_state.flying_boss_wave_leaks = _leaks_this_wave


func _on_enemy_leaked(enemy: Enemy) -> void:
	_leaks_this_wave += 1
	SoundHub.play_leak()
	if _is_clash() and enemy.defender_id >= 0:
		clash_match.credit_leak(enemy.defender_id)
		var leak_p := clash_match.get_player(enemy.defender_id)
		if leak_p != null:
			if enemy.is_flying:
				leak_p.leaks_air_round += 1
			else:
				leak_p.leaks_ground_round += 1
		if _try_clash_overflow(enemy):
			_emit_enemies_remaining()
			return
	elif not _is_clash():
		game_state.lose_life(1)
	enemies_alive = maxi(enemies_alive - 1, 0)
	_emit_enemies_remaining()
	_check_wave_clear()


func _try_clash_overflow(enemy: Enemy) -> bool:
	if enemy == null or not is_instance_valid(enemy):
		return false
	if clash_match == null or clash_match.finished:
		return false
	var nxt := clash_match.next_living_after_lane(enemy.lane_id)
	if nxt == null:
		return false
	var world_path: PackedVector2Array
	if enemy.is_flying:
		world_path = grid.build_lane_air_s_path(nxt.lane_index)
	else:
		world_path = _ensure_lane_ground_path(nxt.lane_index)
	if world_path.size() < 2:
		return false
	enemy.start_overflow(world_path, nxt.lane_index, nxt.player_id)
	return true


## Mid-round Clash sends: dump queued packs into the live spawn list.
func flush_pending_clash_sends() -> int:
	if not _is_clash() or clash_match == null or clash_match.finished:
		return 0
	if game_state == null or game_state.is_game_over:
		return 0
	var added := 0
	var wave := maxi(game_state.wave, 1)
	for p in clash_match.living_players():
		var cp := p as ClashPlayerState
		for send in cp.take_incoming_sends():
			var before := spawn_queue.size()
			_append_clash_send_specs(wave, cp.lane_index, cp.player_id, str(send.get("pack_id", "scout")))
			added += spawn_queue.size() - before
	if added > 0:
		enemies_this_wave_total += added
		spawning = true
		wave_active = true
		if spawn_timer <= 0.0:
			spawn_timer = 0.05
		_emit_enemies_remaining()
	return added


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
	# Only clear once per wave — empty-board re-checks must not re-pay income/bonus.
	if not wave_active:
		return
	if enemies_alive <= 0 and spawn_queue.is_empty():
		wave_active = false
		var wave := game_state.wave
		var kills := kills_this_wave
		var bonus := 0
		if not _is_clash():
			bonus = WaveScaler.wave_clear_bonus(kills, wave)
			if bonus > 0:
				game_state.add_gold(bonus)
		_record_wave_milestones(wave)
		# Clash income must land before wave_cleared so bots spend the new gold.
		if _is_clash() and clash_match != null and not clash_match.finished:
			bonus = clash_match.award_round_income()
		wave_cleared.emit(wave, kills, bonus)
		_emit_enemies_remaining()
		if game_state.is_game_over or (_is_clash() and clash_match.finished):
			return
		# Clash: after the first Start Round, use the same intermission countdown as Classic
		# (no per-wave return to free prep / Start Round).
		var rotate_wave := 0
		if not _is_clash():
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


## Debug: spawn enemies on the player's own path (Clash: human lane). Returns how many spawned.
func debug_spawn_on_self(count: int = 5, flying: bool = false, boss: bool = false) -> int:
	if game_state == null or game_state.is_game_over:
		return 0
	if grid == null or enemy_container == null:
		return 0
	var wave := maxi(game_state.wave, 1)
	var lane_id := -1
	var defender_id := -1
	if _is_clash() and clash_match != null and clash_match.human() != null:
		lane_id = clash_match.human().lane_index
		defender_id = clash_match.human_id
		if not has_path_between_ok(lane_id) and not flying:
			return 0
	elif not flying and not has_open_path():
		return 0
	var spawned := 0
	for _i in maxi(count, 1):
		var hp: float
		var speed: float
		var bounty: int
		if boss and flying:
			hp = WaveScaler.flying_boss_hp(wave)
			speed = WaveScaler.flying_boss_speed(wave)
			bounty = WaveScaler.flying_boss_bounty(wave)
		elif boss:
			hp = WaveScaler.boss_hp(wave)
			speed = WaveScaler.boss_speed(wave)
			bounty = WaveScaler.boss_bounty(wave)
		elif flying:
			hp = WaveScaler.flying_creep_hp(wave)
			speed = WaveScaler.flying_creep_speed(wave)
			bounty = WaveScaler.flying_creep_bounty(wave)
		else:
			hp = WaveScaler.creep_hp(wave)
			speed = WaveScaler.creep_speed(wave)
			bounty = WaveScaler.creep_bounty(wave)
		var spec := _make_spawn_spec(wave, hp, speed, bounty, boss, flying)
		# Debug spawns shouldn't advance wave-clear / early-send kill tracking.
		spec["wave"] = -1
		spec["counts_kill"] = false
		spec["lane_id"] = lane_id
		spec["defender_id"] = defender_id
		if _spawn_enemy(spec):
			spawned += 1
	return spawned


func has_path_between_ok(lane: int) -> bool:
	if not _is_clash() or lane < 0:
		return has_open_path()
	return _ensure_lane_ground_path(lane).size() >= 2


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
		clear_path_blockers()
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
	if _is_clash():
		for child in enemy_container.get_children():
			if child is Enemy:
				var e := child as Enemy
				if e.is_flying:
					continue
				if e.is_wrecker:
					e.refresh_wrecker_hunt()
					continue
				if e.lane_id >= 0:
					e.set_path(_ensure_lane_ground_path(e.lane_id))
		return
	var world_path := _ensure_ground_path()
	for child in enemy_container.get_children():
		if child is Enemy:
			var e2 := child as Enemy
			if e2.is_wrecker:
				e2.refresh_wrecker_hunt()
			else:
				e2.set_path(world_path)
