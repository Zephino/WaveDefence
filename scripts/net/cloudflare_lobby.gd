class_name CloudflareLobby
extends LobbyService
## Online Clash lobbies through the owner's Cloudflare Worker
## (leaderboard-api/src/lobby.mjs): one WebSocket to the match's LobbyRoom,
## which relays messages between the players. Works on the web, PC, and phones.

const BAD_CODE := "Codes are 6 digits."
const NOT_SET_UP := "Online play isn't set up yet."
const NO_CONNECTION := "Couldn't connect. Check your internet."
const HOST_LEFT := "The host left the match."
const KICKED := "The host removed you from the match."
const JOIN_REFUSED := "Couldn't join: wrong code, the match is full, or it already started."
const CONNECTION_LOST := "Lost the connection to the match."
const HOST_REFUSED := "Couldn't start an online match. Check your internet, or online play may not be set up yet."

var _socket: WebSocketPeer
var _was_open: bool = false
var _welcomed: bool = false
var _hosting: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func host() -> void:
	_connect("?host=1")
	_hosting = true


func join(code: String) -> void:
	var digits: String = code.strip_edges().replace(" ", "")
	if digits.length() != 6 or not digits.is_valid_int():
		closed.emit.call_deferred(BAD_CODE)
		return
	_connect("?code=" + digits)


func send(to: int, data: PackedByteArray) -> void:
	if not is_open():
		return
	var framed := PackedByteArray([to])
	framed.append_array(data)
	_socket.send(framed, WebSocketPeer.WRITE_MODE_BINARY)


func lock() -> void:
	if is_open():
		_socket.send_text(JSON.stringify({"t": "start"}))


func kick(id: int) -> void:
	if is_open():
		_socket.send_text(JSON.stringify({"t": "kick", "id": id}))


func leave() -> void:
	_hosting = false
	if _socket != null:
		_socket.close(1000, "left")
		_socket = null
	_was_open = false
	_welcomed = false


func is_open() -> bool:
	return _socket != null and _socket.get_ready_state() == WebSocketPeer.STATE_OPEN and _welcomed


func _connect(query: String) -> void:
	leave()
	var url: String = OnlineConfig.lobby_url()
	if url == "":
		closed.emit.call_deferred(NOT_SET_UP)
		return
	_socket = WebSocketPeer.new()
	# Room for a busy moment (a full board of enemies) without dropping messages.
	_socket.outbound_buffer_size = 1 << 20
	_socket.inbound_buffer_size = 1 << 20
	_socket.max_queued_packets = 4096
	if _socket.connect_to_url(url + query) != OK:
		_socket = null
		closed.emit.call_deferred(NO_CONNECTION)


func _process(_delta: float) -> void:
	if _socket == null:
		return
	_socket.poll()
	match _socket.get_ready_state():
		WebSocketPeer.STATE_OPEN:
			_was_open = true
			while _socket != null and _socket.get_available_packet_count() > 0:
				var packet: PackedByteArray = _socket.get_packet()
				if _socket.was_string_packet():
					_on_text(packet.get_string_from_utf8())
				elif packet.size() >= 1:
					received.emit(packet[0], packet.slice(1))
		WebSocketPeer.STATE_CLOSED:
			var code: int = _socket.get_close_code()
			var reason: String = _socket.get_close_reason()
			_socket = null
			_welcomed = false
			closed.emit(_reason_key(code, reason, _was_open, _hosting))
			_was_open = false


func _on_text(text: String) -> void:
	var json := JSON.new()
	if json.parse(text) != OK or not json.data is Dictionary:
		return
	var msg: Dictionary = json.data
	match str(msg.get("t", "")):
		"welcome":
			_welcomed = true
			var peers := PackedInt32Array()
			for id: Variant in msg.get("peers", []):
				peers.append(int(id))
			opened.emit(int(msg.get("id", 0)), str(msg.get("code", "")), peers)
		"join":
			peer_joined.emit(int(msg.get("id", 0)))
		"leave":
			peer_left.emit(int(msg.get("id", 0)))


## Turns how the connection ended into a message for the player.
static func _reason_key(code: int, reason: String, was_open: bool, hosting: bool = false) -> String:
	if code == 4000:
		return HOST_LEFT
	if code == 4001:
		return KICKED
	if code == 1000 and reason == "left":
		return ""
	if not was_open:
		# The Worker refuses a join before the WebSocket opens (wrong code, full, started).
		return HOST_REFUSED if hosting else JOIN_REFUSED
	return CONNECTION_LOST
