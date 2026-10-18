class_name ClashMazeTemplates
extends RefCounted

## 7×15 one-tile maze paths (spawn/exit at center col). From player reference sheets.
## Local coords: lx 0..6, ly 0..14. Towers go on every non-path cell.
## Chord-free walks so the forced route matches the corridor (~40–50 moves).

const WIDTH := 7
const HEIGHT := 15
const MID := 3

## Named styles from the maze sheets (plus older aliases mapped in path_cells).
const TEMPLATE_IDS := [
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
]


static func is_template(id: String) -> bool:
	return TEMPLATE_IDS.has(id) or _alias_id(id) != ""


static func _alias_id(id: String) -> String:
	match id:
		"long_switchback", "mirrored_switchback", "side_to_side":
			return "switchback"
		"tower_alley", "crossfield_route":
			return "winding_path"
		"outer_detour":
			return "deep_detour"
		"double_bend", "hairpin_trail":
			return "hard_turns"
		"winding_gauntlet":
			return "the_serpent"
		"slalom_route":
			return "slalom"
		"deep_zigzag":
			return "long_zigzag"
		"final_s_bends":
			return "sidewinder"
		_:
			return ""


static func path_cells(template_id: String) -> Array[Vector2i]:
	var id := template_id
	var aliased := _alias_id(id)
	if aliased != "":
		id = aliased
	match id:
		"switchback":
			return _switchback(false, 0, WIDTH - 1)
		"long_zigzag":
			return _jagged([6, 0, 6, 0, 6, 0, 6])
		"tower_banks":
			return _tower_banks()
		"slalom":
			return _slalom()
		"deep_detour":
			return _deep_detour()
		"the_serpent":
			return _serpent()
		"sidewinder":
			return _sidewinder()
		"hard_turns":
			return _hard_turns()
		"narrow_pass":
			return _switchback(false, 1, WIDTH - 2)
		"fortress":
			return _fortress()
		"long_walk":
			return _long_walk()
		"winding_path":
			return _jagged([5, 1, 6, 0, 5, 1, 6])
		_:
			return _switchback(false, 0, WIDTH - 1)


static func tower_cells_for_lane(grid: GameGrid, lane: int, template_id: String) -> Array[Vector2i]:
	var r: Vector2i = grid.lane_col_ranges[lane]
	var path := path_cells(template_id)
	var path_set: Dictionary = {}
	for p in path:
		path_set[p] = true
	var out: Array[Vector2i] = []
	var h := mini(HEIGHT, grid.rows)
	var w := mini(WIDTH, r.y - r.x + 1)
	for ly in h:
		for lx in w:
			if path_set.has(Vector2i(lx, ly)):
				continue
			out.append(Vector2i(r.x + lx, ly))
	return out


class _Walker:
	var cells: Array[Vector2i] = []
	var seen: Dictionary = {}

	func start(x: int, y: int) -> void:
		cells.clear()
		seen.clear()
		_put(Vector2i(x, y))

	func at() -> Vector2i:
		return cells[cells.size() - 1]

	func _put(c: Vector2i) -> bool:
		c = Vector2i(clampi(c.x, 0, WIDTH - 1), clampi(c.y, 0, HEIGHT - 1))
		if seen.has(c):
			return false
		if not cells.is_empty():
			var prev: Vector2i = cells[cells.size() - 1]
			if absi(c.x - prev.x) + absi(c.y - prev.y) != 1:
				return false
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var n: Vector2i = c + d
				if seen.has(n) and n != prev:
					return false
		seen[c] = true
		cells.append(c)
		return true

	func step(dx: int, dy: int) -> bool:
		var a := at()
		return _put(Vector2i(a.x + dx, a.y + dy))

	func walk_x(x1: int) -> bool:
		if at().x < x1:
			while at().x < x1:
				if not step(1, 0):
					return false
		else:
			while at().x > x1:
				if not step(-1, 0):
					return false
		return true

	func walk_y(y1: int) -> bool:
		if at().y < y1:
			while at().y < y1:
				if not step(0, 1):
					return false
		else:
			while at().y > y1:
				if not step(0, -1):
					return false
		return true


static func _switchback(mirror: bool, lo: int, hi: int) -> Array[Vector2i]:
	var w := _Walker.new()
	w.start(MID, 0)
	var go_right := not mirror
	w.walk_y(1)
	var y := 1
	while y + 2 <= HEIGHT - 2:
		var target := clampi(hi if go_right else lo, lo, hi)
		w.walk_x(target)
		w.step(0, 1)
		w.step(0, 1)
		y += 2
		go_right = not go_right
	if w.at().y < HEIGHT - 1:
		w.walk_x(MID)
		w.walk_y(HEIGHT - 1)
	return w.cells


static func _jagged(targets: Array) -> Array[Vector2i]:
	var w := _Walker.new()
	w.start(MID, 0)
	w.walk_y(1)
	var y := 1
	for i in targets.size():
		var can_drop := y + 2 <= HEIGHT - 2
		var is_last := (i == targets.size() - 1) or not can_drop
		var target := MID if is_last else clampi(int(targets[i]), 0, WIDTH - 1)
		w.walk_x(target)
		if is_last:
			break
		w.step(0, 1)
		w.step(0, 1)
		y += 2
	w.walk_y(HEIGHT - 1)
	return w.cells


## Longer vertical drops between sweeps leave tall tower banks (sheet "Tower Banks").
static func _tower_banks() -> Array[Vector2i]:
	return _drop_switchback(3, false)


## Tight rhythmic zig with 2-row drops (sheet "Slalom").
static func _slalom() -> Array[Vector2i]:
	return _jagged([6, 0, 5, 1, 6, 0, 5])


## Deep edge pockets (sheet "Deep Detour").
static func _deep_detour() -> Array[Vector2i]:
	return _drop_switchback(2, true)


## Dense full-width folds (sheet "The Serpent").
static func _serpent() -> Array[Vector2i]:
	return _jagged([0, 6, 0, 6, 0, 6, 0])


## Side-biased then cross (sheet "Sidewinder").
static func _sidewinder() -> Array[Vector2i]:
	return _jagged([0, 2, 0, 6, 4, 6, 1])


## Boxy turns via inset then full sweeps (sheet "Hard Turns").
static func _hard_turns() -> Array[Vector2i]:
	return _jagged([0, 6, 1, 5, 0, 6, 2])


## Edge-heavy weave leaving thick mid banks (sheet "Fortress").
static func _fortress() -> Array[Vector2i]:
	return _jagged([0, 6, 0, 5, 1, 6, 0])


## Fewer folds, more tower cells (sheet "Long Walk").
static func _long_walk() -> Array[Vector2i]:
	return _drop_switchback(4, false)


## Switchback with taller tower rows between path corridors.
static func _drop_switchback(drop: int, mirror: bool) -> Array[Vector2i]:
	var w := _Walker.new()
	w.start(MID, 0)
	var go_right := not mirror
	w.walk_y(1)
	var y := 1
	var step_drop := maxi(drop, 2)
	while y + step_drop <= HEIGHT - 2:
		var target := WIDTH - 1 if go_right else 0
		w.walk_x(target)
		for _i in step_drop:
			if not w.step(0, 1):
				break
		y += step_drop
		go_right = not go_right
	w.walk_x(MID)
	w.walk_y(HEIGHT - 1)
	return w.cells
