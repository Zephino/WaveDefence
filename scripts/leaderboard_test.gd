extends SceneTree

func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	# Use the real save path but clear before/after so player data is not left polluted.
	if FileAccess.file_exists(LeaderboardStore.SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(LeaderboardStore.SAVE_PATH))

	var errors: Array[String] = []
	if LeaderboardStore.qualifies(1, WaveScaler.Difficulty.MEDIUM) != true:
		errors.append("empty medium board should qualify wave 1")

	LeaderboardStore.add_score("Alice", 10, WaveScaler.Difficulty.MEDIUM)
	LeaderboardStore.add_score("Bob!!", 5, WaveScaler.Difficulty.MEDIUM)
	LeaderboardStore.add_score("Hardy", 8, WaveScaler.Difficulty.HARD)
	var medium := LeaderboardStore.load_entries(WaveScaler.Difficulty.MEDIUM)
	var hard := LeaderboardStore.load_entries(WaveScaler.Difficulty.HARD)
	var easy := LeaderboardStore.load_entries(WaveScaler.Difficulty.EASY)
	if medium.size() != 2:
		errors.append("expected 2 medium entries")
	if hard.size() != 1:
		errors.append("expected 1 hard entry")
	if easy.size() != 0:
		errors.append("easy board should stay empty")
	if str(medium[0]["name"]) != "Alice":
		errors.append("Alice should be first on medium")
	if str(medium[1]["name"]) != "Bob":
		errors.append("name sanitize failed: %s" % str(medium[1]["name"]))
	if str(hard[0]["name"]) != "Hardy":
		errors.append("Hardy should be on hard board")

	# Legacy flat array migrates into Medium.
	var file := FileAccess.open(LeaderboardStore.SAVE_PATH, FileAccess.WRITE)
	file.store_string("[{\"name\":\"Old\",\"wave\":12}]")
	file.close()
	file = null
	var migrated := LeaderboardStore.load_entries(WaveScaler.Difficulty.MEDIUM)
	if migrated.is_empty() or str(migrated[0]["name"]) != "Old":
		errors.append("legacy leaderboard should migrate to medium")
	var boards := LeaderboardStore.load_boards()
	if typeof(boards.get("medium", null)) != TYPE_ARRAY:
		errors.append("migrated save should use per-difficulty boards")

	for i in 10:
		LeaderboardStore.add_score("P%d" % i, 20 + i, WaveScaler.Difficulty.EASY)
	easy = LeaderboardStore.load_entries(WaveScaler.Difficulty.EASY)
	if easy.size() != LeaderboardStore.MAX_ENTRIES:
		errors.append("expected max easy entries")
	if LeaderboardStore.qualifies(1, WaveScaler.Difficulty.EASY):
		errors.append("wave 1 should not qualify on full easy board")
	if not LeaderboardStore.qualifies(1, WaveScaler.Difficulty.HARD):
		errors.append("hard board should still qualify low waves")
	if not LeaderboardStore.qualifies(int(easy[LeaderboardStore.MAX_ENTRIES - 1]["wave"]), WaveScaler.Difficulty.EASY):
		errors.append("tie with last place should qualify")

	# Cleanup test save
	if FileAccess.file_exists(LeaderboardStore.SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(LeaderboardStore.SAVE_PATH))

	if errors.is_empty():
		print("LEADERBOARD_TEST_OK")
		quit(0)
		return
	for e in errors:
		push_error("FAIL: " + e)
	print("LEADERBOARD_TEST_FAIL")
	quit(1)
