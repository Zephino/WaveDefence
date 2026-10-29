class_name ClashNetHost
extends Node
## Online Clash on the host's device. The host's game simulates every lane.
## Joined players send actions (place, sell, upgrade, sends…); this node checks
## each one against that player's own lane and wallet, using the same
## BuildSystem rules as the host's lane, and replies with a status line.
## About 10 times a second it sends everyone a snapshot of the match: each
## lane's gold and lives, the timer, enemy positions (new enemies come with
## what they look like), shots fired, and the towers when they change.

## Main asks for a bot to take over this lane (a player left).
signal bot_needed(player_id: int)

const SEND_INTERVAL := 0.1
## Towers are resent this often even when nothing changed (cheap safety net).
const TOWER_RESEND_SEC := 3.0
const MAX_CELLS_PER_ACTION := 64

var main: Node
var grid: GameGrid
var clash_match: ClashMatch
var wave_manager: WaveManager

var _send_in: float = 0.0
var _next_enemy_id: int = 1
var _new_enemies: Array = []
var _last_towers_hash: int = 0
var _last_traps_hash: int = 0
var _tower_resend_in: float = 0.0
## player_id -> {"wallet": GameState, "builder": BuildSystem}
var _remote: Dictionary = {}


func setup(p_main: Node) -> void:
	main = p_main
	grid = main.grid
	clash_match = main.clash_match
	wave_manager = main.wave_manager
	for p in clash_match.players:
		var cp := p as ClashPlayerState
		if cp.is_remote:
			_add_remote_builder(cp)
	wave_manager.enemy_spawned.connect(_on_enemy_spawned)
	wave_manager.wave_started.connect(func(_w: int, _b: String) -> void: Net.clear_round_ready())
	Net.match_message.connect(_on_message)
	Net.player_left_match.connect(_on_player_left)
	Tower.net_shot_log_on = true
	Tower.net_shot_log.clear()


func _exit_tree() -> void:
	Tower.net_shot_log_on = false
	Tower.net_shot_log.clear()


func _add_remote_builder(cp: ClashPlayerState) -> void:
	var wallet := GameState.new()
	wallet.name = "RemoteWallet%d" % cp.player_id
	add_child(wallet)
	wallet.game_mode = WaveScaler.GameMode.CLASH
	var builder := BuildSystem.new()
	builder.name = "RemoteBuilder%d" % cp.player_id
	add_child(builder)
	builder.setup(grid, main.pathfinder, wallet, main.enemies, main.projectiles)
	builder.set_clash_match(clash_match, cp.lane_index)
	builder.owner_id = cp.player_id
	_remote[cp.player_id] = {"wallet": wallet, "builder": builder}


func _process(delta: float) -> void:
	_send_in -= delta
	_tower_resend_in -= delta
	if _send_in > 0.0:
		return
	_send_in = SEND_INTERVAL
	Net.send(LobbyService.EVERYONE, [NetMsg.STATE, snapshot()])


# --- Snapshot ---------------------------------------------------------------------------

func snapshot() -> Dictionary:
	var gs: GameState = main.game_state
	var snap := {
		"w": gs.wave,
		"ph": int(wave_manager.phase),
		"tl": wave_manager.intermission_left,
		"sk": wave_manager.can_skip_timer(),
		"rm": PackedInt32Array([
			wave_manager.enemies_remaining(), wave_manager.enemies_alive, wave_manager.spawn_queue.size()
		]),
		"sl": clash_match.send_shop_level,
		"pl": _players_state(),
		"rd": Net.ready_ids.keys(),
	}
	_add_enemies(snap)
	if not Tower.net_shot_log.is_empty():
		snap["sh"] = Tower.net_shot_log
		Tower.net_shot_log = PackedInt32Array()
	_add_towers(snap)
	var traps := _traps_state()
	var traps_hash := hash(traps)
	if traps_hash != _last_traps_hash or snap.has("tw"):
		_last_traps_hash = traps_hash
		snap["tr"] = traps
	if clash_match.finished:
		snap["fin"] = _winner_id()
	return snap


func _players_state() -> Array:
	var out: Array = []
	for p in clash_match.players:
		var cp := p as ClashPlayerState
		var gold := cp.gold
		if cp.is_human:
			gold = main.game_state.gold
		out.append([gold, cp.lives, cp.income_per_round, cp.alive, cp.cheater_healing, cp.display_name, cp.place])
	return out


