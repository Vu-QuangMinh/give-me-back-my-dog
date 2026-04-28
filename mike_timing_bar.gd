extends Node3D

# ═══════════════════════════════════════════════════════════
#  MikeTimingBar 3D — Mốc 8.1 (port từ mike_timing_bar.gd 2D)
#
#  Cơ chế Mike's Draw Shot (đơn giản hóa cho 3D, không có aim mode):
#  ► Click LMB lên enemy có LOS → spawn bar.
#  ► Ball dao động sin quanh drag_center; biên độ tăng dần theo t hold.
#  ► Drag chuột (X-axis) → dịch drag_center 0.0 → 1.0.
#  ► Release LMB → resolve dựa vào |ball_pos - TIMING_LINE|:
#       ≤ ZONE_PERFECT → "perfect" (1.5× dmg)
#       ≤ ZONE_HIT     → "hit"     (1.0× dmg)
#       else           → "miss"    (0 dmg)
#
#  Visual cùng pattern 2 bar trước (BarRoot scale 0.20 + tilt 25°):
#  tray + 2 rails + 2 caps + zone overlays + ball + timing-line.
#  Riêng có thêm "ghost" sphere nhỏ chỉ vị trí drag_center.
# ═══════════════════════════════════════════════════════════

signal timing_resolved(result: String)

# ─── Layout (mirror DodgeBar / SonnyChargeBar) ───
const SCALE_FACTOR     : float = 0.20
const TILT_X_DEG       : float = 25.0
const TRAY_W           : float = 2.00
const TRAY_H           : float = 0.05
const TRAY_D           : float = 0.40
const RAIL_THICK       : float = 0.04
const RAIL_HEIGHT      : float = 0.08
const ZONE_DEPTH_FRAC  : float = 0.78
const ZONE_THICK       : float = 0.008
const LINE_W           : float = 0.014
const BALL_RADIUS      : float = 0.085
const GHOST_RADIUS     : float = 0.05

# ─── Timing mechanics ───
const TIMING_LINE      : float = 0.70    # vị trí cần ball lệch tới
const ZONE_PERFECT     : float = 0.04
const ZONE_HIT         : float = 0.08
const OSC_PERIOD       : float = 1.0     # giây / chu kỳ
const OSC_WIDTH_MAX    : float = 0.18    # biên độ max
const OSC_GROW_RATE    : float = 0.025   # biên độ thêm / giây hold
const DRAG_SCALE       : float = 0.0020  # 1px chuột → drag_center delta
const RESULT_SHOW_TIME : float = 0.55

# ─── State ───
var drag_center  : float   = 0.05
var ball_pos     : float   = 0.05
var osc_time     : float   = 0.0
var drag_anchor  : Vector2 = Vector2.ZERO   # screen pos lúc bắt đầu (set từ main.gd)
var active       : bool    = true
var result       : String  = ""
var result_timer : float   = 0.0

# ─── Mesh refs ───
var bar_root     : Node3D         = null
var ball         : MeshInstance3D = null
var ghost        : MeshInstance3D = null   # marker drag_center
var hint_label   : Label3D        = null
var result_label : Label3D        = null

# ═══════════════════════════════════════════════════════════
#  LIFECYCLE
# ═══════════════════════════════════════════════════════════

# Gọi từ main.gd ngay sau add_child với mouse position lúc click.
func setup(click_pixel: Vector2) -> void:
	drag_anchor = click_pixel
	drag_center = 0.05
	ball_pos    = 0.05

func _ready() -> void:
	bar_root = Node3D.new()
	bar_root.scale            = Vector3(SCALE_FACTOR, SCALE_FACTOR, SCALE_FACTOR)
	bar_root.rotation_degrees = Vector3(TILT_X_DEG, 0.0, 0.0)
	add_child(bar_root)
	_build_geometry()
	_update_ball_position()

func _process(delta: float) -> void:
	if active:
		osc_time += delta
		var osc_w : float = clampf(osc_time * OSC_GROW_RATE, 0.0, OSC_WIDTH_MAX)
		var osc   : float = sin(osc_time * TAU / OSC_PERIOD) * osc_w
		ball_pos = clampf(drag_center + osc, 0.0, 1.0)
		_update_ball_position()
	else:
		result_timer += delta
		if result_timer >= RESULT_SHOW_TIME:
			timing_resolved.emit(result)
			queue_free()

# Gọi từ main.gd khi chuột move (tay đang giữ LMB).
func update_drag(current_mouse: Vector2) -> void:
	if not active: return
	# X-axis delta → đẩy drag_center về phía 1.0
	var dx : float = current_mouse.x - drag_anchor.x
	drag_center = clampf(0.05 + dx * DRAG_SCALE, 0.05, 0.95)

