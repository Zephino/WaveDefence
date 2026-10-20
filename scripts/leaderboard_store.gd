class_name LeaderboardStore
extends RefCounted

## Overridable in tests so player boards are never wiped.
static var SAVE_PATH := "user://leaderboard.json"
const MAX_ENTRIES := 10
const MAX_NAME_LENGTH := 12
const MAX_SEEDS := 40
const MODES := ["classic", "random", "siege", "clash"]
const DIFFS := ["easy", "medium", "hard"]
## Flat keys: classic_easy, random_medium, …
const BOARD_KEYS: PackedStringArray = [
	"classic_easy", "classic_medium", "classic_hard",
	"random_easy", "random_medium", "random_hard",
	"siege_easy", "siege_medium", "siege_hard",
	"clash_easy", "clash_medium", "clash_hard",
]


static func mode_key(mode: int) -> String:
	match mode:
		WaveScaler.GameMode.RANDOM:
			return "random"
		WaveScaler.GameMode.SIEGE:
			return "siege"
		WaveScaler.GameMode.CLASH:
			return "clash"
		_:
			return "classic"


static func mode_from_key(key: String) -> int:
	match key:
		"random":
			return WaveScaler.GameMode.RANDOM
		"siege":
			return WaveScaler.GameMode.SIEGE
		"clash":
			return WaveScaler.GameMode.CLASH
		_:
			return WaveScaler.GameMode.CLASSIC


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


static func board_key(mode: int, difficulty: int) -> String:
	return "%s_%s" % [mode_key(mode), difficulty_key(difficulty)]


static func parse_board_key(key: String) -> Dictionary:
	var parts := key.split("_")
	if parts.size() != 2:
		return {"mode": WaveScaler.GameMode.CLASSIC, "difficulty": WaveScaler.Difficulty.MEDIUM}
	return {
		"mode": mode_from_key(parts[0]),
		"difficulty": difficulty_from_key(parts[1]),
	}


static func _empty_boards() -> Dictionary:
	var boards := {}
	for key in BOARD_KEYS:
		boards[key] = []
	return boards


static func normalize_seeds(raw) -> Array:
	var out: Array = []
	if typeof(raw) != TYPE_ARRAY:
		return out
	for item in raw:
		var n := int(item)
		if n < 0:
			continue
		out.append(n)
		if out.size() >= MAX_SEEDS:
			break
	return out


static func normalize_board_png(raw) -> String:
	return BoardScreenshot.sanitize_board_b64(str(raw))


static func _normalize_entry(item) -> Dictionary:
	if typeof(item) != TYPE_DICTIONARY:
		return {}
	var entry: Dictionary = item
	if not entry.has("name") or not entry.has("wave"):
		return {}
	var normalized := {
		"name": sanitize_name(str(entry["name"])),
		"wave": maxi(int(entry["wave"]), 0),
	}
	var seeds := normalize_seeds(entry.get("seeds", []))
	if not seeds.is_empty():
		normalized["seeds"] = seeds
	var png := normalize_board_png(entry.get("board_png", ""))
	if not png.is_empty():
		normalized["board_png"] = png
	return normalized


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


## Loads all mode×difficulty boards. Migrates legacy easy/medium/hard → classic_*.
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
		boards["classic_medium"] = _sort_and_trim(data as Array)
		save_boards(boards)
		return boards
	if typeof(data) != TYPE_DICTIONARY:
		return boards
	var raw: Dictionary = data
	var migrated := false
	# Legacy difficulty-only boards → classic_*.
	for diff in DIFFS:
		if raw.has(diff) and typeof(raw[diff]) == TYPE_ARRAY:
			var dest := "classic_%s" % diff
			if not raw.has(dest) or (raw[dest] as Array).is_empty():
				raw[dest] = raw[diff]
				migrated = true
	for key in BOARD_KEYS:
		if raw.has(key) and typeof(raw[key]) == TYPE_ARRAY:
			boards[key] = _sort_and_trim(raw[key])
		else:
			boards[key] = []
	if migrated:
		save_boards(boards)
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


static func load_entries(
	difficulty: int = WaveScaler.Difficulty.MEDIUM,
	mode: int = WaveScaler.GameMode.CLASSIC
) -> Array:
	var key := board_key(mode, difficulty)
	return load_boards().get(key, [])


static func save_entries(
	entries: Array,
	difficulty: int = WaveScaler.Difficulty.MEDIUM,
	mode: int = WaveScaler.GameMode.CLASSIC
) -> void:
	var boards := load_boards()
	boards[board_key(mode, difficulty)] = _sort_and_trim(entries)
	save_boards(boards)


