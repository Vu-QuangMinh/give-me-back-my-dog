extends Node2D

# ═══════════════════════════════════════════════════════════
#  Projectile visual node
#
#  Main.gd handles all trajectory / collision logic.
#  This script only drives how the ball looks.
#
#  Properties set by main.gd BEFORE add_child():
#    redirect_count  — how many times Sonny perfectly redirected this ball
#                      Each redirect: ball grows 10%, tints more red.
#    is_supercharged — true once redirect_count == 3.
#                      Ball blinks bright red; next hit = AoE explosion.
# ═══════════════════════════════════════════════════════════

var damage          : float = 1.0
var owner_char      : Node  = null
var redirect_count  : int   = 0
var is_supercharged : bool  = false

var _blink_timer : float = 0.0

func _ready() -> void:
	queue_redraw()

func _process(delta: float) -> void:
	if is_supercharged:
		_blink_timer += delta
		if _blink_timer >= 0.18:
			_blink_timer = 0.0
		queue_redraw()

func _draw() -> void:
	var radius := 5.0 * (1.0 + redirect_count * 0.10)
	var color  : Color

	if is_supercharged:
		# Blink between bright red and pale orange
		var blink_on = _blink_timer < 0.09
		color = Color(1.0, 0.08, 0.08, 0.97) if blink_on \
			  else Color(1.0, 0.55, 0.20, 0.97)
	elif redirect_count > 0:
		# Gradually shift from white toward red with each redirect
		var red_t  = minf(1.0, redirect_count * 0.34)
		color = Color(1.0,
					  1.0 - red_t * 0.82,
					  1.0 - red_t * 0.90,
					  0.96)
	else:
		color = Color(1.0, 1.0, 1.0, 0.96)

	draw_circle(Vector2.ZERO, radius, color)
