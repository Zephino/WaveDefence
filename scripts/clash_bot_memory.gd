class_name ClashBotMemory
extends RefCounted

## Persistent learning for Clash bots (saved per device in user://clash_bot_memory.cfg).
##
## Maze styles are a multi-armed bandit: after every wave the bot scores the style it used
## (longer path + fewer leaks = higher reward, 0..1). Easy ignores memory, Medium usually
## picks the best-scoring style but still explores, Hard/Cheater pick with UCB1 (try each
## style, then lean hard on what works while occasionally re-testing).
##
## Tower types keep a running reward the same way, so Medium+ bots learn which towers
## actually stop leaks and buy them more often.

const SAVE_PATH := "user://clash_bot_memory.cfg"
const SECTION := "maze"
const TOWER_SECTION := "towers"
const STRATEGIES := [
	"switchback",
	"long_zigzag",
	"tower_banks",
	"slalom",
	"deep_detour",
	"the_serpent",
	"sidewinder",
	"hard_turns",
	"narrow_pass",
	"fortress",
	"long_walk",
	"winding_path",
	"greedy",
	"scatter",
]
## UCB exploration strength for Hard/Cheater, and Medium's chance to explore randomly.
const UCB_C := 0.35
const MEDIUM_EXPLORE := 0.3
## Untried arms start at this optimistic value (plus the UCB bonus for Hard).
const UNTRIED_REWARD := 0.62
## Rewards are blended toward neutral until an arm has this many samples.
const PRIOR_WEIGHT := 3.0

static var _loaded: bool = false
## strategy_id → { "n", "avg" (path length), "rn" (reward samples), "reward" (0..1) }
static var _scores: Dictionary = {}
## tower_id → { "n", "reward" }
static var _towers: Dictionary = {}


static func ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	_scores.clear()
	_towers.clear()
	for id in STRATEGIES:
		_scores[id] = {"n": 0, "avg": 36.0, "rn": 0, "reward": 0.5}
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	for id in STRATEGIES:
		_scores[id] = {
			"n": int(cfg.get_value(SECTION, id + "_n", 0)),
			"avg": float(cfg.get_value(SECTION, id + "_avg", 36.0)),
			"rn": int(cfg.get_value(SECTION, id + "_rn", 0)),
			"reward": float(cfg.get_value(SECTION, id + "_reward", 0.5)),
		}
	if cfg.has_section(TOWER_SECTION):
		for key in cfg.get_section_keys(TOWER_SECTION):
			if not key.ends_with("_n"):
				continue
			var tid: String = key.substr(0, key.length() - 2)
			_towers[tid] = {
				"n": int(cfg.get_value(TOWER_SECTION, tid + "_n", 0)),
				"reward": float(cfg.get_value(TOWER_SECTION, tid + "_reward", 0.5)),
			}


static func _save() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SAVE_PATH)
	for id in STRATEGIES:
		var s: Dictionary = _scores.get(id, {})
		cfg.set_value(SECTION, id + "_n", int(s.get("n", 0)))
		cfg.set_value(SECTION, id + "_avg", float(s.get("avg", 36.0)))
		cfg.set_value(SECTION, id + "_rn", int(s.get("rn", 0)))
		cfg.set_value(SECTION, id + "_reward", float(s.get("reward", 0.5)))
	for tid in _towers.keys():
		var t: Dictionary = _towers[tid]
		cfg.set_value(TOWER_SECTION, str(tid) + "_n", int(t.get("n", 0)))
		cfg.set_value(TOWER_SECTION, str(tid) + "_reward", float(t.get("reward", 0.5)))
	cfg.save(SAVE_PATH)


## Uniform random maze style (Easy bots, and Medium's exploration rolls).
static func pick_strategy(rng: RandomNumberGenerator) -> String:
	ensure_loaded()
	return STRATEGIES[rng.randi_range(0, STRATEGIES.size() - 1)]


## Difficulty-aware choice that actually uses what previous matches learned.
static func choose_strategy(rng: RandomNumberGenerator, difficulty: int) -> String:
	ensure_loaded()
	match difficulty:
		WaveScaler.Difficulty.EASY:
			return pick_strategy(rng)
		WaveScaler.Difficulty.MEDIUM:
			if rng.randf() < MEDIUM_EXPLORE:
				return pick_strategy(rng)
			return _best_strategy(rng, 0.0)
		_:
			return _best_strategy(rng, UCB_C)


