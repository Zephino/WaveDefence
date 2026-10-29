class_name NetSession
extends Node
## Autoload "Net": the online Clash session. Holds the lobby connection from the
## lobby screen through the match, the seats (lanes), and who is ready.
## The host's game simulates every lane; joining players send their actions
## (see ClashNetHost / ClashNetClient, which get match messages via `match_message`).
##
## Seats: the host picks the player count and bots as usual. A friend who joins
## takes a new lane while there are fewer than 4; when all 4 are taken, they
## replace a bot. Everyone presses Ready, then the host starts.

signal changed
## The session ended; `reason` is a message for the player ("" when this player left).
signal ended(reason: String)
signal match_message(from: int, msg: Array)
## Host → everyone: the match is starting (the menu loads the game).
signal match_starting
## A player left during the match (the host gives their lane to a bot).
signal player_left_match(net_id: int)

enum State { OFF, CONNECTING, LOBBY, IN_MATCH }

const SEAT_HOST := "host"
const SEAT_HUMAN := "human"
const SEAT_BOT := "bot"

var state: State = State.OFF
var lobby: LobbyService
var my_id: int = 0
var code: String = ""
## One per lane, left to right: {"kind": host/human/bot, "net_id": int (0 for bots),
## "name": String, "diff": WaveScaler.Difficulty (bots)}. The host is always lane 0.
var seats: Array = []
## net_id -> true for players who pressed Ready (lobby, then each round).
var ready_ids: Dictionary = {}
## Set before connecting to use another service (the tests use LocalLobby).
var service_override: LobbyService = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


# --- State --------------------------------------------------------------------------------

func active() -> bool:
	return state != State.OFF


func in_match() -> bool:
	return state == State.IN_MATCH


func is_host() -> bool:
	return active() and my_id == LobbyService.HOST_ID


## True on a joining player's device during a match: the host decides
## everything that happens, and this device shows it.
func is_client() -> bool:
	return state == State.IN_MATCH and my_id != LobbyService.HOST_ID


## This device's lane, or -1.
func my_seat() -> int:
	return seat_of(my_id)


func seat_of(net_id: int) -> int:
	if net_id <= 0:
		return -1
	for i in seats.size():
		if int((seats[i] as Dictionary).get("net_id", 0)) == net_id:
			return i
	return -1


## Net ids of the joined players (not the host).
func guest_ids() -> Array[int]:
	var out: Array[int] = []
	for s in seats:
		if str((s as Dictionary).get("kind", "")) == SEAT_HUMAN:
			out.append(int((s as Dictionary).get("net_id", 0)))
	return out


func is_ready(net_id: int) -> bool:
	return net_id == LobbyService.HOST_ID or ready_ids.has(net_id)


## Everyone but the host has pressed Ready.
func all_guests_ready() -> bool:
	for id in guest_ids():
		if not ready_ids.has(id):
			return false
	return true


## Names of joined players who haven't pressed Ready.
func waiting_on_names() -> PackedStringArray:
	var out := PackedStringArray()
	for s in seats:
		var seat := s as Dictionary
		var id := int(seat.get("net_id", 0))
		if str(seat.get("kind", "")) == SEAT_HUMAN and not ready_ids.has(id):
			out.append(str(seat.get("name", "Player")))
	return out


func can_start() -> bool:
	return is_host() and state == State.LOBBY and seats.size() >= WaveScaler.CLASH_MIN_PLAYERS and all_guests_ready()


# --- Starting and leaving ---------------------------------------------------------------

## Host: open a lobby with the Clash setup (player count and bot difficulties).
func host_match(player_count: int, bot_difficulties: Array) -> void:
	_open()
	seats = [_seat(SEAT_HOST, LobbyService.HOST_ID, "Host")]
	var count := clampi(player_count, WaveScaler.CLASH_MIN_PLAYERS, WaveScaler.CLASH_MAX_PLAYERS)
	for i in count - 1:
		var diff := int(bot_difficulties[i]) if i < bot_difficulties.size() else WaveScaler.Difficulty.MEDIUM
		seats.append(_bot_seat(diff))
	_rename_bots()
	lobby.host()


