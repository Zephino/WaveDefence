extends SceneTree
## Clash bot evaluation: godot --headless --path . -s res://scripts/clash_bot_eval.gd
## Compares difficulties on maze length / defence coverage, checks no lane is ever sealed,
## and checks that memory + in-match adaptation change what bots do.

func _init() -> void:
	call_deferred("_run")

func _sealed(pf: Pathfinder, grid: GameGrid, lane: int) -> bool:
	pf.rebuild()
	return pf.get_cell_path_between(grid.get_lane_spawn(lane), grid.get_lane_exit(lane)).size() < 2

func _defence(ai: ClashBotAI, grid: GameGrid, pf: Pathfinder, lane: int) -> Array:
	pf.rebuild()
	var path := pf.get_cell_path_between(grid.get_lane_spawn(lane), grid.get_lane_exit(lane))
	var score := 0.0
	var towers := 0
	for cell in grid.towers.keys():
		var t: Node = grid.towers[cell]
		if not (t is Tower) or not t.has_meta("clash_owner") or int(t.get_meta("clash_owner")) != ai.player_id:
			continue
		var tw := t as Tower
		if TowerData.is_wall(tw.tower_id):
			continue
		# Real upgraded stats (damage x fire rate, splash, DoT) x path cells covered.
		score += ai._tower_dps(tw.tower_id, tw.upgrade_level, tw.final_element) * ai._coverage_score(cell, tw.tower_id, path)
		towers += 1
	return [path.size(), score, towers]

func _run() -> void:
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	var build: BuildSystem = main.get_node("BuildSystem")
	var state: GameState = main.get_node("GameState")
	var grid: GameGrid = null
	for c in main.get_children():
		if c is GameGrid: grid = c
	var pf := build.pathfinder
	var fails: Array[String] = []
	ClashBotMemory.reset_for_tests()
	var names := {WaveScaler.Difficulty.EASY: "Easy", WaveScaler.Difficulty.MEDIUM: "Medium", WaveScaler.Difficulty.HARD: "Hard", WaveScaler.Difficulty.CHEATER: "Cheater"}
	var results := {}
	var seals := 0
	const TRIALS := 12
	const WAVES := 5
	for diff in [WaveScaler.Difficulty.EASY, WaveScaler.Difficulty.MEDIUM, WaveScaler.Difficulty.HARD, WaveScaler.Difficulty.CHEATER]:
		var sum_len := 0.0; var sum_def := 0.0; var sum_t := 0.0
		for trial in TRIALS:
			seed(1000 + trial)
			grid.reset_clash(2); pf.sync_region(); pf.rebuild()
			var cm := ClashMatch.new(); main.add_child(cm)
			cm.setup(state, 2, [diff])
			var ai := ClashBotAI.new()
			ai.setup(cm, grid, pf, main.enemies, main.projectiles, main.traps, 1)
			ai._rng.seed = 5000 + trial
			# Controlled: same maze style + plan for every difficulty in a trial, so we compare the brains.
			ai._build_plan = ClashBotAI.BuildPlan.MAZE; ai._maze_strategy = ClashBotMemory.STRATEGIES[trial % 12]
			var p := cm.get_player(1)
			for w in range(1, WAVES + 1):
				p.add_gold(WaveScaler.CLASH_BASE_INCOME + 60 * w)
				ai.run_prep_turn(w)
				if _sealed(pf, grid, p.lane_index):
					seals += 1
					fails.append("%s sealed its lane (trial %d wave %d)" % [names[diff], trial, w])
					break
			var r := _defence(ai, grid, pf, p.lane_index)
			sum_len += float(r[0]); sum_def += float(r[1]); sum_t += float(r[2])
			cm.queue_free()
		results[diff] = [sum_len / TRIALS, sum_def / TRIALS, sum_t / TRIALS]
		print("%-8s avg path %5.1f   defence score %7.1f   combat towers %4.1f" % [names[diff], sum_len / TRIALS, sum_def / TRIALS, sum_t / TRIALS])
	if float(results[WaveScaler.Difficulty.HARD][1]) <= float(results[WaveScaler.Difficulty.EASY][1]):
		fails.append("Hard should out-defend Easy")
	if float(results[WaveScaler.Difficulty.MEDIUM][1]) <= float(results[WaveScaler.Difficulty.EASY][1]):
		fails.append("Medium should out-defend Easy")
	if float(results[WaveScaler.Difficulty.HARD][1]) <= float(results[WaveScaler.Difficulty.MEDIUM][1]):
		fails.append("Hard should out-defend Medium")
	if float(results[WaveScaler.Difficulty.CHEATER][1]) <= float(results[WaveScaler.Difficulty.HARD][1]):
		fails.append("Cheater should out-defend Hard")
	# ---- learning: one style scores well → Hard/Medium should favour it, Easy should not care
	ClashBotMemory.reset_for_tests()
	for s in ClashBotMemory.STRATEGIES:
		var good: bool = (s == "the_serpent")
		for _k in 6:
			ClashBotMemory.record_wave(s, 58 if good else 30, 0 if good else 5, [])
	var rng := RandomNumberGenerator.new(); rng.seed = 3
	var picks := {}
	for diff in [WaveScaler.Difficulty.EASY, WaveScaler.Difficulty.MEDIUM, WaveScaler.Difficulty.HARD]:
		var hit := 0
		for _k in 100:
			if ClashBotMemory.choose_strategy(rng, diff) == "the_serpent": hit += 1
		picks[diff] = hit
	print("learned best style picked /100:  Easy %d   Medium %d   Hard %d" % [picks[0], picks[1], picks[2]])
	if picks[WaveScaler.Difficulty.HARD] < 80: fails.append("Hard should exploit the learned best style")
	if picks[WaveScaler.Difficulty.MEDIUM] < 55: fails.append("Medium should usually use the learned best style")
	if picks[WaveScaler.Difficulty.EASY] > 25: fails.append("Easy should not follow memory")
	# ---- adaptation: fliers leaking → more air-capable picks
	grid.reset_clash(2); pf.sync_region(); pf.rebuild()
	var cm2 := ClashMatch.new(); main.add_child(cm2); cm2.setup(state, 2, [WaveScaler.Difficulty.HARD])
	var ai2 := ClashBotAI.new(); ai2.setup(cm2, grid, pf, main.enemies, main.projectiles, main.traps, 1)
	ClashBotMemory.reset_for_tests()
	var air_before := 0; var air_after := 0
	for _k in 200:
		var id := ai2._pick_affordable_tower_id(3, WaveScaler.Difficulty.HARD, 120)
		if TowerData.target_filter(TowerData.get_def(id)) == "air": air_before += 1
	var p2 := cm2.get_player(1)
	p2.leaks_air_round = 6
	ai2._learn_from_last_wave(p2, 3)
	for _k in 200:
		var id2 := ai2._pick_affordable_tower_id(3, WaveScaler.Difficulty.HARD, 120)
		if TowerData.target_filter(TowerData.get_def(id2)) == "air": air_after += 1
	print("anti-air picks /200 before flier leaks %d, after %d" % [air_before, air_after])
	if air_after <= air_before * 2: fails.append("bots should buy more anti-air after fliers leak")
	ClashBotMemory.reset_for_tests()
	print("lane seals: ", seals)
	for f in fails: print("FAIL ", f)
	print("BOT_EVAL ", "OK" if fails.is_empty() else "FAIL")
	quit()
