extends SceneTree

func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	# Isolate tests from the player's real leaderboard file.
	var real_path := LeaderboardStore.SAVE_PATH
	var test_path := "user://leaderboard_test_tmp.json"
	LeaderboardStore.SAVE_PATH = test_path
	if FileAccess.file_exists(test_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(test_path))

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

	# Legacy flat array migrates into classic Medium.
	var file := FileAccess.open(LeaderboardStore.SAVE_PATH, FileAccess.WRITE)
	file.store_string("[{\"name\":\"Old\",\"wave\":12}]")
	file.close()
	file = null
	var migrated := LeaderboardStore.load_entries(WaveScaler.Difficulty.MEDIUM)
	if migrated.is_empty() or str(migrated[0]["name"]) != "Old":
		errors.append("legacy leaderboard should migrate to classic medium")
	var boards := LeaderboardStore.load_boards()
	if typeof(boards.get("classic_medium", null)) != TYPE_ARRAY:
		errors.append("migrated save should use classic_medium key")

	# Legacy difficulty-only keys migrate to classic_*.
	file = FileAccess.open(LeaderboardStore.SAVE_PATH, FileAccess.WRITE)
	file.store_string("{\"easy\":[{\"name\":\"LegE\",\"wave\":3}],\"medium\":[],\"hard\":[]}")
	file.close()
	file = null
	var leg_easy := LeaderboardStore.load_entries(WaveScaler.Difficulty.EASY, WaveScaler.GameMode.CLASSIC)
	if leg_easy.is_empty() or str(leg_easy[0]["name"]) != "LegE":
		errors.append("legacy easy board should migrate to classic_easy")

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

	# Per-mode boards stay separate.
	LeaderboardStore.add_score("SiegeA", 15, WaveScaler.Difficulty.MEDIUM, [], WaveScaler.GameMode.SIEGE)
	var siege_m := LeaderboardStore.load_entries(WaveScaler.Difficulty.MEDIUM, WaveScaler.GameMode.SIEGE)
	var classic_m := LeaderboardStore.load_entries(WaveScaler.Difficulty.MEDIUM, WaveScaler.GameMode.CLASSIC)
	var siege_ok := false
	for e in siege_m:
		if str(e.get("name", "")) == "SiegeA":
			siege_ok = true
			break
	if not siege_ok:
		errors.append("siege score should land on siege_medium")
	for e2 in classic_m:
		if str(e2.get("name", "")) == "SiegeA":
			errors.append("siege score should not appear on classic board")
			break

	# Clash records player count + bot difficulties.
	LeaderboardStore.add_score(
		"Clashy",
		21,
		WaveScaler.Difficulty.MEDIUM,
		[],
		WaveScaler.GameMode.CLASH,
		"",
		4,
		["easy", "hard", "cheater"]
	)
	var clash_entries := LeaderboardStore.load_entries(
		WaveScaler.Difficulty.MEDIUM, WaveScaler.GameMode.CLASH
	)
	var clash_ok := false
	for ce in clash_entries:
		if str(ce.get("name", "")) != "Clashy":
			continue
		if int(ce.get("clash_players", 0)) != 4:
			errors.append("clash entry should store player count")
		var bots: Array = LeaderboardStore.normalize_clash_bots(ce.get("clash_bots", []))
		if bots.size() != 3 or str(bots[2]) != "cheater":
			errors.append("clash entry should store bot difficulties")
		if LeaderboardStore.format_clash_summary(4, bots) != "4p · Easy / Hard / Cheater":
			errors.append("clash summary format wrong: %s" % LeaderboardStore.format_clash_summary(4, bots))
		clash_ok = true
		break
	if not clash_ok:
		errors.append("clash score should appear on clash board")

	# Seeds + board snapshot persist.
	var tiny_png := Marshalls.raw_to_base64(PackedByteArray([137, 80, 78, 71, 13, 10, 26, 10]))
	LeaderboardStore.add_score(
		"Seedy", 33, WaveScaler.Difficulty.MEDIUM, [111, 222, 333], WaveScaler.GameMode.CLASSIC, tiny_png
	)
	var with_seeds := LeaderboardStore.load_entries(WaveScaler.Difficulty.MEDIUM)
	var found_seeds := false
	var found_png := false
	for e in with_seeds:
		if str(e.get("name", "")) == "Seedy":
			var seeds: Array = LeaderboardStore.normalize_seeds(e.get("seeds", []))
			if seeds.size() == 3 and int(seeds[0]) == 111 and int(seeds[2]) == 333:
				found_seeds = true
			if LeaderboardStore.format_seeds_summary(seeds) != "Seeds ×3":
				errors.append("multi-seed summary wrong: %s" % LeaderboardStore.format_seeds_summary(seeds))
			if not str(e.get("board_png", "")).is_empty():
				found_png = true
			break
	if not found_seeds:
		errors.append("leaderboard entry should keep seeds array")
	if not found_png:
		errors.append("leaderboard entry should keep board_png")
	if LeaderboardStore.format_seeds_summary([9]) != "Seed 9":
		errors.append("single seed summary wrong")

	# Merge must keep local scores when remote is empty (upload not configured).
	LeaderboardStore.add_score("KeepMe", 42, WaveScaler.Difficulty.MEDIUM)
	if not LeaderboardStore.merge_boards_from_remote({"easy": [], "medium": [], "hard": []}):
		errors.append("merge empty remote should succeed")
	var after_merge := LeaderboardStore.load_entries(WaveScaler.Difficulty.MEDIUM)
	var kept := false
	for e in after_merge:
		if str(e.get("name", "")) == "KeepMe" and int(e.get("wave", 0)) == 42:
			kept = true
			break
	if not kept:
		errors.append("merge with empty remote must keep local KeepMe score")

	# Cleanup test save only (never the player's real boards).
	if FileAccess.file_exists(test_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(test_path))
	LeaderboardStore.SAVE_PATH = real_path

	if errors.is_empty():
		print("LEADERBOARD_TEST_OK")
		quit(0)
		return
	for e in errors:
		push_error("FAIL: " + e)
	print("LEADERBOARD_TEST_FAIL")
	quit(1)
