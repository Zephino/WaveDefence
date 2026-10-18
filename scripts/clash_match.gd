class_name ClashMatch
extends Node

## Owns Clash players, send economy, elimination, and human GameState sync.

signal players_changed
signal match_over(winner_id: int, human_won: bool, place: int)
signal player_eliminated(player_id: int)

var game_state: GameState
var players: Array = [] ## ClashPlayerState
var human_id: int = 0
var finished: bool = false
var _place_counter: int = 0


func setup(p_state: GameState, player_count: int, bot_difficulties: Array) -> void:
	game_state = p_state
	players.clear()
	finished = false
	_place_counter = 0
	var count := clampi(player_count, WaveScaler.CLASH_MIN_PLAYERS, WaveScaler.CLASH_MAX_PLAYERS)
	for i in count:
		var p := ClashPlayerState.new()
		p.player_id = i
		p.lane_index = i
		p.is_human = i == 0
		if p.is_human:
			p.display_name = "You"
			p.bot_difficulty = WaveScaler.Difficulty.MEDIUM
		else:
			var bot_i := i - 1
			p.display_name = "Bot %d" % i
			p.bot_difficulty = WaveScaler.Difficulty.MEDIUM
			if bot_i < bot_difficulties.size():
				p.bot_difficulty = int(bot_difficulties[bot_i])
		p.reset_economy()
		players.append(p)
	human_id = 0
	sync_human_to_game_state()
	players_changed.emit()


func player_count() -> int:
	return players.size()


func get_player(id: int) -> ClashPlayerState:
	if id < 0 or id >= players.size():
		return null
	return players[id] as ClashPlayerState


func human() -> ClashPlayerState:
	return get_player(human_id)


func living_players() -> Array:
	var out: Array = []
	for p in players:
		var cp := p as ClashPlayerState
		if cp != null and cp.alive:
			out.append(cp)
	return out


func living_opponents_of(player_id: int) -> Array:
	var out: Array = []
	for p in players:
		var cp := p as ClashPlayerState
		if cp != null and cp.alive and cp.player_id != player_id:
			out.append(cp)
	return out


func living_count() -> int:
	return living_players().size()


## Next living player after this lane, wrapping (skips eliminated). Null if none other.
func next_living_after_lane(lane: int) -> ClashPlayerState:
	var n := players.size()
	if n <= 0:
		return null
	for step in n:
		var idx := (lane + 1 + step) % n
		var cp := players[idx] as ClashPlayerState
		if cp != null and cp.alive and cp.lane_index != lane:
			return cp
	return null


func award_round_income() -> void:
	for p in players:
		var cp := p as ClashPlayerState
		if cp != null and cp.alive:
			cp.award_income()
	sync_human_to_game_state()
	players_changed.emit()


## Buy a send pack aimed at target. Returns false if invalid/unaffordable.
func try_send_pack(from_id: int, to_id: int, pack_id: String) -> bool:
	if finished:
		return false
	var from_p := get_player(from_id)
	var to_p := get_player(to_id)
	if from_p == null or to_p == null:
		return false
	if not from_p.alive or not to_p.alive or from_id == to_id:
		return false
	if not WaveScaler.CLASH_SEND_PACKS.has(pack_id):
		return false
	if from_p.is_human and game_state != null:
		from_p.gold = game_state.gold
	var cost: int = int(WaveScaler.clash_send_pack(pack_id)["cost"])
	if not from_p.spend_gold(cost):
		return false
	to_p.enqueue_incoming(pack_id, from_id)
	from_p.bump_income()
	if from_p.is_human:
		sync_human_to_game_state()
	players_changed.emit()
	return true


func credit_kill(defender_id: int, bounty: int) -> void:
	var p := get_player(defender_id)
	if p == null or not p.alive:
		return
	if p.is_human and game_state != null:
		game_state.add_gold(bounty)
		game_state.register_kill()
		p.gold = game_state.gold
	else:
		p.add_gold(bounty)
	players_changed.emit()


func credit_leak(defender_id: int) -> void:
	var p := get_player(defender_id)
	if p == null or not p.alive:
		return
	p.lose_life(1)
	if p.is_human and game_state != null:
		# Mirror lives; avoid double game_over from GameState — Clash handles match end.
		game_state.lives = p.lives
		game_state.lives_changed.emit(game_state.lives)
		game_state.total_leaks += 1
	players_changed.emit()
	if not p.alive:
		_on_eliminated(p)


func spend_human_gold(cost: int) -> bool:
	var h := human()
	if h == null or not h.spend_gold(cost):
		return false
	sync_human_to_game_state()
	players_changed.emit()
	return true


func sync_human_gold_from_game_state() -> void:
	var h := human()
	if h == null or game_state == null:
		return
	h.gold = game_state.gold
	players_changed.emit()


func sync_human_to_game_state() -> void:
	var h := human()
	if h == null or game_state == null:
		return
	game_state.gold = h.gold
	game_state.lives = h.lives
	game_state.gold_changed.emit(game_state.gold)
	game_state.lives_changed.emit(game_state.lives)


func _on_eliminated(p: ClashPlayerState) -> void:
	_place_counter += 1
	player_eliminated.emit(p.player_id)
	_check_match_over()


func _check_match_over() -> void:
	if finished:
		return
	var living := living_players()
	var h := human()
	if h != null and not h.alive:
		finished = true
		var place := living.size() + 1
		if game_state != null and not game_state.is_game_over:
			game_state.is_game_over = true
			game_state.game_over.emit(game_state.highest_wave)
		match_over.emit(-1, false, place)
		return
	if living.size() <= 1:
		finished = true
		var winner_id := -1
		var human_won := false
		if living.size() == 1:
			var w := living[0] as ClashPlayerState
			winner_id = w.player_id
			human_won = w.is_human
		if game_state != null and not game_state.is_game_over:
			game_state.is_game_over = true
			game_state.game_over.emit(game_state.highest_wave)
		match_over.emit(winner_id, human_won, 1 if human_won else 0)
