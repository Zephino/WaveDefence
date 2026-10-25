class_name ClashBotAI
extends RefCounted

## Places a maze, upgrades sometimes, and queues sends for one Clash bot.

## Match-long intent: picked once in setup and kept for the whole game.
enum BuildPlan { MAZE, DPS, HYBRID }

var clash_match: ClashMatch
var grid: GameGrid
var pathfinder: Pathfinder
var enemy_container: Node
var projectile_container: Node
var trap_container: Node
var player_id: int = 1
var _rng := RandomNumberGenerator.new()
## Maze style for this match (maze/hybrid plans). Locked after setup.
var _maze_strategy: String = ""
## Economy / build intent for this match.
var _build_plan: int = BuildPlan.HYBRID
## Coalesce multi-cell wrecker smashes into one repair burst.
var _last_repair_msec: int = -99999
## In-match adaptation (Medium+): 0..1 pressure from leaked fliers / ground mobs last waves.
var _air_threat: float = 0.0
var _ground_threat: float = 0.0
var _last_learn_wave: int = -1
const REPAIR_THROTTLE_MSEC := 400


func setup(
	p_match: ClashMatch,
	p_grid: GameGrid,
	p_pathfinder: Pathfinder,
	p_enemies: Node,
	p_projectiles: Node,
	p_traps: Node,
	p_player_id: int
) -> void:
	clash_match = p_match
	grid = p_grid
	pathfinder = p_pathfinder
	enemy_container = p_enemies
	projectile_container = p_projectiles
	trap_container = p_traps
	player_id = p_player_id
	# Unique stream per bot so simultaneous setups don't share the same sequence.
	_rng.seed = hash([Time.get_ticks_usec(), player_id, randi()])
	_build_plan = _pick_build_plan()
	_maze_strategy = _pick_maze_for_plan(_build_plan)


func _difficulty() -> int:
	if clash_match == null:
		return WaveScaler.Difficulty.MEDIUM
	var p := clash_match.get_player(player_id)
	return p.bot_difficulty if p != null else WaveScaler.Difficulty.MEDIUM


func _is_smart() -> bool:
	var d := _difficulty()
	return d == WaveScaler.Difficulty.HARD or d == WaveScaler.Difficulty.CHEATER


## Easy rolls any plan (including towers-only DPS, the weakest); Hard/Cheater always maze.
func _pick_build_plan() -> int:
	var roll := _rng.randf()
	match _difficulty():
		WaveScaler.Difficulty.EASY:
			if roll < 0.34:
				return BuildPlan.MAZE
			if roll < 0.67:
				return BuildPlan.DPS
			return BuildPlan.HYBRID
		WaveScaler.Difficulty.MEDIUM:
			if roll < 0.4:
				return BuildPlan.MAZE
			if roll < 0.85:
				return BuildPlan.HYBRID
			return BuildPlan.DPS
		_:
			return BuildPlan.MAZE if roll < 0.6 else BuildPlan.HYBRID


func _pick_maze_for_plan(plan: int) -> String:
	# DPS bots skip sheet templates — they buy damage, not corridors.
	if plan == BuildPlan.DPS:
		return "scatter" if _rng.randf() < 0.5 else "greedy"
	return ClashBotMemory.choose_strategy(_rng, _difficulty())


func run_prep_turn(wave: int) -> void:
	if clash_match == null or clash_match.finished:
		return
	var p := clash_match.get_player(player_id)
	if p == null or not p.alive or p.is_human:
		return
	# Keep the match plan — do not re-roll style or intent each round.
	if _maze_strategy == "":
		_maze_strategy = _pick_maze_for_plan(_build_plan)
	var spawn := grid.get_lane_spawn(p.lane_index)
	var exit_c := grid.get_lane_exit(p.lane_index)
	pathfinder.rebuild()
	_learn_from_last_wave(p, wave)
	var len_before := pathfinder.get_cell_path_between(spawn, exit_c).size()
	match _build_plan:
		BuildPlan.MAZE:
			_prep_maze_focus(p, wave)
		BuildPlan.DPS:
			_prep_dps_focus(p, wave)
		_:
			_prep_hybrid_focus(p, wave)
	_lengthen_maze_greedy(p)
	var len_after := pathfinder.get_cell_path_between(spawn, exit_c).size()
	if len_after > len_before and _build_plan != BuildPlan.DPS:
		ClashBotMemory.record_result(_maze_strategy, len_after)
	if clash_match != null:
		clash_match.players_changed.emit()


func _prep_maze_focus(p: ClashPlayerState, wave: int) -> void:
	# Long corridor first, then overbuild walls into DPS, then fills/sends.
	_build_maze(p, wave, 1.0)
	_replace_walls_with_towers(p, wave)
	_place_combat_towers(p, wave, 16)
	_try_sends(p, wave, false)
	_upgrade_owned_towers(p, not _is_smart())
	_build_maze(p, wave, 0.45)
	_replace_walls_with_towers(p, wave)
	_place_combat_towers(p, wave, 10)
	_upgrade_owned_towers(p, _is_smart())
	_use_command_abilities(p, false)


func _prep_dps_focus(p: ClashPlayerState, wave: int) -> void:
	# Skip wall mazes — spend on combat towers and upgrades.
	_place_combat_towers(p, wave, 28)
	_try_sends(p, wave, false)
	_upgrade_owned_towers(p, not _is_smart())
	_place_combat_towers(p, wave, 16)
	_upgrade_owned_towers(p, _is_smart())
	_use_command_abilities(p, false)


func _prep_hybrid_focus(p: ClashPlayerState, wave: int) -> void:
	# Short maze sketch, then prioritize DPS over finishing every wall.
	_build_maze(p, wave, 0.4)
	_replace_walls_with_towers(p, wave)
	_place_combat_towers(p, wave, 20)
	_try_sends(p, wave, false)
	_upgrade_owned_towers(p, not _is_smart())
	_place_combat_towers(p, wave, 12)
	_upgrade_owned_towers(p, _is_smart())
	_use_command_abilities(p, false)


func run_send_turn(wave: int) -> void:
	if clash_match == null or clash_match.finished:
		return
	var p := clash_match.get_player(player_id)
	if p == null or not p.alive or p.is_human:
		return
	_try_sends(p, wave, true)
	_use_command_abilities(p, true)


