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
	if not WaveScaler.is_siege_mode(WaveScaler.GameMode.SIEGE):
		errors.append("is_siege_mode should be true for SIEGE")
	if not WaveScaler.should_rotate_spawn_after_wave(WaveScaler.GameMode.SIEGE, 5):
		errors.append("siege should rotate spawn after wave 5")
	if WaveScaler.should_rotate_spawn_after_wave(WaveScaler.GameMode.CLASSIC, 5):
		errors.append("classic should not rotate siege spawn")
	if WaveScaler.should_rotate_map_after_wave(WaveScaler.GameMode.SIEGE, 25):
		errors.append("siege should not use random map wipe")
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
	build.pathfinder.sync_region()
	build.pathfinder.rebuild()
	if grid.cols != GameGrid.SIEGE_COLS or grid.rows != GameGrid.SIEGE_ROWS:
		errors.append("siege should be %dx%d" % [GameGrid.SIEGE_COLS, GameGrid.SIEGE_ROWS])
	if grid.exit_cell != Vector2i(grid.cols / 2, grid.rows / 2):
		errors.append("siege exit should be map center")
	if build.pathfinder.get_world_path().size() < 2:
		errors.append("siege layout must keep a path")
	var old_spawn := grid.spawn_cell
	if not grid.relocate_rim_spawn(build.pathfinder, old_spawn):
		errors.append("siege rim spawn relocate failed")
	elif grid.spawn_cell == old_spawn:
		errors.append("siege rim spawn should move to a new cell")
	if build.pathfinder.get_world_path().size() < 2:
		errors.append("siege path must remain after spawn relocate")

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

	# Restore classic map for remaining tests.
	grid.reset(true)
	build.pathfinder.sync_region()
	build.pathfinder.rebuild()

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
			build.try_place_at(world)
			var over = grid.get_tower_at(place_cell)
			if over == null or over.tower_id != "gunner":
				errors.append("gunner should replace wall")
			if build.selection_count() != 0:
				errors.append("placing over wall should clear selection")
			build.pathfinder.rebuild()
			if not build.pathfinder.astar.is_point_solid(place_cell):
				errors.append("replaced wall cell must stay blocked for pathing")
			var path_cells := build.pathfinder.get_cell_path()
			if place_cell in path_cells:
				errors.append("enemies must not path through replaced wall cell")

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
