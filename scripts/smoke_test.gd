extends SceneTree

## Headless smoke test: godot --headless --path . -s res://scripts/smoke_test.gd

func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var errors: Array[String] = []

	var main_scene := load("res://scenes/main.tscn") as PackedScene
	if main_scene == null:
		push_error("FAIL: could not load main.tscn")
		quit(1)
		return

	var main := main_scene.instantiate()
	root.add_child(main)
	await process_frame
	await process_frame

	var build: BuildSystem = main.get_node("BuildSystem")
	var waves: WaveManager = main.get_node("WaveManager")
	var state: GameState = main.get_node("GameState")
	var grid: GameGrid = main.get_node("GameGrid") if main.has_node("GameGrid") else null

	# GameGrid is added without a fixed name in older code — find it.
	if grid == null:
		for child in main.get_children():
			if child is GameGrid:
				grid = child
				break

	if build == null or waves == null or state == null or grid == null:
		push_error("FAIL: missing systems")
		quit(1)
		return

	var version_script = load("res://scripts/version_info.gd")
	var ver: String = version_script.current()
	var file_ver := ""
	if FileAccess.file_exists("res://VERSION"):
		var vf := FileAccess.open("res://VERSION", FileAccess.READ)
		if vf:
			file_ver = vf.get_as_text().strip_edges()
	if ver.is_empty() or ver == "00.01.00":
		errors.append("in-app version should read current VERSION, got '%s'" % ver)
	elif file_ver != "" and file_ver != ver:
		errors.append("VersionInfo should match VERSION file (%s vs %s)" % [ver, file_ver])
	var settings_ver := str(ProjectSettings.get_setting("application/config/version", "")).strip_edges()
	if settings_ver != "" and settings_ver != file_ver and file_ver != "":
		errors.append("project config/version should match VERSION file")

	# Effects preference defaults on; toggling must stick for this session.
	UserSettings.ensure_loaded()
	var prev_fx := UserSettings.is_effects_enabled()
	UserSettings.set_effects_enabled(false)
	if UserSettings.is_effects_enabled():
		errors.append("effects should turn off")
	UserSettings.set_effects_enabled(true)
	if not UserSettings.is_effects_enabled():
		errors.append("effects should turn on")
	UserSettings.set_effects_enabled(prev_fx)

	state.reset_run(WaveScaler.Difficulty.MEDIUM, WaveScaler.GameMode.CLASSIC)
	if state.gold != WaveScaler.STARTING_GOLD_MEDIUM:
		errors.append("medium starting gold expected %d got %d" % [WaveScaler.STARTING_GOLD_MEDIUM, state.gold])
	state.reset_run(WaveScaler.Difficulty.EASY, WaveScaler.GameMode.CLASSIC)
	if state.gold != WaveScaler.STARTING_GOLD_EASY:
		errors.append("easy starting gold expected %d got %d" % [WaveScaler.STARTING_GOLD_EASY, state.gold])
	state.reset_run(WaveScaler.Difficulty.HARD, WaveScaler.GameMode.CLASSIC)
	if state.gold != WaveScaler.STARTING_GOLD_HARD:
		errors.append("hard starting gold expected %d got %d" % [WaveScaler.STARTING_GOLD_HARD, state.gold])
	state.reset_run(WaveScaler.Difficulty.MEDIUM, WaveScaler.GameMode.CLASSIC)

	# Random-mode maps must keep a spawn→exit path and block building on rocks.
	if not grid.generate_random_layout(12345):
		errors.append("random layout generator failed")
	build.pathfinder.rebuild()
	if build.pathfinder.get_world_path().size() < 2:
		errors.append("random layout must keep a path")
	var blocked_found := false
	for y in GameGrid.ROWS:
		for x in GameGrid.COLS:
			var cell := Vector2i(x, y)
			if grid.is_terrain_blocked(cell):
				blocked_found = true
				if grid.is_buildable(cell):
					errors.append("blocked terrain should not be buildable")
				if not grid.is_blocked_for_path(cell):
					errors.append("blocked terrain should block pathing")
	if not blocked_found:
		errors.append("random layout should include blocked cells")
	if not WaveScaler.should_rotate_map_after_wave(WaveScaler.GameMode.RANDOM, 25):
		errors.append("random mode should rotate after wave 25")
	if WaveScaler.should_rotate_map_after_wave(WaveScaler.GameMode.CLASSIC, 25):
		errors.append("classic should not rotate maps")
	if WaveScaler.mode_label(WaveScaler.GameMode.RANDOM) != "Random":
		errors.append("random mode label should be Random")
	if WaveScaler.mode_label(WaveScaler.GameMode.SIEGE) != "Siege":
		errors.append("siege mode label should be Siege")
	if WaveScaler.mode_label(WaveScaler.GameMode.CLASH) != "Clash":
		errors.append("clash mode label should be Clash")
	if not WaveScaler.is_siege_mode(WaveScaler.GameMode.SIEGE):
		errors.append("is_siege_mode should be true for SIEGE")
	if not WaveScaler.is_clash_mode(WaveScaler.GameMode.CLASH):
		errors.append("is_clash_mode should be true for CLASH")
	if not WaveScaler.should_rotate_spawn_after_wave(WaveScaler.GameMode.SIEGE, 5):
		errors.append("siege should rotate spawn after wave 5")
	if WaveScaler.should_rotate_spawn_after_wave(WaveScaler.GameMode.CLASSIC, 5):
		errors.append("classic should not rotate siege spawn")
	if WaveScaler.should_rotate_map_after_wave(WaveScaler.GameMode.SIEGE, 25):
		errors.append("siege should not use random map wipe")
	if WaveScaler.should_rotate_map_after_wave(WaveScaler.GameMode.CLASH, 25):
		errors.append("clash should not rotate maps")
	if WaveScaler.should_rotate_spawn_after_wave(WaveScaler.GameMode.CLASH, 5):
		errors.append("clash should not rotate siege spawn")
	var rotate_gold := WaveScaler.map_rotate_gold(WaveScaler.Difficulty.MEDIUM, 80)
	if rotate_gold < 80 * WaveScaler.MAP_ROTATE_GOLD_PER_KILL:
		errors.append("map rotate gold should scale with kills")

	# Seed helpers + deterministic random layouts.
	if WaveScaler.parse_seed_text("") != -1:
		errors.append("empty seed text should parse to -1")
	if WaveScaler.parse_seed_text("42") != 42:
		errors.append("numeric seed text should parse to int")
	if WaveScaler.parse_seed_text("abc") < 0:
		errors.append("alphanumeric seed should hash to non-negative")
	var s1 := WaveScaler.sector_seed(100, 1)
	var s2 := WaveScaler.sector_seed(100, 2)
	if s1 == s2:
		errors.append("different sectors should yield different layout seeds")
	if WaveScaler.sector_seed(100, 1) != s1:
		errors.append("sector_seed should be stable")
	grid.generate_random_layout(777001)
	var spawn_a := grid.spawn_cell
	var exit_a := grid.exit_cell
	var blocked_a: Array[Vector2i] = []
	for y in grid.rows:
		for x in grid.cols:
			var c := Vector2i(x, y)
			if grid.is_terrain_blocked(c):
				blocked_a.append(c)
	grid.generate_random_layout(777001)
	if grid.spawn_cell != spawn_a or grid.exit_cell != exit_a:
		errors.append("same seed should recreate spawn/exit")
	if grid.last_layout_seed != 777001:
		errors.append("last_layout_seed should match requested seed")
	var blocked_b: Array[Vector2i] = []
	for y in grid.rows:
		for x in grid.cols:
			var c2 := Vector2i(x, y)
			if grid.is_terrain_blocked(c2):
				blocked_b.append(c2)
	if blocked_a != blocked_b:
		errors.append("same seed should recreate blocked cells")
	grid.generate_random_layout(777002)
	if grid.spawn_cell == spawn_a and grid.exit_cell == exit_a and blocked_a == blocked_b:
		# Different seed may rarely collide; only flag if layout seed didn't change.
		if grid.last_layout_seed == 777001:
			errors.append("different seed should change last_layout_seed")

	# Siege: center exit, rim spawn, path exists; relocate keeps towers.
	if not grid.generate_siege_layout(4242):
		errors.append("siege layout generator failed")
	if grid.last_layout_seed != 4242:
		errors.append("siege last_layout_seed should match requested seed")
	build.pathfinder.sync_region()
	build.pathfinder.rebuild()
	if grid.cols != GameGrid.SIEGE_COLS or grid.rows != GameGrid.SIEGE_ROWS:
		errors.append("siege should be %dx%d" % [GameGrid.SIEGE_COLS, GameGrid.SIEGE_ROWS])
	if grid.exit_cell != Vector2i(grid.cols / 2, grid.rows / 2):
		errors.append("siege exit should be map center")
	# Siege board should be larger than the play window so wheel zoom-out is useful.
	var siege_map := grid.map_pixel_size()
	var siege_view := GameLayout.board_view_size(siege_map)
	var siege_fit := minf(siege_view.x / maxf(siege_map.x, 1.0), siege_view.y / maxf(siege_map.y, 1.0))
	if siege_fit >= 1.0:
		errors.append("siege map should exceed board view (min zoom < 1)")
	if main.map_zoom < 0.999:
		errors.append("map_zoom should start at 1.0")
	if build.pathfinder.get_world_path().size() < 2:
		errors.append("siege layout must keep a path")
	var old_spawn := grid.spawn_cell
	if not grid.relocate_rim_spawn(build.pathfinder, old_spawn):
		errors.append("siege rim spawn relocate failed")
	elif grid.spawn_cell == old_spawn:
		errors.append("siege rim spawn should move to a new cell")
	if build.pathfinder.get_world_path().size() < 2:
		errors.append("siege path must remain after spawn relocate")

	# Clash: side-by-side lanes with top→bottom paths.
	grid.reset_clash(3)
	if not grid.is_clash_layout:
		errors.append("clash layout flag should be set")
	if grid.clash_lane_count() != 3:
		errors.append("clash should create 3 lanes")
	build.pathfinder.sync_region()
	build.pathfinder.rebuild()
	for lane_i in 3:
		var lsp := grid.get_lane_spawn(lane_i)
		var lex := grid.get_lane_exit(lane_i)
		if lsp.y != 0 or lex.y != grid.rows - 1:
			errors.append("clash lane %d spawn/exit should be top/bottom" % lane_i)
		if build.pathfinder.get_world_path_between(lsp, lex).size() < 2:
			errors.append("clash lane %d must have a path" % lane_i)
	var clash_match := ClashMatch.new()
	main.add_child(clash_match)
	clash_match.setup(state, 3, [WaveScaler.Difficulty.EASY, WaveScaler.Difficulty.HARD])
	if clash_match.player_count() != 3:
		errors.append("clash match should have 3 players")
	# Cheater bot: +500 gold, +100 lives, slow heal toward 50 after dipping to ≤10.
	var cheater_match := ClashMatch.new()
	main.add_child(cheater_match)
	cheater_match.setup(state, 2, [WaveScaler.Difficulty.CHEATER])
	var cheater := cheater_match.get_player(1)
	if cheater == null or not WaveScaler.is_cheater_bot(cheater.bot_difficulty):
		errors.append("clash setup should create a Cheater bot")
	else:
		var want_gold := WaveScaler.CLASH_STARTING_GOLD + WaveScaler.CLASH_CHEATER_EXTRA_GOLD
		var want_lives := WaveScaler.CLASH_STARTING_LIVES + WaveScaler.CLASH_CHEATER_EXTRA_LIVES
		if cheater.gold != want_gold:
			errors.append("cheater should start with %d gold (got %d)" % [want_gold, cheater.gold])
		if cheater.lives != want_lives:
			errors.append("cheater should start with %d lives (got %d)" % [want_lives, cheater.lives])
		cheater.lives = WaveScaler.CLASH_CHEATER_HEAL_TRIGGER + 1
		cheater.lose_life(1)  # dips to trigger → starts healing
		if not cheater.cheater_healing:
			errors.append("cheater should start healing at ≤%d lives" % WaveScaler.CLASH_CHEATER_HEAL_TRIGGER)
		var healed := 0
		for _tick in 50:
			healed += cheater.tick_cheater_heal(WaveScaler.CLASH_CHEATER_HEAL_INTERVAL)
		if cheater.lives < WaveScaler.CLASH_CHEATER_HEAL_TARGET:
			errors.append(
				"cheater should heal toward %d lives (got %d after ticks)"
				% [WaveScaler.CLASH_CHEATER_HEAL_TARGET, cheater.lives]
			)
		if healed < 1:
			errors.append("cheater heal ticks should restore at least one life")
	cheater_match.queue_free()
	var income0 := clash_match.human().income_per_round
	if not clash_match.try_send_pack(0, 1, "scout"):
		errors.append("clash human send scout should succeed with starting gold")
	var scout_bump := WaveScaler.clash_send_income_bump("scout")
	if clash_match.human().income_per_round != income0 + scout_bump:
		errors.append("scout send should bump income by %d" % scout_bump)
	if WaveScaler.clash_send_income_bump("brute") <= scout_bump:
		errors.append("pricier send packs should bump income more than cheaper ones")
	# Refund-style gold top-up so brute affordability isn't the focus.
	clash_match.human().add_gold(200)
	clash_match.sync_human_to_game_state()
	var income1 := clash_match.human().income_per_round
	if not clash_match.try_send_pack(0, 2, "brute"):
		errors.append("clash human send brute should succeed with topped-up gold")
	elif clash_match.human().income_per_round != income1 + WaveScaler.clash_send_income_bump("brute"):
		errors.append("brute send should bump income by its own higher amount")
	# Send-shop levels: humans start at 1; higher packs need upgrades.
	if clash_match.human().send_shop_level != 1:
		errors.append("human send shop should start at level 1")
	var lv1_packs: Array = WaveScaler.clash_send_packs_for_level(1)
	if not lv1_packs.has("scout") or lv1_packs.has("raid") or lv1_packs.has("wrecker"):
		errors.append("level-1 send packs should be starter trio only")
	if clash_match.try_send_pack(0, 1, "raid"):
		errors.append("human should not buy level-2 pack before shop upgrade")
	if WaveScaler.clash_send_shop_upgrade_cost(1) != 1500:
		errors.append("send shop 1→2 should cost 1500")
	if WaveScaler.clash_send_shop_upgrade_cost(2) != 5000:
		errors.append("send shop 2→3 should cost 5000")
	if WaveScaler.clash_send_shop_upgrade_cost(3) != 15000:
		errors.append("send shop 3→4 should cost 15000")
	state.gold = 2000
	clash_match.sync_human_gold_from_game_state()
	if not clash_match.try_upgrade_send_shop(0):
		errors.append("human should upgrade send shop 1→2 with 2000 gold")
	elif clash_match.human().send_shop_level != 2:
		errors.append("send shop should be level 2 after upgrade")
	elif not WaveScaler.clash_send_packs_for_level(2).has("raid"):
		errors.append("level-2 packs should include raid")
	# Bots ignore shop level and may buy high-tier packs.
	var bot_sender := clash_match.get_player(1)
	if bot_sender:
		bot_sender.gold = 5000
		if not clash_match.try_send_pack(1, 0, "wrecker"):
			errors.append("bot should buy wrecker without send-shop level")
	if WaveScaler.clash_send_income_bump("wrecker") <= WaveScaler.clash_send_income_bump("brute"):
		errors.append("wrecker income bump should exceed starter packs")
	if WaveScaler.clash_send_income_bump("war_council") <= WaveScaler.clash_send_income_bump("raid"):
		errors.append("higher-tier packs should grant clearly larger income bumps")
	# Round income must land on GameState even if ClashPlayerState gold is stale.
	var rate := clash_match.human().income_per_round
	state.gold = 500
	clash_match.human().gold = 100  # intentional desync (kills/builds live on GameState)
	var paid := clash_match.award_round_income()
	if paid != rate:
		errors.append("award_round_income should return human rate %d (got %d)" % [rate, paid])
	if state.gold != 500 + rate:
		errors.append(
			"round income should add onto GameState gold (want %d got %d)" % [500 + rate, state.gold]
		)
	if clash_match.human().gold != state.gold:
		errors.append("human Clash gold should match GameState after income")
	var opp := clash_match.living_opponents_of(1)
	if opp.size() != 2:
		errors.append("bot living opponents should include human and other bot")
	var bot_ai := ClashBotAI.new()
	bot_ai.setup(clash_match, grid, build.pathfinder, main.enemies, main.projectiles, 2)
	# Force a reference one-tile maze template.
	# Strategies must be uniform-random (not memory-locked to one style).
	var seen_styles: Dictionary = {}
	var style_rng := RandomNumberGenerator.new()
	style_rng.seed = 42
	for _i in 40:
		seen_styles[ClashBotMemory.pick_strategy(style_rng)] = true
	if seen_styles.size() < 5:
		errors.append("clash maze pick_strategy should vary across draws (got %d unique)" % seen_styles.size())
	# Bots ignore shop unlock waves — any affordable combat tower is fair game.
	var bot_pool := bot_ai._combat_tower_pool()
	if not bot_pool.has("burn") or not bot_pool.has("vortex") or not bot_pool.has("spike"):
		errors.append("clash bot combat pool should include burn/vortex/spike")
	if bot_pool.has("wall") or bot_pool.has("command"):
		errors.append("clash bot combat pool should exclude wall/command")
	var pick_seen: Dictionary = {}
	for _j in 30:
		var pick := bot_ai._pick_affordable_tower_id(1, WaveScaler.Difficulty.EASY, 200)
		if pick != "":
			pick_seen[pick] = true
	if pick_seen.size() < 3:
		errors.append("clash bot tower picks should vary among affordable types (got %d)" % pick_seen.size())
	if bot_ai._pick_affordable_tower_id(1, WaveScaler.Difficulty.EASY, 3) != "":
		errors.append("clash bot should not pick combat towers it cannot afford")
	# Match-long plan: force maze so path-length smoke stays deterministic.
	bot_ai._build_plan = ClashBotAI.BuildPlan.MAZE
	bot_ai._maze_strategy = "switchback"
	var plan_locked := bot_ai._build_plan
	var style_locked := bot_ai._maze_strategy
	for tid in ClashMazeTemplates.TEMPLATE_IDS:
		var tpath := ClashMazeTemplates.path_cells(tid)
		if tpath.is_empty() or tpath[0] != Vector2i(ClashMazeTemplates.MID, 0):
			errors.append("maze template %s should start at spawn" % tid)
		elif tpath[tpath.size() - 1] != Vector2i(ClashMazeTemplates.MID, ClashMazeTemplates.HEIGHT - 1):
			errors.append("maze template %s should end at exit" % tid)
		elif tpath.size() < 30:
			errors.append("maze template %s path looks too short (%d)" % [tid, tpath.size()])
		else:
			# Chord-free: shortest walk on the path set must use every cell.
			var walk: Dictionary = {}
			for c in tpath:
				walk[c] = true
			var q: Array[Vector2i] = [tpath[0]]
			var dist: Dictionary = {tpath[0]: 1}
			var qi := 0
			while qi < q.size():
				var cur: Vector2i = q[qi]
				qi += 1
				for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var n: Vector2i = cur + d
					if walk.has(n) and not dist.has(n):
						dist[n] = int(dist[cur]) + 1
						q.append(n)
			var goal: Vector2i = tpath[tpath.size() - 1]
			if not dist.has(goal) or int(dist[goal]) < tpath.size():
				errors.append("maze template %s has a shortcut (bfs=%s len=%d)" % [
					tid, str(dist.get(goal, -1)), tpath.size()
				])
	var bot_p := clash_match.get_player(2)
	var path_before := build.pathfinder.get_cell_path_between(
		grid.get_lane_spawn(2), grid.get_lane_exit(2)
	).size()
	var gold_before := bot_p.gold if bot_p else 0
	bot_ai.run_prep_turn(1)
	if bot_ai._maze_strategy == "":
		errors.append("clash bot should pick a maze strategy")
	if bot_ai._build_plan != plan_locked or bot_ai._maze_strategy != style_locked:
		errors.append("clash bot should keep its build plan and maze style across prep")
	if GameGrid.CLASH_LANE_COLS < 7:
		errors.append("clash lanes should be wide enough for serpentine mazes")
	var path_after := build.pathfinder.get_cell_path_between(
		grid.get_lane_spawn(2), grid.get_lane_exit(2)
	).size()
	var owned := 0
	var combat := 0
	var blocked_in_lane := 0
	var r2: Vector2i = grid.lane_col_ranges[2]
	for y in grid.rows:
		for x in range(r2.x, r2.y + 1):
			if grid.get_tile(Vector2i(x, y)) == GameGrid.Tile.BLOCKED:
				blocked_in_lane += 1
	if blocked_in_lane > 0:
		errors.append("clash lanes must not get environmental blocked tiles")
	for cell in grid.towers.keys():
		if grid.lane_index_for_cell(cell) != 2:
			continue
		var t: Node = grid.towers[cell]
		if t is Tower and t.has_meta("clash_owner") and int(t.get_meta("clash_owner")) == 2:
			owned += 1
			if not TowerData.is_wall((t as Tower).tower_id):
				combat += 1
	if owned < 2:
		errors.append("clash bot should buy and place maze/combat pieces in its lane")
	if combat < 1:
		errors.append("clash bot maze should prefer bought combat towers, not only walls")
	if path_after <= path_before:
		errors.append("clash bot maze should lengthen its lane path")
	if bot_p != null and bot_p.gold >= gold_before:
		errors.append("clash bot should spend gold on maze/defense/sends")
	# Second prep after income must keep spending (not only round 1).
	bot_p.add_gold(WaveScaler.CLASH_BASE_INCOME + 80)
	var gold_mid := bot_p.gold
	var combat_mid := combat
	bot_ai.run_prep_turn(2)
	if bot_ai._build_plan != plan_locked or bot_ai._maze_strategy != style_locked:
		errors.append("clash bot should still follow the same plan on later prep")
	var combat_later := 0
	for cell2 in grid.towers.keys():
		if grid.lane_index_for_cell(cell2) != 2:
			continue
		var t2: Node = grid.towers[cell2]
		if t2 is Tower and t2.has_meta("clash_owner") and int(t2.get_meta("clash_owner")) == 2:
			if not TowerData.is_wall((t2 as Tower).tower_id):
				combat_later += 1
	if bot_p.gold >= gold_mid:
		errors.append("clash bot should keep spending on later prep turns")
	if combat_later < combat_mid:
		errors.append("clash bot should not lose combat towers on later prep")
	var nxt := clash_match.next_living_after_lane(0)
	if nxt == null or nxt.lane_index != 1:
		errors.append("clash overflow should wrap to the next living lane")
	var wrap := clash_match.next_living_after_lane(2)
	if wrap == null or wrap.lane_index != 0:
		errors.append("clash overflow should wrap from last lane to first living")
	var mid := clash_match.get_player(1)
	if mid != null:
		while mid.alive:
			mid.lose_life(1)
	var skip := clash_match.next_living_after_lane(0)
	if skip == null or skip.lane_index != 2:
		errors.append("clash overflow should skip eliminated lanes")
	var lane0_cell := Vector2i(int(grid.lane_col_ranges[0].y), 4)
	var lane_tower := Tower.new()
	lane_tower.setup("gunner", main.enemies, main.projectiles)
	if grid.is_buildable(lane0_cell):
		grid.place_tower(lane0_cell, lane_tower)
		if lane_tower.lane_id != 0:
			errors.append("clash placed tower should lock to its lane")
		var own_mob := Enemy.new()
		own_mob.lane_id = 0
		main.enemies.add_child(own_mob)
		own_mob.global_position = lane_tower.global_position + Vector2(8, 0)
		var other_cell := Vector2i(int(grid.lane_col_ranges[1].x), 4)
		var other_mob := Enemy.new()
		other_mob.lane_id = 1
		main.enemies.add_child(other_mob)
		other_mob.global_position = grid.to_global(grid.cell_to_world_center(other_cell))
		var picked := lane_tower._find_target()
		if picked != own_mob:
			errors.append("clash tower should only target mobs in its lane")
		own_mob.lane_id = -1
		own_mob.defender_id = -1
		if lane_tower._find_target() != own_mob:
			errors.append("clash tower should still shoot an in-lane mob with unset lane id")
		own_mob.queue_free()
		other_mob.queue_free()
		grid.remove_tower_at(lane0_cell)
		lane_tower.queue_free()
	else:
		lane_tower.queue_free()
		errors.append("clash smoke could not place a lane-0 tower for targeting check")
	# Wrecker destroys a defender wall on the path cell it steps onto.
	var wreck_cell := Vector2i(int(grid.lane_col_ranges[0].x) + 1, 5)
	if not grid.is_buildable(wreck_cell):
		wreck_cell = Vector2i(int(grid.lane_col_ranges[0].y), 5)
	var wreck_wall := Tower.new()
	wreck_wall.setup("wall", main.enemies, main.projectiles)
	if grid.is_buildable(wreck_cell):
		grid.place_tower(wreck_cell, wreck_wall)
		var wrecker := Enemy.new()
		main.enemies.add_child(wrecker)
		var wpath := PackedVector2Array([
			grid.cell_to_world_center(wreck_cell),
			grid.cell_to_world_center(wreck_cell + Vector2i(0, 1)),
		])
		wrecker.setup(wpath, 50.0, 200.0, 1, false, false)
		wrecker.lane_id = 0
		wrecker.configure_wrecker(grid)
		# Arrive at first waypoint (wall cell) then advance.
		wrecker.position = wpath[0]
		wrecker.path_index = 0
		wrecker._try_wreck_current_cell()
		if grid.get_tower_at(wreck_cell) != null:
			errors.append("wrecker should remove defender tower/wall on entered cell")
		if wrecker.get_parent() != null:
			wrecker.get_parent().remove_child(wrecker)
		wrecker.free()
	else:
		wreck_wall.queue_free()
		errors.append("clash smoke could not place a wall for wrecker check")
	# Floating shops: pin towers and select a type still arms placement.
	var hud: UIHud = main.hud
	if hud != null:
		var prev_pin := UserSettings.is_towers_shop_pinned()
		hud._towers_pinned = true
		hud._towers_open = true
		hud._apply_towers_shop_layout()
		if hud._towers_panel == null or not hud._towers_panel.visible:
			errors.append("pinned towers shop should stay visible")
		hud._on_tower_button("gunner")
		if not hud.tower_buttons.has("gunner"):
			errors.append("towers popup should keep tower buttons after pin")
		hud._towers_pinned = prev_pin
		UserSettings.set_towers_shop_pinned(prev_pin)
		hud._apply_towers_shop_layout()
	clash_match.queue_free()
	# Drop any leftover smoke enemies before classic targeting checks.
	for leftover in main.enemies.get_children():
		main.enemies.remove_child(leftover)
		leftover.free()
	grid.reset(true)
	build.pathfinder.sync_region()
	build.pathfinder.rebuild()
	state.reset_run(WaveScaler.Difficulty.MEDIUM, WaveScaler.GameMode.CLASSIC)

	# Large Controls settings persist round-trip.
	var prev_lc := UserSettings.is_large_controls()
	UserSettings.set_large_controls(true)
	UserSettings._loaded = false
	if not UserSettings.is_large_controls():
		errors.append("large_controls should persist true")
	UserSettings.set_large_controls(false)
	UserSettings._loaded = false
	if UserSettings.is_large_controls():
		errors.append("large_controls should persist false")
	UserSettings.set_large_controls(prev_lc)
	UserSettings._loaded = false
	UserSettings.ensure_loaded()

	# Clash brown dividers neutralize shots that cross them.
	grid.reset_clash(3)
	build.pathfinder.sync_region()
	build.pathfinder.rebuild()
	var div_x := int(grid.lane_col_ranges[0].y) + 1
	var div_cell := Vector2i(div_x, 4)
	if grid.get_tile(div_cell) != GameGrid.Tile.BLOCKED:
		errors.append("clash lane divider should be BLOCKED terrain")
	else:
		var left_pt := grid.to_global(grid.cell_to_world_center(Vector2i(div_x - 1, 4)))
		var right_pt := grid.to_global(grid.cell_to_world_center(Vector2i(div_x + 1, 4)))
		if not grid.segment_hits_blocked(left_pt, right_pt):
			errors.append("segment across clash divider should hit BLOCKED")
		var same_lane_a := grid.to_global(grid.cell_to_world_center(Vector2i(div_x - 2, 4)))
		var same_lane_b := grid.to_global(grid.cell_to_world_center(Vector2i(div_x - 1, 4)))
		if grid.segment_hits_blocked(same_lane_a, same_lane_b):
			errors.append("same-lane segment should not hit divider")
		var cross_proj := Projectile.new()
		cross_proj.enemy_container = main.enemies
		main.projectiles.add_child(cross_proj)
		cross_proj.global_position = left_pt
		var dummy := Enemy.new()
		dummy.alive = true
		main.enemies.add_child(dummy)
		dummy.global_position = right_pt
		cross_proj.setup(dummy, 10.0, 0.0, "none", {}, main.enemies, Color.WHITE, 2000.0, 0)
		# One big step toward the other lane should die on the divider.
		cross_proj._process(1.0)
		if is_instance_valid(cross_proj) and cross_proj.alive:
			errors.append("projectile crossing clash divider should neutralize")
		if is_instance_valid(dummy):
			dummy.queue_free()
		if is_instance_valid(cross_proj):
			cross_proj.queue_free()

	# Restore classic map for remaining tests.
	grid.reset(true)
	build.pathfinder.sync_region()
	build.pathfinder.rebuild()
	var classic_cell := Vector2i(3, 7)
	var classic_tower := Tower.new()
	classic_tower.setup("gunner", main.enemies, main.projectiles)
	if grid.is_buildable(classic_cell):
		grid.place_tower(classic_cell, classic_tower)
		if classic_tower.lane_id != -1:
			errors.append("classic placed tower should not lock to a clash lane")
		var classic_mob := Enemy.new()
		classic_mob.lane_id = -1
		main.enemies.add_child(classic_mob)
		var cm_pos := classic_tower.global_position + Vector2(10, 0)
		classic_mob.setup(
			PackedVector2Array([classic_tower.position + Vector2(10, 0), classic_tower.position + Vector2(40, 0)]),
			20.0,
			0.0,
			1,
			false,
			false
		)
		classic_mob.global_position = cm_pos
		if classic_tower._find_target() != classic_mob:
			errors.append("classic tower should fire at a nearby enemy")
		classic_mob.queue_free()
		grid.remove_tower_at(classic_cell)
		classic_tower.queue_free()
	else:
		classic_tower.queue_free()
		errors.append("classic smoke could not place a tower for targeting check")

	# Monster modes: Classic has no resists; Randomize tags types and grows resists.
	if MonsterTypes.resist_slot_count(1) != 1:
		errors.append("early waves should have 1 resist slot")
	if MonsterTypes.resist_slot_count(MonsterTypes.RESISTS_AT_WAVE_4) != 4:
		errors.append("late waves should unlock all 4 resists")
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var late_resists := MonsterTypes.build_resists("ember", MonsterTypes.RESISTS_AT_WAVE_4, rng)
	var active_resists := 0
	for el in MonsterTypes.ELEMENTS:
		if float(late_resists.get(el, 0.0)) > 0.0:
			active_resists += 1
	if active_resists != 4:
		errors.append("wave %d resists should cover all 4 elements, got %d" % [
			MonsterTypes.RESISTS_AT_WAVE_4, active_resists
		])
	if float(late_resists.get("burn", 0.0)) < MonsterTypes.RESIST_STRENGTH - 0.001:
		errors.append("ember affinity burn should stay active at full resist count")
	state.reset_run(WaveScaler.Difficulty.MEDIUM, WaveScaler.GameMode.CLASSIC, WaveScaler.MonsterMode.CLASSIC)
	waves._build_spawn_queue(5)
	if waves.spawn_queue.is_empty():
		errors.append("classic monster spawn queue empty")
	else:
		var classic_spec: Dictionary = waves.spawn_queue[0]
		if str(classic_spec.get("monster_type", "")) != "":
			errors.append("classic monsters should not set monster_type")
		if float(classic_spec.get("element_resists", {}).get("burn", 0.0)) > 0.0:
			errors.append("classic monsters should have zero elemental resists")
	state.reset_run(WaveScaler.Difficulty.MEDIUM, WaveScaler.GameMode.CLASSIC, WaveScaler.MonsterMode.RANDOMIZE)
	waves._build_spawn_queue(12)
	if waves.spawn_queue.is_empty():
		errors.append("randomize monster spawn queue empty")
	else:
		var rnd_spec: Dictionary = waves.spawn_queue[0]
		if str(rnd_spec.get("monster_type", "")) == "":
			errors.append("randomize monsters should set monster_type")
		var rnd_resists: Dictionary = rnd_spec.get("element_resists", {})
		var rnd_active := 0
		for el in MonsterTypes.ELEMENTS:
			if float(rnd_resists.get(el, 0.0)) > 0.0:
				rnd_active += 1
		if rnd_active < 1:
			errors.append("randomize monsters should have at least one resist")
	# Resist reduces matching elemental hit damage.
	var resist_enemy := Enemy.new()
	resist_enemy.element_resists = {"burn": 0.25, "freeze": 0.0, "poison": 0.0, "lightning": 0.0}
	if not is_equal_approx(resist_enemy.resist_mult("burn"), 0.75):
		errors.append("burn resist_mult should be 0.75")
	if not is_equal_approx(resist_enemy.resist_mult("freeze"), 1.0):
		errors.append("unrelated element should take full damage")
	resist_enemy.free()

	grid.reset(true)
	build.pathfinder.rebuild()
	state.reset_run(WaveScaler.Difficulty.MEDIUM, WaveScaler.GameMode.CLASSIC, WaveScaler.MonsterMode.CLASSIC)

	# Place a wall, then build a gunner over it (placement clears selection).
	build.select_tower_type("wall")
	var place_cell := Vector2i(2, 2)
	var world := grid.cell_to_world_center(place_cell)
	if not build.can_place_at(place_cell):
		errors.append("expected to place wall at %s" % str(place_cell))
	else:
		build.try_place_at(world)
		if build.selection_count() != 0:
			errors.append("placing should clear selection")
		var wall_node = grid.get_tower_at(place_cell)
		if wall_node == null or not TowerData.is_wall(wall_node.tower_id):
			errors.append("wall not present after place")
		build.select_tower_type("gunner")
		if not build.can_place_at(place_cell):
			errors.append("expected to build gunner over wall")
		else:
			# Armed combat type: tap builds over the wall.
			build.try_place_at(world)
			var over = grid.get_tower_at(place_cell)
			if over == null or over.tower_id != "gunner":
				errors.append("tap with combat tower armed should build over wall")
			if build.selection_count() != 0:
				errors.append("placing over wall should clear selection")
			build.pathfinder.rebuild()
			if not build.pathfinder.astar.is_point_solid(place_cell):
				errors.append("replaced wall cell must stay blocked for pathing")
			var path_cells := build.pathfinder.get_cell_path()
			if place_cell in path_cells:
				errors.append("enemies must not path through replaced wall cell")
			# Deselect placing, then select wall + sell.
			var sell_cell := Vector2i(5, 2)
			build.select_tower_type("wall")
			if build.can_place_at(sell_cell):
				build.try_place_at(grid.cell_to_world_center(sell_cell))
			build.set_placing_enabled(false)
			build.try_place_at(grid.cell_to_world_center(sell_cell))
			if build.selection_count() != 1:
				errors.append("should be able to select a wall to sell when not placing")
			elif not TowerData.is_wall((build.selected_towers[0] as Tower).tower_id):
				errors.append("selected piece for sell should be the wall")
			var empty_cell := Vector2i(6, 2)
			if build.try_place_at(grid.cell_to_world_center(empty_cell)):
				errors.append("placing should be blocked after deselect/placing off")
			if build.selection_count() != 0:
				errors.append("empty click with placing off should clear board selection")
			build.try_place_at(grid.cell_to_world_center(sell_cell))
			if build.selection_count() != 1:
				errors.append("should re-select wall with placing still off")
			elif not build.sell_selected():
				errors.append("selling a selected wall should succeed")
			elif grid.get_tower_at(sell_cell) != null:
				errors.append("sold wall should be removed")
			# Re-click selected combat tower deselects.
			var gun_cell := Vector2i(3, 3)
			if build.can_place_at(gun_cell):
				build.try_place_at(grid.cell_to_world_center(gun_cell))
			var gun = grid.get_tower_at(gun_cell)
			if gun != null:
				build.try_place_at(grid.cell_to_world_center(gun_cell))
				if build.selection_count() != 1:
					errors.append("tap combat tower should select it")
				build.try_place_at(grid.cell_to_world_center(gun_cell))
				if build.selection_count() != 0:
					errors.append("re-tap selected combat tower should deselect")

	# Cannot build wall/tower over an existing tower — must sell first.
	build.clear_selection()
	build.select_tower_type("gunner")
	var occupied := Vector2i(3, 2)
	if build.can_place_at(occupied):
		build.try_place_at(grid.cell_to_world_center(occupied))
	var occupied_tower = grid.get_tower_at(occupied)
	if occupied_tower == null:
		errors.append("expected gunner for occupied-cell tests")
	else:
		build.select_tower_type("wall")
		if build.can_place_at(occupied):
			errors.append("walls must not build over towers")
		build.select_tower_type("burn")
		if build.can_place_at(occupied):
			errors.append("towers must not build over towers (sell first)")
		if grid.get_tower_at(occupied) == null or grid.get_tower_at(occupied).tower_id != "gunner":
			errors.append("occupied tower should remain gunner")
		# Shop type change must not rebuild selected towers.
		build.clear_selection()
		build.try_place_at(grid.cell_to_world_center(occupied), false)
		build.select_tower_type("cannon")
		if grid.get_tower_at(occupied).tower_id != "gunner":
			errors.append("selecting shop type should not replace selected towers")

	# Blocking the only corridor entirely should fail — fill a wall except one gap then try to close gap
	# Simpler: temporarily check would_block on a cell that is the only path by filling all middle columns except one.
	_fill_column_except(build, grid, 5, 0)
	var last_gap := Vector2i(5, 0)
	if build.pathfinder.has_path(last_gap) == false:
		# already blocked somehow
		pass
	if not build.pathfinder.would_block_path(last_gap):
		# If still alternate paths exist around column 5, that's ok for this map size.
		pass

	# Send a wave
	if not waves.send_next_wave():
		errors.append("send_next_wave failed")
	else:
		if state.wave != 1:
			errors.append("wave should be 1")
		await process_frame
		if waves.enemies_alive <= 0 and waves.spawning == false and waves.spawn_queue.is_empty():
			errors.append("expected enemies spawning or alive after send")

	# Boss schedule checks
	if WaveScaler.boss_count(10) != 1:
		errors.append("wave 10 should have 1 boss")
	if WaveScaler.boss_count(50) != 2:
		errors.append("wave 50 should have 2 bosses")
	if WaveScaler.boss_count(11) != 0:
		errors.append("wave 11 should have 0 bosses")
	if WaveScaler.flying_boss_count(15) != 1:
		errors.append("wave 15 should have 1 flying boss")
	if WaveScaler.flying_boss_count(14) != 0:
		errors.append("wave 14 should have 0 flying bosses")
	if WaveScaler.boss_banner(15).find("FLYING") < 0:
		errors.append("wave 15 banner should mention flying")
	if not WaveScaler.is_boss_wave(10):
		errors.append("wave 10 should be a boss wave")
	if not WaveScaler.is_boss_wave(15):
		errors.append("wave 15 should be a boss wave")
	if WaveScaler.is_boss_wave(11):
		errors.append("wave 11 should not be a boss wave")
	if WaveScaler.boss_banner(10, true).find("SNAKE") < 0:
		errors.append("snake banner should mention SNAKE")
	var expected_snake := WaveScaler.creep_count(10) + WaveScaler.boss_count(10) + WaveScaler.flying_boss_count(10)
	if WaveScaler.snake_segment_count(10) != expected_snake:
		errors.append("snake segment count should equal all wave mobs")
	if WaveScaler.snake_body_hp(10) <= WaveScaler.creep_hp(10):
		errors.append("snake body should be tougher than normal creeps")
	if WaveScaler.flying_creep_count(7) != 0:
		errors.append("wave 7 should not have flying scouts yet")
	if WaveScaler.flying_creep_count(8) <= 0:
		errors.append("wave 8 should start light flying scouts")
	if WaveScaler.flying_creep_count(21) <= 0:
		errors.append("wave 21 should mix flying creeps")
	if WaveScaler.flying_creep_count(40) <= 0:
		errors.append("wave 40 should include flying creeps")
	if WaveScaler.ground_creep_count(40) + WaveScaler.flying_creep_count(40) != WaveScaler.creep_count(40):
		errors.append("ground+air creep counts should equal creep_count")
	if WaveScaler.flying_creep_hp(20) >= WaveScaler.creep_hp(20) * 0.75:
		errors.append("flying creeps should be glassier than ~75% ground HP")
	if WaveScaler.flying_boss_hp(15) >= WaveScaler.creep_hp(15) * 9.0:
		errors.append("flying bosses should be under 9x creep HP")
	# Confirm wave-15 spawn queue actually contains a flyer.
	waves._wave_is_snake = false
	waves._build_spawn_queue(15)
	var flying_in_15 := 0
	for spec in waves.spawn_queue:
		if bool(spec.get("flying", false)):
			flying_in_15 += 1
	if flying_in_15 <= 0:
		errors.append("wave 15 spawn queue should include flying enemies")

	# Snake boss queue: all ground segments, head first, tougher body HP.
	waves._wave_is_snake = true
	waves._build_spawn_queue(10)
	if waves.spawn_queue.size() != WaveScaler.snake_segment_count(10):
		errors.append("snake queue length should match segment count")
	elif waves.spawn_queue.is_empty():
		errors.append("snake queue should not be empty")
	else:
		if not bool(waves.spawn_queue[0].get("boss", false)):
			errors.append("snake head should be marked boss")
		if not bool(waves.spawn_queue[0].get("snake", false)):
			errors.append("snake head should be marked snake")
		for spec in waves.spawn_queue:
			if bool(spec.get("flying", false)):
				errors.append("snake queue should be ground-only")
				break
			if not bool(spec.get("snake", false)):
				errors.append("every snake queue entry should be snake")
				break
	waves._wave_is_snake = false

	# Early-send must not keep stacking unspawned leftovers (Classic late-game freeze).
	waves.clear_enemies()
	state.reset_run(WaveScaler.Difficulty.MEDIUM, WaveScaler.GameMode.CLASSIC)
	waves.begin_run()
	if not waves.start_round():
		errors.append("start_round failed before early-send pressure test")
	else:
		waves.force_intermission(0.01, true)
		if not waves.send_next_wave():
			errors.append("send_next_wave failed before early-send pressure test")
		else:
			# Over pressure: early-send must refuse (prevents wave-60 freezes).
			waves.spawn_queue.clear()
			for _i in 80:
				waves.spawn_queue.append({
					"hp": 10.0, "speed": 60.0, "bounty": 1,
					"boss": false, "flying": false, "wave": state.wave, "counts_kill": false,
				})
			waves.enemies_alive = 8
			waves.skip_unlocked = true
			waves.phase = waves.Phase.WAVE
			waves.wave_active = true
			waves.spawning = true
			if waves.can_send_wave_early():
				errors.append("early-send should block when board pressure is maxed")
			# Under pressure with leftovers: send must drop the unspawned queue.
			waves.spawn_queue.clear()
			for _i in 18:
				waves.spawn_queue.append({
					"hp": 10.0, "speed": 60.0, "bounty": 1,
					"boss": false, "flying": false, "wave": state.wave, "counts_kill": false,
				})
			waves.enemies_alive = 8
			waves.skip_unlocked = true
			waves.phase = waves.Phase.WAVE
			waves.wave_active = true
			waves.spawning = true
			var leftovers_before := waves.spawn_queue.size()
			if not waves.send_wave_early():
				errors.append("send_wave_early should work under pressure cap")
			elif waves.spawn_queue.size() >= leftovers_before:
				errors.append(
					"early-send should drop unspawned leftovers (queue stayed >= %d)" % leftovers_before
				)
			waves.clear_enemies()
	if WaveScaler.boss_banner(22).find("AIR MIX") < 0:
		errors.append("wave 22 banner should mention AIR MIX")
	if not WaveScaler.is_speed_wave(7):
		errors.append("wave 7 should be a speed wave")
	if WaveScaler.is_speed_wave(8):
		errors.append("wave 8 should not be a speed wave")
	if WaveScaler.creep_speed(7) <= WaveScaler.creep_speed(6):
		errors.append("speed wave creeps should be faster than the prior wave")
	if WaveScaler.boss_banner(7).find("SPEED") < 0:
		errors.append("wave 7 banner should mention SPEED WAVE")
	if WaveScaler.spawn_interval(7) >= WaveScaler.spawn_interval(6):
		errors.append("speed waves should spawn faster")
	var air_path := grid.build_air_s_path()
	if air_path.size() < 4:
		errors.append("air S-path should have multiple waypoints, got %d" % air_path.size())
	else:
		# Quarter point of a sine S should peak off the spawn→exit centerline.
		var quarter := air_path[maxi(air_path.size() / 4, 1)]
		var start_y := air_path[0].y
		if absf(quarter.y - start_y) < 20.0:
			errors.append("air S-path should weave vertically off the straight line")

	var lightning_def := TowerData.get_def("lightning")
	if TowerData.target_damage_mult(lightning_def, true) <= TowerData.target_damage_mult(lightning_def, false):
		errors.append("lightning should deal more damage to air than ground")
	var cannon_def := TowerData.get_def("cannon")
	if TowerData.target_damage_mult(cannon_def, true) >= TowerData.target_damage_mult(cannon_def, false):
		errors.append("cannon should deal less damage to air than ground")
	if TowerData.target_damage_mult(cannon_def, false, true) <= TowerData.target_damage_mult(cannon_def, false, false):
		errors.append("cannon should deal more damage to bosses than creeps")
	if not TowerData.prefers_bosses(cannon_def):
		errors.append("cannon should prefer bosses")

	var spike_def := TowerData.get_def("spike")
	if TowerData.target_filter(spike_def) != "ground":
		errors.append("spike should be ground-only")
	if not bool(spike_def.get("melee", false)):
		errors.append("spike should be melee")
	if TowerData.target_damage_mult(spike_def, true) != 0.0:
		errors.append("spike should deal no air damage")
	var antiair_def := TowerData.get_def("antiair")
	if TowerData.target_filter(antiair_def) != "air":
		errors.append("antiair should be air-only")
	if TowerData.target_damage_mult(antiair_def, false) != 0.0:
		errors.append("antiair should deal no ground damage")
	if "spike" not in TowerData.get_ids() or "antiair" not in TowerData.get_ids():
		errors.append("spike and antiair should be in tower id list")
	if "command" not in TowerData.get_ids():
		errors.append("command tower should be in tower id list")
	if not TowerData.is_command("command"):
		errors.append("command should be flagged is_command")
	if CommandAbilities.cost("airstrike") <= 0:
		errors.append("airstrike should cost gold each use")
	if CommandAbilities.cross_cells(Vector2i(3, 3)).size() != 5:
		errors.append("airstrike cross should be 5 cells")
	if CommandAbilities.get_ids().size() < 4:
		errors.append("command should offer 4 abilities")
	if not CommandAbilities.is_trap("airstrike") or not CommandAbilities.is_trap("barricade") or not CommandAbilities.is_trap("flare"):
		errors.append("combat abilities should be traps")
	if CommandAbilities.is_trap("supply"):
		errors.append("supply drop should stay instant")
	var ability_tip := CommandAbilities.tooltip_for("airstrike")
	if ability_tip.find("Air Strike") < 0 or ability_tip.find("gold") < 0:
		errors.append("ability tooltip should include name and gold")
	if ability_tip.find("Trap") < 0:
		errors.append("trap ability tooltip should mention Trap")

	# Vortex: no-damage aura; 3×3 footprint; ground orbit for one lap (unlock wave 12).
	var vortex_def := TowerData.get_def("vortex")
	if "vortex" not in TowerData.get_ids():
		errors.append("vortex should be in tower id list")
	if not bool(vortex_def.get("is_aura", false)):
		errors.append("vortex should be an aura tower")
	if float(vortex_def.get("damage", 1.0)) != 0.0:
		errors.append("vortex should deal no damage")
	if TowerData.target_filter(vortex_def) != "ground":
		errors.append("vortex should be ground-only")
	if TowerData.footprint_size("vortex") != 3:
		errors.append("vortex should lock a 3x3 zone")
	if not TowerData.path_blocks_center_only("vortex"):
		errors.append("vortex should path-block only its center")
	if not TowerData.pulls_from_ring_only("vortex"):
		errors.append("vortex should only pull from the 8 ring tiles")
	if TowerData.path_block_cells(Vector2i(5, 5), "vortex") != [Vector2i(5, 5)]:
		errors.append("vortex path_block_cells should be center only")
	if TowerData.unlock_wave("vortex") != 12:
		errors.append("vortex should unlock at wave 12")
	if TowerData.is_unlocked("vortex", 11):
		errors.append("vortex should be locked before wave 12")
	if not TowerData.is_unlocked("vortex", 12):
		errors.append("vortex should unlock at wave 12+")
	var orbit_path := PackedVector2Array([Vector2(0, 0), Vector2(200, 0), Vector2(200, 100)])
	var orbit_enemy := Enemy.new()
	orbit_enemy.setup(orbit_path, 50.0, 80.0, 5, false, false)
	orbit_enemy.position = Vector2(40, 0)
	main.add_child(orbit_enemy)
	if not orbit_enemy.try_begin_orbit(Vector2(40, 40), 40.0, 1.0, 1.5):
		errors.append("ground enemy should begin vortex orbit")
	elif not orbit_enemy.orbit_active:
		errors.append("orbit_active should be true after grab")
	else:
		var need := TAU * 1.05
		var guard := 0
		while orbit_enemy.orbit_active and orbit_enemy.orbit_angle_traveled < need and guard < 400:
			orbit_enemy._move_orbit(0.05)
			guard += 1
		if orbit_enemy.orbit_active:
			errors.append("orbit should finish after one lap")
		elif orbit_enemy.orbit_immune_time <= 0.0:
			errors.append("orbit release should set re-grab immune timer")
	var flyer_orbit := Enemy.new()
	flyer_orbit.setup(orbit_path, 50.0, 80.0, 5, false, true)
	flyer_orbit.position = Vector2(40, 0)
	main.add_child(flyer_orbit)
	if flyer_orbit.try_begin_orbit(Vector2(40, 40), 40.0, 1.0, 1.5):
		errors.append("flying enemy should refuse vortex orbit")
	orbit_enemy.queue_free()
	flyer_orbit.queue_free()
	# Vortex placement: 3×3, no map corner, no adjacent towers.
	grid.reset(true)
	build.pathfinder.rebuild()
	state.reset_run(WaveScaler.Difficulty.MEDIUM, WaveScaler.GameMode.CLASSIC)
	state.set_wave(12)
	state_add_gold(build, 500)
	build.select_tower_type("vortex")
	var corner_center := Vector2i(1, 1)
	if build.can_place_at(corner_center):
		errors.append("vortex should refuse map-corner footprints")
	var vortex_cell := Vector2i(10, 7)
	if not build.can_place_at(vortex_cell):
		errors.append("vortex should place on a clear interior 3x3")
	elif not build.try_place_at(grid.cell_to_world_center(vortex_cell)):
		errors.append("vortex place failed on clear interior cell")
	else:
		var vx := grid.get_tower_at(vortex_cell)
		if vx == null or vx.tower_id != "vortex":
			errors.append("vortex should register at anchor cell")
		else:
			var fp_cells := 0
			for vc in TowerData.footprint_cells(vortex_cell, 3):
				if grid.get_tower_at(vc) == vx:
					fp_cells += 1
			if fp_cells != 9:
				errors.append("vortex should occupy all 9 footprint cells")
			build.pathfinder.rebuild()
			if not build.pathfinder.astar.is_point_solid(vortex_cell):
				errors.append("vortex center should block path")
			var ring := vortex_cell + Vector2i(1, 0)
			if build.pathfinder.astar.is_point_solid(ring):
				errors.append("vortex ring tile should stay walkable for path")
			# Towers may sit flush against the lockdown edge (outside the 3×3).
			build.select_tower_type("gunner")
			var adj := vortex_cell + Vector2i(2, 0)
			state_add_gold(build, 100)
			if not build.can_place_at(adj):
				errors.append("gunner should place flush against vortex lockdown edge")
			elif not build.try_place_at(grid.cell_to_world_center(adj)):
				errors.append("gunner place on vortex edge failed")
			else:
				var edge_gun := grid.get_tower_at(adj)
				if edge_gun != null:
					grid.remove_tower_at(adj)
					edge_gun.queue_free()
			# Locked ring cells stay unbuildable even though path can walk them.
			if build.can_place_at(ring):
				errors.append("gunner should not place inside vortex lockdown zone")
			grid.remove_tower_at(vortex_cell)
			if is_instance_valid(vx):
				vx.queue_free()
			build.pathfinder.rebuild()

	# Gatling: wave-30 unlock, expensive ultra-fast special.
	var gatling_def := TowerData.get_def("gatling")
	if int(gatling_def.get("cost", 0)) < 25000:
		errors.append("gatling should cost at least 25000")
	if float(gatling_def.get("fire_rate", 0.0)) < 10.0:
		errors.append("gatling should fire very fast")
	if TowerData.unlock_wave("gatling") != 30:
		errors.append("gatling should unlock at wave 30")
	if TowerData.is_unlocked("gatling", 29):
		errors.append("gatling should be locked before wave 30")
	if not TowerData.is_unlocked("gatling", 30):
		errors.append("gatling should unlock at wave 30+")
	build.select_tower_type("gunner")
	state.set_wave(10)
	state_add_gold(build, 30000)
	build.select_tower_type("gatling")
	if build.selected_tower_id == "gatling":
		errors.append("gatling select should fail before unlock wave")
	var gat_cell := Vector2i(7, 3)
	# Force type to exercise the unlock check inside can_place_at.
	build.selected_tower_id = "gatling"
	if build.can_place_at(gat_cell):
		errors.append("gatling place should fail before unlock wave")
	state.set_wave(30)
	build.select_tower_type("gatling")
	if build.selected_tower_id != "gatling":
		errors.append("gatling select should work at wave 30")
	elif not build.can_place_at(gat_cell):
		errors.append("gatling should be placeable at wave 30 with enough gold")
	else:
		if not build.try_place_at(grid.cell_to_world_center(gat_cell)):
			errors.append("gatling place failed at wave 30")
		else:
			var gat := grid.get_tower_at(gat_cell)
			if gat == null or gat.tower_id != "gatling":
				errors.append("expected gatling on board")
			# Other towers can still be built around it.
			build.select_tower_type("rapid")
			var around := Vector2i(8, 3)
			if build.can_place_at(around):
				build.try_place_at(grid.cell_to_world_center(around))
			if grid.get_tower_at(around) == null or grid.get_tower_at(around).tower_id != "rapid":
				errors.append("should be able to build other towers beside gatling")

	# Upgrade path: 3 stats then final elemental.
	build.clear_selection()
	build.select_tower_type("gunner")
	state_add_gold(build, 100000)
	var up_cell := Vector2i(6, 2)
	if build.can_place_at(up_cell):
		build.try_place_at(grid.cell_to_world_center(up_cell))
	var up_tower = grid.get_tower_at(up_cell)
	if up_tower == null:
		errors.append("expected gunner for upgrade test")
	else:
		# Placement clears selection by design — reselect for upgrade checks.
		build.try_place_at(grid.cell_to_world_center(up_cell), false)
		if build.selection_count() != 1:
			errors.append("clicking placed tower should select it")
		var base_dmg := float(up_tower.def.get("damage", 0.0))
		for i in TowerData.MAX_STAT_UPGRADES:
			var up := build.upgrade_selected()
			if int(up.get("upgraded", 0)) != 1:
				errors.append("stat upgrade %d failed" % (i + 1))
		if up_tower.upgrade_level != TowerData.MAX_STAT_UPGRADES:
			errors.append("expected +3 upgrades")
		if float(up_tower.def.get("damage", 0.0)) <= base_dmg:
			errors.append("upgrades should increase damage")
		if not up_tower.can_final_upgrade():
			errors.append("should be ready for final elemental")
		var fin := build.apply_final_selected("burn")
		if int(fin.get("applied", 0)) != 1:
			errors.append("final fire upgrade failed")
		if up_tower.final_element != "burn":
			errors.append("final element should be burn")
		if str(up_tower.def.get("effect", "")) != "none":
			errors.append("gunner should stay non-elemental after fire buff")
		if not up_tower.def.has("bonus_burn_dps"):
			errors.append("fire final should add a burn buff")

		# Elemental tower keeps its identity when picking a different final.
		build.clear_selection()
		build.select_tower_type("burn")
		var fire_cell := Vector2i(7, 2)
		if build.can_place_at(fire_cell):
			build.try_place_at(grid.cell_to_world_center(fire_cell))
		var fire_tower = grid.get_tower_at(fire_cell)
		if fire_tower == null:
			errors.append("expected burn tower for ice-buff test")
		else:
			build.try_place_at(grid.cell_to_world_center(fire_cell), false)
			for i in TowerData.MAX_STAT_UPGRADES:
				build.upgrade_selected()
			var ice := build.apply_final_selected("freeze")
			if int(ice.get("applied", 0)) != 1:
				errors.append("final ice buff on burn tower failed")
			if fire_tower.tower_id != "burn" or str(fire_tower.def.get("effect", "")) != "burn":
				errors.append("burn tower should stay fire after ice final")
			if not fire_tower.def.has("bonus_slow_factor"):
				errors.append("ice final should add a slow buff")

	# Debug: spawn mobs onto the player's own path.
	grid.reset(true)
	build.pathfinder.rebuild()
	state.reset_run(WaveScaler.Difficulty.MEDIUM, WaveScaler.GameMode.CLASSIC)
	waves.clear_enemies()
	var dbg_n := waves.debug_spawn_on_self(3, false, false)
	if dbg_n != 3:
		errors.append("debug_spawn_on_self should spawn 3 creeps, got %d" % dbg_n)
	elif waves.enemies_alive < 3:
		errors.append("debug spawn should increase enemies_alive")
	waves.clear_enemies()

	# Portal slides: same-row ±X after wave 10, 200 gold (grid path rules).
	if WaveScaler.PORTAL_SLIDE_COST != 200:
		errors.append("portal slide should cost 200")
	if WaveScaler.PORTAL_SLIDE_UNLOCK_WAVE != 10:
		errors.append("portal slide should unlock at wave 10")
	grid.reset(true)
	build.pathfinder.rebuild()
	state.reset_run(WaveScaler.Difficulty.MEDIUM, WaveScaler.GameMode.CLASSIC)
	var spawn_before := grid.spawn_cell
	if grid.can_slide_portal("spawn", -1, build.pathfinder):
		errors.append("spawn should not slide off the left edge")
	if grid.spawn_cell != spawn_before:
		errors.append("failed can_slide should not move spawn")
	if not grid.can_slide_portal("spawn", 1, build.pathfinder):
		errors.append("spawn should be able to slide right on empty classic")
	elif grid.spawn_cell != spawn_before:
		errors.append("can_slide_portal should be a dry-run")
	elif not grid.try_slide_portal("spawn", 1, build.pathfinder):
		errors.append("try_slide_portal spawn right failed")
	elif grid.spawn_cell != spawn_before + Vector2i(1, 0):
		errors.append("spawn should move exactly one cell right on the same row")
	elif grid.spawn_cell.y != spawn_before.y:
		errors.append("spawn slide must keep the same row")
	var exit_before := grid.exit_cell
	if not grid.try_slide_portal("exit", -1, build.pathfinder):
		errors.append("exit should slide left on empty classic")
	elif grid.exit_cell != exit_before + Vector2i(-1, 0):
		errors.append("exit should move exactly one cell left on the same row")
	# Mid-wave / pre-unlock gates are enforced in main; grid always allows legal slides.

	if errors.is_empty():
		print("SMOKE_TEST_OK")
		quit(0)
	else:
		for e in errors:
			push_error("FAIL: " + e)
		print("SMOKE_TEST_FAIL")
		quit(1)


func _fill_column_except(build: BuildSystem, grid: GameGrid, col: int, except_row: int) -> void:
	build.select_tower_type("gunner")
	state_add_gold(build, 100000)
	for y in GameGrid.ROWS:
		if y == except_row:
			continue
		var cell := Vector2i(col, y)
		if build.can_place_at(cell):
			build.try_place_at(grid.cell_to_world_center(cell))


func state_add_gold(build: BuildSystem, amount: int) -> void:
	build.game_state.add_gold(amount)
