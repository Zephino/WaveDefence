class_name ClashBotAI
extends RefCounted

## Places a maze, upgrades sometimes, and queues sends for one Clash bot.

var clash_match: ClashMatch
var grid: GameGrid
var pathfinder: Pathfinder
var enemy_container: Node
var projectile_container: Node
var player_id: int = 1
var _rng := RandomNumberGenerator.new()
## Maze style chosen for this match (varies; bias from ClashBotMemory).
var _maze_strategy: String = ""


func setup(
	p_match: ClashMatch,
	p_grid: GameGrid,
	p_pathfinder: Pathfinder,
	p_enemies: Node,
	p_projectiles: Node,
	p_player_id: int
) -> void:
	clash_match = p_match
	grid = p_grid
	pathfinder = p_pathfinder
	enemy_container = p_enemies
	projectile_container = p_projectiles
	player_id = p_player_id
	_rng.randomize()
	_maze_strategy = ClashBotMemory.pick_strategy(_rng)


func run_prep_turn(wave: int) -> void:
	if clash_match == null or clash_match.finished:
		return
	var p := clash_match.get_player(player_id)
	if p == null or not p.alive or p.is_human:
		return
	if _maze_strategy == "":
		_maze_strategy = ClashBotMemory.pick_strategy(_rng)
	var spawn := grid.get_lane_spawn(p.lane_index)
	var exit_c := grid.get_lane_exit(p.lane_index)
	var len_before := pathfinder.get_cell_path_between(spawn, exit_c).size()
	# Serpentine maze → combat cover → walls become towers → send → upgrades.
	_build_maze(p, wave)
	_place_combat_towers(p, wave)
	_replace_walls_with_towers(p, wave)
	_try_sends(p, wave, false)
	_upgrade_owned_towers(p, true)
	_build_maze(p, wave)
	_place_combat_towers(p, wave)
	_replace_walls_with_towers(p, wave)
	_upgrade_owned_towers(p, false)
	var len_after := pathfinder.get_cell_path_between(spawn, exit_c).size()
	if len_after > len_before:
		ClashBotMemory.record_result(_maze_strategy, len_after)
	if clash_match != null:
		clash_match.players_changed.emit()


func run_send_turn(wave: int) -> void:
	if clash_match == null or clash_match.finished:
		return
	var p := clash_match.get_player(player_id)
	if p == null or not p.alive or p.is_human:
		return
	_try_sends(p, wave, true)


func _cheapest_send_cost() -> int:
	if WaveScaler.CLASH_SEND_PACKS.has("scout"):
		return int(WaveScaler.clash_send_pack("scout")["cost"])
	return 40


func _gold_reserve(p: ClashPlayerState) -> int:
	var ratio := 0.12
	match p.bot_difficulty:
		WaveScaler.Difficulty.EASY:
			ratio = 0.18
		WaveScaler.Difficulty.HARD:
			ratio = 0.08
		_:
			ratio = 0.12
	var send := _cheapest_send_cost()
	var soft := int(float(p.gold) * ratio)
	# Keep a send reserve when flush, but never lock almost all income away from building.
	if p.gold >= send + 40:
		return maxi(soft, send)
	return mini(soft, maxi(p.gold / 3, 0))


## Buy a serpentine maze (style varies). Walls sketch the snake cheaply; later passes turn them into towers.
func _build_maze(p: ClashPlayerState, wave: int) -> void:
	var reserve := _gold_reserve(p)
	var spawn := grid.get_lane_spawn(p.lane_index)
	var exit_c := grid.get_lane_exit(p.lane_index)
	var wall_cost: int = int(TowerData.get_def("wall")["cost"])
	var gunner_cost: int = int(TowerData.get_def("gunner")["cost"])
	var max_pieces := 18
	match p.bot_difficulty:
		WaveScaler.Difficulty.EASY:
			max_pieces = 12
		WaveScaler.Difficulty.HARD:
			max_pieces = 28
		_:
			max_pieces = 20
	var blueprint := _maze_blueprint(p.lane_index, _maze_strategy)
	var placed := 0
	# First: follow the chosen serpentine blueprint.
	for cell in blueprint:
		if placed >= max_pieces or p.gold <= reserve:
			break
		var spendable := p.gold - reserve
		if spendable < wall_cost:
			break
		if not grid.is_buildable(cell):
			continue
		if pathfinder.would_block_path_between(spawn, exit_c, cell):
			continue
		var piece_id := "wall"
		# Sometimes drop a combat tower into the snake early.
		if spendable >= gunner_cost and _rng.randf() < 0.18:
			var tid := _pick_affordable_tower_id(wave, p.bot_difficulty, spendable)
			if tid != "" and not TowerData.is_wall(tid):
				piece_id = tid
		var cost: int = int(TowerData.get_def(piece_id)["cost"])
		if cost > spendable or not p.spend_gold(cost):
			break
		_place_owned(cell, piece_id)
		pathfinder.rebuild()
		placed += 1
	# Then: greedy lengthening so each bot still finds its own shape.
	while p.gold > reserve and placed < max_pieces:
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
		_place_owned(cell2, piece2)
		pathfinder.rebuild()
		placed += 1