## Mid-wave: refill smashed blueprint walls, then a few combat towers. Returns true if anything placed.
func repair_lane(wave: int) -> bool:
	if clash_match == null or clash_match.finished:
		return false
	var p := clash_match.get_player(player_id)
	if p == null or not p.alive or p.is_human:
		return false
	var now := Time.get_ticks_msec()
	if now - _last_repair_msec < REPAIR_THROTTLE_MSEC:
		return false
	_last_repair_msec = now
	# Wrecker damage changed the board — make sure legality checks see the real state.
	pathfinder.rebuild()
	if _maze_strategy == "":
		_maze_strategy = _pick_maze_for_plan(_build_plan)
	var placed_any := false
	if _build_plan != BuildPlan.DPS:
		placed_any = _repair_blueprint_walls(p) or placed_any
	var gold_before := p.gold
	_place_combat_towers(p, wave, 6)
	if p.gold < gold_before:
		placed_any = true
	if placed_any and clash_match != null:
		clash_match.players_changed.emit()
	return placed_any


## Patch empty maze-blueprint cells with cheap walls (emergency reserve = one send).
func _repair_blueprint_walls(p: ClashPlayerState) -> bool:
	var wall_cost: int = int(TowerData.get_def("wall")["cost"])
	var reserve := _cheapest_send_cost()
	var blueprint := _maze_blueprint(p.lane_index, _maze_strategy)
	var placed := 0
	const MAX_REPAIR_WALLS := 12
	pathfinder.rebuild()
	for cell in blueprint:
		if placed >= MAX_REPAIR_WALLS:
			break
		var spendable := p.gold - reserve
		if spendable < wall_cost:
			break
		# Same rule as a human: skip any blueprint cell that would seal the lane.
		if not _is_legal_placement(cell, "wall"):
			continue
		if not p.spend_gold(wall_cost):
			break
		if not _place_owned(cell, "wall"):
			p.add_gold(wall_cost)
			continue
		placed += 1
	if placed > 0:
		pathfinder.rebuild()
	return placed > 0


func _cheapest_send_cost() -> int:
	if WaveScaler.CLASH_SEND_PACKS.has("scout"):
		return int(WaveScaler.clash_send_pack("scout")["cost"])
	return 40


func _gold_reserve(p: ClashPlayerState) -> int:
	var ratio := 0.12
	match p.bot_difficulty:
		WaveScaler.Difficulty.EASY:
			ratio = 0.18
		WaveScaler.Difficulty.HARD, WaveScaler.Difficulty.CHEATER:
			ratio = 0.06
		_:
			ratio = 0.12
	var send := _cheapest_send_cost()
	var soft := int(float(p.gold) * ratio)
	# Keep a send reserve when flush, but never lock almost all income away from building.
	if p.gold >= send + 40:
		return maxi(soft, send)
	return mini(soft, maxi(p.gold / 3, 0))


## Buy a one-tile maze from the reference templates (or greedy/scatter). Walls sketch it; later → towers.
## budget_scale 0..1 limits how much of this prep goes into walls vs saving for DPS.
func _build_maze(p: ClashPlayerState, wave: int, budget_scale: float = 1.0) -> void:
	var spawn := grid.get_lane_spawn(p.lane_index)
	var exit_c := grid.get_lane_exit(p.lane_index)
	var wall_cost: int = int(TowerData.get_def("wall")["cost"])
	var gunner_cost: int = int(TowerData.get_def("gunner")["cost"])
	var use_template := ClashMazeTemplates.is_template(_maze_strategy)
	var scale := clampf(budget_scale, 0.15, 1.0)
	# Templates need many walls, but hybrid/partial budgets stop early for DPS gold.
	var max_pieces := int(round(float(98 if use_template else 48) * scale))
	if use_template and p.bot_difficulty == WaveScaler.Difficulty.EASY:
		# Easy only sketches part of a template — sloppier, shorter corridors.
		max_pieces = int(round(float(max_pieces) * 0.55))
	if not use_template:
		match p.bot_difficulty:
			WaveScaler.Difficulty.EASY:
				max_pieces = int(round(32.0 * scale))
			WaveScaler.Difficulty.HARD:
				max_pieces = int(round(56.0 * scale))
			_:
				max_pieces = int(round(48.0 * scale))
	max_pieces = maxi(max_pieces, 4)
	var blueprint := _maze_blueprint(p.lane_index, _maze_strategy)
	# Always keep gold for combat — denser maze plans reserve less, DPS-friendly more.
	var combat_floor := gunner_cost * (3 if _build_plan == BuildPlan.MAZE else 6)
	var reserve := maxi(_gold_reserve(p), combat_floor)
	var placed := 0
	for cell in blueprint:
		if placed >= max_pieces:
			break
		var spendable := p.gold - reserve
		if spendable < wall_cost:
			break
		if not grid.is_buildable(cell):
			continue
		# Templates used to skip this check; partial templates + other towers could seal the lane.
		if not _is_legal_placement(cell, "wall"):
			continue
		# Templates stick to walls; non-templates may drop early combat pieces.
		var piece_id := "wall"
		if not use_template and spendable >= gunner_cost and _rng.randf() < 0.18:
			var tid := _pick_affordable_tower_id(wave, p.bot_difficulty, spendable)
			if tid != "" and not TowerData.is_wall(tid):
				piece_id = tid
		var cost: int = int(TowerData.get_def(piece_id)["cost"])
		if cost > spendable or not p.spend_gold(cost):
			break
		if not _place_owned(cell, piece_id):
			p.add_gold(cost)
			continue
		placed += 1
	if placed > 0:
		pathfinder.rebuild()
	# Non-template / leftover: greedy lengthening (capped — rebuilds are expensive).
	var greedy_left := 0 if use_template else int(round(8.0 * scale))
	reserve = maxi(_gold_reserve(p), combat_floor)
	while greedy_left > 0 and p.gold > reserve and placed < max_pieces:
		greedy_left -= 1
		var spendable2 := p.gold - reserve
		if spendable2 < wall_cost:
			break
		var cell2 := _best_maze_cell(spawn, exit_c, p.lane_index)
		if cell2.x < 0:
			break
		var piece2 := "wall"
		if spendable2 >= gunner_cost and _rng.randf() < 0.35:
			var tid2 := _pick_affordable_tower_id(wave, p.bot_difficulty, spendable2)
			if tid2 != "" and not TowerData.is_wall(tid2):
				piece2 = tid2
		var cost2: int = int(TowerData.get_def(piece2)["cost"])
		if cost2 > spendable2 or not p.spend_gold(cost2):
			break
		if not _place_owned(cell2, piece2):
			p.add_gold(cost2)
			break
		placed += 1


