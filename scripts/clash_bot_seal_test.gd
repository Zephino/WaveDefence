extends SceneTree
## Run: godot --headless --path . -s res://scripts/clash_bot_seal_test.gd   (expect 0 sealed)
## Repro: how often does a Clash bot fully seal its own lane?
func _sealed(pf: Pathfinder, grid: GameGrid, lane: int) -> bool:
	pf.rebuild()
	return pf.get_cell_path_between(grid.get_lane_spawn(lane), grid.get_lane_exit(lane)).size() < 2

func _init() -> void:
	call_deferred("_run")

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
	var styles: Array = ClashBotMemory.STRATEGIES
	var trials := 0; var seal_prep := 0; var seal_repair := 0
	var by_source := {"prep": {}, "repair": {}}
	var rng := RandomNumberGenerator.new(); rng.seed = 7
	for diff in [WaveScaler.Difficulty.MEDIUM, WaveScaler.Difficulty.HARD]:
		for style in styles:
			for plan in [ClashBotAI.BuildPlan.MAZE, ClashBotAI.BuildPlan.HYBRID, ClashBotAI.BuildPlan.DPS]:
				trials += 1
				grid.reset_clash(2)
				pf.sync_region(); pf.rebuild()
				var cm := ClashMatch.new(); main.add_child(cm)
				cm.setup(state, 2, [diff])
				var ai := ClashBotAI.new()
				ai.setup(cm, grid, pf, main.enemies, main.projectiles, main.traps, 1)
				ai._build_plan = plan; ai._maze_strategy = style
				var p := cm.get_player(1)
				var lane := p.lane_index
				var sealed_now := false
				for w in range(1, 5):
					p.add_gold(WaveScaler.CLASH_BASE_INCOME + 60 * w)
					ai.run_prep_turn(w)
					if _sealed(pf, grid, lane):
						seal_prep += 1; sealed_now = true
						by_source["prep"][style] = int(by_source["prep"].get(style, 0)) + 1
						break
					# Wrecker smashes 1-4 random owned pieces, bot repairs mid-wave.
					var owned: Array = []
					for cell in grid.towers.keys():
						var t: Node = grid.towers[cell]
						if t is Tower and t.has_meta("clash_owner") and int(t.get_meta("clash_owner")) == 1:
							owned.append(cell)
					for _k in rng.randi_range(1, 4):
						if owned.is_empty(): break
						var cc: Vector2i = owned.pop_at(rng.randi_range(0, owned.size() - 1))
						var rm := grid.remove_tower_at(cc)
						if is_instance_valid(rm): rm.queue_free()
					pf.rebuild()
					p.gold = maxi(p.gold, 300)
					ai._last_repair_msec = -99999
					ai.repair_lane(w)
					if _sealed(pf, grid, lane):
						seal_repair += 1; sealed_now = true
						by_source["repair"][style] = int(by_source["repair"].get(style, 0)) + 1
						break
				cm.queue_free()
	print("trials ", trials, "  sealed during PREP ", seal_prep, "  sealed during MID-WAVE REPAIR ", seal_repair)
	print("prep seals by style ", by_source["prep"])
	print("repair seals by style ", by_source["repair"])
	quit()
