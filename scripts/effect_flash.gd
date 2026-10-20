class_name EffectFlash
extends Node2D

## One-shot (or short) cosmetic effect flash. Visual only.

const _EffectSprites := preload("res://scripts/effect_sprites.gd")

var _effect: String = ""
var _time: float = 0.0
var _angle: float = 0.0
var _extra_scale: float = 1.0
var _max_life: float = 0.25


func setup(effect_name: String, global_pos: Vector2, angle: float, extra_scale: float) -> void:
	_effect = effect_name
	_angle = angle
	_extra_scale = extra_scale
	global_position = global_pos
	z_index = 9
	_max_life = maxf(_EffectSprites.anim_duration(effect_name), 0.08)
	if _EffectSprites.anim_loops(effect_name):
		_max_life = minf(_max_life, 0.35)


func _process(delta: float) -> void:
	_time += delta
	if _time >= _max_life:
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	_EffectSprites.draw_effect(self, _effect, _time, _angle, _extra_scale)
