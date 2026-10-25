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
## Cheater heal: after dipping to ≤ trigger, regenerate toward target.
var cheater_healing: bool = false
var cheater_heal_timer: float = 0.0
## Bot learning: monsters that got past this player since the last prep (reset by the bot).
var leaks_ground_round: int = 0
var leaks_air_round: int = 0


func reset_economy() -> void:
	gold = WaveScaler.clash_starting_gold()
	lives = WaveScaler.CLASH_STARTING_LIVES
	income_per_round = WaveScaler.CLASH_BASE_INCOME
	alive = true
	incoming_sends.clear()
	cheater_healing = false
	cheater_heal_timer = 0.0
	if not is_human and WaveScaler.is_cheater_bot(bot_difficulty):
		gold += WaveScaler.CLASH_CHEATER_EXTRA_GOLD
		lives += WaveScaler.CLASH_CHEATER_EXTRA_LIVES


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
	if (
		not is_human
		and WaveScaler.is_cheater_bot(bot_difficulty)
		and lives > 0
		and lives <= WaveScaler.CLASH_CHEATER_HEAL_TRIGGER
	):
		cheater_healing = true
	if lives <= 0:
		alive = false
		cheater_healing = false


## Slow +1 life ticks while cheater_healing toward HEAL_TARGET. Returns lives gained.
func tick_cheater_heal(delta: float) -> int:
	if not alive or is_human or not WaveScaler.is_cheater_bot(bot_difficulty):
		return 0
	if lives <= WaveScaler.CLASH_CHEATER_HEAL_TRIGGER:
		cheater_healing = true
	if not cheater_healing:
		return 0
	if lives >= WaveScaler.CLASH_CHEATER_HEAL_TARGET:
		cheater_healing = false
		cheater_heal_timer = 0.0
		return 0
	cheater_heal_timer += delta
	var gained := 0
	while (
		cheater_heal_timer >= WaveScaler.CLASH_CHEATER_HEAL_INTERVAL
		and lives < WaveScaler.CLASH_CHEATER_HEAL_TARGET
		and alive
	):
		cheater_heal_timer -= WaveScaler.CLASH_CHEATER_HEAL_INTERVAL
		lives += 1
		gained += 1
	if lives >= WaveScaler.CLASH_CHEATER_HEAL_TARGET:
		cheater_healing = false
		cheater_heal_timer = 0.0
	return gained


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