## Blueprint = tower slots for a 7×15 one-tile path template (or legacy fallbacks).
func _maze_blueprint(lane: int, strategy: String) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if ClashMazeTemplates.is_template(strategy):
		# Keep template order — partial shuffled fills open shortcuts.
		return ClashMazeTemplates.tower_cells_for_lane(grid, lane, strategy)
	var r: Vector2i = grid.lane_col_ranges[lane]
	var spawn := grid.get_lane_spawn(lane)
	var exit_c := grid.get_lane_exit(lane)
	match strategy:
		"scatter":
			for _i in 14:
				var cell3 := Vector2i(_rng.randi_range(r.x, r.y), _rng.randi_range(2, grid.rows - 3))
				if cell3 != spawn and cell3 != exit_c:
					out.append(cell3)
		_:
			pass
	for i in range(out.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var tmp := out[i]
		out[i] = out[j]
		out[j] = tmp
	return out


func _place_combat_towers(p: ClashPlayerState, wave: int, max_place: int = 20) -> void:
	var reserve := _gold_reserve(p)
	var spawn := grid.get_lane_spawn(p.lane_index)
	var exit_c := grid.get_lane_exit(p.lane_index)
	var placed := 0
	var cap := maxi(max_place, 1)
	var attempts := 0
	while p.gold > reserve and placed < cap and attempts < 48:
		attempts += 1
		var spendable := p.gold - reserve
		var path_cells := pathfinder.get_cell_path_between(spawn, exit_c)
		var candidates := _build_combat_candidates(p.lane_index, path_cells)
		var tower_id := ""
		var cell := Vector2i(-1, -1)
		if _is_smart():
			var pick := _best_tower_and_cell(spendable, candidates, path_cells, spawn, exit_c, p.lane_index)
			if not pick.is_empty():
				tower_id = str(pick["id"])
				cell = pick["cell"]
		if tower_id == "":
			tower_id = _pick_affordable_tower_id(wave, p.bot_difficulty, spendable)
			if tower_id == "" or TowerData.is_wall(tower_id):
				break
			cell = _choose_combat_cell(tower_id, candidates, path_cells, spawn, exit_c, p.lane_index)
		var melee := TowerData.is_melee(tower_id)
		# Melee must stay path-adjacent; ranged may fill any empty lane cell later.
		if cell.x < 0 and not melee:
			cell = _next_open_lane_cell_for(tower_id, p.lane_index, spawn, exit_c)
		if cell.x < 0:
			continue
		var cost: int = int(TowerData.get_def(tower_id)["cost"])
		if not p.spend_gold(cost):
			break
		if not _place_owned(cell, tower_id):
			p.add_gold(cost)
			continue
		placed += 1


## Build combat towers over walls (same cell) — walls are the maze platforms.
## Prefers path-adjacent / corner walls so one tower covers multiple corridor segments.
func _replace_walls_with_towers(p: ClashPlayerState, wave: int) -> void:
	var reserve := _gold_reserve(p)
	var max_swaps := 18
	match p.bot_difficulty:
		WaveScaler.Difficulty.EASY:
			max_swaps = 14
		WaveScaler.Difficulty.HARD:
			max_swaps = 28
		WaveScaler.Difficulty.CHEATER:
			max_swaps = 40
		_:
			max_swaps = 22
	var spawn := grid.get_lane_spawn(p.lane_index)
	var exit_c := grid.get_lane_exit(p.lane_index)
	var path_cells := pathfinder.get_cell_path_between(spawn, exit_c)
	var swapped := 0
	while p.gold > reserve and swapped < max_swaps:
		var spendable := p.gold - reserve
		var tower_id := ""
		var wall_cell := Vector2i(-1, -1)
		if _is_smart():
			# Hard/Cheater: best (tower type, own wall) pair by damage on the path per gold.
			var pick := _best_wall_swap(spendable, p.lane_index, path_cells)
			if pick.is_empty():
				break
			tower_id = str(pick["id"])
			wall_cell = pick["cell"]
		else:
			tower_id = _pick_affordable_tower_id(wave, p.bot_difficulty, spendable)
			if tower_id == "" or TowerData.is_wall(tower_id):
				break
			# Multi-cell towers need a clear footprint — cannot overbuild a single wall.
			if TowerData.footprint_size(tower_id) > 1:
				continue
			# Melee only overbuilds walls that actually touch the path.
			wall_cell = _best_wall_to_overbuild(p.lane_index, path_cells, TowerData.is_melee(tower_id))
		var cost: int = int(TowerData.get_def(tower_id)["cost"])
		if wall_cell.x < 0:
			break
		if not p.spend_gold(cost):
			break
		var removed := grid.remove_tower_at(wall_cell, false)
		if removed != null and is_instance_valid(removed):
			removed.queue_free()
		if not _place_owned(wall_cell, tower_id, true):
			p.add_gold(cost)
			_place_owned(wall_cell, "wall", true)
			break
		# Path unchanged when swapping wall→tower; skip rebuild.
		swapped += 1
		# Refresh path adjacency scoring occasionally as coverage grows.
		if swapped % 6 == 0:
			path_cells = pathfinder.get_cell_path_between(spawn, exit_c)


func _best_wall_swap(gold: int, lane: int, path_cells: Array[Vector2i]) -> Dictionary:
	var walls: Array[Vector2i] = []
	for cell in grid.towers.keys():
		if grid.lane_index_for_cell(cell) != lane:
			continue
		var node: Node = grid.towers[cell]
		if node is Tower and node.has_meta("clash_owner") and int(node.get_meta("clash_owner")) == player_id \
				and TowerData.is_wall((node as Tower).tower_id):
			walls.append(cell)
	if walls.is_empty():
		return {}
	var best := {}
	var best_v := 0.0
	for id in _combat_tower_pool():
		if TowerData.footprint_size(id) > 1 or TowerData.is_command(id):
			continue
		var d: Dictionary = TowerData.get_def(id)
		var cost := float(d.get("cost", 0))
		if cost <= 0.0 or cost > float(gold) or float(d.get("damage", 0.0)) <= 0.0:
			continue
		var per := _tower_dps(id, 0, "") / cost * _threat_mult(d) * (0.5 + ClashBotMemory.tower_reward(id))
		for wc in walls:
			var v := per * _coverage_score(wc, id, path_cells) * (1.0 + _rng.randf() * 0.03)
			if v > best_v:
				best_v = v
				best = {"id": id, "cell": wc}
	return best


## Highest-value owned wall: more orthogonal path neighbors = better overbuild target.
## When require_path_touch is true (melee), walls with 0 path neighbors are ignored.
func _best_wall_to_overbuild(
	lane: int, path_cells: Array[Vector2i], require_path_touch: bool = false
) -> Vector2i:
	var path_set: Dictionary = {}
	for c in path_cells:
		path_set[c] = true
	var best := Vector2i(-1, -1)
	var best_score := -1
	for cell in grid.towers.keys():
		if grid.lane_index_for_cell(cell) != lane:
			continue
		var node: Node = grid.towers[cell]
		if not (node is Tower):
			continue
		var tower := node as Tower
		if not tower.has_meta("clash_owner") or int(tower.get_meta("clash_owner")) != player_id:
			continue
		if not TowerData.is_wall(tower.tower_id):
			continue
		var adj := 0
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			if path_set.has(cell + d):
				adj += 1
		if require_path_touch and adj < 1:
			continue
		# Corners (2+) beat single-edge walls; slight bias toward mid-lane.
		var score := adj * 30 + (grid.rows - absi(cell.y - grid.rows / 2))
		if score > best_score:
			best_score = score
			best = cell
	return best


func _next_open_lane_cell(lane: int, spawn: Vector2i, exit_c: Vector2i) -> Vector2i:
	return _next_open_lane_cell_for("gunner", lane, spawn, exit_c)


func _next_open_lane_cell_for(tower_id: String, lane: int, spawn: Vector2i, exit_c: Vector2i) -> Vector2i:
	var r: Vector2i = grid.lane_col_ranges[lane]
	var cells: Array[Vector2i] = []
	for y in range(1, grid.rows - 1):
		for x in range(r.x, r.y + 1):
			var cell := Vector2i(x, y)
			if grid.is_buildable(cell):
				cells.append(cell)
	# Prefer mid-lane empties; shuffle lightly.
	cells.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		var da := absi(a.y - grid.rows / 2)
		var db := absi(b.y - grid.rows / 2)
		return da > db
	)
	while not cells.is_empty():
		var cell2: Vector2i = cells.pop_back()
		if _can_bot_place(cell2, tower_id, spawn, exit_c):
			return cell2
	return Vector2i(-1, -1)


