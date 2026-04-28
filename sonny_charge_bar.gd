extends Node3D

# ═══════════════════════════════════════════════════════════
#  SonnyChargeBar 3D — Mốc 7.1 (port từ sonny_charge_bar.gd 2D)
#  ► Sonny giữ LMB trên enemy kề bên → ball ĐẨY về phía 1.0
#    (PUSH_SPEED). Thả LMB → main.gd gọi resolve().
#  ► Khi không giữ LMB, ball trôi NGƯỢC về 0.0 (DRIFT_SPEED).
#  ► Resolve:
#      ball_t ≥ THRESH_PERFECT (0.85) → "perfect" (1.5× dmg, +push)
#      ball_t ≥ THRESH_NORMAL  (0.65) → "normal"  (1.0× dmg)
#      else                            → "miss"   (0 dmg)
#  ► Visual cùng pattern DodgeBar: BarRoot (scale 0.20 + tilt 25°) chứa
#    tray + rails + caps + zone overlays + ball; labels ngoài để khỏi scale.
#  ► Spawn = child Camera3D, position (0, -0.18, -1.2) — giống DodgeBar.
# ═══════════════════════════════════════════════════════════

signal charge_resolved(result: String)

# ─── Layout constants (mirror DodgeBar) ───
const SCALE_FACTOR     : float = 0.20
const TILT_X_DEG       : float = 25.0
const TRAY_W           : float = 2.00
const TRAY_H           : float = 0.05
const TRAY_D           : float = 0.40
const RAIL_THICK       : float = 0.04
const RAIL_HEIGHT      : float = 0.08
const ZONE_DEPTH_FRAC  : float = 0.78
const ZONE_THICK       : float = 0.008
const BALL_RADIUS      : float = 0.085

# ─── Charge mechanics ───
const DRIFT_SPEED      : float = 0.22   # ball trôi về 0 khi không hold
const PUSH_SPEED       : float = 0.52   # ball bị đẩy lên khi hold
# Zone widths thu hẹp 30% so với 2D defaults (0.65/0.85):
#   normal range  = 0.06 (was 0.20) → THRESH_NORMAL  = 0.895
#   perfect range = 0.045 (was 0.15) → THRESH_PERFECT = 0.955
# Player phải hold đúng giây cuối để ăn perfect.
const THRESH_PERFECT   : float = 0.955
const THRESH_NORMAL    : float = 0.895
const RESULT_SHOW_TIME : float = 0.65

# ─── State ───
var ball_t     : float  = 0.02
var is_holding : bool   = false
var active     : bool   = true
var result     : String = ""
var show_timer : float  = 0.0

# ─── Mesh refs ───
var bar_root     : Node3D         = null
var ball         : MeshInstance3D = null
var hint_label   : Label3D        = null
var result_label : Label3D        = null

# ═══════════════════════════════════════════════════════════
#  LIFECYCLE
# ═══════════════════════════════════════════════════════════

func _ready() -> void:
	bar_root = Node3D.new()
	bar_root.scale            = Vector3(SCALE_FACTOR, SCALE_FACTOR, SCALE_FACTOR)
	bar_root.rotation_degrees = Vector3(TILT_X_DEG, 0.0, 0.0)
	add_child(bar_root)
	_build_geometry()
	_update_ball_position()

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
	_update_ball_position()

# Gọi từ main.gd khi player thả LMB (hoặc cancel).
func resolve() -> void:
	if not active: return
	active = false
	if   ball_t >= THRESH_PERFECT: result = "perfect"
	elif ball_t >= THRESH_NORMAL:  result = "normal"
	else:                          result = "miss"
	show_timer = RESULT_SHOW_TIME
	_update_labels()

# ═══════════════════════════════════════════════════════════
#  GEOMETRY
# ═══════════════════════════════════════════════════════════

