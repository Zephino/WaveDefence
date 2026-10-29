class_name ClashNetClient
extends Node

const SoundHub := preload("res://scripts/sound_hub.gd")
## Online Clash on a joining player's device. The host's game decides everything;
## this device draws the host's snapshots (gold, lives, timer, enemies, shots,
## towers, traps) and sends this player's actions to the host. The local
## WaveManager is switched off and towers only animate (Tower.net_view).

## The host finished the match (winner_id = -1 when nobody won).
signal match_finished(winner_id: int)

var main: Node
var grid: GameGrid
var clash_match: ClashMatch
var game_state: GameState
var hud: UIHud

## net id -> Enemy
var _enemies: Dictionary = {}
var _last_players_hash: int = 0
var _finished: bool = false


func setup(p_main: Node) -> void:
	main = p_main
	grid = main.grid
	clash_match = main.clash_match
	game_state = main.game_state
	hud = main.hud
	main.build_system.remote_place = func(cell: Vector2i, tower_id: String) -> void:
		send_action(["place", cell, tower_id])
	Net.match_message.connect(_on_message)
	Tower.net_view = true


func _exit_tree() -> void:
	Tower.net_view = false


func send_action(action: Array) -> void:
	Net.send(LobbyService.HOST_ID, [NetMsg.ACTION] + action)


func _on_message(from: int, msg: Array) -> void:
	if from != LobbyService.HOST_ID or msg.size() < 2:
		return
	match int(msg[0]):
		NetMsg.STATE:
			if msg[1] is Dictionary:
				apply(msg[1])
		NetMsg.STATUS:
			hud.set_status(str(msg[1]))


## Shows one snapshot from the host (ClashNetHost.snapshot).
func apply(snap: Dictionary) -> void:
	if _finished:
		return
	_apply_wave(snap)
	_apply_players(snap)
	if snap.has("tw"):
		_apply_towers(snap.get("tw", []), snap.get("po", PackedInt32Array()))
	if snap.has("tr"):
		_apply_traps(snap.get("tr", []))
	_apply_cooldowns(snap.get("cd", []))
	_apply_spawns(snap.get("sp", []))
	_apply_enemies(snap.get("en", PackedFloat32Array()))
	_apply_shots(snap.get("sh", PackedInt32Array()))
	if snap.has("fin"):
		_finished = true
		match_finished.emit(int(snap["fin"]))


func _apply_wave(snap: Dictionary) -> void:
	var wave := int(snap.get("w", 0))
	if wave != game_state.wave:
		game_state.set_wave(wave)
		hud.refresh_run_labels()
		if wave > 0:
			hud.set_status("Wave %d started." % wave)
			SoundHub.play_wave_start(WaveScaler.is_boss_wave(wave))
	var wm: WaveManager = main.wave_manager
	wm.phase = clampi(int(snap.get("ph", 0)), 0, WaveManager.Phase.WAVE) as WaveManager.Phase
	wm.intermission_left = float(snap.get("tl", 0.0))
	var mode := "prep"
	if wm.phase == WaveManager.Phase.INTERMISSION:
		mode = "intermission"
	elif wm.phase == WaveManager.Phase.WAVE:
		mode = "wave"
	hud.update_timer(wm.intermission_left, bool(snap.get("sk", false)), mode)
	Net.ready_ids.clear()
	for id in snap.get("rd", []):
		Net.ready_ids[int(id)] = true
	main.refresh_online_round_button()
	var rm: PackedInt32Array = snap.get("rm", PackedInt32Array([0, 0, 0]))
	if rm.size() >= 3:
		hud.update_enemies_remaining(rm[0], rm[1], rm[2])
	clash_match.send_shop_level = int(snap.get("sl", 1))


func _apply_players(snap: Dictionary) -> void:
	var rows: Array = snap.get("pl", [])
	var h := hash([rows, clash_match.send_shop_level])
	if h == _last_players_hash:
		return
	_last_players_hash = h
	for i in mini(rows.size(), clash_match.players.size()):
		var row: Array = rows[i]
		if row.size() < 7:
			continue
		var cp := clash_match.players[i] as ClashPlayerState
		var was_alive := cp.alive
		cp.gold = int(row[0])
		cp.lives = int(row[1])
		cp.income_per_round = int(row[2])
		cp.alive = bool(row[3])
		cp.cheater_healing = bool(row[4])
		cp.place = int(row[6])
		if not cp.is_human:
			cp.display_name = str(row[5])
		if was_alive and not cp.alive:
			clash_match.player_eliminated.emit(cp.player_id)
	clash_match.sync_human_to_game_state()
	clash_match.players_changed.emit()


