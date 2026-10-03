extends SceneTree

func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var main_scene := load("res://scenes/main.tscn") as PackedScene
	var main := main_scene.instantiate()
	root.add_child(main)
	await process_frame
	await process_frame

	var waves: WaveManager = main.get_node("WaveManager")
	var state: GameState = main.get_node("GameState")
	var errors: Array[String] = []

	if waves.phase != WaveManager.Phase.PREP:
		errors.append("expected PREP at start")

	if not waves.start_round():
		errors.append("start_round failed")
	if not waves.can_skip_timer():
		errors.append("build timer should be skippable")
	var gold_before_timer_skip := state.gold
	if not waves.try_skip_timer():
		errors.append("skip build timer failed")
	if waves.phase != WaveManager.Phase.WAVE:
		errors.append("expected WAVE after skip")
	if state.gold <= gold_before_timer_skip:
		errors.append("skipping build timer should grant early-send gold")

	waves.enemies_this_wave_total = 8
	waves.kills_this_wave = 2
	waves.skip_unlocked = false
	waves.enemies_alive = 3
	waves.spawning = false
	waves.spawn_queue.clear()
	waves._update_skip_unlock()
	if not waves.skip_unlocked:
		errors.append("25% kills should unlock")
	if not waves.can_skip_timer():
		errors.append("early send should be available during wave after unlock")

	var gold_before_early := state.gold
	var wave_before := state.wave
	if not waves.try_skip_timer():
		errors.append("early send failed")
	if state.wave != wave_before + 1:
		errors.append("early send should advance wave")
	if waves.enemies_alive != 3:
		errors.append("early send should keep leftover enemies alive, got %d" % waves.enemies_alive)
	if not waves.spawning:
		errors.append("early send should start spawning next wave immediately")
	if state.gold <= gold_before_early:
		errors.append("early send should grant bonus gold")
	if waves.last_early_send_bonus <= 0:
		errors.append("last_early_send_bonus should be set")

	if errors.is_empty():
		print("SKIP_TIMER_DIAG_OK")
		quit(0)
		return
	for e in errors:
		push_error("FAIL: " + e)
	print("SKIP_TIMER_DIAG_FAIL")
	quit(1)
