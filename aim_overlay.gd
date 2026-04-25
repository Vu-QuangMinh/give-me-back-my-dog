extends Node2D

var trajectory : Array = []

func _draw() -> void:
	for i in range(trajectory.size()):
		var seg = trajectory[i]
		var col = Color(0.35, 0.65, 1.0, 0.85) if i == 0 else Color(0.60, 0.80, 1.0, 0.50)
		draw_line(seg[0], seg[1], col, 3.0)
		var d = (seg[1] - seg[0]).normalized()
		var p = Vector2(-d.y, d.x)
		draw_line(seg[1] - d * 12 + p * 5, seg[1], col, 2.0)
		draw_line(seg[1] - d * 12 - p * 5, seg[1], col, 2.0)
