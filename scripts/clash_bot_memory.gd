class_name ClashBotMemory
extends RefCounted

## Lightweight "learning": remembers which maze styles make longer lanes.
## Not a neural net — a bandit over named strategies from the maze sheets + greedy/scatter.

const SAVE_PATH := "user://clash_bot_memory.cfg"
const SECTION := "maze"
## Sheet styles teach serpentine shapes; greedy/scatter explore original pathing.
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

static var _loaded: bool = false
## strategy_id → { "n": int, "avg": float }
static var _scores: Dictionary = {}


static func ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	_scores.clear()
	for id in STRATEGIES:
		_scores[id] = {"n": 0, "avg": 36.0}
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	for id in STRATEGIES:
		var n := int(cfg.get_value(SECTION, id + "_n", 0))
		var avg := float(cfg.get_value(SECTION, id + "_avg", 36.0))
		_scores[id] = {"n": n, "avg": avg}


static func _save() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SAVE_PATH)
	for id in STRATEGIES:
		var s: Dictionary = _scores.get(id, {"n": 0, "avg": 36.0})
		cfg.set_value(SECTION, id + "_n", int(s.get("n", 0)))
		cfg.set_value(SECTION, id + "_avg", float(s.get("avg", 36.0)))
	cfg.save(SAVE_PATH)


## Softmax / epsilon mix: usually prefer high avg path length, sometimes explore.
static func pick_strategy(rng: RandomNumberGenerator) -> String:
	ensure_loaded()
	# Explore sheets often; still leave room for greedy "own pathing".
	if rng.randf() < 0.28:
		return STRATEGIES[rng.randi_range(0, STRATEGIES.size() - 1)]
	var best_id := STRATEGIES[0]
	var best_score := -INF
	for id in STRATEGIES:
		var s: Dictionary = _scores[id]
		var avg := float(s.get("avg", 36.0))
		var n := int(s.get("n", 0))
		var score := avg + 8.0 / float(n + 1) + rng.randf() * 2.0
		if score > best_score:
			best_score = score
			best_id = id
	return best_id


static func record_result(strategy_id: String, path_length: int) -> void:
	ensure_loaded()
	var id := strategy_id
	if not _scores.has(id) and ClashMazeTemplates.is_template(id):
		# Old alias IDs still record against their sheet style.
		var aliased: String = ClashMazeTemplates._alias_id(id)
		if aliased != "" and _scores.has(aliased):
			id = aliased
	if not _scores.has(id):
		return
	var s: Dictionary = _scores[id]
	var n := int(s.get("n", 0))
	var avg := float(s.get("avg", 36.0))
	var pl := float(maxi(path_length, 1))
	var new_n := n + 1
	var new_avg := (avg * float(n) + pl) / float(new_n)
	_scores[id] = {"n": new_n, "avg": new_avg}
	_save()
