class_name RunSummaryOverlay
extends Control

const _WavePreview := preload("res://data/wave_preview.gd")

signal continued

var _wave_reached: int = 0


func show_summary(state: GameState, coaching: Dictionary) -> void:
	_wave_reached = maxi(state.highest_wave, state.wave)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.04, 0.06, 0.92)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(460, 0)
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	var title := Label.new()
	title.text = "Run summary"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 26)
	box.add_child(title)
	var stats := Label.new()
	stats.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stats.custom_minimum_size = Vector2(420, 0)
	stats.text = (
		"Wave reached: %d\nKills: %d\nLeaks: %d\nGold earned: ~%d\nWalls: %d  Towers: %d"
		% [
			_wave_reached,
			state.total_kills,
			state.total_leaks,
			state.run_gold_earned,
			state.walls_placed,
			state.towers_placed,
		]
	)
	box.add_child(stats)
	var seed_text := seed_clipboard_text(state)
	if not seed_text.is_empty():
		var seed_label := Label.new()
		seed_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		seed_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		seed_label.custom_minimum_size = Vector2(420, 0)
		seed_label.modulate = Color(0.72, 0.78, 0.85)
		if seed_text.contains(","):
			seed_label.text = "Map seeds: %s" % seed_text
		else:
			seed_label.text = "Map seed: %s" % seed_text
		seed_label.tooltip_text = "Paste into Classic → Custom layout to replay this map."
		box.add_child(seed_label)
	if bool(coaching.get("new_best", false)):
		var best := Label.new()
		best.text = "New personal best!"
		best.modulate = Color(0.75, 0.9, 0.55)
		best.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(best)
	var coach := Label.new()
	coach.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	coach.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	coach.custom_minimum_size = Vector2(420, 0)
	coach.modulate = Color(0.65, 0.72, 0.78)
	coach.add_theme_font_size_override("font_size", 13)
	coach.text = str(coaching.get("coaching_text", ""))
	box.add_child(coach)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	box.add_child(row)
	var cont := Button.new()
	cont.text = "Continue"
	cont.custom_minimum_size = Vector2(140, 44)
	cont.pressed.connect(func() -> void:
		continued.emit()
		queue_free()
	)
	row.add_child(cont)
	if not seed_text.is_empty():
		var copy_seed := Button.new()
		copy_seed.text = "Copy seed"
		copy_seed.custom_minimum_size = Vector2(130, 44)
		copy_seed.pressed.connect(func() -> void:
			DisplayServer.clipboard_set(seed_text)
			copy_seed.text = "Copied!"
			copy_seed.disabled = true
		)
		row.add_child(copy_seed)
	if coaching.has("screenshot_cb"):
		var shot := Button.new()
		shot.text = "Save maze image"
		shot.custom_minimum_size = Vector2(160, 44)
		shot.pressed.connect(coaching["screenshot_cb"])
		row.add_child(shot)


static func seed_clipboard_text(state: GameState) -> String:
	var seeds: Array = state.seeds_for_leaderboard()
	if seeds.is_empty() and state.current_map_seed >= 0:
		seeds = [state.current_map_seed]
	if seeds.is_empty():
		return ""
	var parts: PackedStringArray = []
	for s in seeds:
		parts.append(str(int(s)))
	return ", ".join(parts)


static func build_coaching_text(state: GameState) -> String:
	var lines: PackedStringArray = []
	var top: Array = []
	for w in state.leaks_per_wave.keys():
		top.append({"w": int(w), "n": int(state.leaks_per_wave[w])})
	top.sort_custom(func(a, b): return int(a["n"]) > int(b["n"]))
	for i in mini(3, top.size()):
		var e: Dictionary = top[i]
		lines.append("Wave %d: %d leak(s)" % [int(e["w"]), int(e["n"])])
	if state.sell_count > 0:
		lines.append("Sold %d times (~%d gold refunded)" % [state.sell_count, state.sell_refund_total])
	if not lines.is_empty():
		var worst: Dictionary = top[0]
		var tip := _WavePreview.summary_line(int(worst["w"]), state.game_mode, state.monster_mode)
		lines.append("Most leaks: wave %d (%s)" % [int(worst["w"]), tip])
	return "\n".join(lines)