func _next_place_cell_for(
	tower_id: String, candidates: Array[Vector2i], spawn: Vector2i, exit_c: Vector2i
) -> Vector2i:
	for cell in candidates:
		if _can_bot_place(cell, tower_id, spawn, exit_c):
			return cell
	return Vector2i(-1, -1)


func _can_bot_place(cell: Vector2i, tower_id: String, spawn: Vector2i, exit_c: Vector2i) -> bool:
	var footprint := TowerData.footprint_size(tower_id)
	if footprint > 1:
		if not grid.footprint_in_bounds(cell, footprint):
			return false
		if grid.footprint_touches_map_corner(cell, footprint):
			return false
		var lane := grid.lane_index_for_cell(cell)
		for c in TowerData.footprint_cells(cell, footprint):
			if grid.lane_index_for_cell(c) != lane:
				return false
			if grid.is_clash_spawn_or_exit(c):
				return false
			if not grid.is_buildable(c):
				return false
		return not pathfinder.would_block_path_between_cells(
			spawn, exit_c, TowerData.path_block_cells(cell, tower_id)
		)
	if not grid.is_buildable(cell):
		return false
	return not pathfinder.would_block_path_between(spawn, exit_c, cell)


## Every bot placement goes through here and must pass the same rules a human gets in
## BuildSystem.can_place_at: own lane, not spawn/exit, buildable, and never sealing spawn→exit.
## replacing_wall: overbuilding one of our own walls (path is unchanged, like the human wall swap).
func _place_owned(cell: Vector2i, tower_id: String, replacing_wall: bool = false) -> bool:
	if not _is_legal_placement(cell, tower_id, replacing_wall):
		return false
	var tower := Tower.new()
	tower.setup(tower_id, enemy_container, projectile_container)
	tower.set_meta("clash_owner", player_id)
	grid.place_tower(cell, tower)
	# Keep the pathfinder current so the NEXT legality check sees this piece.
	pathfinder.rebuild()
	return true


func _is_legal_placement(cell: Vector2i, tower_id: String, replacing_wall: bool = false) -> bool:
	if not grid.in_bounds(cell) or grid.is_clash_spawn_or_exit(cell):
		return false
	var p := clash_match.get_player(player_id) if clash_match != null else null
	if p == null or grid.lane_index_for_cell(cell) != p.lane_index:
		return false
	if replacing_wall:
		return TowerData.footprint_size(tower_id) == 1 and grid.get_tower_at(cell) == null
	return _can_bot_place(cell, tower_id, grid.get_lane_spawn(p.lane_index), grid.get_lane_exit(p.lane_index))


## Pick the buildable lane cell that lengthens the path the most without sealing it.
func _best_maze_cell(spawn: Vector2i, exit_c: Vector2i, lane: int) -> Vector2i:
	var path_cells := pathfinder.get_cell_path_between(spawn, exit_c)
	if path_cells.size() < 2:
		return Vector2i(-1, -1)
	var base_len := path_cells.size()
	var path_set: Dictionary = {}
	for c in path_cells:
		path_set[c] = true
	var r: Vector2i = grid.lane_col_ranges[lane]
	var best := Vector2i(-1, -1)
	var best_score := -1
	# Prefer path cells and path-adjacent cells that force a detour.
	var candidates: Array[Vector2i] = []
	for c in path_cells:
		if c == spawn or c == exit_c:
			continue
		candidates.append(c)
	for y in range(1, grid.rows - 1):
		for x in range(r.x, r.y + 1):
			var cell := Vector2i(x, y)
			if path_set.has(cell) or not grid.is_buildable(cell):
				continue
			var adj := false
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				if path_set.has(cell + d):
					adj = true
					break
			if adj:
				candidates.append(cell)
	for cell in candidates:
		if not grid.is_buildable(cell):
			continue
		if pathfinder.would_block_path_between(spawn, exit_c, cell):
			continue
		var new_len := pathfinder.path_length_with_block(spawn, exit_c, cell)
		if new_len <= 0:
			continue
		var gain := new_len - base_len
		# Prefer lengthening; on ties favor mid-lane path cells (real maze bits).
		var score := gain * 100
		if path_set.has(cell):
			score += 40
		score += (grid.rows - absi(cell.y - grid.rows / 2))
		score += _rng.randi_range(0, 5)
		if score > best_score:
			best_score = score
			best = cell
	# Even if no length gain, still place a safe path choke when possible.
	if best.x < 0:
		for cell2 in path_cells:
			if cell2 == spawn or cell2 == exit_c:
				continue
			if not grid.is_buildable(cell2):
				continue
			if pathfinder.would_block_path_between(spawn, exit_c, cell2):
				continue
			return cell2
	return best


