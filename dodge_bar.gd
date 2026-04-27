extends Node3D

# ═══════════════════════════════════════════════════════════
#  DodgeBar 3D — Mốc 6.3
#  ► Khay gỗ 3D có viên bi lăn trong rãnh giữa 2 rail.
#  ► Logic giữ y nguyên 2D version: ball lăn trái→phải (theo trục X local),
#    SPACE để freeze, perfect ±zone_perfect, dodge ±zone_dodge, else hit.
#  ► Zone colors / dodge_line / mọi cơ chế đặt vạch — không đổi.
#  ► Visual: BoxMesh tray + 2 rails + zone overlays unshaded + sphere ball.
#  ► Spawn = child của Camera3D với local position = trước mặt + dưới center
#    → bar luôn trong view, không bị scene che.
# ═══════════════════════════════════════════════════════════

# ─── Layout constants (units = mét trong BarRoot local space) ───
# BarRoot có scale = SCALE_FACTOR + tilt; mesh constants giữ ở "size gốc" để dễ đọc.
const SCALE_FACTOR     : float = 0.20   # bar chỉ còn 20% so với original
const TILT_X_DEG       : float = 25.0   # nghiêng top khay về phía camera
const TRAY_W           : float = 2.00   # chiều dài rãnh
const TRAY_H           : float = 0.05   # độ dày tấm khay
const TRAY_D           : float = 0.40   # bề rộng (depth)
const RAIL_THICK       : float = 0.04
const RAIL_HEIGHT      : float = 0.08
const ZONE_DEPTH_FRAC  : float = 0.78   # zone chiếm 78% bề rộng rãnh
const ZONE_THICK       : float = 0.008  # độ cao của zone overlay
const LINE_W           : float = 0.014
const BALL_RADIUS      : float = 0.085
const RESULT_SHOW_TIME : float = 0.7
const BALL_SPEED       : float = 0.85   # tray-widths per second @ speed_mult=1

# ─── State (giống 2D, không đổi) ───
var dodge_line   : float  = 0.75
var speed_mult   : float  = 1.0
var zone_perfect : float  = 0.04
var zone_dodge   : float  = 0.08
var ball_t       : float  = 0.0
var active       : bool   = true
var space_used   : bool   = false
var result       : String = ""
var result_timer : float  = 0.0

signal bar_finished(result: String)

# ─── Mesh refs (build trong _ready) ───
# bar_root: chứa toàn bộ mesh (tray + rails + caps + zones + line + ball),
# scale + tilt apply lên cả khối. Labels thì là con trực tiếp self → không scale.
var bar_root     : Node3D         = null
var ball         : MeshInstance3D = null
var hint_label   : Label3D        = null
var result_label : Label3D        = null

# ─── Setup (gọi trước add_child) ───
func setup(line_pos: float, speed: float = 1.0,
		zp: float = 0.04, zd: float = 0.08) -> void:
	dodge_line   = clampf(line_pos, 0.05, 0.95)
	speed_mult   = max(0.1, speed)
	zone_perfect = zp
	zone_dodge   = zd

func _ready() -> void:
	bar_root = Node3D.new()
	bar_root.scale            = Vector3(SCALE_FACTOR, SCALE_FACTOR, SCALE_FACTOR)
	bar_root.rotation_degrees = Vector3(TILT_X_DEG, 0.0, 0.0)
	add_child(bar_root)
	_build_geometry()
	_update_ball_position()

# ═══════════════════════════════════════════════════════════
#  GEOMETRY BUILD
# ═══════════════════════════════════════════════════════════

