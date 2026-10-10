class_name Achievements
extends RefCounted

## Curated hard achievements — thresholds in data only.

static func definitions() -> Array:
	return [
		{"id": "deep_run", "title": "Deep Run", "hint": "Reach wave 50", "hidden": false},
		{"id": "iron_wall", "title": "Iron Wall", "hint": "Hard mode milestone", "hidden": false},
		{"id": "siege_master", "title": "Siege Master", "hint": "Siege endurance", "hidden": false},
		{"id": "random_endurance", "title": "Sector Hopper", "hint": "Random map mode", "hidden": false},
		{"id": "flawless_ten", "title": "Flawless Ten", "hint": "No leaks early", "hidden": false},
		{"id": "flawless_twenty", "title": "Flawless Twenty", "hint": "No leaks mid", "hidden": false},
		{"id": "snake_slayer", "title": "Snake Slayer", "hint": "Boss variant", "hidden": true},
		{"id": "sky_denied", "title": "Sky Denied", "hint": "Flying boss", "hidden": true},
		{"id": "economy_king", "title": "Economy King", "hint": "Gold hoard", "hidden": false},
		{"id": "gatling_unlock", "title": "Gatling Online", "hint": "Late tower", "hidden": false},
		{"id": "elemental_menu", "title": "Full Elemental", "hint": "Four finals", "hidden": false},
		{"id": "commando", "title": "Commando", "hint": "Command abilities", "hidden": true},
	]


static func description_for(id: String) -> String:
	match id:
		"deep_run":
			return "Reach wave 50 in any difficulty."
		"iron_wall":
			return "Reach wave 30 on Hard."
		"siege_master":
			return "Reach wave 100 in Siege."
		"random_endurance":
			return "Reach wave 50 in Random map mode."
		"flawless_ten":
			return "Zero leaks through wave 10."
		"flawless_twenty":
			return "Zero leaks through wave 20."
		"snake_slayer":
			return "Clear a SNAKE boss wave on Medium or Hard."
		"sky_denied":
			return "Clear a flying boss wave with at most one leak."
		"economy_king":
			return "Finish wave 15 with at least 500 gold."
		"gatling_unlock":
			return "Unlock and place a Gatling in one run."
		"elemental_menu":
			return "Have four different final elements on towers in one run."
		"commando":
			return "Land Supply Drop and Air Strike traps successfully in one run."
		_:
			return ""


static func check_run_end(state: GameState, run_stats: Dictionary) -> Array:
	var newly: Array = []
	if state == null:
		return newly
	if bool(run_stats.get("tutorial", false)) or state.debug_used:
		return newly
	var wave := int(run_stats.get("highest_wave", state.highest_wave))
	var diff := state.difficulty
	var mode := state.game_mode
	if wave >= 50:
		newly.append("deep_run")
	if diff == WaveScaler.Difficulty.HARD and wave >= 30:
		newly.append("iron_wall")
	if WaveScaler.is_siege_mode(mode) and wave >= 100:
		newly.append("siege_master")
	if WaveScaler.is_random_mode(mode) and wave >= 50:
		newly.append("random_endurance")
	var leaks_dict: Dictionary = run_stats.get("leaks_at_or_before_wave", {})
	if wave >= 10 and int(leaks_dict.get("10", leaks_dict.get(10, 0))) == 0:
		newly.append("flawless_ten")
	if wave >= 20 and int(leaks_dict.get("20", leaks_dict.get(20, 0))) == 0:
		newly.append("flawless_twenty")
	if bool(run_stats.get("snake_cleared_medium_plus", false)):
		newly.append("snake_slayer")
	if bool(run_stats.get("flying_boss_max_leaks_ok", false)):
		newly.append("sky_denied")
	if bool(run_stats.get("economy_king", false)):
		newly.append("economy_king")
	if bool(run_stats.get("gatling_placed", false)):
		newly.append("gatling_unlock")
	if int(run_stats.get("distinct_final_elements", 0)) >= 4:
		newly.append("elemental_menu")
	if bool(run_stats.get("commando_done", false)):
		newly.append("commando")
	return newly


static func _leaks_through_wave(run_stats: Dictionary, max_wave: int) -> int:
	var d: Dictionary = run_stats.get("leaks_per_wave", {})
	var total := 0
	for w in d.keys():
		if int(w) <= max_wave:
			total += int(d[w])
	return total