func _upgrade_owned_towers(p: ClashPlayerState, force: bool = false) -> void:
	# Easy upgrades sometimes; Medium/Hard more often. Forced pass spends leftovers.
	var upgrade_chance := 0.35
	var max_upgrades := 2
	match p.bot_difficulty:
		WaveScaler.Difficulty.EASY:
			upgrade_chance = 0.35
			max_upgrades = 3
		WaveScaler.Difficulty.HARD:
			upgrade_chance = 0.9
			max_upgrades = 12
		WaveScaler.Difficulty.CHEATER:
			upgrade_chance = 1.0
			max_upgrades = 16
		_:
			upgrade_chance = 0.55
			max_upgrades = 6
	if force:
		upgrade_chance = 1.0
		max_upgrades = maxi(max_upgrades, 6)
	if _rng.randf() > upgrade_chance:
		return
	var reserve := _gold_reserve(p)
	var towers := _owned_towers_in_lane(p.lane_index)
	var upgraded := 0
	# Hard/Cheater upgrade the towers that cover the most path first (gold per covered cell),
	# instead of whatever is cheapest.
	var smart := _is_smart()
	var up_path: Array[Vector2i] = []
	var new_tower_value := 0.0
	if smart:
		up_path = pathfinder.get_cell_path_between(
			grid.get_lane_spawn(p.lane_index), grid.get_lane_exit(p.lane_index)
		)
		new_tower_value = _best_new_tower_value(p.lane_index, up_path)
	while p.gold > reserve and upgraded < max_upgrades:
		var best: Tower = null
		var best_cost := 1 << 30
		var want_final := false
		var best_key := INF
		for tower in towers:
			if tower == null or not is_instance_valid(tower):
				continue
			if TowerData.is_wall(tower.tower_id) or TowerData.is_command(tower.tower_id):
				continue
			if tower.can_stat_upgrade():
				var cost := tower.next_stat_upgrade_cost()
				if cost <= 0 or cost > p.gold - reserve:
					continue
				var key := float(cost)
				if smart:
					# Lower key = more damage-on-path gained per gold.
					var gain := _tower_dps(tower.tower_id, tower.upgrade_level + 1, tower.final_element) - _tower_dps(tower.tower_id, tower.upgrade_level, tower.final_element)
					var val := gain * _coverage_score(_tower_cell(tower), tower.tower_id, up_path) / maxf(float(cost), 1.0)
					# Only upgrade when it beats buying a fresh tower in the best open spot.
					if not force and val < new_tower_value * 0.9:
						continue
					key = -val
				if key < best_key:
					best_key = key
					best_cost = cost
					best = tower
					want_final = false
			elif tower.can_final_upgrade():
				var fcost := tower.final_upgrade_cost()
				if fcost <= 0 or fcost > p.gold - reserve:
					continue
				# Prefer finishing a tower once stats are done (slight priority over cheaper stats).
				var fkey := float(fcost - 5)
				if smart:
					# Finals add a light buff; treat as ~15% more damage on the path.
					var fval := _tower_dps(tower.tower_id, tower.upgrade_level, "") * 0.15 * _coverage_score(_tower_cell(tower), tower.tower_id, up_path) / maxf(float(fcost), 1.0)
					if not force and fval < new_tower_value * 0.9:
						continue
					fkey = -fval
				if fkey < best_key:
					best_key = fkey
					best_cost = fcost
					best = tower
					want_final = true
		if best == null:
			break
		if want_final:
			var element := _pick_final_element(best)
			var fpay := best.final_upgrade_cost()
			if not p.spend_gold(fpay):
				break
			best.apply_final_element(element)
		else:
			if not p.spend_gold(best_cost):
				break
			best.apply_stat_upgrade()
		upgraded += 1


func _tower_dps(tower_id: String, level: int, final_element: String) -> float:
	var d: Dictionary = TowerData.combat_def(tower_id, level, final_element)
	var splash := float(d.get("splash_radius", 0.0))
	var dot := float(d.get("burn_dps", 0.0)) + float(d.get("poison_dps", 0.0))
	return float(d.get("damage", 0.0)) * float(d.get("fire_rate", 0.0)) * (1.0 + splash / 40.0) + dot


## Damage-on-path per gold of the best affordable new tower in the best open spot (0 = no room).
func _best_new_tower_value(lane: int, path_cells: Array[Vector2i]) -> float:
	var cands := _build_combat_candidates(lane, path_cells)
	if cands.is_empty():
		return 0.0
	var best := 0.0
	var spawn := grid.get_lane_spawn(lane)
	var exit_c := grid.get_lane_exit(lane)
	for tid in ["gunner", "rapid", "cannon"]:
		var cost := maxf(float(TowerData.get_def(tid).get("cost", 1)), 1.0)
		var top := 0.0
		for c in cands:
			var cov := _coverage_score(c, tid, path_cells)
			if cov > top and _can_bot_place(c, tid, spawn, exit_c):
				top = cov
		best = maxf(best, _tower_dps(tid, 0, "") * top / cost)
	return best


func _tower_cell(tower: Tower) -> Vector2i:
	for cell in grid.towers.keys():
		if grid.towers[cell] == tower:
			return cell
	return Vector2i(-1, -1)


func _pick_final_element(tower: Tower) -> String:
	# Match native element when the tower already is one; otherwise pick any final.
	match tower.tower_id:
		"burn":
			return "burn"
		"freeze":
			return "freeze"
		"poison":
			return "poison"
		"lightning":
			return "lightning"
		_:
			var opts: Array = TowerData.FINAL_ELEMENTS
			return str(opts[_rng.randi_range(0, opts.size() - 1)])


