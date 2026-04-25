extends Node2D

# Drag-timing bar for Mike's slingshot.
# Bar rotates to match the locked shot direction.
# Ball oscillates around a drag-controlled center.
# Resolved on left-click release (not SPACE).

signal timing_resolved(result: String)

const BAR_W            = 130.0
const BAR_H            = 20.0
const OSC_WIDTH_START  = 0.00    # initial ± oscillation amplitude (very small)
const OSC_WIDTH_MAX    = 0.10    # cap after ~10 s of holding
const OSC_GROW_RATE    = 0.01    # amplitude added per second of hold
const OSC_PERIOD       = 1.0     # seconds per full oscillation
const TIMING_LINE      = 0.7
const ZONE_PERFECT     = 0.04
const ZONE_HIT         = 0.08
const RESULT_SHOW_TIME = 0.5

const C_BG      = Color(0.04, 0.04, 0.04)
const C_YELLOW  = Color(0.51, 0.43, 0.08)
const C_GREEN   = Color(0.12, 0.43, 0.20)
const C_GHOST   = Color(0.40, 0.55, 1.00, 0.45)
const C_LINE    = Color(1.00, 1.00, 1.00)
const C_BALL    = Color(1.00, 1.00, 1.00)
const C_OUTLINE = Color(0.70, 0.70, 0.70)

var shot_direction    : Vector2 = Vector2.RIGHT
var drag_start_pixel  : Vector2 = Vector2.ZERO
var drag_center       : float   = 0.05
var osc_time          : float   = 0.0
var ball_pos          : float   = 0.05
var active            : bool    = true
var result            : String  = ""
var result_timer      : float   = 0.0

func setup(shot_dir: Vector2, click_pixel: Vector2) -> void:
	shot_direction   = shot_dir.normalized()
	drag_start_pixel = click_pixel
	drag_center      = 0.05
	ball_pos         = 0.05
	rotation         = shot_direction.angle() + PI

func _process(delta: float) -> void:
	if active:
		osc_time += delta
		var osc_width = clampf(OSC_WIDTH_START + osc_time * OSC_GROW_RATE, OSC_WIDTH_START, OSC_WIDTH_MAX)
		var osc       = sin(osc_time * TAU / OSC_PERIOD) * osc_width
		ball_pos = clampf(drag_center + osc, 0.0, 1.0)
	else:
		result_timer += delta
		if result_timer >= RESULT_SHOW_TIME:
			timing_resolved.emit(result)
			queue_free()
			return
	queue_redraw()

func update_drag(current_mouse: Vector2) -> void:
	if not active: return
	# Dragging backward (opposite to shot_direction) increases center rightward
	var delta_px = current_mouse - drag_start_pixel
	var pull     = -shot_direction.dot(delta_px) / (BAR_W * 2.0)
	drag_center  = clampf(0.05 + pull, 0.05, 0.95)

func update_direction(new_dir: Vector2) -> void:
	if not active: return
	shot_direction = new_dir.normalized()
	rotation       = shot_direction.angle() + PI

func resolve() -> void:
	if not active: return
	active = false
	var dist = absf(ball_pos - TIMING_LINE)
	if   dist <= ZONE_PERFECT: result = "perfect"
	elif dist <= ZONE_HIT:     result = "hit"
	else:                      result = "miss"
	queue_redraw()

func _draw() -> void:
	var bx = -BAR_W / 2.0
	var by = -BAR_H / 2.0

	draw_rect(Rect2(bx, by, BAR_W, BAR_H), C_BG)

	# Yellow hit zone
	var yw = BAR_W * ZONE_HIT * 2.0
	var yx = bx + BAR_W * TIMING_LINE - yw / 2.0
	draw_rect(Rect2(yx, by, yw, BAR_H), C_YELLOW)

	# Green perfect zone
	var gw = BAR_W * ZONE_PERFECT * 2.0
	var gx = bx + BAR_W * TIMING_LINE - gw / 2.0
	draw_rect(Rect2(gx, by, gw, BAR_H), C_GREEN)

	# Timing line
	var lx = bx + BAR_W * TIMING_LINE
	draw_line(Vector2(lx, by), Vector2(lx, by + BAR_H), C_LINE, 2.0)

	# Outline
	draw_rect(Rect2(bx, by, BAR_W, BAR_H), C_OUTLINE, false, 2.0)

	# Ghost: drag_center indicator
	if active:
		var cx = bx + BAR_W * drag_center
		draw_circle(Vector2(cx, 0), 5.0, C_GHOST)

	# Oscillating ball
	var ball_x = bx + BAR_W * ball_pos
	draw_circle(Vector2(ball_x, 0), 7.0, C_BALL)

	# Result color flash
	if result != "":
		var c := Color(0.31, 1.0, 0.51)
		if result == "hit":  c = Color(0.86, 0.86, 0.24)
		if result == "miss": c = Color(1.00, 0.24, 0.24)
		draw_rect(Rect2(bx, by, BAR_W, BAR_H), Color(c.r, c.g, c.b, 0.20))