static func _best_strategy(rng: RandomNumberGenerator, c: float) -> String:
	var total := 0
	for id in STRATEGIES:
		total += int(_scores[id].get("rn", 0))
	var best: String = STRATEGIES[0]
	var best_v := -INF
	for id in STRATEGIES:
		var s: Dictionary = _scores[id]
		var n := int(s.get("rn", 0))
		var v: float
		if n == 0:
			v = UNTRIED_REWARD + c
		else:
			v = strategy_reward(id) + c * sqrt(log(float(total) + 1.0) / float(n))
		v += rng.randf() * 0.001  # tie-break
		if v > best_v:
			best_v = v
			best = id
	return best


## Reward for one wave: half for path length (60+ cells = full), half for zero leaks (8+ = none).
static func wave_reward(path_length: int, leaks: int) -> float:
	var len_part := clampf(float(path_length) / 60.0, 0.0, 1.0)
	var leak_part := 1.0 - clampf(float(leaks) / 8.0, 0.0, 1.0)
	return clampf(0.5 * len_part + 0.5 * leak_part, 0.0, 1.0)


static func strategy_reward(strategy_id: String) -> float:
	ensure_loaded()
	if not _scores.has(strategy_id):
		return 0.5
	var s: Dictionary = _scores[strategy_id]
	var n := float(int(s.get("rn", 0)))
	return (float(s.get("reward", 0.5)) * n + 0.5 * PRIOR_WEIGHT) / (n + PRIOR_WEIGHT)


static func tower_reward(tower_id: String) -> float:
	ensure_loaded()
	if not _towers.has(tower_id):
		return 0.5
	var t: Dictionary = _towers[tower_id]
	var n := float(int(t.get("n", 0)))
	return (float(t.get("reward", 0.5)) * n + 0.5 * PRIOR_WEIGHT) / (n + PRIOR_WEIGHT)


## Called once per finished wave by each bot. strategy_id may be "" (DPS plan: towers only).
static func record_wave(strategy_id: String, path_length: int, leaks: int, tower_ids: Array) -> void:
	ensure_loaded()
	var r := wave_reward(path_length, leaks)
	var id := _resolve(strategy_id)
	if id != "":
		var s: Dictionary = _scores[id]
		var rn := int(s.get("rn", 0)) + 1
		s["reward"] = (float(s.get("reward", 0.5)) * float(rn - 1) + r) / float(rn)
		s["rn"] = rn
		_scores[id] = s
	var seen: Dictionary = {}
	for tid in tower_ids:
		var key := str(tid)
		if seen.has(key):
			continue
		seen[key] = true
		var t: Dictionary = _towers.get(key, {"n": 0, "reward": 0.5})
		var n := int(t.get("n", 0)) + 1
		t["reward"] = (float(t.get("reward", 0.5)) * float(n - 1) + r) / float(n)
		t["n"] = n
		_towers[key] = t
	_save()


## Legacy: path-length average per style (still recorded; shown for debugging).
static func record_result(strategy_id: String, path_length: int) -> void:
	ensure_loaded()
	var id := _resolve(strategy_id)
	if id == "":
		return
	var s: Dictionary = _scores[id]
	var n := int(s.get("n", 0))
	var avg := float(s.get("avg", 36.0))
	var pl := float(maxi(path_length, 1))
	var new_n := n + 1
	s["n"] = new_n
	s["avg"] = (avg * float(n) + pl) / float(new_n)
	_scores[id] = s
	_save()


static func _resolve(strategy_id: String) -> String:
	if _scores.has(strategy_id):
		return strategy_id
	if ClashMazeTemplates.is_template(strategy_id):
		var aliased: String = ClashMazeTemplates._alias_id(strategy_id)
		if aliased != "" and _scores.has(aliased):
			return aliased
	return ""


## Test/debug helper: forget everything (does not delete the file until the next save).
static func reset_for_tests() -> void:
	_loaded = true
	_scores.clear()
	_towers.clear()
	for id in STRATEGIES:
		_scores[id] = {"n": 0, "avg": 36.0, "rn": 0, "reward": 0.5}
