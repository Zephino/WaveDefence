extends SceneTree

func _init() -> void:
	call_deferred("_run")


func _bfs_len(cells: Array[Vector2i]) -> int:
	var walk: Dictionary = {}
	for c in cells:
		walk[c] = true
	var start := Vector2i(ClashMazeTemplates.MID, 0)
	var goal := Vector2i(ClashMazeTemplates.MID, ClashMazeTemplates.HEIGHT - 1)
	if not walk.has(start) or not walk.has(goal):
		return -1
	var q: Array[Vector2i] = [start]
	var dist: Dictionary = {start: 1}
	var qi := 0
	while qi < q.size():
		var cur: Vector2i = q[qi]
		qi += 1
		if cur == goal:
			return int(dist[cur])
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = cur + d
			if walk.has(n) and not dist.has(n):
				dist[n] = int(dist[cur]) + 1
				q.append(n)
	return -1


func _run() -> void:
	print("TEMPLATES 7x%d" % ClashMazeTemplates.HEIGHT)
	var bad := 0
	for tid in ClashMazeTemplates.TEMPLATE_IDS:
		var p := ClashMazeTemplates.path_cells(tid)
		var bfs := _bfs_len(p)
		var note := ""
		if bfs < 0 or p.is_empty() or p[p.size() - 1] != Vector2i(ClashMazeTemplates.MID, ClashMazeTemplates.HEIGHT - 1):
			note = " BROKEN"
			bad += 1
		elif bfs < p.size():
			note = " SHORTCUT(bfs=%d)" % bfs
			bad += 1
		print("%s len=%d bfs=%d%s" % [tid, p.size(), bfs, note])
	print("DIAG_OK" if bad == 0 else "DIAG_FAIL bad=%d" % bad)
	quit()