func _owned_towers_in_lane(lane: int) -> Array[Tower]:
	var out: Array[Tower] = []
	var seen: Dictionary = {}
	for cell in grid.towers.keys():
		if grid.lane_index_for_cell(cell) != lane:
			continue
		var node: Node = grid.towers[cell]
		if node is Tower:
			var tower := node as Tower
			if seen.has(tower):
				continue
			if tower.has_meta("clash_owner") and int(tower.get_meta("clash_owner")) == player_id:
				seen[tower] = true
				out.append(tower)
	return out


func _owned_command_tower(lane: int) -> Tower:
	for tower in _owned_towers_in_lane(lane):
		if TowerData.is_command(tower.tower_id):
			return tower
	return null


## Any combat tower the bot can afford right now (no wave/difficulty unlock gates).
func _pick_affordable_tower_id(_wave: int, difficulty: int, gold: int) -> String:
	var affordable: Array[String] = []
	var lane := -1
	if clash_match != null:
		var cp := clash_match.get_player(player_id)
		if cp != null:
			lane = cp.lane_index
	var has_command := lane >= 0 and _owned_command_tower(lane) != null
	for id in _combat_tower_pool():
		if TowerData.is_command(id) and has_command:
			continue
		var cost: int = int(TowerData.get_def(id)["cost"])
		if cost > 0 and cost <= gold:
			affordable.append(id)
	if affordable.is_empty():
		return ""
	# Easy: uniform among affordable (money is the only gate). Medium mixes in some randomness.
	if difficulty == WaveScaler.Difficulty.EASY:
		return affordable[_rng.randi_range(0, affordable.size() - 1)]
	if difficulty == WaveScaler.Difficulty.MEDIUM and _rng.randf() < 0.5:
		return affordable[_rng.randi_range(0, affordable.size() - 1)]
	var sharp := difficulty == WaveScaler.Difficulty.HARD or difficulty == WaveScaler.Difficulty.CHEATER
	var weights: Array[float] = []
	var total := 0.0
	for id in affordable:
		var w := _tower_weight(id)
		if sharp:
			w = w * w
		weights.append(w)
		total += w
	var roll := _rng.randf() * total
	for i in affordable.size():
		roll -= weights[i]
		if roll <= 0.0:
			return affordable[i]
	return affordable[affordable.size() - 1]


## How much a Medium+ bot wants a tower: damage per gold, adjusted for what is leaking
## (fliers → air-capable towers) and for what memory says has worked in past matches.
func _tower_weight(tower_id: String) -> float:
	var d: Dictionary = TowerData.get_def(tower_id)
	var cost := maxf(float(d.get("cost", 1)), 1.0)
	var w: float
	if TowerData.is_command(tower_id):
		w = 1.6
	elif float(d.get("damage", 0.0)) <= 0.0:
		# Utility (e.g. Vortex): worth it for maze builders, less so for scatter/DPS bots.
		w = 1.2 if _build_plan != BuildPlan.DPS else 0.5
	else:
		var splash := float(d.get("splash_radius", 0.0))
		var dps := float(d.get("damage", 0.0)) * float(d.get("fire_rate", 1.0)) * (1.0 + splash / 40.0)
		w = clampf(dps / cost * 10.0, 0.05, 6.0)
	# Short-range (melee) towers reach far less of the path than their DPS suggests.
	var tiles := float(d.get("range", 0.0)) / maxf(float(grid.tile_px()), 1.0)
	if TowerData.is_melee(tower_id):
		tiles = 1.0
	if float(d.get("damage", 0.0)) > 0.0:
		w *= clampf(tiles / 3.0, 0.35, 1.4)
	w *= _threat_mult(d)
	w *= 0.5 + ClashBotMemory.tower_reward(tower_id)
	return maxf(w, 0.02)


func _threat_mult(d: Dictionary) -> float:
	match TowerData.target_filter(d):
		"air":
			return 0.25 + 2.5 * _air_threat
		"ground":
			return 1.0 - 0.45 * _air_threat
		_:
			return 1.0 + 0.5 * _air_threat


## Hard/Cheater: choose tower type AND spot together — the pair that puts the most damage on
## the path per gold (adjusted for flier pressure and learned tower rewards).
func _best_tower_and_cell(
	gold: int, candidates: Array[Vector2i], path_cells: Array[Vector2i],
	spawn: Vector2i, exit_c: Vector2i, lane: int
) -> Dictionary:
	var has_command := _owned_command_tower(lane) != null
	var combat_count := 0
	for t in _owned_towers_in_lane(lane):
		if t != null and is_instance_valid(t) and not TowerData.is_wall(t.tower_id):
			combat_count += 1
	var best := {}
	var best_v := 0.0
	var dmg_values: Array[float] = []
	var utility: Array = []
	for id in _combat_tower_pool():
		if TowerData.is_command(id) and has_command:
			continue
		var d: Dictionary = TowerData.get_def(id)
		var cost := float(d.get("cost", 0))
		if cost <= 0.0 or cost > float(gold):
			continue
		if float(d.get("damage", 0.0)) <= 0.0 or TowerData.is_command(id):
			utility.append(id)
			continue
		var cell := _choose_combat_cell(id, candidates, path_cells, spawn, exit_c, lane)
		if cell.x < 0:
			continue
		var v := _tower_dps(id, 0, "") * _coverage_score(cell, id, path_cells) / cost
		v *= _threat_mult(d) * (0.5 + ClashBotMemory.tower_reward(id))
		v *= 1.0 + _rng.randf() * 0.05
		dmg_values.append(v)
		if v > best_v:
			best_v = v
			best = {"id": id, "cell": cell}
	# Support/utility (Command, Vortex) once there is a real defence to support.
	if combat_count >= 4 and not dmg_values.is_empty():
		var avg := 0.0
		for x in dmg_values:
			avg += x
		avg /= float(dmg_values.size())
		for uid in utility:
			var uv := avg * (0.9 if TowerData.is_command(uid) else 0.7)
			if _build_plan == BuildPlan.DPS and not TowerData.is_command(uid):
				uv *= 0.5
			if uv > best_v:
				var ucell := _choose_combat_cell(uid, candidates, path_cells, spawn, exit_c, lane)
				if ucell.x >= 0:
					best_v = uv
					best = {"id": uid, "cell": ucell}
	return best