func _winner_id() -> int:
	for p in clash_match.living_players():
		return (p as ClashPlayerState).player_id
	return -1


func _on_enemy_spawned(enemy: Enemy) -> void:
	enemy.set_meta("net_id", _next_enemy_id)
	_next_enemy_id += 1
	_new_enemies.append(enemy)


## Positions as [id, x, y, hp 0..1, status flags] for every living enemy, plus
## what each new enemy looks like ("sp"), sent once.
func _add_enemies(snap: Dictionary) -> void:
	var spawns: Array = []
	for e in _new_enemies:
		if not is_instance_valid(e) or not (e as Enemy).alive:
			continue
		var en := e as Enemy
		var kind := (1 if en.is_boss else 0) | (2 if en.is_flying else 0) | (4 if en.is_wrecker else 0) | (8 if en.is_snake else 0)
		spawns.append([
			int(en.get_meta("net_id")), en.sprite_species, kind, en.snake_index, en.monster_type,
			en.max_hp, en.bounty, en.wave_index, en.lane_id, en.defender_id,
		])
	_new_enemies.clear()
	if not spawns.is_empty():
		snap["sp"] = spawns
	var flat := PackedFloat32Array()
	for child in main.enemies.get_children():
		var e := child as Enemy
		if e == null or not e.alive or not e.has_meta("net_id"):
			continue
		var flags := (1 if e.burn_time > 0.0 else 0) | (2 if e.poison_time > 0.0 else 0) \
			| (4 if e.slow_time > 0.0 else 0) | (8 if e.mark_time > 0.0 else 0) | (16 if e.orbit_active else 0)
		flat.append_array([
			float(e.get_meta("net_id")), e.position.x, e.position.y, e.hp / maxf(e.max_hp, 1.0), float(flags)
		])
	snap["en"] = flat


## Towers [x, y, id, level, final element, owner, gold invested] and lane portals,
## only when they changed. Command tower cooldowns go every time.
func _add_towers(snap: Dictionary) -> void:
	var towers: Array = []
	var cooldowns: Array = []
	var seen: Dictionary = {}
	for cell in grid.towers.keys():
		var t := grid.towers[cell] as Tower
		if t == null or not is_instance_valid(t) or seen.has(t):
			continue
		seen[t] = true
		var anchor: Vector2i = t.get_meta("anchor_cell", cell)
		var owner := int(t.get_meta("clash_owner", grid.lane_index_for_cell(anchor)))
		towers.append([anchor.x, anchor.y, t.tower_id, t.upgrade_level, t.final_element, owner, t.gold_invested])
		if not t.ability_cooldowns.is_empty():
			cooldowns.append([anchor.x, anchor.y, t.ability_cooldowns.duplicate()])
	if not cooldowns.is_empty():
		snap["cd"] = cooldowns
	var portals := PackedInt32Array()
	for lane in grid.clash_lane_count():
		var s := grid.get_lane_spawn(lane)
		var x := grid.get_lane_exit(lane)
		portals.append_array([s.x, s.y, x.x, x.y])
	var h := hash([towers, portals])
	if h == _last_towers_hash and _tower_resend_in > 0.0:
		return
	_last_towers_hash = h
	_tower_resend_in = TOWER_RESEND_SEC
	snap["tw"] = towers
	snap["po"] = portals


func _traps_state() -> Array:
	var out: Array = []
	for child in main.traps.get_children():
		var trap := child as CommandTrap
		if trap != null and trap.is_active():
			out.append([trap.cell.x, trap.cell.y, trap.ability_id])
	return out


# --- Players' actions -------------------------------------------------------------------

func _on_message(from: int, msg: Array) -> void:
	if int(msg[0]) != NetMsg.ACTION or msg.size() < 2 or not (msg[1] is String):
		return
	var seat := Net.seat_of(from)
	var cp := clash_match.get_player(seat)
	if cp == null or not cp.is_remote or not _remote.has(seat):
		return
	if clash_match.finished or main.game_state.is_game_over:
		return
	if not cp.alive:
		_reply(from, "You're out of the match.")
		return
	var text := _apply_action(cp, str(msg[1]), msg.slice(2))
	if text != "":
		_reply(from, text)


