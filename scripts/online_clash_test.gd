extends SceneTree

## Headless online Clash test (no internet; LocalLobby passes messages in-process):
##   godot --headless --path . -s res://scripts/online_clash_test.gd
## 1. Lobby seats: a friend takes a new lane, or replaces a bot when all 4 are taken;
##    Ready / Start.
## 2. Host: a joined player's actions build in their own lane with their own gold.
## 3. Joined player: the host's snapshot shows the same towers and gold.

var _fails: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _check(ok: bool, what: String) -> void:
	if not ok:
		_fails.append(what)
		push_error("FAIL: " + what)


func _frames(n: int = 3) -> void:
	for i in n:
		await process_frame


func _session() -> NetSession:
	var s := NetSession.new()
	s.service_override = LocalLobby.new()
	root.add_child(s)
	return s


func _run() -> void:
	await _test_lobby_seats()
	var snaps := await _test_host_actions()
	await _test_client_view(snaps)
	if _fails.is_empty():
		print("ONLINE_CLASH_TEST_OK")
		quit(0)
	else:
		print("ONLINE_CLASH_TEST_FAILED: %d" % _fails.size())
		quit(1)


func _test_lobby_seats() -> void:
	# All 4 lanes taken by the host + 3 bots: a friend replaces a bot.
	var host := _session()
	host.host_match(4, [WaveScaler.Difficulty.EASY, WaveScaler.Difficulty.HARD, WaveScaler.Difficulty.MEDIUM])
	await _frames()
	_check(host.state == NetSession.State.LOBBY and host.code.length() == 6, "host gets a 6-digit code")
	_check(host.seats.size() == 4, "host + 3 bots = 4 lanes")
	var guest := _session()
	guest.join_match(host.code)
	await _frames(6)
	_check(host.seats.size() == 4, "still 4 lanes after a friend joins a full match")
	_check(str((host.seats[3] as Dictionary)["kind"]) == NetSession.SEAT_HUMAN, "the friend replaced the last bot")
	_check(guest.seats.size() == 4 and guest.my_seat() == 3, "the friend sees the lanes and their own lane")
	_check(not host.can_start(), "can't start until the friend is Ready")
	guest.set_ready(true)
	await _frames()
	_check(host.can_start(), "can start once everyone is Ready")
	var started := [false]
	guest.match_starting.connect(func() -> void: started[0] = true)
	host.start_match()
	await _frames()
	_check(started[0] and guest.in_match(), "the friend's game starts with the host's")
	guest.leave()
	host.leave()
	await _frames()

	# Room left (host + 1 bot): a friend takes a new lane instead.
	var host2 := _session()
	host2.host_match(2, [WaveScaler.Difficulty.MEDIUM])
	await _frames()
	var guest2 := _session()
	guest2.join_match(host2.code)
	await _frames(6)
	_check(host2.seats.size() == 3, "a friend takes a new lane while there are fewer than 4")
	_check(str((host2.seats[1] as Dictionary)["kind"]) == NetSession.SEAT_BOT, "the bot keeps its lane")
	guest2.leave()
	await _frames()
	_check(host2.seats.size() == 2, "a friend leaving the lobby frees their lane")
	host2.leave()
	for s in [host, guest, host2, guest2]:
		s.queue_free()
	await _frames()


## The real Net autoload as host with a joined player (net id 2) in lane 1.
func _fake_match(my_id: int) -> void:
	var net: NetSession = root.get_node("Net")
	net.seats = [
		NetSession._seat(NetSession.SEAT_HOST, 1, "Host"),
		NetSession._seat(NetSession.SEAT_HUMAN, 2, "Player 2"),
		NetSession._seat(NetSession.SEAT_BOT, 0, "Bot 2"),
	]
	net.my_id = my_id
	net.state = NetSession.State.IN_MATCH
	var session: Node = root.get_node("Session")
	session.game_mode = WaveScaler.GameMode.CLASH
	session.clash_player_count = 3


func _load_main() -> Node:
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await _frames()
	return main


