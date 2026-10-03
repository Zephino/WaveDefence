extends Node

## Fetches/pushes shared leaderboards. Autoload: OnlineLeaderboard.

signal boards_updated(ok: bool)
signal push_finished(ok: bool)

const PENDING_PATH := "user://pending_global_score.json"
const BOOTSTRAP_FLAG := "user://global_boards_bootstrapped.flag"

var last_source: String = "local" ## "global" | "local" | "offline"
var _http: HTTPRequest
var _busy: bool = false
var _queue: Array = [] ## Array of Dictionaries {kind, ...}


func _ready() -> void:
	_http = HTTPRequest.new()
	_http.timeout = 12.0
	add_child(_http)
	_http.request_completed.connect(_on_request_completed)
	call_deferred("bootstrap_and_flush")


func is_online_likely() -> bool:
	return true


func bootstrap_and_flush() -> void:
	await fetch_boards()
	await flush_pending_if_online()


func fetch_boards() -> bool:
	if not OnlineConfig.can_read():
		last_source = "local"
		boards_updated.emit(false)
		return false
	var ok := await _enqueue_and_wait({"kind": "get"})
	return ok


func flush_pending_if_online() -> bool:
	var pending := load_pending()
	if pending.is_empty():
		return true
	if not OnlineConfig.can_post():
		return false
	if not bool(pending.get("needed", false)) or bool(pending.get("done", false)):
		return true
	return await push_score(
		str(pending.get("name", "")),
		int(pending.get("wave", 0)),
		int(pending.get("difficulty", WaveScaler.Difficulty.MEDIUM))
	)


func queue_pending_score(player_name: String, wave: int, difficulty: int) -> void:
	var name := LeaderboardStore.sanitize_name(player_name)
	if name.is_empty() or wave <= 0:
		return
	var data := {
		"name": name,
		"wave": wave,
		"difficulty": difficulty,
		"needed": true,
		"done": false,
	}
	_save_pending(data)
	Session.global_push_name = name
	Session.global_push_wave = wave
	Session.global_push_difficulty = difficulty
	Session.global_push_needed = true
	Session.global_push_done = false


func clear_pending() -> void:
	if FileAccess.file_exists(PENDING_PATH):
		DirAccess.remove_absolute(PENDING_PATH)
	Session.global_push_name = ""
	Session.global_push_wave = -1
	Session.global_push_needed = false
	Session.global_push_done = false


func load_pending() -> Dictionary:
	if not FileAccess.file_exists(PENDING_PATH):
		return {}
	var f := FileAccess.open(PENDING_PATH, FileAccess.READ)
	if f == null:
		return {}
	var data = JSON.parse_string(f.get_as_text())
	if typeof(data) != TYPE_DICTIONARY:
		return {}
	return data


func push_score(player_name: String, wave: int, difficulty: int) -> bool:
	if not OnlineConfig.can_post():
		push_finished.emit(false)
		return false
	var name := LeaderboardStore.sanitize_name(player_name)
	if name.is_empty() or wave <= 0 or wave > OnlineConfig.MAX_WAVE_SANITY:
		push_finished.emit(false)
		return false
	var body := {
		"name": name,
		"wave": wave,
		"difficulty": LeaderboardStore.difficulty_key(difficulty),
	}
	var ok := await _enqueue_and_wait({"kind": "post", "body": body, "difficulty": difficulty})
	return ok


func _save_pending(data: Dictionary) -> void:
	var f := FileAccess.open(PENDING_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data))


func _enqueue_and_wait(job: Dictionary) -> bool:
	var result := {"done": false, "ok": false}
	job["result"] = result
	_queue.append(job)
	_pump()
	while not result["done"]:
		await get_tree().process_frame
	return bool(result["ok"])


func _pump() -> void:
	if _busy or _queue.is_empty():
		return
	_busy = true
	var job: Dictionary = _queue.pop_front()
	var kind := str(job.get("kind", ""))
	if kind == "get":
		var err := _http.request(OnlineConfig.read_url(), [], HTTPClient.METHOD_GET)
		if err != OK:
			_finish_job(job, false)
			return
		_current_job = job
	elif kind == "post":
		var headers := PackedStringArray([
			"Content-Type: application/json",
			"Accept: application/json",
		])
		var payload := JSON.stringify(job.get("body", {}))
		var err := _http.request(OnlineConfig.post_url(), headers, HTTPClient.METHOD_POST, payload)
		if err != OK:
			_finish_job(job, false)
			return
		_current_job = job
	else:
		_finish_job(job, false)


var _current_job: Dictionary = {}


func _on_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	var job := _current_job
	_current_job = {}
	if job.is_empty():
		_busy = false
		_pump()
		return
	var kind := str(job.get("kind", ""))
	var ok := false
	if result == HTTPRequest.RESULT_SUCCESS and response_code >= 200 and response_code < 300:
		var text := body.get_string_from_utf8()
		if kind == "get":
			ok = _apply_remote_boards(text)
			if ok:
				last_source = "global"
				var flag := FileAccess.open(BOOTSTRAP_FLAG, FileAccess.WRITE)
				if flag:
					flag.store_string("1")
		elif kind == "post":
			ok = _apply_remote_boards(text) or text.strip_edges().is_empty()
			if not ok and response_code >= 200 and response_code < 300:
				ok = true
			if ok:
				last_source = "global"
				var pending := load_pending()
				if not pending.is_empty():
					pending["done"] = true
					pending["needed"] = false
					_save_pending(pending)
				Session.global_push_done = true
				Session.global_push_needed = false
				# Refresh boards after a successful push.
				call_deferred("_deferred_refetch")
	else:
		if kind == "get":
			last_source = "offline" if result != HTTPRequest.RESULT_SUCCESS else "local"
	_finish_job(job, ok)
	if kind == "get":
		boards_updated.emit(ok)
	else:
		push_finished.emit(ok)


func _deferred_refetch() -> void:
	fetch_boards()


func _finish_job(job: Dictionary, ok: bool) -> void:
	var result: Dictionary = job.get("result", {})
	if typeof(result) == TYPE_DICTIONARY:
		result["ok"] = ok
		result["done"] = true
	_busy = false
	_pump()


func _apply_remote_boards(text: String) -> bool:
	var data = JSON.parse_string(text.strip_edges())
	if typeof(data) != TYPE_DICTIONARY:
		return false
	return LeaderboardStore.replace_boards_from_remote(data)
