class_name RangeOverlay
extends Node2D

var show_ring: bool = false
var center: Vector2 = Vector2.ZERO
var radius: float = 0.0


func _draw() -> void:
	if not show_ring or radius <= 0.0:
		return
	draw_arc(center, radius, 0.0, TAU, 64, Color(0.35, 0.75, 0.95, 0.55), 2.0)
	draw_arc(center, radius, 0.0, TAU, 64, Color(0.35, 0.75, 0.95, 0.12), radius * 0.02)
