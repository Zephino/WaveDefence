class_name CommandTraps
extends Node

## Path traps placed by Command tower abilities (Barricade, Air Strike, Recon Flare).

var grid: GameGrid

var _traps: Array[Dictionary] = []


func setup(p_grid: GameGrid) -> void:
	grid = p_grid


func clear_all() -> void:
	_traps.clear()
	if grid:
		grid.queue_redraw()


func trap_cells_for(ability_id: String, center: Vector2i) -> Array[Vector2i]:
	if ability_id == "barricade":
		return [center]
	return CommandAbilities.cross_cells(center)


func overlaps_existing(ability_id: String, center: Vector2i) -> bool:
	var wanted := {}
	for c in trap_cells_for(ability_id, center):
		wanted[c] = true
	for trap in _traps:
		for c in trap.get("cells", []):
			if wanted.has(c):
				return true
	return false


func place(ability_id: String, center: Vector2i) -> void:
	var def := CommandAbilities.get_def(ability_id)
	if def.is_empty() or not CommandAbilities.places_trap(ability_id):
		return
	var cells := trap_cells_for(ability_id, center)
	_traps.append({
		"ability_id": ability_id,
		"center": center,
		"cells": cells,
		"time_left": float(def.get("trap_duration", 14.0)),
		"tick_accum": 0.0,
	})
	if grid:
		grid.queue_redraw()


func get_traps_for_draw() -> Array:
	return _traps


func tick(delta: float, enemy_container: Node) -> void:
	if _traps.is_empty() or enemy_container == null or grid == null:
		return
	var i := _traps.size() - 1
	while i >= 0:
		var trap: Dictionary = _traps[i]
		trap["time_left"] = float(trap.get("time_left", 0.0)) - delta
		if float(trap["time_left"]) <= 0.0:
			_traps.remove_at(i)
			i -= 1
			continue
		var ability_id := str(trap.get("ability_id", ""))
		match ability_id:
			"barricade":
				_tick_barricade(trap, delta, enemy_container)
			"airstrike":
				_try_airstrike_trap(trap, enemy_container)
			"flare":
				_try_flare_trap(trap, enemy_container)
		i -= 1
	if grid:
		grid.queue_redraw()


func _enemies_on_cells(enemy_container: Node, cells: Array[Vector2i]) -> Array[Enemy]:
	return CommandCaster.enemies_on_cells(enemy_container, grid, cells)


func _tick_barricade(trap: Dictionary, delta: float, enemy_container: Node) -> void:
	var def := CommandAbilities.get_def("barricade")
	var cells: Array[Vector2i] = trap.get("cells", [])
	var targets := _enemies_on_cells(enemy_container, cells)
	if targets.is_empty():
		return
	var slow_f := float(def.get("slow_factor", 0.4))
	var slow_d := float(def.get("slow_duration", 3.0))
	var dps := float(def.get("dot_dps", 18.0))
	var dot_d := float(def.get("dot_duration", 3.0))
	for e in targets:
		if e.is_flying:
			continue
		e.apply_slow(slow_f, slow_d)
		e.apply_poison(dps, dot_d)


func _try_airstrike_trap(trap: Dictionary, enemy_container: Node) -> void:
	var cells: Array[Vector2i] = trap.get("cells", [])
	var present := _enemies_on_cells(enemy_container, cells)
	if present.is_empty():
		return
	var def := CommandAbilities.get_def("airstrike")
	var targets := present
	var dmg := float(def.get("damage", 140.0))
	var hit := 0
	for e in targets:
		var amount := dmg * (1.15 if e.is_boss else 1.0)
		e.take_damage(amount)
		hit += 1
	trap["time_left"] = 0.0
	trap["last_message"] = "Air Strike hit %d enem%s!" % [hit, "y" if hit == 1 else "ies"] if hit > 0 else "Air Strike triggered."


func _try_flare_trap(trap: Dictionary, enemy_container: Node) -> void:
	var cells: Array[Vector2i] = trap.get("cells", [])
	var present := _enemies_on_cells(enemy_container, cells)
	if present.is_empty():
		return
	var def := CommandAbilities.get_def("flare")
	var mult := float(def.get("mark_mult", 1.4))
	var duration := float(def.get("mark_duration", 4.0))
	for e in present:
		e.apply_mark(mult, duration)
	trap["time_left"] = 0.0
	trap["last_message"] = "Recon Flare marked %d enem%s." % [
		present.size(),
		"y" if present.size() == 1 else "ies",
	]
