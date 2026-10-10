class_name CommandTrap
extends Node2D

## Armed Command ability on the board. Gold was paid on place; effect waits for enemies.

signal consumed(trap: CommandTrap)

var ability_id: String = ""
var cell: Vector2i = Vector2i.ZERO
var grid: GameGrid
var enemy_container: Node
var def: Dictionary = {}
## Barricade stays active for this many seconds after placement.
var _duration_left: float = 0.0
var _one_shot: bool = true
var _spent: bool = false


func is_active() -> bool:
	return not _spent


func setup(
	p_ability_id: String,
	p_cell: Vector2i,
	p_grid: GameGrid,
	p_enemies: Node,
	p_def: Dictionary
) -> void:
	ability_id = p_ability_id
	cell = p_cell
	grid = p_grid
	enemy_container = p_enemies
	def = p_def
	_one_shot = ability_id != "barricade"
	if ability_id == "barricade":
		_duration_left = float(def.get("trap_duration", 8.0))
	position = grid.cell_to_world_center(cell)
	z_index = 2
	queue_redraw()


func _process(delta: float) -> void:
	if _spent or grid == null or enemy_container == null:
		return
	if ability_id == "barricade":
		_tick_barricade(delta)
		return
	var cells := _watch_cells()
	var targets := CommandAbilities.enemies_on_cells(enemy_container, grid, cells)
	if targets.is_empty():
		return
	_trigger(targets)


func _watch_cells() -> Array[Vector2i]:
	if ability_id == "airstrike" or ability_id == "flare":
		return CommandAbilities.cross_cells(cell)
	var single: Array[Vector2i] = [cell]
	return single


func _tick_barricade(delta: float) -> void:
	_duration_left -= delta
	var cells: Array[Vector2i] = [cell]
	var targets := CommandAbilities.enemies_on_cells(enemy_container, grid, cells)
	var slow_f := float(def.get("slow_factor", 0.4))
	var slow_d := float(def.get("slow_duration", 3.0))
	var dps := float(def.get("dot_dps", 18.0))
	var dot_d := float(def.get("dot_duration", 3.0))
	for e in targets:
		if e.is_flying:
			continue
		e.apply_slow(slow_f, slow_d)
		e.apply_poison(dps, dot_d)
	queue_redraw()
	if _duration_left <= 0.0:
		_finish()


func _trigger(targets: Array[Enemy]) -> void:
	match ability_id:
		"airstrike":
			var dmg := float(def.get("damage", 140.0))
			for e in targets:
				var amount := dmg * (1.15 if e.is_boss else 1.0)
				e.take_damage(amount)
		"flare":
			var mult := float(def.get("mark_mult", 1.4))
			var duration := float(def.get("mark_duration", 4.0))
			for e in targets:
				e.apply_mark(mult, duration)
		_:
			pass
	_finish()


func _finish() -> void:
	if _spent:
		return
	_spent = true
	consumed.emit(self)
	queue_free()


func _draw() -> void:
	if grid == null:
		return
	var ts := float(grid.tile_px())
	var half := ts * 0.42
	var color := Color(0.9, 0.35, 0.25, 0.55)
	match ability_id:
		"airstrike":
			color = Color(0.95, 0.35, 0.2, 0.5)
		"barricade":
			color = Color(0.75, 0.55, 0.2, 0.55)
		"flare":
			color = Color(0.95, 0.85, 0.25, 0.5)
		"supply":
			color = Color(0.3, 0.75, 0.45, 0.5)
	draw_rect(Rect2(Vector2(-half, -half), Vector2(half * 2.0, half * 2.0)), color)
	draw_rect(Rect2(Vector2(-half, -half), Vector2(half * 2.0, half * 2.0)), color.lightened(0.35), false, 2.0)
	if ability_id == "airstrike" or ability_id == "flare":
		for c in CommandAbilities.cross_cells(cell):
			if c == cell:
				continue
			var offset := grid.cell_to_world_center(c) - position
			var h2 := ts * 0.28
			draw_rect(Rect2(offset - Vector2(h2, h2), Vector2(h2 * 2.0, h2 * 2.0)), Color(color, 0.28))
