class_name LocalLobby
extends LobbyService
## A lobby inside this one program, for the automated tests: several
## LocalLobby nodes with the same code pass messages to each other directly,
## exactly as CloudflareLobby does through the Worker.

static var _rooms: Dictionary = {}

var my_id: int = 0
var code: String = ""
var _locked: bool = false


func host() -> void:
	code = "%06d" % (randi() % 1000000)
	my_id = HOST_ID
	_rooms[code] = {HOST_ID: self}
	opened.emit.call_deferred(my_id, code, PackedInt32Array())


func join(join_code: String) -> void:
	var room: Dictionary = _rooms.get(join_code, {})
	if room.is_empty() or (room[HOST_ID] as LocalLobby)._locked or room.size() >= 4:
		closed.emit.call_deferred(CloudflareLobby.JOIN_REFUSED)
		return
	code = join_code
	my_id = 2
	while room.has(my_id):
		my_id += 1
	var peers := PackedInt32Array(room.keys())
	for other: LocalLobby in room.values():
		other.peer_joined.emit.call_deferred(my_id)
	room[my_id] = self
	opened.emit.call_deferred(my_id, code, peers)


func send(to: int, data: PackedByteArray) -> void:
	for id: int in _rooms.get(code, {}):
		if id != my_id and (to == EVERYONE or to == id):
			(_rooms[code][id] as LocalLobby).received.emit.call_deferred(my_id, data.duplicate())


func lock() -> void:
	_locked = true


func kick(id: int) -> void:
	var target: LocalLobby = _rooms.get(code, {}).get(id)
	if target != null:
		target._drop(CloudflareLobby.KICKED)


func leave() -> void:
	if not _rooms.has(code):
		return
	var room: Dictionary = _rooms[code]
	room.erase(my_id)
	for other: LocalLobby in room.values():
		if my_id == HOST_ID:
			other._drop(CloudflareLobby.HOST_LEFT)
		else:
			other.peer_left.emit.call_deferred(my_id)
	if my_id == HOST_ID or room.is_empty():
		_rooms.erase(code)
	code = ""


func is_open() -> bool:
	return code != "" and _rooms.has(code)


func _drop(reason: String) -> void:
	if _rooms.has(code):
		(_rooms[code] as Dictionary).erase(my_id)
	code = ""
	closed.emit.call_deferred(reason)