func join_match(join_code: String) -> void:
	_open()
	seats = []
	lobby.join(join_code)


## Leaves the lobby or the match (the host leaving ends it for everyone).
func leave() -> void:
	if lobby != null:
		lobby.leave()
	_close("")


## Lobby (guest): ready to start. Match (guest): ready for the next round.
func set_ready(on: bool) -> void:
	if not active() or is_host():
		return
	if on:
		ready_ids[my_id] = true
	else:
		ready_ids.erase(my_id)
	send(LobbyService.HOST_ID, [NetMsg.READY, on])
	changed.emit()


## Host: a new round started, so everyone readies up again.
func clear_round_ready() -> void:
	if is_host():
		ready_ids.clear()


## Host only (lobby): add a bot lane.
func add_bot() -> void:
	if not is_host() or state != State.LOBBY or seats.size() >= WaveScaler.CLASH_MAX_PLAYERS:
		return
	seats.append(_bot_seat(WaveScaler.Difficulty.MEDIUM))
	_seats_changed()


## Host only (lobby): remove the bot in this lane.
func remove_bot(index: int) -> void:
	if not is_host() or state != State.LOBBY or index <= 0 or index >= seats.size():
		return
	if str((seats[index] as Dictionary).get("kind", "")) != SEAT_BOT:
		return
	if seats.size() <= WaveScaler.CLASH_MIN_PLAYERS:
		return
	seats.remove_at(index)
	_seats_changed()


## Host only (lobby): set the difficulty of the bot in this lane.
func set_bot_difficulty(index: int, diff: int) -> void:
	if not is_host() or state != State.LOBBY or index <= 0 or index >= seats.size():
		return
	var seat := seats[index] as Dictionary
	if str(seat.get("kind", "")) != SEAT_BOT:
		return
	seat["diff"] = diff
	_seats_changed()


## Host only: starts the match for everyone.
func start_match() -> void:
	if not can_start():
		return
	lobby.lock()
	ready_ids.clear()
	send(LobbyService.EVERYONE, [NetMsg.START, seats])
	_begin_match()


func send(to: int, msg: Array) -> void:
	if lobby != null:
		lobby.send(to, NetMsg.encode(msg))


func _open() -> void:
	if lobby != null:
		lobby.leave()
		lobby.queue_free()
	lobby = service_override if service_override != null else CloudflareLobby.new()
	add_child(lobby)
	lobby.opened.connect(_on_opened)
	lobby.peer_left.connect(_on_peer_left)
	lobby.received.connect(_on_received)
	lobby.closed.connect(_close)
	state = State.CONNECTING
	my_id = 0
	code = ""
	ready_ids.clear()
	changed.emit()


func _close(reason: String) -> void:
	if state == State.OFF:
		return
	state = State.OFF
	seats = []
	ready_ids.clear()
	my_id = 0
	code = ""
	if lobby != null:
		if lobby == service_override:
			remove_child(lobby)
		else:
			lobby.queue_free()
		lobby = null
	ended.emit(reason)
	changed.emit()


func _begin_match() -> void:
	state = State.IN_MATCH
	match_starting.emit()
	changed.emit()


# --- Seats ------------------------------------------------------------------------------

static func _seat(kind: String, net_id: int, name: String, diff: int = WaveScaler.Difficulty.MEDIUM) -> Dictionary:
	return {"kind": kind, "net_id": net_id, "name": name, "diff": diff}


static func _bot_seat(diff: int) -> Dictionary:
	return _seat(SEAT_BOT, 0, "Bot", diff)


## Bots are named by lane, like offline Clash ("Bot 1", "Cheater 2").
func _rename_bots() -> void:
	for i in seats.size():
		var seat := seats[i] as Dictionary
		if str(seat.get("kind", "")) != SEAT_BOT:
			continue
		seat["name"] = ("Cheater %d" if WaveScaler.is_cheater_bot(int(seat.get("diff", 0))) else "Bot %d") % i