func _build_geometry() -> void:
	# Khay (tấm gỗ tối, shaded để có depth feeling)
	_add_box(
		Vector3(TRAY_W, TRAY_H, TRAY_D),
		Vector3.ZERO,
		Color(0.16, 0.11, 0.06),
		false  # shaded
	)
	# 2 rail dọc theo trục X (front + back)
	var rail_y : float = TRAY_H * 0.5 + RAIL_HEIGHT * 0.5
	_add_box(
		Vector3(TRAY_W + 0.04, RAIL_HEIGHT, RAIL_THICK),
		Vector3(0.0, rail_y, TRAY_D * 0.5 - RAIL_THICK * 0.5),
		Color(0.30, 0.20, 0.10),
		false
	)
	_add_box(
		Vector3(TRAY_W + 0.04, RAIL_HEIGHT, RAIL_THICK),
		Vector3(0.0, rail_y, -TRAY_D * 0.5 + RAIL_THICK * 0.5),
		Color(0.30, 0.20, 0.10),
		false
	)
	# 2 cap chặn 2 đầu
	_add_box(
		Vector3(RAIL_THICK, RAIL_HEIGHT, TRAY_D),
		Vector3(TRAY_W * 0.5 + RAIL_THICK * 0.5, rail_y, 0.0),
		Color(0.30, 0.20, 0.10),
		false
	)
	_add_box(
		Vector3(RAIL_THICK, RAIL_HEIGHT, TRAY_D),
		Vector3(-TRAY_W * 0.5 - RAIL_THICK * 0.5, rail_y, 0.0),
		Color(0.30, 0.20, 0.10),
		false
	)

	# Zone vàng (dodge) — overlay trên mặt khay
	var zone_z_extent : float = TRAY_D * ZONE_DEPTH_FRAC
	var zone_top_y    : float = TRAY_H * 0.5 + ZONE_THICK * 0.5
	var line_x        : float = -TRAY_W * 0.5 + TRAY_W * dodge_line
	var yellow_w      : float = TRAY_W * zone_dodge * 2.0
	_add_box(
		Vector3(yellow_w, ZONE_THICK, zone_z_extent),
		Vector3(line_x, zone_top_y, 0.0),
		Color(0.78, 0.65, 0.10),
		true   # unshaded — vibrant
	)
	# Zone xanh (perfect) — đè trên zone vàng (cao hơn 1 chút để tránh z-fight)
	var green_w : float = TRAY_W * zone_perfect * 2.0
	_add_box(
		Vector3(green_w, ZONE_THICK, zone_z_extent),
		Vector3(line_x, zone_top_y + ZONE_THICK * 0.6, 0.0),
		Color(0.18, 0.65, 0.30),
		true
	)
	# Vạch trắng đứng (dodge_line)
	_add_box(
		Vector3(LINE_W, RAIL_HEIGHT * 0.85, TRAY_D * 0.92),
		Vector3(line_x, rail_y - 0.005, 0.0),
		Color.WHITE,
		true
	)

	# Bi lăn — sphere có shading + metallic chút để thấy 3D
	ball = MeshInstance3D.new()
	var ball_mesh := SphereMesh.new()
	ball_mesh.radius          = BALL_RADIUS
	ball_mesh.height          = BALL_RADIUS * 2.0
	ball_mesh.radial_segments = 24
	ball_mesh.rings           = 12
	ball.mesh = ball_mesh
	var ball_mat := StandardMaterial3D.new()
	ball_mat.albedo_color = Color(0.95, 0.95, 0.95)
	ball_mat.metallic     = 0.4
	ball_mat.roughness    = 0.25
	ball.material_override = ball_mat
	bar_root.add_child(ball)

	# Hint label — DIRECT child of self → không bị scale 0.2 / tilt của bar_root.
	# Position relative to self (camera local space), tính theo size NHỎ của bar.
	hint_label = Label3D.new()
	hint_label.text                = "SPACE to Dodge!"
	hint_label.font_size           = 48
	hint_label.pixel_size          = 0.0020
	hint_label.outline_size        = 6
	hint_label.outline_modulate    = Color(0, 0, 0, 0.9)
	hint_label.modulate            = Color(1.0, 0.95, 0.55)
	hint_label.position            = Vector3(0, 0.07, 0)
	hint_label.no_depth_test       = true
	hint_label.billboard           = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(hint_label)

	# Result label — sibling của hint, cao hơn
	result_label = Label3D.new()
	result_label.text                = ""
	result_label.font_size           = 64
	result_label.pixel_size          = 0.0024
	result_label.outline_size        = 8
	result_label.outline_modulate    = Color(0, 0, 0, 0.95)
	result_label.position            = Vector3(0, 0.13, 0)
	result_label.no_depth_test       = true
	result_label.billboard           = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(result_label)

# Helper: thêm 1 BoxMesh node làm con của bar_root (sẽ bị scale + tilt cùng).
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

# ═══════════════════════════════════════════════════════════
#  RUNTIME LOOP
# ═══════════════════════════════════════════════════════════

func _process(delta: float) -> void:
	if active:
		ball_t += BALL_SPEED * speed_mult * delta
		if ball_t >= 1.0:
			ball_t = 1.0
			active = false
			if result == "":
				result = "hit"
			_update_labels()
		_update_ball_position()
	else:
		result_timer += delta
		if result_timer >= RESULT_SHOW_TIME:
			bar_finished.emit(result)
			queue_free()

func _input(event: InputEvent) -> void:
	if not active or space_used: return
	if event is InputEventKey and event.pressed and event.keycode == KEY_SPACE:
		_resolve()
		get_viewport().set_input_as_handled()

func _resolve() -> void:
	space_used = true
	active     = false
	var dist : float = abs(ball_t - dodge_line)
	if   dist <= zone_perfect: result = "perfect"
	elif dist <= zone_dodge:   result = "dodged"
	else:                      result = "hit"
	_update_labels()

func _update_ball_position() -> void:
	if ball == null: return
	var ball_y : float = TRAY_H * 0.5 + BALL_RADIUS
	var ball_x : float = -TRAY_W * 0.5 + TRAY_W * minf(ball_t, 1.0)
	ball.position = Vector3(ball_x, ball_y, 0.0)

func _update_labels() -> void:
	if hint_label:
		hint_label.visible = active and not space_used
	if result_label:
		result_label.text = _result_text()
		match result:
			"perfect": result_label.modulate = Color(0.31, 1.00, 0.51)
			"dodged":  result_label.modulate = Color(0.95, 0.90, 0.30)
			"hit":     result_label.modulate = Color(1.00, 0.30, 0.30)

func _result_text() -> String:
	match result:
		"perfect": return "PERFECT!  +HYPE"
		"dodged":  return "DODGED!  +HYPE"
		"hit":     return "HIT!"
	return ""