## Path cells this tower would cover from `cell` (corners of a serpentine count twice — that
## is exactly why mazes work).
func _coverage_score(cell: Vector2i, tower_id: String, path_cells: Array[Vector2i]) -> float:
	var d: Dictionary = TowerData.get_def(tower_id)
	var tiles := float(d.get("range", 0.0)) / maxf(float(grid.tile_px()), 1.0)
	if TowerData.is_melee(tower_id):
		tiles = 1.01
	if tiles <= 0.0:
		tiles = 1.5
	var r2 := tiles * tiles
	var n := 0
	for c in path_cells:
		var dx := float(c.x - cell.x)
		var dy := float(c.y - cell.y)
		if dx * dx + dy * dy <= r2:
			n += 1
	return float(n)


## Where to put a combat tower. Easy: first legal spot (sometimes a random open cell).
## Medium: one of the top few by path coverage. Hard/Cheater: the single best legal spot.
func _choose_combat_cell(
	tower_id: String, candidates: Array[Vector2i], path_cells: Array[Vector2i],
	spawn: Vector2i, exit_c: Vector2i, lane: int
) -> Vector2i:
	var diff := _difficulty()
	if diff == WaveScaler.Difficulty.EASY:
		if not TowerData.is_melee(tower_id) and _rng.randf() < 0.3:
			var sloppy := _next_open_lane_cell_for(tower_id, lane, spawn, exit_c)
			if sloppy.x >= 0:
				return sloppy
		return _next_place_cell_for(tower_id, candidates, spawn, exit_c)
	var scored: Array = []
	for cell in candidates:
		scored.append({"cell": cell, "score": _coverage_score(cell, tower_id, path_cells) + _rng.randf() * 0.01})
	scored.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["score"]) > float(b["score"])
	)
	var legal: Array[Vector2i] = []
	var want := 1 if diff != WaveScaler.Difficulty.MEDIUM else 6
	for item in scored:
		var c2: Vector2i = item["cell"]
		if _can_bot_place(c2, tower_id, spawn, exit_c):
			legal.append(c2)
			if legal.size() >= want:
				break
	if legal.is_empty():
		return Vector2i(-1, -1)
	return legal[_rng.randi_range(0, legal.size() - 1)]


## After each wave: read leaks, adapt this match (Medium+), and teach the shared memory.
func _learn_from_last_wave(p: ClashPlayerState, wave: int) -> void:
	var air := p.leaks_air_round
	var ground := p.leaks_ground_round
	p.leaks_air_round = 0
	p.leaks_ground_round = 0
	if wave <= 1 or wave == _last_learn_wave:
		return
	_last_learn_wave = wave
	if _difficulty() != WaveScaler.Difficulty.EASY:
		_air_threat = clampf(_air_threat * 0.6 + clampf(float(air) / 3.0, 0.0, 1.0) * 0.6, 0.0, 1.0)
		_ground_threat = clampf(_ground_threat * 0.6 + clampf(float(ground) / 4.0, 0.0, 1.0) * 0.6, 0.0, 1.0)
	var spawn := grid.get_lane_spawn(p.lane_index)
	var exit_c := grid.get_lane_exit(p.lane_index)
	var plen := pathfinder.get_cell_path_between(spawn, exit_c).size()
	var ids: Array = []
	for t in _owned_towers_in_lane(p.lane_index):
		if t != null and is_instance_valid(t) and not TowerData.is_wall(t.tower_id):
			ids.append(t.tower_id)
	var style := _maze_strategy if _build_plan != BuildPlan.DPS else ""
	ClashBotMemory.record_wave(style, plen, air + ground, ids)


## Smart bots keep stretching the corridor with cheap walls where it adds the most length;
## Medium only does it when ground mobs are leaking. Always legal (never seals the lane).
func _lengthen_maze_greedy(p: ClashPlayerState) -> void:
	var walls := 0
	match _difficulty():
		WaveScaler.Difficulty.HARD:
			walls = 6
		WaveScaler.Difficulty.CHEATER:
			walls = 8
		WaveScaler.Difficulty.MEDIUM:
			walls = 3 if _ground_threat > 0.3 else 0
		_:
			walls = 0
	if _ground_threat > 0.3:
		walls += 4
	if walls <= 0 or _build_plan == BuildPlan.DPS:
		return
	var wall_cost: int = int(TowerData.get_def("wall")["cost"])
	var reserve := _gold_reserve(p)
	var spawn := grid.get_lane_spawn(p.lane_index)
	var exit_c := grid.get_lane_exit(p.lane_index)
	for _i in walls:
		if p.gold - reserve < wall_cost:
			break
		var base_len := pathfinder.get_cell_path_between(spawn, exit_c).size()
		var cell := _best_maze_cell(spawn, exit_c, p.lane_index)
		if cell.x < 0:
			break
		if pathfinder.path_length_with_block(spawn, exit_c, cell) <= base_len:
			break  # no real gain left
		if not p.spend_gold(wall_cost):
			break
		if not _place_owned(cell, "wall"):
			p.add_gold(wall_cost)
			break


## Full combat shop for Clash bots. Walls stay maze-only; Command is allowed (one per lane).
func _combat_tower_pool() -> Array[String]:
	var pool: Array[String] = []
	for id in TowerData.get_ids():
		if TowerData.is_wall(id):
			continue
		pool.append(id)
	return pool


## Fire Command abilities from an owned Command hub (prep or mid-wave).
func _use_command_abilities(p: ClashPlayerState, during_wave: bool) -> void:
	var cmd := _owned_command_tower(p.lane_index)
	if cmd == null or trap_container == null:
		return
	var chance := 0.45
	var max_casts := 1
	match p.bot_difficulty:
		WaveScaler.Difficulty.EASY:
			chance = 0.25
			max_casts = 1
		WaveScaler.Difficulty.HARD:
			chance = 0.7
			max_casts = 2
		WaveScaler.Difficulty.CHEATER:
			chance = 0.85
			max_casts = 3
		_:
			chance = 0.5
			max_casts = 1
	if during_wave:
		chance = minf(chance + 0.15, 0.95)
		max_casts += 1
	if _rng.randf() > chance:
		return
	var reserve := _gold_reserve(p)
	var casts := 0
	while casts < max_casts and p.gold > reserve:
		var ability_id := _pick_command_ability(cmd, p.gold - reserve)
		if ability_id == "":
			break
		var cell := _command_aim_cell(ability_id, p.lane_index)
		if cell.x < 0:
			break
		var cost := CommandAbilities.cost(ability_id)
		if cost > p.gold - reserve:
			break
		var result := CommandCaster.place(
			ability_id, cell, grid, pathfinder, enemy_container, trap_container
		)
		if not bool(result.get("ok", false)):
			break
		if not p.spend_gold(cost):
			break
		cmd.start_ability_cooldown(ability_id, CommandAbilities.cooldown(ability_id))
		cmd.play_visual_action("action")
		casts += 1


