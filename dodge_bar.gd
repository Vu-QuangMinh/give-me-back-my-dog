extends Node2D

# ═══════════════════════════════════════════════
#  CONSTANTS
# ═══════════════════════════════════════════════

const BAR_W            = 130.0
const BAR_H            = 20.0
const BALL_SPEED       = 160.0
const ZONE_PERFECT     = 0.04
const ZONE_DODGE       = 0.08
const RESULT_SHOW_TIME = 0.8

const C_BG      = Color(0.04, 0.04, 0.04)
const C_YELLOW  = Color(0.51, 0.43, 0.08)
const C_GREEN   = Color(0.12, 0.43, 0.20)
const C_LINE    = Color(1.00, 1.00, 1.00)
const C_BALL    = Color(1.00, 1.00, 1.00)
const C_OUTLINE = Color(0.70, 0.70, 0.70)

# ═══════════════════════════════════════════════
#  STATE
# ═══════════════════════════════════════════════

var dodge_line   : float  = 0.75   # set by setup() before _ready()
var speed_mult   : float  = 1.0
var zone_perfect : float  = ZONE_PERFECT
var zone_dodge   : float  = ZONE_DODGE
var ball_t       : float  = 0.0
var active       : bool   = true
var space_used   : bool   = false
var result       : String = ""
var result_timer : float  = 0.0

# ═══════════════════════════════════════════════
#  SIGNALS
# ═══════════════════════════════════════════════

signal bar_finished(result: String)

# ═══════════════════════════════════════════════
#  LABELS
# ═══════════════════════════════════════════════

var hint_label   : Label = null
var result_label : Label = null

# ═══════════════════════════════════════════════
#  LIFECYCLE
# ═══════════════════════════════════════════════

func setup(line_pos: float, speed: float = 1.0, zp: float = ZONE_PERFECT, zd: float = ZONE_DODGE) -> void:
	dodge_line   = line_pos
	speed_mult   = max(0.1, speed)
	zone_perfect = zp
	zone_dodge   = zd

func _ready() -> void:
	hint_label            = $HintLabel
	result_label          = $ResultLabel
	result_label.text     = ""
	hint_label.position   = Vector2(-65, -36)
	result_label.position = Vector2(-65, -52)
	_update_labels()

# ═══════════════════════════════════════════════
#  MAIN LOOP
# ═══════════════════════════════════════════════

func _process(delta: float) -> void:
	if active:
		# Advance ball
		ball_t += (BALL_SPEED * speed_mult / BAR_W) * delta
		if ball_t >= 1.0:
			ball_t = 1.0
			active = false
			if result == "":
				result = "hit"   # ball reached end — auto hit
			_update_labels()
	else:
		# Show result briefly then finish
		result_timer += delta
		if result_timer >= RESULT_SHOW_TIME:
			bar_finished.emit(result)
			queue_free()
			return   # stop processing after freeing

	queue_redraw()

# ═══════════════════════════════════════════════
#  INPUT
# ═══════════════════════════════════════════════

func _input(event: InputEvent) -> void:
	# Only accept SPACE while bar is active and not already pressed
	if not active or space_used: return
	if event is InputEventKey:
		if event.keycode == KEY_SPACE and event.pressed:
			_resolve()

# ═══════════════════════════════════════════════
#  RESOLVE DODGE
# ═══════════════════════════════════════════════

func _resolve() -> void:
	space_used = true
	active     = false
	var dist   = abs(ball_t - dodge_line)
	if   dist <= zone_perfect: result = "perfect"
	elif dist <= zone_dodge:   result = "dodged"
	else:                      result = "hit"
	_update_labels()
	queue_redraw()

# ═══════════════════════════════════════════════
#  LABELS
# ═══════════════════════════════════════════════

func _update_labels() -> void:
	if not hint_label or not result_label: return
	hint_label.visible = active and not space_used
	if result != "":
		result_label.text = _result_text()
		match result:
			"perfect": result_label.modulate = Color(0.31, 1.00, 0.51)
			"dodged":  result_label.modulate = Color(0.86, 0.86, 0.24)
			"hit":     result_label.modulate = Color(1.00, 0.24, 0.24)

func _result_text() -> String:
	match result:
		"perfect": return "PERFECT!  +Empower"
		"dodged":  return "DODGED!"
		"hit":     return "HIT!  -1 HP"
	return ""

# ═══════════════════════════════════════════════
#  DRAWING
# ═══════════════════════════════════════════════

func _draw() -> void:
	var bx = -BAR_W / 2.0
	var by = -BAR_H / 2.0

	# Background
	draw_rect(Rect2(bx, by, BAR_W, BAR_H), C_BG)

	# Yellow dodge zone
	var yw = BAR_W * zone_dodge * 2.0
	var yx = bx + BAR_W * dodge_line - yw / 2.0
	draw_rect(Rect2(yx, by, yw, BAR_H), C_YELLOW)

	# Green perfect zone
	var gw = BAR_W * zone_perfect * 2.0
	var gx = bx + BAR_W * dodge_line - gw / 2.0
	draw_rect(Rect2(gx, by, gw, BAR_H), C_GREEN)

	# Dodge line
	var lx = bx + BAR_W * dodge_line
	draw_line(Vector2(lx, by), Vector2(lx, by + BAR_H), C_LINE, 2.0)

	# Bar outline
	draw_rect(Rect2(bx, by, BAR_W, BAR_H), C_OUTLINE, false, 2.0)

	# Moving ball
	var ball_x = bx + BAR_W * min(ball_t, 1.0)
	draw_circle(Vector2(ball_x, 0), 7.0, C_BALL)

	# Result color overlay
	if result != "":
		var c = Color(0.31, 1.0, 0.51)
		if result == "dodged": c = Color(0.86, 0.86, 0.24)
		if result == "hit":    c = Color(1.00, 0.24, 0.24)
		draw_rect(Rect2(bx, by, BAR_W, BAR_H), Color(c.r, c.g, c.b, 0.15))
