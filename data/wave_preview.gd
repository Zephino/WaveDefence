class_name WavePreview
extends RefCounted

## Icons + text for upcoming waves (pause timeline, intermission briefing).


static func icon_for_wave(wave: int, game_mode: int, rng_seed: int = 0) -> String:
	if wave <= 0:
		return "·"
	if WaveScaler.is_boss_wave(wave):
		if wave % 50 == 0:
			return "BB"
		if wave % 15 == 0:
			return "F"
		if WaveScaler.roll_snake_boss(wave, _rng(rng_seed, wave)):
			return "S"
		return "B"
	if WaveScaler.is_speed_wave(wave):
		return "!"
	if WaveScaler.flying_creep_count(wave) > 0:
		return "A"
	if WaveScaler.should_rotate_spawn_after_wave(game_mode, wave):
		return "R"
	return "·"


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
		parts.append("SPEED WAVE")
	if WaveScaler.flying_creep_count(wave) > 0:
		parts.append("Air mix")
	if WaveScaler.is_randomize_monsters(monster_mode):
		parts.append("Elemental resists scale with wave")
	return " — ".join(parts)


static func timeline_text(from_wave: int, count: int, game_mode: int) -> String:
	var lines: PackedStringArray = []
	for i in count:
		var w := from_wave + i
		if w <= 0:
			continue
		lines.append("W%d %s" % [w, icon_for_wave(w, game_mode, 12345)])
	return "  ".join(lines)