func _build_geometry() -> void:
	# Tray
	_add_box(Vector3(TRAY_W, TRAY_H, TRAY_D), Vector3.ZERO,
		Color(0.16, 0.11, 0.06), false)
	# 2 rail front/back + 2 cap left/right
	var rail_y : float = TRAY_H * 0.5 + RAIL_HEIGHT * 0.5
	_add_box(Vector3(TRAY_W + 0.04, RAIL_HEIGHT, RAIL_THICK),
		Vector3(0.0, rail_y, TRAY_D * 0.5 - RAIL_THICK * 0.5),
		Color(0.30, 0.20, 0.10), false)
	_add_box(Vector3(TRAY_W + 0.04, RAIL_HEIGHT, RAIL_THICK),
		Vector3(0.0, rail_y, -TRAY_D * 0.5 + RAIL_THICK * 0.5),
		Color(0.30, 0.20, 0.10), false)
	_add_box(Vector3(RAIL_THICK, RAIL_HEIGHT, TRAY_D),
		Vector3(TRAY_W * 0.5 + RAIL_THICK * 0.5, rail_y, 0.0),
		Color(0.30, 0.20, 0.10), false)
	_add_box(Vector3(RAIL_THICK, RAIL_HEIGHT, TRAY_D),
		Vector3(-TRAY_W * 0.5 - RAIL_THICK * 0.5, rail_y, 0.0),
		Color(0.30, 0.20, 0.10), false)

	# Zone layout (theo BAR_W = TRAY_W):
	#   miss  : 0.00 → THRESH_NORMAL (0.65)         (gray)
	#   normal: THRESH_NORMAL → THRESH_PERFECT      (yellow)
	#   perfect: THRESH_PERFECT → 1.00              (green)
	var zone_z   : float = TRAY_D * ZONE_DEPTH_FRAC
	var zone_y   : float = TRAY_H * 0.5 + ZONE_THICK * 0.5
	var bx_left  : float = -TRAY_W * 0.5

	var miss_w : float = TRAY_W * THRESH_NORMAL
	_add_box(Vector3(miss_w, ZONE_THICK, zone_z),
		Vector3(bx_left + miss_w * 0.5, zone_y, 0.0),
		Color(0.22, 0.22, 0.22), true)

	var norm_w : float = TRAY_W * (THRESH_PERFECT - THRESH_NORMAL)
	_add_box(Vector3(norm_w, ZONE_THICK, zone_z),
		Vector3(bx_left + TRAY_W * THRESH_NORMAL + norm_w * 0.5, zone_y, 0.0),
		Color(0.78, 0.65, 0.10), true)

	var perf_w : float = TRAY_W * (1.0 - THRESH_PERFECT)
	_add_box(Vector3(perf_w, ZONE_THICK, zone_z),
		Vector3(bx_left + TRAY_W * THRESH_PERFECT + perf_w * 0.5, zone_y, 0.0),
		Color(0.18, 0.65, 0.30), true)

	# Ball — đỏ (Sonny color theme)
	ball = MeshInstance3D.new()
	var ball_mesh := SphereMesh.new()
	ball_mesh.radius          = BALL_RADIUS
	ball_mesh.height          = BALL_RADIUS * 2.0
	ball_mesh.radial_segments = 24
	ball_mesh.rings           = 12
	ball.mesh = ball_mesh
	var ball_mat := StandardMaterial3D.new()
	ball_mat.albedo_color = Color(0.95, 0.20, 0.20)
	ball_mat.metallic     = 0.5
	ball_mat.roughness    = 0.25
	ball.material_override = ball_mat
	bar_root.add_child(ball)

	# Hint label (ngoài bar_root, không scale)
	hint_label = Label3D.new()
	hint_label.text                = "HOLD LMB to charge BOONG!"
	hint_label.font_size           = 48
	hint_label.pixel_size          = 0.0010
	hint_label.outline_size        = 4
	hint_label.outline_modulate    = Color(0, 0, 0, 0.9)
	hint_label.modulate            = Color(1.0, 0.95, 0.55)
	hint_label.position            = Vector3(0, 0.07, 0)
	hint_label.no_depth_test       = true
	hint_label.billboard           = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(hint_label)

	# Result label
	result_label = Label3D.new()
	result_label.text                = ""
	result_label.font_size           = 64
	result_label.pixel_size          = 0.0012
	result_label.outline_size        = 5
	result_label.outline_modulate    = Color(0, 0, 0, 0.95)
	result_label.position            = Vector3(0, 0.13, 0)
	result_label.no_depth_test       = true
	result_label.billboard           = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(result_label)

func _add_box(size: Vector3, pos: Vector3, color: Color, unshaded: bool) -> void:
	var box := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	box.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	if unshaded:
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	box.material_override = mat
	box.position = pos
	bar_root.add_child(box)

func _update_ball_position() -> void:
	if ball == null: return
	var ball_y : float = TRAY_H * 0.5 + BALL_RADIUS
	var ball_x : float = -TRAY_W * 0.5 + TRAY_W * clampf(ball_t, 0.0, 1.0)
	ball.position = Vector3(ball_x, ball_y, 0.0)

func _update_labels() -> void:
	if hint_label:
		hint_label.visible = active
	if result_label:
		result_label.text = _result_text()
		match result:
			"perfect": result_label.modulate = Color(0.31, 1.00, 0.51)
			"normal":  result_label.modulate = Color(0.95, 0.90, 0.30)
			"miss":    result_label.modulate = Color(1.00, 0.30, 0.30)

func _result_text() -> String:
	match result:
		"perfect": return "PERFECT BOONG!"
		"normal":  return "NORMAL HIT"
		"miss":    return "MISS!"
	return ""