## Blueprint cells for a maze family. Random offsets keep runs from looking identical.
func _maze_blueprint(lane: int, strategy: String) -> Array[Vector2i]:
	var r: Vector2i = grid.lane_col_ranges[lane]
	var x0 := r.x
	var x1 := r.y
	var spawn := grid.get_lane_spawn(lane)
	var exit_c := grid.get_lane_exit(lane)
	var out: Array[Vector2i] = []
	var row_step := 2 if _rng.randf() < 0.55 else 1
	var start_y := 1 + _rng.randi_range(0, 1)
	match strategy:
		"serp_h", "serp_h_flip":
			# Alternating horizontal barriers (gap left / gap right) — like a weave.
			var gap_left := strategy == "serp_h_flip"
			if _rng.randf() < 0.5:
				gap_left = not gap_left
			var y := start_y
			while y < grid.rows - 1:
				var gap_x := x0 if gap_left else x1
				for x in range(x0, x1 + 1):
					if x == gap_x:
						continue
					var cell := Vector2i(x, y)
					if cell == spawn or cell == exit_c:
						continue
					out.append(cell)
				gap_left = not gap_left
				y += row_step
		"serp_v", "serp_v_flip":
			# Vertical corridor walls with U-turn openings at alternating ends.
			var flip := strategy == "serp_v_flip"
			if _rng.randf() < 0.5:
				flip = not flip
			var cols: Array[int] = []
			# Interior dividers between corridors (leave edges + mid walkable-ish).
			if x1 - x0 >= 4:
				cols = [x0 + 1, x0 + 3] if not flip else [x0 + 1, x1 - 1]
			else:
				cols = [x0 + 1] if not flip else [x1 - 1]
			var open_at_top := true
			for cx in cols:
				var open_y := 1 if open_at_top else grid.rows - 2
				if flip:
					open_y = grid.rows - 2 if open_at_top else 1
				for y in range(1, grid.rows - 1):
					if y == open_y:
						continue
					var cell2 := Vector2i(cx, y)
					if cell2 == spawn or cell2 == exit_c:
						continue
					out.append(cell2)
				# Cap near spawn/exit to force the U-turn.
				var cap_y := 2 if open_at_top else grid.rows - 3
				for x in range(x0, x1 + 1):
					if x == cx:
						continue
					# Only block toward the closed end so one corridor remains.
					var toward_closed := (open_at_top and x < cx) or ((not open_at_top) and x > cx)
					if flip:
						toward_closed = (open_at_top and x > cx) or ((not open_at_top) and x < cx)
					if not toward_closed and _rng.randf() < 0.65:
						continue
					var cap := Vector2i(x, cap_y)
					if cap == spawn or cap == exit_c:
						continue
					out.append(cap)
				open_at_top = not open_at_top
		"scatter":
			# Random mid-lane chokes; greedy pass finishes the shape.
			for _i in 10:
				var cell3 := Vector2i(_rng.randi_range(x0, x1), _rng.randi_range(2, grid.rows - 3))
				if cell3 != spawn and cell3 != exit_c:
					out.append(cell3)
		_:
			# greedy: no blueprint — pure lengthening below.
			pass
	# Mild shuffle so placement order isn't identical every time.
	for i in range(out.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var tmp := out[i]
		out[i] = out[j]
		out[j] = tmp
	return out


func _place_combat_towers(p: ClashPlayerState, wave: int) -> void:
	var reserve := _gold_reserve(p)
	var spawn := grid.get_lane_spawn(p.lane_index)
	var exit_c := grid.get_lane_exit(p.lane_index)
	var placed := 0
	while p.gold > reserve and placed < 20:
		var spendable := p.gold - reserve
		var tower_id := _pick_affordable_tower_id(wave, p.bot_difficulty, spendable)
		if tower_id == "" or TowerData.is_wall(tower_id):
			break
		var path_cells := pathfinder.get_cell_path_between(spawn, exit_c)
		var candidates := _build_combat_candidates(p.lane_index, path_cells)
		var cell := _next_place_cell(candidates, spawn, exit_c)
		# Path-adjacent full after early rounds — keep spending on any empty lane cell.
		if cell.x < 0:
			cell = _next_open_lane_cell(p.lane_index, spawn, exit_c)
		if cell.x < 0:
			break
		var cost: int = int(TowerData.get_def(tower_id)["cost"])
		if not p.spend_gold(cost):
			break
		_place_owned(cell, tower_id)
		pathfinder.rebuild()
		placed += 1


## Spend gold upgrading owned walls into combat towers (same cell).
func _replace_walls_with_towers(p: ClashPlayerState, wave: int) -> void:
	var reserve := _gold_reserve(p)
	var swapped := 0
	while p.gold > reserve and swapped < 12:
		var spendable := p.gold - reserve
		var tower_id := _pick_affordable_tower_id(wave, p.bot_difficulty, spendable)
		if tower_id == "" or TowerData.is_wall(tower_id):
			break
		var cost: int = int(TowerData.get_def(tower_id)["cost"])
		var wall_cell := _owned_wall_cell(p.lane_index)
		if wall_cell.x < 0:
			break
		if not p.spend_gold(cost):
			break
		var removed := grid.remove_tower_at(wall_cell, false)
		if removed != null and is_instance_valid(removed):
			removed.queue_free()
		_place_owned(wall_cell, tower_id)
		pathfinder.rebuild()
		swapped += 1


func _owned_wall_cell(lane: int) -> Vector2i:
	for cell in grid.towers.keys():
		if grid.lane_index_for_cell(cell) != lane:
			continue
		var node: Node = grid.towers[cell]
		if node is Tower:
			var tower := node as Tower
			if tower.has_meta("clash_owner") and int(tower.get_meta("clash_owner")) == player_id:
				if TowerData.is_wall(tower.tower_id):
					return cell
	return Vector2i(-1, -1)


func _next_open_lane_cell(lane: int, spawn: Vector2i, exit_c: Vector2i) -> Vector2i:
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
		if not grid.is_buildable(cell2):
			continue
		if pathfinder.would_block_path_between(spawn, exit_c, cell2):
			continue
		return cell2
	return Vector2i(-1, -1)


func _place_owned(cell: Vector2i, tower_id: String) -> void:
	var tower := Tower.new()
	tower.setup(tower_id, enemy_container, projectile_container)
	tower.set_meta("clash_owner", player_id)
	grid.place_tower(cell, tower)


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
		_:
			upgrade_chance = 0.65
			max_upgrades = 8
	if force:
		upgrade_chance = 1.0
		max_upgrades = maxi(max_upgrades, 6)
	if _rng.randf() > upgrade_chance:
		return
	var reserve := _gold_reserve(p)
	var towers := _owned_towers_in_lane(p.lane_index)
	var upgraded := 0
	while p.gold > reserve and upgraded < max_upgrades:
		var best: Tower = null
		var best_cost := 1 << 30
		for tower in towers:
			if tower == null or not is_instance_valid(tower):
				continue
			if TowerData.is_wall(tower.tower_id):
				continue
			if not tower.can_stat_upgrade():
				continue
			var cost := tower.next_stat_upgrade_cost()
			if cost <= 0 or cost > p.gold - reserve:
				continue
			if cost < best_cost:
				best_cost = cost
				best = tower
		if best == null:
			break
		if not p.spend_gold(best_cost):
			break
		best.apply_stat_upgrade()
		upgraded += 1


func _owned_towers_in_lane(lane: int) -> Array[Tower]:
	var out: Array[Tower] = []
	for cell in grid.towers.keys():
		if grid.lane_index_for_cell(cell) != lane:
			continue
		var node: Node = grid.towers[cell]
		if node is Tower:
			var tower := node as Tower
			if tower.has_meta("clash_owner") and int(tower.get_meta("clash_owner")) == player_id:
				out.append(tower)
	return out


func _pick_affordable_tower_id(wave: int, difficulty: int, gold: int) -> String:
	var pool := _tower_pool(wave, difficulty)
	var affordable: Array[String] = []
	for id in pool:
		var cost: int = int(TowerData.get_def(id)["cost"])
		if cost > 0 and cost <= gold and TowerData.is_unlocked(id, wave):
			affordable.append(id)
	if affordable.is_empty():
		var gunner_cost: int = int(TowerData.get_def("gunner")["cost"])
		if gunner_cost <= gold:
			return "gunner"
		return ""
	if gold >= 80 and affordable.size() > 1 and _rng.randf() < 0.65:
		return affordable[_rng.randi_range(0, affordable.size() - 1)]
	var cheapest := affordable[0]
	var cheapest_cost: int = int(TowerData.get_def(cheapest)["cost"])
	for id in affordable:
		var cost: int = int(TowerData.get_def(id)["cost"])
		if cost < cheapest_cost:
			cheapest = id
			cheapest_cost = cost
	return cheapest


func _tower_pool(wave: int, difficulty: int) -> Array[String]:
	var pool: Array[String] = ["gunner"]
	if wave >= 3:
		pool.append("rapid")
	if wave >= 5 and difficulty >= WaveScaler.Difficulty.MEDIUM:
		pool.append("cannon")
	if wave >= 8 and difficulty >= WaveScaler.Difficulty.MEDIUM:
		pool.append("freeze")
	if wave >= 10 and difficulty >= WaveScaler.Difficulty.HARD:
		pool.append("lightning")
	if wave >= 8:
		pool.append("antiair")
	return pool


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