## A friend joined: take a new lane, or replace the last bot when all lanes are taken.
## Returns false when every lane already has a person.
func _seat_guest(net_id: int) -> bool:
	if seat_of(net_id) >= 0:
		return true
	var seat := _seat(SEAT_HUMAN, net_id, "Player %d" % net_id)
	if seats.size() < WaveScaler.CLASH_MAX_PLAYERS:
		seats.append(seat)
		return true
	for i in range(seats.size() - 1, 0, -1):
		if str((seats[i] as Dictionary).get("kind", "")) == SEAT_BOT:
			seats[i] = seat
			return true
	return false


func _seats_changed() -> void:
	_rename_bots()
	send(LobbyService.EVERYONE, [NetMsg.SEATS, seats, ready_ids.keys()])
	changed.emit()


# --- Lobby messages ---------------------------------------------------------------------

func _on_opened(id: int, lobby_code: String, _peers: PackedInt32Array) -> void:
	my_id = id
	code = lobby_code
	state = State.LOBBY
	if not is_host():
		send(LobbyService.HOST_ID, [NetMsg.HELLO, _version()])
	changed.emit()


func _on_peer_left(id: int) -> void:
	ready_ids.erase(id)
	if state == State.IN_MATCH:
		player_left_match.emit(id)
		match_message.emit(id, [NetMsg.BYE])
		changed.emit()
		return
	if is_host():
		var index := seat_of(id)
		if index > 0:
			seats.remove_at(index)
		_seats_changed()
	changed.emit()


func _on_received(from: int, data: PackedByteArray) -> void:
	var msg: Array = NetMsg.decode(data)
	if msg.is_empty():
		return
	var kind: int = msg[0]
	if is_host():
		if kind == NetMsg.READY:
			_host_ready(from, msg)
			return
		if kind >= NetMsg.ACTION:
			if state == State.IN_MATCH:
				match_message.emit(from, msg)
			return
		_host_lobby_message(from, msg)
	elif from == LobbyService.HOST_ID:
		if kind >= NetMsg.ACTION:
			if state == State.IN_MATCH:
				match_message.emit(from, msg)
			return
		_client_lobby_message(msg)


func _host_ready(from: int, msg: Array) -> void:
	if seat_of(from) < 0 or msg.size() < 2:
		return
	if bool(msg[1]):
		ready_ids[from] = true
	else:
		ready_ids.erase(from)
	if state == State.LOBBY:
		send(LobbyService.EVERYONE, [NetMsg.SEATS, seats, ready_ids.keys()])
	changed.emit()


func _host_lobby_message(from: int, msg: Array) -> void:
	if int(msg[0]) != NetMsg.HELLO or state != State.LOBBY:
		return
	if msg.size() < 2 or str(msg[1]) != _version():
		send(from, [NetMsg.WRONG_VERSION, _version()])
		lobby.kick(from)
		return
	if not _seat_guest(from):
		send(from, [NetMsg.FULL])
		lobby.kick(from)
		return
	_seats_changed()


func _client_lobby_message(msg: Array) -> void:
	match int(msg[0]):
		NetMsg.SEATS:
			if msg.size() >= 3 and msg[1] is Array:
				seats = msg[1]
				ready_ids.clear()
				for id in msg[2]:
					ready_ids[int(id)] = true
		NetMsg.START:
			if msg.size() >= 2 and msg[1] is Array:
				seats = msg[1]
				ready_ids.clear()
				_begin_match()
				return
		NetMsg.WRONG_VERSION:
			_close("Your game version doesn't match the host's (%s). Update and try again." % str(msg[1]) if msg.size() > 1 else "")
			return
		NetMsg.FULL:
			_close("That match is full.")
			return
	changed.emit()


static func _version() -> String:
	return VersionInfo.current()