static func qualifies(
	wave: int,
	difficulty: int = WaveScaler.Difficulty.MEDIUM,
	mode: int = WaveScaler.GameMode.CLASSIC
) -> bool:
	if wave <= 0:
		return false
	var entries := load_entries(difficulty, mode)
	if entries.size() < MAX_ENTRIES:
		return true
	return wave >= int(entries[MAX_ENTRIES - 1]["wave"])


static func sanitize_name(raw: String) -> String:
	return InputSanitize.sanitize_name(raw)


static func add_score(
	player_name: String,
	wave: int,
	difficulty: int = WaveScaler.Difficulty.MEDIUM,
	seeds: Array = [],
	mode: int = WaveScaler.GameMode.CLASSIC,
	board_png: String = ""
) -> Array:
	var name := sanitize_name(player_name)
	if name.is_empty() or wave <= 0:
		return load_entries(difficulty, mode)
	if not qualifies(wave, difficulty, mode):
		return load_entries(difficulty, mode)
	var entries := load_entries(difficulty, mode)
	var row := {"name": name, "wave": wave}
	var cleaned_seeds := normalize_seeds(seeds)
	if not cleaned_seeds.is_empty():
		row["seeds"] = cleaned_seeds
	var png := normalize_board_png(board_png)
	if not png.is_empty():
		row["board_png"] = png
	entries.append(row)
	entries = _sort_and_trim(entries)
	save_entries(entries, difficulty, mode)
	return entries


static func format_seeds_summary(seeds: Array) -> String:
	var cleaned := normalize_seeds(seeds)
	if cleaned.is_empty():
		return ""
	if cleaned.size() == 1:
		return "Seed %d" % int(cleaned[0])
	return "Seeds ×%d" % cleaned.size()


static func format_seeds_detail(seeds: Array) -> String:
	var cleaned := normalize_seeds(seeds)
	if cleaned.is_empty():
		return "No seeds recorded."
	var parts: PackedStringArray = PackedStringArray()
	for i in cleaned.size():
		parts.append("Map %d: %d" % [i + 1, int(cleaned[i])])
	return "\n".join(parts)


## Replace local cache with remote worldwide boards payload.
static func replace_boards_from_remote(data: Dictionary) -> bool:
	if typeof(data) != TYPE_DICTIONARY:
		return false
	var boards := _empty_boards()
	var raw := _migrate_remote_dict(data)
	for key in BOARD_KEYS:
		if raw.has(key) and typeof(raw[key]) == TYPE_ARRAY:
			boards[key] = _sort_and_trim(raw[key])
		else:
			boards[key] = []
	save_boards(boards)
	return true


## Merge remote boards into local (keeps local scores when upload is unavailable).
static func merge_boards_from_remote(data: Dictionary) -> bool:
	if typeof(data) != TYPE_DICTIONARY:
		return false
	var local := load_boards()
	var raw := _migrate_remote_dict(data)
	var boards := _empty_boards()
	for key in BOARD_KEYS:
		var combined: Array = []
		combined.append_array(local.get(key, []))
		if raw.has(key) and typeof(raw[key]) == TYPE_ARRAY:
			combined.append_array(raw[key])
		boards[key] = _dedupe_sort_and_trim(combined)
	save_boards(boards)
	return true


static func _migrate_remote_dict(data: Dictionary) -> Dictionary:
	var raw := data.duplicate(true)
	for diff in DIFFS:
		if raw.has(diff) and typeof(raw[diff]) == TYPE_ARRAY:
			var dest := "classic_%s" % diff
			if not raw.has(dest) or (raw[dest] as Array).is_empty():
				raw[dest] = raw[diff]
	return raw


static func _dedupe_sort_and_trim(entries: Array) -> Array:
	var seen := {}
	var unique: Array = []
	for item in entries:
		var entry := _normalize_entry(item)
		if entry.is_empty() or int(entry["wave"]) <= 0 or str(entry["name"]).is_empty():
			continue
		var sig := "%s|%d" % [str(entry["name"]), int(entry["wave"])]
		if seen.has(sig):
			var idx: int = seen[sig]
			var existing: Dictionary = unique[idx]
			if not existing.has("seeds") and entry.has("seeds"):
				existing["seeds"] = entry["seeds"]
			if not existing.has("board_png") and entry.has("board_png"):
				existing["board_png"] = entry["board_png"]
			unique[idx] = existing
			continue
		seen[sig] = unique.size()
		unique.append(entry)
	return _sort_and_trim(unique)
