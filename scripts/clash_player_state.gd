class_name ClashPlayerState
extends RefCounted

## One Clash lane participant (human or bot).

var player_id: int = 0
var is_human: bool = false
var bot_difficulty: int = WaveScaler.Difficulty.MEDIUM
var lane_index: int = 0
var display_name: String = "Player"
var gold: int = WaveScaler.CLASH_STARTING_GOLD
var lives: int = WaveScaler.CLASH_STARTING_LIVES
var income_per_round: int = WaveScaler.CLASH_BASE_INCOME
var alive: bool = true
## Queued send packs for the next wave aimed at this player: Array of {pack_id, from_id}.
var incoming_sends: Array = []


func reset_economy() -> void:
	gold = WaveScaler.clash_starting_gold()
	lives = WaveScaler.CLASH_STARTING_LIVES
	income_per_round = WaveScaler.CLASH_BASE_INCOME
	alive = true
	incoming_sends.clear()


func add_gold(amount: int) -> void:
	if amount == 0:
		return
	gold = maxi(gold + amount, 0)


func can_afford(cost: int) -> bool:
	return gold >= cost


func spend_gold(cost: int) -> bool:
	if cost < 0 or gold < cost:
		return false
	gold -= cost
	return true


func lose_life(amount: int = 1) -> void:
	if not alive:
		return
	lives = maxi(lives - amount, 0)
	if lives <= 0:
		alive = false


func award_income() -> void:
	if not alive:
		return
	add_gold(income_per_round)


func bump_income(amount: int = WaveScaler.CLASH_SEND_INCOME_BUMP) -> void:
	income_per_round = maxi(income_per_round + amount, 0)


func enqueue_incoming(pack_id: String, from_id: int) -> void:
	incoming_sends.append({"pack_id": pack_id, "from_id": from_id})


func take_incoming_sends() -> Array:
	var out := incoming_sends.duplicate(true)
	incoming_sends.clear()
	return out
