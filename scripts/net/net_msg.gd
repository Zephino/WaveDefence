class_name NetMsg
extends RefCounted
## Online Clash message types. Every message is an Array whose first item is one
## of these, sent as bytes with var_to_bytes (no objects, so nothing can run code).

# Lobby
## Client → host: [HELLO, version]
const HELLO := 1
## Host → all: [SEATS, seats] (see NetSession.seats)
const SEATS := 2
## Client → host: [READY, on] (lobby: ready to start; match: ready for the next round)
const READY := 3
## Host → all: [START, seats]
const START := 4
## Host → one client: [WRONG_VERSION, host_version]
const WRONG_VERSION := 5
## Host → one client: [FULL] (every seat is a human already)
const FULL := 6

# In a match (host-authoritative; see ClashNetHost / ClashNetClient)
## Client → host: [ACTION, kind, args…] (place, sell, upgrade, final, cmd, portal, send, shop)
const ACTION := 20
## Host → all, ~10/s: [STATE, snapshot Dictionary]
const STATE := 21
## Host → one client: [STATUS, text] (result of that player's action)
const STATUS := 22
## Internal (not sent): a player left the match.
const BYE := 27


static func encode(msg: Array) -> PackedByteArray:
	return var_to_bytes(msg)


## The message, or [] if the bytes aren't a valid message.
static func decode(data: PackedByteArray) -> Array:
	var value: Variant = bytes_to_var(data)
	if value is Array and not (value as Array).is_empty() and (value as Array)[0] is int:
		return value
	return []