## Returns the host's snapshots during a wave, as a joined player would receive them.
func _test_host_actions() -> Array:
	var Net: NetSession = root.get_node("Net")
	_fake_match(1)
	var main := await _load_main()
	# Untyped: these scripts use the Net autoload, which test scripts can't name at load time.
	var net_host: Node = main.get_node_or_null("ClashNetHost")
	_check(net_host != null, "host runs ClashNetHost")
	if net_host == null:
		return []
	var clash: ClashMatch = main.clash_match
	_check(clash.online and clash.players.size() == 3, "3 online lanes")
	var guest := clash.get_player(1)
	_check(guest.is_remote and not guest.is_human, "lane 1 is the joined player")
	_check(main._clash_bots.size() == 1, "only the bot lane has an AI")
	var grid: GameGrid = main.grid
	var lane1: Vector2i = grid.lane_col_ranges[1]
	var cell := Vector2i(lane1.x, 3)
	var gold_before := guest.gold
	Net.match_message.emit(2, [NetMsg.ACTION, "place", cell, "wall"])
	var placed := grid.get_tower_at(cell) as Tower
	_check(placed != null and placed.tower_id == "wall", "the joined player's wall is built in their lane")
	_check(placed != null and int(placed.get_meta("clash_owner", -1)) == 1, "and belongs to them")
	_check(guest.gold == gold_before - int(TowerData.get_def("wall")["cost"]), "paid from their own gold")
	var host_lane: Vector2i = grid.lane_col_ranges[0]
	var host_cell := Vector2i(host_lane.x, 3)
	Net.match_message.emit(2, [NetMsg.ACTION, "place", host_cell, "wall"])
	_check(grid.get_tower_at(host_cell) == null, "a joined player can't build in the host's lane")
	Net.match_message.emit(2, [NetMsg.ACTION, "place", "not a cell", 7])
	Net.match_message.emit(2, [NetMsg.ACTION, "sell", [cell, "junk"]])
	_check(grid.get_tower_at(cell) == null, "selling their own wall works (bad values are ignored)")
	Net.match_message.emit(2, [NetMsg.ACTION, "place", cell, "gunner"])
	var snap: Dictionary = net_host.snapshot()
	var rows: Array = snap.get("pl", [])
	_check(rows.size() == 3 and int((rows[1] as Array)[0]) == guest.gold, "snapshot carries each lane's gold")
	_check(snap.has("tw") and (snap["tw"] as Array).size() >= 1, "snapshot carries the towers")
	var snaps: Array = [_over_the_wire(snap)]
	# Run a wave and collect what the host sends (~10 a second).
	main._on_skip_timer()
	_check(main.wave_manager.phase == WaveManager.Phase.PREP, "Start Round waits for the joined player's Ready")
	Net._host_ready(2, [NetMsg.READY, true])
	main._on_skip_timer()
	_check(main.wave_manager.phase == WaveManager.Phase.INTERMISSION, "the host starts the round once everyone is Ready")
	main.wave_manager.force_next_wave()
	_check(Net.ready_ids.is_empty(), "Ready resets when a wave starts")
	for i in 40:
		await _frames(6)
		snaps.append(_over_the_wire(net_host.snapshot()))
	var biggest := 0
	var saw_enemies := false
	for sn in snaps:
		biggest = maxi(biggest, NetMsg.encode([NetMsg.STATE, sn]).size())
		saw_enemies = saw_enemies or (sn.get("en", PackedFloat32Array()) as PackedFloat32Array).size() > 0
	_check(saw_enemies, "the wave's enemies are in the snapshots")
	_check(biggest < 64000, "snapshots stay small (%d bytes)" % biggest)
	print("largest snapshot: %d bytes" % biggest)
	# The joined player leaves: a bot takes their lane.
	Net.player_left_match.emit(2)
	_check(not guest.is_remote and main._clash_bots.size() == 2, "a bot takes over when a player leaves")
	main.queue_free()
	await _frames()
	return snaps


## Encode and decode like the real connection does.
func _over_the_wire(snap: Dictionary) -> Dictionary:
	var msg := NetMsg.decode(NetMsg.encode([NetMsg.STATE, snap]))
	return msg[1] if msg.size() >= 2 and msg[1] is Dictionary else {}


func _test_client_view(snaps: Array) -> void:
	if snaps.is_empty():
		return
	var snap: Dictionary = snaps[0]
	var Net: NetSession = root.get_node("Net")
	_fake_match(2)
	var main := await _load_main()
	var client: Node = main.get_node_or_null("ClashNetClient")
	_check(client != null, "a joined player runs ClashNetClient")
	if client == null:
		return
	_check(main.wave_manager.process_mode == Node.PROCESS_MODE_DISABLED, "no local simulation on a joined player's device")
	_check(main.build_system.human_lane == 1, "a joined player builds in their own lane")
	client.apply(snap)
	await _frames()
	var lane1: Vector2i = main.grid.lane_col_ranges[1]
	var t := main.grid.get_tower_at(Vector2i(lane1.x, 3)) as Tower
	_check(t != null and t.tower_id == "gunner", "the host's tower shows on the joined player's screen")
	var me := (snap["pl"] as Array)[1] as Array
	_check(main.game_state.gold == int(me[0]), "the joined player's gold comes from the host")
	var most := 0
	for i in range(1, snaps.size()):
		client.apply(snaps[i])
		await _frames(2)
		var shown := 0
		for e in main.enemies.get_children():
			if e is Enemy and (e as Enemy).visible:
				shown += 1
		most = maxi(most, shown)
	_check(most > 0, "the host's enemies show on the joined player's screen (up to %d)" % most)
	_check(main.game_state.wave >= 1, "the joined player's wave number follows the host")
	var sent: Array = []
	Net.lobby = null
	main.build_system.remote_place = func(c: Vector2i, id: String) -> void: sent.append([c, id])
	main.build_system.select_tower_type("wall")
	main.build_system.try_place_at(main.grid.cell_to_world_center(Vector2i(lane1.x + 1, 5)), false, true)
	_check(sent.size() == 1 and main.grid.get_tower_at(Vector2i(lane1.x + 1, 5)) == null, "placing sends a request instead of building")
	Net.state = NetSession.State.OFF
	main.queue_free()
	await _frames()