func _reply(to: int, text: String) -> void:
	Net.send(to, [NetMsg.STATUS, text])


## Runs one action for a joined player. Every value came from another device, so
## each one is checked before use. Returns a status line for that player.
func _apply_action(cp: ClashPlayerState, kind: String, args: Array) -> String:
	match kind:
		"place":
			if args.size() < 2 or not (args[0] is Vector2i) or not (args[1] is String):
				return ""
			return _place(cp, args[0], args[1])
		"sell", "upgrade":
			if args.is_empty():
				return ""
			return _with_builder(cp, kind, _cells(args[0]), "")
		"final":
			if args.size() < 2 or not (args[1] is String):
				return ""
			return _with_builder(cp, kind, _cells(args[0]), args[1])
		"cmd":
			if args.size() < 3 or not (args[0] is Vector2i) or not (args[1] is String) or not (args[2] is Vector2i):
				return ""
			return _command(cp, args[0], args[1], args[2])
		"portal":
			if args.size() < 2 or not (args[0] is String) or not (args[1] is int):
				return ""
			return _portal(cp, args[0], args[1])
		"send":
			if args.size() < 2 or not (args[0] is int) or not (args[1] is String):
				return ""
			return _send_pack(cp, args[0], args[1])
		"shop":
			return _upgrade_shop(cp)
	return ""


func _cells(value: Variant) -> Array:
	var out: Array = []
	if not (value is Array):
		return out
	for c in value:
		if c is Vector2i and grid.in_bounds(c) and out.size() < MAX_CELLS_PER_ACTION:
			out.append(c)
	return out


## Load the player's gold into their builder's wallet, run, then store it back.
func _begin_wallet(cp: ClashPlayerState) -> BuildSystem:
	var entry: Dictionary = _remote[cp.player_id]
	var wallet: GameState = entry["wallet"]
	wallet.gold = cp.gold
	wallet.wave = main.game_state.wave
	wallet.is_game_over = main.game_state.is_game_over
	return entry["builder"]


func _end_wallet(cp: ClashPlayerState) -> void:
	var wallet: GameState = (_remote[cp.player_id] as Dictionary)["wallet"]
	cp.gold = wallet.gold
	clash_match.players_changed.emit()


func _place(cp: ClashPlayerState, cell: Vector2i, tower_id: String) -> String:
	if not TowerData.TYPES.has(tower_id) or not grid.in_bounds(cell):
		return ""
	var builder := _begin_wallet(cp)
	var placed := false
	if TowerData.is_unlocked(tower_id, main.game_state.wave):
		builder.select_tower_type(tower_id)
		builder.set_placing_enabled(true)
		placed = builder.try_place_at(grid.cell_to_world_center(cell), false, true)
	var cost := int(TowerData.get_def(tower_id)["cost"])
	var afford := cp.gold >= cost
	_end_wallet(cp)
	if placed:
		_paths_changed()
		return ""
	if not afford:
		return "Not enough gold."
	return "Can't place there."


func _with_builder(cp: ClashPlayerState, kind: String, cells: Array, element_id: String) -> String:
	if cells.is_empty():
		return "Nothing selected."
	var builder := _begin_wallet(cp)
	builder.select_cells(cells)
	var count := builder.selection_count()
	var text := ""
	if count == 0:
		text = "Nothing selected."
	elif kind == "sell":
		var refund := builder.selection_sell_total()
		builder.sell_selected()
		text = "Sold %d tower(s) for %d gold." % [count, refund]
	elif kind == "upgrade":
		var r := builder.upgrade_selected()
		if int(r["upgraded"]) > 0:
			text = "Upgraded %d tower(s) (-%d gold)." % [int(r["upgraded"]), int(r["spent"])]
		elif int(r["failed_afford"]) > 0:
			text = "Not enough gold to upgrade."
		else:
			text = "Select towers under +3 to upgrade (walls can't upgrade)."
	else:
		var r := builder.apply_final_selected(element_id)
		if int(r["applied"]) > 0:
			text = "Final %s on %d tower(s) (-%d gold)." % [TowerData.final_element_label(element_id), int(r["applied"]), int(r["spent"])]
		elif int(r["failed_afford"]) > 0:
			text = "Not enough gold for that final upgrade."
		else:
			text = "Need +3 upgrades before choosing a final elemental buff."
	builder.clear_selection()
	_end_wallet(cp)
	if kind == "sell":
		_paths_changed()
	return text


