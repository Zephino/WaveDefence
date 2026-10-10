class_name SoundHub
extends RefCounted

## Runtime bridge to GameAudio autoload (avoids compile-order issues).

const MUSIC_MENU := 1
const MUSIC_GAME_STANDARD := 2
const MUSIC_GAME_SIEGE := 3


static func _audio() -> Node:
	var tree := Engine.get_main_loop()
	if tree is SceneTree:
		return (tree as SceneTree).root.get_node_or_null("GameAudio")
	return null


static func unlock() -> void:
	var a := _audio()
	if a:
		a.unlock()


static func play_ui() -> void:
	var a := _audio()
	if a:
		a.play_ui()


static func play_place() -> void:
	var a := _audio()
	if a:
		a.play_place()


static func play_sell() -> void:
	var a := _audio()
	if a:
		a.play_sell()


static func play_kill() -> void:
	var a := _audio()
	if a:
		a.play_kill()


static func play_leak() -> void:
	var a := _audio()
	if a:
		a.play_leak()


static func play_wave_start(boss: bool) -> void:
	var a := _audio()
	if a:
		a.play_wave_start(boss)


static func play_game_over() -> void:
	var a := _audio()
	if a:
		a.play_game_over()


static func play_achievement() -> void:
	var a := _audio()
	if a:
		a.play_achievement()


static func set_music_context(ctx: int) -> void:
	var a := _audio()
	if a:
		a.set_music_context(ctx)


static func refresh_volumes() -> void:
	var a := _audio()
	if a:
		a.refresh_volumes()


static func set_paused_duck(duck: bool) -> void:
	var a := _audio()
	if a:
		a.set_paused_duck(duck)


static func set_gameplay_music_source(enemies: Node2D, wave: int, boss_wave: bool) -> void:
	var a := _audio()
	if a:
		a.set_gameplay_music_source(enemies, wave, boss_wave)
