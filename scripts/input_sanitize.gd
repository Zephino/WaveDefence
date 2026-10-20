class_name InputSanitize
extends RefCounted

## Shared allowlist sanitizers for every LineEdit / API string.
## There is no SQL database in Wave Defence (JSON + KV only); allowlisting still
## blocks quote/semicolon/comment injection payloads before they touch any sink.

const MAX_NAME_LENGTH := 12
const MAX_SEED_TEXT_LENGTH := 64
## SQL / script metacharacters rejected before allowlisting (defense in depth).
## Keyword lists are omitted — they false-positive normal names like "Select".
const _INJECTION_MARKERS: PackedStringArray = [
	"'", "\"", ";", "--", "/*", "*/", "\\", "`", "<", ">",
]


## Letters, digits, space, underscore, hyphen. Empty after trim → invalid name.
static func sanitize_name(raw: String) -> String:
	var cleaned := filter_name_typing(raw).strip_edges()
	if cleaned.length() > MAX_NAME_LENGTH:
		cleaned = cleaned.substr(0, MAX_NAME_LENGTH)
	return cleaned


## Live typing filter: same charset, no edge-trim (so spaces can be typed mid-name).
static func filter_name_typing(raw: String) -> String:
	var cleaned := ""
	for i in raw.length():
		var ch := raw[i]
		if _is_name_char(ch):
			cleaned += ch
		if cleaned.length() >= MAX_NAME_LENGTH:
			break
	return cleaned


## Seed field: alnum / space / _ / - only, capped length. Empty stays empty.
static func sanitize_seed_text(raw: String) -> String:
	return filter_seed_typing(raw).strip_edges()


static func filter_seed_typing(raw: String) -> String:
	var cleaned := ""
	for i in raw.length():
		var ch := raw[i]
		if _is_seed_char(ch):
			cleaned += ch
		if cleaned.length() >= MAX_SEED_TEXT_LENGTH:
			break
	return cleaned


## True if raw looks like an injection / script payload (pre-allowlist check).
static func looks_like_injection(raw: String) -> bool:
	if raw.is_empty():
		return false
	var lower := raw.to_lower()
	for marker in _INJECTION_MARKERS:
		if lower.find(marker) >= 0:
			return true
	for i in raw.length():
		var code := raw.unicode_at(i)
		# Control chars except tab/newline (those are stripped by allowlists anyway).
		if code < 32 and code != 9 and code != 10 and code != 13:
			return true
	return false


## Clamp a LineEdit to an allowlist as the player types. mode: "name" | "seed"
static func bind_line_edit(edit: LineEdit, mode: String) -> void:
	if edit == null:
		return
	match mode:
		"name":
			edit.max_length = MAX_NAME_LENGTH
			edit.text_changed.connect(func(new_text: String) -> void:
				_rewrite_line_edit(edit, filter_name_typing(new_text))
			)
			edit.text = filter_name_typing(edit.text)
		"seed":
			edit.max_length = MAX_SEED_TEXT_LENGTH
			edit.text_changed.connect(func(new_text: String) -> void:
				_rewrite_line_edit(edit, filter_seed_typing(new_text))
			)
			edit.text = filter_seed_typing(edit.text)
		_:
			push_warning("InputSanitize.bind_line_edit: unknown mode '%s'" % mode)


static func _rewrite_line_edit(edit: LineEdit, cleaned: String) -> void:
	if edit == null or cleaned == edit.text:
		return
	var caret := edit.caret_column
	edit.text = cleaned
	edit.caret_column = mini(caret, cleaned.length())


static func _is_name_char(ch: String) -> bool:
	var code := ch.unicode_at(0)
	return (
		(code >= 65 and code <= 90)
		or (code >= 97 and code <= 122)
		or (code >= 48 and code <= 57)
		or ch == " "
		or ch == "_"
		or ch == "-"
	)


static func _is_seed_char(ch: String) -> bool:
	# Same safe charset as names — seeds are hashed or parsed as ints, never executed.
	return _is_name_char(ch)