## Same rules as the host's own Command abilities (main.gd _resolve_command_aim).
func _command(cp: ClashPlayerState, tower_cell: Vector2i, ability_id: String, cell: Vector2i) -> String:
	if CommandAbilities.get_def(ability_id).is_empty() or not grid.in_bounds(cell):
		return ""
	var tower := grid.get_tower_at(tower_cell) as Tower
	if tower == null or not TowerData.is_command(tower.tower_id):
		return "Select a Command tower to use abilities."
	if int(tower.get_meta("clash_owner", -1)) != cp.player_id:
		return "That isn't your Command tower."
	var cost := CommandAbilities.cost(ability_id)
	if tower.ability_cooldown_left(ability_id) > 0.05:
		return "%s is cooling down." % CommandAbilities.display_name(ability_id)
	if cp.gold < cost:
		return "Need %d gold for %s." % [cost, CommandAbilities.display_name(ability_id)]
	var result := CommandCaster.place(ability_id, cell, grid, main.pathfinder, main.enemies, main.traps)
	if not bool(result.get("ok", false)):
		return str(result.get("message", "Can't place there."))
	cp.spend_gold(cost)
	tower.start_ability_cooldown(ability_id, CommandAbilities.cooldown(ability_id))
	tower.play_visual_action("action")
	clash_match.players_changed.emit()
	return "%s (-%d gold). %s" % [CommandAbilities.display_name(ability_id), cost, str(result.get("message", ""))]


## Same rules as the host's own portal slides (main.gd _on_portal_slide_pressed).
func _portal(cp: ClashPlayerState, which: String, dx: int) -> String:
	if main.game_state.wave < WaveScaler.PORTAL_SLIDE_UNLOCK_WAVE or wave_manager.phase == WaveManager.Phase.WAVE:
		return "Portal moves unlock after wave %d, between waves." % WaveScaler.PORTAL_SLIDE_UNLOCK_WAVE
	if cp.gold < WaveScaler.PORTAL_SLIDE_COST:
		return "Need %d gold to move a portal." % WaveScaler.PORTAL_SLIDE_COST
	if not grid.try_slide_portal(which, dx, main.pathfinder, cp.lane_index):
		return "Can't move that portal that way (edge, blocked, or would seal the path)."
	cp.spend_gold(WaveScaler.PORTAL_SLIDE_COST)
	clash_match.players_changed.emit()
	_paths_changed()
	return "%s moved (-%d gold)." % ["Spawn" if which == "spawn" else "Exit", WaveScaler.PORTAL_SLIDE_COST]


func _send_pack(cp: ClashPlayerState, target_id: int, pack_id: String) -> String:
	if not clash_match.try_send_pack(cp.player_id, target_id, pack_id):
		return "Can't send that package."
	if wave_manager.phase == WaveManager.Phase.WAVE:
		wave_manager.flush_pending_clash_sends()
	var dest := clash_match.get_player(target_id)
	return "Sent %s to %s (income now +%d/rnd)." % [
		str(WaveScaler.clash_send_pack(pack_id).get("label", pack_id)), dest.display_name, cp.income_per_round
	]


func _upgrade_shop(cp: ClashPlayerState) -> String:
	if clash_match.try_upgrade_send_shop(cp.player_id):
		return "Send shop upgraded to Lv%d for everyone." % clash_match.send_shop_level
	return "Can't upgrade the send shop."


func _paths_changed() -> void:
	wave_manager.invalidate_ground_path()
	main.build_system.rebuild_paths()


func _on_player_left(net_id: int) -> void:
	var seat := Net.seat_of(net_id)
	var cp := clash_match.get_player(seat)
	if cp == null or not cp.is_remote:
		return
	var name := cp.display_name
	_remote.erase(seat)
	clash_match.convert_to_bot(seat)
	if cp.alive and not clash_match.finished:
		bot_needed.emit(seat)
		main.hud.set_status("%s left — a bot took over their lane." % name)