func _pick_command_ability(cmd: Tower, budget: int) -> String:
	var options: Array[String] = []
	for id in CommandAbilities.get_ids():
		if cmd.ability_cooldown_left(str(id)) > 0.05:
			continue
		if CommandAbilities.cost(str(id)) > budget:
			continue
		options.append(str(id))
	if options.is_empty():
		return ""
	# Prefer damaging/slow traps during fights; still allow supply.
	if options.has("airstrike") and _rng.randf() < 0.4:
		return "airstrike"
	if options.has("barricade") and _rng.randf() < 0.35:
		return "barricade"
	return options[_rng.randi_range(0, options.size() - 1)]


func _command_aim_cell(ability_id: String, lane: int) -> Vector2i:
	var spawn := grid.get_lane_spawn(lane)
	var exit_c := grid.get_lane_exit(lane)
	if CommandAbilities.aim_mode(ability_id) == "path":
		var path_cells := pathfinder.get_cell_path_between(spawn, exit_c)
		if path_cells.size() < 3:
			return Vector2i(-1, -1)
		# Aim mid-path so traps trigger before the exit.
		var mid := path_cells[path_cells.size() / 2]
		var check := CommandCaster.validate_aim(ability_id, mid, grid, pathfinder)
		if bool(check.get("ok", false)):
			return mid
		# Fallback: try a few random path tiles.
		for _i in 6:
			var cell: Vector2i = path_cells[_rng.randi_range(1, path_cells.size() - 2)]
			var ok := CommandCaster.validate_aim(ability_id, cell, grid, pathfinder)
			if bool(ok.get("ok", false)):
				return cell
		return Vector2i(-1, -1)
	# Supply Drop: aim at a dense owned combat cluster.
	var towers := _owned_towers_in_lane(lane)
	var best := Vector2i(-1, -1)
	var best_n := 0
	for tower in towers:
		if TowerData.is_wall(tower.tower_id) or TowerData.is_command(tower.tower_id):
			continue
		var anchor: Vector2i = tower.get_meta("anchor_cell", grid.world_to_cell(tower.position))
		var n := 0
		for other in towers:
			if TowerData.is_wall(other.tower_id) or TowerData.is_command(other.tower_id):
				continue
			var oc: Vector2i = other.get_meta("anchor_cell", grid.world_to_cell(other.position))
			if absi(oc.x - anchor.x) + absi(oc.y - anchor.y) <= 2:
				n += 1
		if n > best_n:
			best_n = n
			best = anchor
	return best


func _build_combat_candidates(lane: int, path_cells: Array[Vector2i]) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var path_set: Dictionary = {}
	for c in path_cells:
		path_set[c] = true
	var r: Vector2i = grid.lane_col_ranges[lane]
	var scored: Array = []
	for y in range(1, grid.rows - 1):
		for x in range(r.x, r.y + 1):
			var cell := Vector2i(x, y)
			if path_set.has(cell) or not grid.is_buildable(cell):
				continue
			var adj := 0
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				if path_set.has(cell + d):
					adj += 1
			if adj > 0:
				scored.append({"cell": cell, "score": adj * 20 + (grid.rows - y)})
	scored.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["score"]) < int(b["score"])
	)
	for item in scored:
		out.append(item["cell"] as Vector2i)
	if out.is_empty():
		for y in range(1, grid.rows - 1):
			for x in range(r.x, r.y + 1):
				var cell2 := Vector2i(x, y)
				if grid.is_buildable(cell2):
					out.append(cell2)
	return out


func _next_place_cell(candidates: Array[Vector2i], spawn: Vector2i, exit_c: Vector2i) -> Vector2i:
	while not candidates.is_empty():
		var cell: Vector2i = candidates.pop_back()
		if not grid.is_buildable(cell):
			continue
		if pathfinder.would_block_path_between(spawn, exit_c, cell):
			continue
		return cell
	return Vector2i(-1, -1)


func _try_sends(p: ClashPlayerState, wave: int, during_wave: bool = false) -> void:
	var opponents := clash_match.living_opponents_of(player_id)
	if opponents.is_empty():
		return
	var send_chance := 0.35
	var max_sends := 1
	var budget_ratio := 0.2
	match p.bot_difficulty:
		WaveScaler.Difficulty.EASY:
			send_chance = 0.2
			max_sends = 1
			budget_ratio = 0.12
		WaveScaler.Difficulty.HARD:
			send_chance = 0.65
			max_sends = 2
			budget_ratio = 0.35
		WaveScaler.Difficulty.CHEATER:
			send_chance = 0.8
			max_sends = 3
			budget_ratio = 0.45
		_:
			send_chance = 0.4
			max_sends = 1
			budget_ratio = 0.22
	if during_wave:
		send_chance = minf(send_chance + 0.25, 0.9)
		budget_ratio = minf(budget_ratio + 0.15, 0.5)

	var cheapest := _cheapest_send_cost()
	if p.gold < cheapest:
		return
	if _rng.randf() > send_chance:
		return
	var budget := maxi(int(float(p.gold) * budget_ratio), cheapest)
	var sent := 0
	while sent < max_sends and budget > 0:
		var pack_id := _pick_pack(budget, wave)
		if pack_id == "":
			break
		var cost: int = int(WaveScaler.clash_send_pack(pack_id)["cost"])
		var target: ClashPlayerState = opponents[_rng.randi_range(0, opponents.size() - 1)]
		if not clash_match.try_send_pack(player_id, target.player_id, pack_id):
			break
		budget -= cost
		sent += 1
		opponents = clash_match.living_opponents_of(player_id)
		if opponents.is_empty():
			break


func _pick_pack(budget: int, wave: int) -> String:
	var options: Array[String] = []
	for id in WaveScaler.clash_send_pack_ids():
		var cost: int = int(WaveScaler.clash_send_pack(str(id))["cost"])
		if cost <= budget:
			options.append(str(id))
	if options.is_empty():
		return ""
	if wave >= 10 and options.has("brute") and _rng.randf() < 0.35:
		return "brute"
	if options.has("pack") and _rng.randf() < 0.5:
		return "pack"
	return options[_rng.randi_range(0, options.size() - 1)]
