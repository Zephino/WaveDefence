class_name LobbyService
extends Node
## What online Clash needs from an online service (same design as Mythriven
## co-op): host a match and get a 6-digit code, join with a code, and pass
## messages between up to 4 players. CloudflareLobby is the one used; another
## service can be added as another subclass without changing the game.
##
## Player ids: the host is 1, others 2–4. `to` = 0 means everyone else.

## Connected: this device's id, the game's code, and the players already there.
signal opened(my_id: int, code: String, peers: PackedInt32Array)
signal peer_joined(id: int)
signal peer_left(id: int)
signal received(from: int, data: PackedByteArray)
## The connection ended (the host left, the code was wrong, no internet…):
## `reason` is a message for the player ("" when this player left).
signal closed(reason: String)

const HOST_ID := 1
const EVERYONE := 0


func host() -> void:
	pass


func join(_code: String) -> void:
	pass


func send(_to: int, _data: PackedByteArray) -> void:
	pass


## Host only: no one else can join (the match is starting).
func lock() -> void:
	pass


## Host only: removes a player from the lobby.
func kick(_id: int) -> void:
	pass


func leave() -> void:
	pass


func is_open() -> bool:
	return false