## Rebuild only the towers that changed (by anchor cell), then the lane portals.
func _apply_towers(rows: Array, portals: PackedInt32Array) -> void:
	var want: Dictionary = {}
	for row in rows:
		if row is Array and (row as Array).size() >= 7:
			var anchor := Vector2i(int(row[0]), int(row[1]))
			if grid.in_bounds(anchor):
				want[anchor] = row
	var have: Dictionary = {}
	for cell in grid.towers.keys():
		var t := grid.towers[cell] as Tower
		if t != null and is_instance_valid(t):
			have[t.get_meta("anchor_cell", cell)] = t
	for anchor in have.keys():
		var t := have[anchor] as Tower
		var row: Array = want.get(anchor, [])
		if row.is_empty() or str(row[2]) != t.tower_id:
			if t in main.build_system.selected_towers:
				main.build_system.clear_selection()
			grid.remove_tower_at(anchor, false)
			t.queue_free()
			have.erase(anchor)
	for anchor in want.keys():
		var row: Array = want[anchor]
		var t := have.get(anchor, null) as Tower
		if t == null:
			if not TowerData.TYPES.has(str(row[2])):
				continue
			t = Tower.new()
			t.setup(str(row[2]), main.enemies, main.projectiles)
			t.set_meta("clash_owner", int(row[5]))
			grid.place_tower(anchor, t)
		if t.upgrade_level != int(row[3]) or t.final_element != str(row[4]):
			t.upgrade_level = int(row[3])
			t.final_element = str(row[4])
			t._refresh_combat_def()
			t.queue_redraw()
		t.gold_invested = int(row[6])
	for lane in mini(portals.size() / 4, grid.clash_lane_count()):
		var s := Vector2i(portals[lane * 4], portals[lane * 4 + 1])
		var x := Vector2i(portals[lane * 4 + 2], portals[lane * 4 + 3])
		if grid.in_bounds(s) and s != grid.get_lane_spawn(lane):
			grid._apply_portal_cell("spawn", s, lane)
		if grid.in_bounds(x) and x != grid.get_lane_exit(lane):
			grid._apply_portal_cell("exit", x, lane)
	main.pathfinder.sync_region()
	main.build_system.rebuild_paths()
	grid.queue_redraw()


func _apply_traps(rows: Array) -> void:
	for child in main.traps.get_children():
		child.queue_free()
	for row in rows:
		if not (row is Array) or (row as Array).size() < 3:
			continue
		var cell := Vector2i(int(row[0]), int(row[1]))
		var def := CommandAbilities.get_def(str(row[2]))
		if def.is_empty() or not grid.in_bounds(cell):
			continue
		var trap := CommandTrap.new()
		# No enemy container: a shown trap never triggers (the host's does).
		trap.setup(str(row[2]), cell, grid, null, def)
		main.traps.add_child(trap)


func _apply_cooldowns(rows: Array) -> void:
	for row in rows:
		if not (row is Array) or (row as Array).size() < 3 or not (row[2] is Dictionary):
			continue
		var t := grid.get_tower_at(Vector2i(int(row[0]), int(row[1]))) as Tower
		if t != null:
			t.ability_cooldowns = (row[2] as Dictionary).duplicate()


func _apply_spawns(rows: Array) -> void:
	for row in rows:
		if not (row is Array) or (row as Array).size() < 10:
			continue
		var id := int(row[0])
		if _enemies.has(id):
			continue
		var kind := int(row[2])
		var e := Enemy.new()
		e.is_wrecker = kind & 4 != 0
		e.is_snake = kind & 8 != 0
		e.snake_index = int(row[3])
		main.enemies.add_child(e)
		e.setup(
			PackedVector2Array([Vector2(-1000, -1000)]),
			float(row[5]), 0.0, int(row[6]), kind & 1 != 0, kind & 2 != 0,
			int(row[7]), str(row[4])
		)
		if EnemySprites.has_species(str(row[1])):
			e.sprite_species = str(row[1])
		e.lane_id = int(row[8])
		e.defender_id = int(row[9])
		e.net_remote = true
		e.visible = false
		_enemies[id] = e


func _apply_enemies(flat: PackedFloat32Array) -> void:
	var seen: Dictionary = {}
	for i in range(0, flat.size() - 4, 5):
		var id := int(flat[i])
		var found: Variant = _enemies.get(id, null)
		if not is_instance_valid(found):
			continue
		var e := found as Enemy
		seen[id] = true
		var pos := Vector2(flat[i + 1], flat[i + 2])
		if not e.visible:
			e.position = pos
			e.visible = true
		e.net_target = pos
		e.hp = clampf(flat[i + 3], 0.0, 1.0) * e.max_hp
		var flags := int(flat[i + 4])
		e.burn_time = 1.0 if flags & 1 else 0.0
		e.poison_time = 1.0 if flags & 2 else 0.0
		e.slow_time = 1.0 if flags & 4 else 0.0
		e.mark_time = 1.0 if flags & 8 else 0.0
		e.orbit_active = flags & 16 != 0
	for id in _enemies.keys():
		if seen.has(id):
			continue
		var gone: Variant = _enemies[id]
		_enemies.erase(id)
		if is_instance_valid(gone):
			(gone as Enemy).alive = false
			(gone as Enemy).queue_free()


func _apply_shots(flat: PackedInt32Array) -> void:
	for i in range(0, flat.size() - 2, 3):
		var tower := grid.get_tower_at(Vector2i(flat[i], flat[i + 1])) as Tower
		var found: Variant = _enemies.get(flat[i + 2], null)
		if tower != null and is_instance_valid(found) and (found as Enemy).visible:
			tower.fire_cosmetic(found as Enemy)
