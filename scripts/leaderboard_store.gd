class_name LeaderboardStore
extends RefCounted

const SAVE_PATH := "user://leaderboard.json"
const MAX_ENTRIES := 10
const MAX_NAME_LENGTH := 12
const BOARD_KEYS := ["easy", "medium", "hard"]


static func difficulty_key(difficulty: int) -> String:
	match difficulty:
		WaveScaler.Difficulty.EASY:
			return "easy"
		WaveScaler.Difficulty.HARD:
			return "hard"
		_:
			return "medium"


static func difficulty_from_key(key: String) -> int:
	match key:
		"easy":
			return WaveScaler.Difficulty.EASY
		"hard":
			return WaveScaler.Difficulty.HARD
		_:
			return WaveScaler.Difficulty.MEDIUM


static func _empty_boards() -> Dictionary:
	return {"easy": [], "medium": [], "hard": []}


static func _normalize_entry(item) -> Dictionary:
	if typeof(item) != TYPE_DICTIONARY:
		return {}
	var entry: Dictionary = item
	if not entry.has("name") or not entry.has("wave"):
		return {}
	return {
		"name": sanitize_name(str(entry["name"])),
		"wave": maxi(int(entry["wave"]), 0),
	}


static func _sort_and_trim(entries: Array) -> Array:
	var cleaned: Array = []
	for item in entries:
		var entry := _normalize_entry(item)
		if entry.is_empty() or int(entry["wave"]) <= 0 or str(entry["name"]).is_empty():
			continue
		cleaned.append(entry)
	cleaned.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["wave"]) > int(b["wave"])
	)
	if cleaned.size() > MAX_ENTRIES:
		cleaned.resize(MAX_ENTRIES)
	return cleaned


## Loads all difficulty boards. Migrates legacy flat arrays into Medium.
static func load_boards() -> Dictionary:
	var boards := _empty_boards()
	if not FileAccess.file_exists(SAVE_PATH):
		return boards
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		return boards
	var text := file.get_as_text().strip_edges()
	file = null
	if text.is_empty():
		return boards
	var data = JSON.parse_string(text)
	if typeof(data) == TYPE_ARRAY:
		# Legacy single-board save → Medium.
		boards["medium"] = _sort_and_trim(data as Array)
		save_boards(boards)
		return boards
	if typeof(data) != TYPE_DICTIONARY:
		return boards
	var raw: Dictionary = data
	for key in BOARD_KEYS:
		if raw.has(key) and typeof(raw[key]) == TYPE_ARRAY:
			boards[key] = _sort_and_trim(raw[key])
		else:
			boards[key] = []
	return boards


static func save_boards(boards: Dictionary) -> void:
	var payload := _empty_boards()
	for key in BOARD_KEYS:
		payload[key] = _sort_and_trim(boards.get(key, []))
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_error("Could not write leaderboard: %s" % SAVE_PATH)
		return
	file.store_string(JSON.stringify(payload, "\t"))


static func load_entries(difficulty: int = WaveScaler.Difficulty.MEDIUM) -> Array:
	var key := difficulty_key(difficulty)
	return load_boards().get(key, [])


static func save_entries(entries: Array, difficulty: int = WaveScaler.Difficulty.MEDIUM) -> void:
	var boards := load_boards()
	boards[difficulty_key(difficulty)] = _sort_and_trim(entries)
	save_boards(boards)


static func qualifies(wave: int, difficulty: int = WaveScaler.Difficulty.MEDIUM) -> bool:
	if wave <= 0:
		return false
	var entries := load_entries(difficulty)
	if entries.size() < MAX_ENTRIES:
		return true
	return wave >= int(entries[MAX_ENTRIES - 1]["wave"])


static func sanitize_name(raw: String) -> String:
	var cleaned := ""
	for i in raw.length():
		var ch := raw[i]
		var code := ch.unicode_at(0)
		var ok := (
			(code >= 65 and code <= 90) or
			(code >= 97 and code <= 122) or
			(code >= 48 and code <= 57) or
			ch == " " or ch == "_" or ch == "-"
		)
		if ok:
			cleaned += ch
	cleaned = cleaned.strip_edges()
	if cleaned.length() > MAX_NAME_LENGTH:
		cleaned = cleaned.substr(0, MAX_NAME_LENGTH)
	return cleaned


static func add_score(player_name: String, wave: int, difficulty: int = WaveScaler.Difficulty.MEDIUM) -> Array:
	var name := sanitize_name(player_name)
	if name.is_empty() or wave <= 0:
		return load_entries(difficulty)
	if not qualifies(wave, difficulty):
		return load_entries(difficulty)
	var entries := load_entries(difficulty)
	entries.append({"name": name, "wave": wave})
	entries = _sort_and_trim(entries)
	save_entries(entries, difficulty)
	return entries


## Replace local cache with remote worldwide boards payload.
static func replace_boards_from_remote(data: Dictionary) -> bool:
	if typeof(data) != TYPE_DICTIONARY:
		return false
	var boards := _empty_boards()
	for key in BOARD_KEYS:
		if data.has(key) and typeof(data[key]) == TYPE_ARRAY:
			boards[key] = _sort_and_trim(data[key])
		else:
			boards[key] = []
	save_boards(boards)
	return true


## Merge remote boards into local (keeps local scores when upload is unavailable).
static func merge_boards_from_remote(data: Dictionary) -> bool:
	if typeof(data) != TYPE_DICTIONARY:
		return false
	var local := load_boards()
	var boards := _empty_boards()
	for key in BOARD_KEYS:
		var combined: Array = []
		combined.append_array(local.get(key, []))
		if data.has(key) and typeof(data[key]) == TYPE_ARRAY:
			combined.append_array(data[key])
		boards[key] = _dedupe_sort_and_trim(combined)
	save_boards(boards)
	return true


static func _dedupe_sort_and_trim(entries: Array) -> Array:
	var seen := {}
	var unique: Array = []
	for item in entries:
		var entry := _normalize_entry(item)
		if entry.is_empty() or int(entry["wave"]) <= 0 or str(entry["name"]).is_empty():
			continue
		var sig := "%s|%d" % [str(entry["name"]), int(entry["wave"])]
		if seen.has(sig):
			continue
		seen[sig] = true
		unique.append(entry)
	return _sort_and_trim(unique)
