extends SceneTree

## Confirms local vs global path bug.
## godot --headless --path . -s res://scripts/path_coord_diag.gd

func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var main_scene := load("res://scenes/main.tscn") as PackedScene
	var main := main_scene.instantiate()
	root.add_child(main)
	await process_frame
	await process_frame

	var waves: WaveManager = main.get_node("WaveManager")
	var enemies: Node2D = main.get_node("Enemies")
	var grid: GameGrid = main.get_node("GameGrid")

	waves.send_next_wave()
	# Force immediate spawn
	waves.spawn_timer = 0.0
	await process_frame
	await process_frame

	if enemies.get_child_count() == 0:
		push_error("No enemy spawned")
		quit(1)
		return

	var enemy: Enemy = enemies.get_child(0)
	var spawn_local := grid.cell_to_world_center(grid.spawn_cell)
	var exit_local := grid.cell_to_world_center(grid.exit_cell)
	print("SPAWN_LOCAL=", spawn_local)
	print("EXIT_LOCAL=", exit_local)
	print("ENEMY_POS=", enemy.position)
	print("ENEMY_GLOBAL=", enemy.global_position)
	print("PATH0=", enemy.path[0] if enemy.path.size() > 0 else Vector2.ZERO)
	print("PATH_LAST=", enemy.path[enemy.path.size() - 1] if enemy.path.size() > 0 else Vector2.ZERO)
	print("MAP_OFFSET=", enemies.position)

	var delta_to_path1 := Vector2.ZERO
	if enemy.path.size() > 1:
		delta_to_path1 = enemy.path[1] - enemy.global_position
		print("OLD_STYLE_DELTA_GLOBAL=", delta_to_path1)
		print("NEW_STYLE_DELTA_LOCAL=", enemy.path[1] - enemy.position)

	var ok := enemy.position.distance_to(spawn_local) < 1.0
	print("AT_SPAWN_LOCAL=%s" % str(ok))
	print("PATH_COORD_DIAG_DONE")
	quit(0 if ok else 1)
