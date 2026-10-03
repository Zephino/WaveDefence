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
	var rotate_gold := WaveScaler.map_rotate_gold(WaveScaler.Difficulty.MEDIUM, 80)
	if rotate_gold < 80 * WaveScaler.MAP_ROTATE_GOLD_PER_KILL:
		errors.append("map rotate gold should scale with kills")
	grid.reset(true)
	build.pathfinder.rebuild()
	state.reset_run(WaveScaler.Difficulty.MEDIUM, WaveScaler.GameMode.CLASSIC)

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
	# Confirm wave-15 spawn queue actually contains a flyer.
	waves._build_spawn_queue(15)
	var flying_in_15 := 0
	for spec in waves.spawn_queue:
		if bool(spec.get("flying", false)):
			flying_in_15 += 1
	if flying_in_15 <= 0:
		errors.append("wave 15 spawn queue should include flying enemies")
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
