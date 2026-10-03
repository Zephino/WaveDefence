extends SceneTree

## Diagnoses why map clicks may not place towers.
## godot --headless --path . -s res://scripts/place_input_diag.gd

func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var main_scene := load("res://scenes/main.tscn") as PackedScene
	var main := main_scene.instantiate()
	root.add_child(main)
	await process_frame
	await process_frame

	var blockers: Array[String] = []
	for child in main.get_children():
		if child is Control:
			var c := child as Control
			var filter_name := str(c.mouse_filter)
			if c.mouse_filter == Control.MOUSE_FILTER_STOP:
				blockers.append("%s size=%s filter=STOP" % [c.name, str(c.size)])

	print("CONTROL_STOP_COUNT=%d" % blockers.size())
	for b in blockers:
		print("BLOCKER: ", b)

	var build: BuildSystem = main.get_node("BuildSystem")
	var grid: GameGrid = main.get_node("GameGrid")
	var cell := Vector2i(3, 3)
	print("CAN_PLACE_API=%s" % str(build.can_place_at(cell)))
	var ok := build.try_place_at(grid.cell_to_world_center(cell))
	print("PLACE_API_OK=%s TOWER_COUNT=%d" % [str(ok), grid.towers.size()])

	if blockers.size() > 0 and ok:
		print("DIAGNOSIS: API place works; Control STOP nodes can swallow map clicks.")
	print("PLACE_INPUT_DIAG_DONE")
	quit(0)
