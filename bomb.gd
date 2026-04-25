extends Node2D

func _draw() -> void:
	draw_circle(Vector2.ZERO, 12, Color(0.9, 0.75, 0.1))
	draw_circle(Vector2.ZERO, 12, Color(0.55, 0.40, 0.0), false, 2.0)
	draw_line(Vector2(7, -7), Vector2(13, -13), Color(0.85, 0.35, 0.0), 2.5)
