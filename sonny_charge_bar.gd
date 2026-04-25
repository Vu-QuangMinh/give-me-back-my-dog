extends Node2D

# ═══════════════════════════════════════════════════════════
#  Sonny's Boong Q — Charge Bar
#
#  The bar sits between Sonny and the target tile, rotated
#  parallel to the attack direction.
#    0.0 end = Sonny side (left in local space)
#    1.0 end = target side (right in local space)
#
#  Ball starts at 0.0 and auto-drifts back.
#  Hold left-click → pushes ball toward 1.0.
#  Release left-click → main.gd calls resolve().
#
#  Results:
#    "perfect" — ball_t ≥ THRESH_PERFECT  (green zone)
#    "normal"  — ball_t ≥ THRESH_NORMAL   (yellow zone)
#    "miss"    — ball_t <  THRESH_NORMAL
# ═══════════════════════════════════════════════════════════

signal charge_resolved(result: String)

const BAR_W           = 110.0
const BAR_H           = 18.0
const DRIFT_SPEED     = 0.22   # fraction per second drifting back (auto)
const PUSH_SPEED      = 0.52   # fraction per second when holding click
const THRESH_PERFECT  = 0.85   # ball_t above this = perfect
const THRESH_NORMAL   = 0.65   # ball_t above this = normal
const RESULT_SHOW     = 0.65   # seconds to show result flash before emitting

const C_BG      = Color(0.04, 0.04, 0.06, 0.90)
const C_MISS    = Color(0.22, 0.22, 0.22, 0.85)
const C_YELLOW  = Color(0.55, 0.46, 0.08, 0.88)
const C_GREEN   = Color(0.14, 0.50, 0.22, 0.90)
const C_OUTLINE = Color(0.75, 0.75, 0.75, 0.85)
const C_BALL    = Color(1.00, 1.00, 1.00, 0.96)

var ball_t     : float  = 0.02
var is_holding : bool   = false
var active     : bool   = true
var result     : String = ""
var show_timer : float  = 0.0

# ═══════════════════════════════════════════════
#  SETUP
# ═══════════════════════════════════════════════

## Call right after instantiation.
## shot_angle: angle (radians) of the direction from Sonny → target.
func setup(shot_angle: float) -> void:
	rotation = shot_angle

# ═══════════════════════════════════════════════
#  MAIN LOOP
# ═══════════════════════════════════════════════

func _process(delta: float) -> void:
	if not active:
		show_timer -= delta
		if show_timer <= 0.0:
			charge_resolved.emit(result)
			queue_free()
		return

	if is_holding:
		ball_t = minf(1.0, ball_t + PUSH_SPEED * delta)
	else:
		ball_t = maxf(0.0, ball_t - DRIFT_SPEED * delta)

	queue_redraw()

# ═══════════════════════════════════════════════
#  RESOLVE  (called by main.gd on mouse-button release)
# ═══════════════════════════════════════════════

func resolve() -> void:
	if not active: return
	active = false
	if ball_t >= THRESH_PERFECT:
		result = "perfect"
	elif ball_t >= THRESH_NORMAL:
		result = "normal"
	else:
		result = "miss"
	show_timer = RESULT_SHOW
	queue_redraw()

# ═══════════════════════════════════════════════
#  DRAWING  (bar is horizontal in local space)
# ═══════════════════════════════════════════════

func _draw() -> void:
	var half = BAR_W / 2.0
	var by   = -BAR_H / 2.0

	# Background
	draw_rect(Rect2(-half, by, BAR_W, BAR_H), C_BG)

	# Miss zone (Sonny end = left)
	var miss_w = BAR_W * (1.0 - THRESH_NORMAL)
	# Intentionally: miss zone is the leftmost portion where ball hasn't been charged
	# (visual: whole bar background is miss color by default)
	draw_rect(Rect2(-half, by, BAR_W * (1.0 - THRESH_NORMAL), BAR_H), C_MISS)

	# Normal zone (yellow) — between THRESH_NORMAL and THRESH_PERFECT
	var norm_start = -half + BAR_W * (1.0 - THRESH_NORMAL)
	var norm_w     = BAR_W * (THRESH_PERFECT - THRESH_NORMAL)
	draw_rect(Rect2(norm_start, by, norm_w, BAR_H), C_YELLOW)

	# Perfect zone (green) — near target end (right)
	var perf_w     = BAR_W * (1.0 - THRESH_PERFECT)
	var perf_start = half - perf_w
	draw_rect(Rect2(perf_start, by, perf_w, BAR_H), C_GREEN)

	# Outline
	draw_rect(Rect2(-half, by, BAR_W, BAR_H), C_OUTLINE, false, 1.5)

	# Direction arrows: small ">" marks at each end
	draw_line(Vector2(-half + 4, by + 3),  Vector2(-half + 8, 0),          C_OUTLINE, 1.5)
	draw_line(Vector2(-half + 4, by + BAR_H - 3), Vector2(-half + 8, 0),   C_OUTLINE, 1.5)
	draw_line(Vector2(half - 4,  by + 3),  Vector2(half - 8, 0),           C_GREEN,   1.5)
	draw_line(Vector2(half - 4,  by + BAR_H - 3), Vector2(half - 8, 0),    C_GREEN,   1.5)

	# Ball
	var ball_x = -half + BAR_W * ball_t
	draw_circle(Vector2(ball_x, 0), 7.5, C_BALL)

	# Result flash overlay
	if result != "":
		var fc := Color(0.14, 0.50, 0.22, 0.25)
		if result == "normal": fc = Color(0.55, 0.46, 0.08, 0.25)
		if result == "miss":   fc = Color(0.80, 0.20, 0.20, 0.25)
		draw_rect(Rect2(-half, by, BAR_W, BAR_H), fc)