# Gọi từ main.gd khi player thả LMB.
func resolve() -> void:
	if not active: return
	active = false
	var dist : float = absf(ball_pos - TIMING_LINE)
	if   dist <= ZONE_PERFECT: result = "perfect"
	elif dist <= ZONE_HIT:     result = "hit"
	else:                      result = "miss"
	_update_labels()

# ═══════════════════════════════════════════════════════════
#  GEOMETRY
# ═══════════════════════════════════════════════════════════

func _build_geometry() -> void:
	# Tray
	_add_box(Vector3(TRAY_W, TRAY_H, TRAY_D), Vector3.ZERO,
		Color(0.16, 0.11, 0.06), false)
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

	# Yellow hit zone, green perfect zone (đặt giữa TIMING_LINE)
	var zone_z   : float = TRAY_D * ZONE_DEPTH_FRAC
	var zone_y   : float = TRAY_H * 0.5 + ZONE_THICK * 0.5
	var bx_left  : float = -TRAY_W * 0.5
	var line_x   : float = bx_left + TRAY_W * TIMING_LINE
	var yw       : float = TRAY_W * ZONE_HIT * 2.0
	_add_box(Vector3(yw, ZONE_THICK, zone_z),
		Vector3(line_x, zone_y, 0.0), Color(0.78, 0.65, 0.10), true)
	var gw       : float = TRAY_W * ZONE_PERFECT * 2.0
	_add_box(Vector3(gw, ZONE_THICK, zone_z),
		Vector3(line_x, zone_y + ZONE_THICK * 0.6, 0.0),
		Color(0.18, 0.65, 0.30), true)
	# Vạch trắng timing
	_add_box(Vector3(LINE_W, RAIL_HEIGHT * 0.85, TRAY_D * 0.92),
		Vector3(line_x, rail_y - 0.005, 0.0), Color.WHITE, true)

	# Ball — xanh dương để phân biệt với charge bar (vàng cam)
	ball = MeshInstance3D.new()
	var ball_mesh := SphereMesh.new()
	ball_mesh.radius          = BALL_RADIUS
	ball_mesh.height          = BALL_RADIUS * 2.0
	ball_mesh.radial_segments = 24
	ball_mesh.rings           = 12
	ball.mesh = ball_mesh
	var ball_mat := StandardMaterial3D.new()
	ball_mat.albedo_color = Color(0.40, 0.65, 1.00)
	ball_mat.metallic     = 0.5
	ball_mat.roughness    = 0.25
	ball.material_override = ball_mat
	bar_root.add_child(ball)

	# Ghost marker (drag_center) — sphere xanh nhạt nhỏ, semi-transparent
	ghost = MeshInstance3D.new()
	var ghost_mesh := SphereMesh.new()
	ghost_mesh.radius          = GHOST_RADIUS
	ghost_mesh.height          = GHOST_RADIUS * 2.0
	ghost_mesh.radial_segments = 16
	ghost_mesh.rings           = 8
	ghost.mesh = ghost_mesh
	var ghost_mat := StandardMaterial3D.new()
	ghost_mat.albedo_color = Color(0.40, 0.55, 1.00, 0.55)
	ghost_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ghost_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ghost.material_override = ghost_mat
	bar_root.add_child(ghost)

	# Labels (ngoài bar_root, không scale)
	hint_label = Label3D.new()
	hint_label.text                = "DRAG to aim, RELEASE to shoot!"
	hint_label.font_size           = 48
	hint_label.pixel_size          = 0.0010
	hint_label.outline_size        = 4
	hint_label.outline_modulate    = Color(0, 0, 0, 0.9)
	hint_label.modulate            = Color(0.55, 0.85, 1.0)
	hint_label.position            = Vector3(0, 0.07, 0)
	hint_label.no_depth_test       = true
	hint_label.billboard           = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(hint_label)

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
	if ball:
		var by : float = TRAY_H * 0.5 + BALL_RADIUS
		var bx : float = -TRAY_W * 0.5 + TRAY_W * clampf(ball_pos, 0.0, 1.0)
		ball.position = Vector3(bx, by, 0.0)
	if ghost:
		var gy : float = TRAY_H * 0.5 + GHOST_RADIUS + 0.005
		var gx : float = -TRAY_W * 0.5 + TRAY_W * clampf(drag_center, 0.0, 1.0)
		ghost.position = Vector3(gx, gy, TRAY_D * 0.30)   # offset dọc Z để không trùng ball

func _update_labels() -> void:
	if hint_label:
		hint_label.visible = active
	if result_label:
		result_label.text = _result_text()
		match result:
			"perfect": result_label.modulate = Color(0.31, 1.00, 0.51)
			"hit":     result_label.modulate = Color(0.95, 0.90, 0.30)
			"miss":    result_label.modulate = Color(1.00, 0.30, 0.30)

func _result_text() -> String:
	match result:
		"perfect": return "PERFECT SHOT!"
		"hit":     return "HIT"
		"miss":    return "MISS!"
	return ""
