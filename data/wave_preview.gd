class_name WavePreview
extends RefCounted

## Icons + text for upcoming waves (pause timeline, intermission briefing).


static func label_for_wave(wave: int, game_mode: int, rng_seed: int = 0) -> String:
	if wave <= 0:
		return "normal"
	if WaveScaler.is_boss_wave(wave):
		if wave % 50 == 0:
			return "double boss"
		if wave % 15 == 0:
			return "flying boss"
		if WaveScaler.roll_snake_boss(wave, _rng(rng_seed, wave)):
			return "snake boss"
		return "boss"
	if WaveScaler.is_speed_wave(wave):
		return "faster enemies"
	if WaveScaler.flying_creep_count(wave) > 0:
		return "air enemies"
	if WaveScaler.should_rotate_spawn_after_wave(game_mode, wave):
		return "spawn moves after"
	return "normal"


## Kept for older call sites; prefer label_for_wave for UI text.
static func icon_for_wave(wave: int, game_mode: int, rng_seed: int = 0) -> String:
	return label_for_wave(wave, game_mode, rng_seed)


static func _rng(seed_val: int, wave: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = seed_val + wave * 7919
	return r


static func summary_line(wave: int, game_mode: int, monster_mode: int) -> String:
	if wave <= 0:
		return "Build your maze, then Start Round."
	var parts: Array[String] = ["Wave %d" % wave]
	var banner := WaveScaler.boss_banner(wave, WaveScaler.roll_snake_boss(wave, _rng(0, wave)))
	if banner.strip_edges() != "":
		parts.append(banner)
	if WaveScaler.is_speed_wave(wave):
		parts.append("faster enemies")
	if WaveScaler.flying_creep_count(wave) > 0:
		parts.append("air enemies")
	if WaveScaler.is_randomize_monsters(monster_mode):
		parts.append("Elemental resists scale with wave")
	return " — ".join(parts)


static func timeline_text(from_wave: int, count: int, game_mode: int) -> String:
	var parts: PackedStringArray = []
	var normal_start := -1
	var normal_end := -1
	for i in count:
		var w := from_wave + i
		if w <= 0:
			continue
		var label := label_for_wave(w, game_mode, 12345)
		if label == "normal":
			if normal_start < 0:
				normal_start = w
			normal_end = w
			continue
		if normal_start >= 0:
			parts.append(_normal_range(normal_start, normal_end))
			normal_start = -1
			normal_end = -1
		parts.append("%d %s" % [w, label])
	if normal_start >= 0:
		parts.append(_normal_range(normal_start, normal_end))
	return ", ".join(parts)


static func _normal_range(start_w: int, end_w: int) -> String:
	if start_w == end_w:
		return "%d normal" % start_w
	return "%d–%d normal" % [start_w, end_w]
