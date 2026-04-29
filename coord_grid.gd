extends Node3D
class_name CoordGrid

# ═══════════════════════════════════════════════════════════
#  CoordGrid — overlay lưới tọa độ trên mặt sàn để placement debug.
#  ► Lines minor (mỗi 1 unit): xám mờ
#  ► Lines major (mỗi 5 unit): xanh dương đậm hơn
#  ► Trục X = 0  (line dọc theo Z): màu xanh lá
#  ► Trục Z = 0  (line dọc theo X): màu đỏ
#  ► Labels số tọa độ chỉ trên 2 trục chính (z=0 hiện X, x=0 hiện Z) → ít nhiễu
#  ► Toggle bật/tắt: phím F4 (xử lý ở main.gd)
# ═══════════════════════════════════════════════════════════

const HALF_SIZE   : int   = 15      # lưới trải -15..+15
const MAJOR_STEP  : int   = 5
const Y_OFFSET    : float = 0.01    # nằm sát trên mặt nền, dưới hex tile top

const MINOR_COLOR : Color = Color(0.65, 0.85, 1.0, 0.35)
const MAJOR_COLOR : Color = Color(0.30, 0.65, 1.0, 0.85)
const AXIS_X_COL  : Color = Color(1.00, 0.30, 0.30, 0.95)   # đỏ — trục X (z=0)
const AXIS_Z_COL  : Color = Color(0.30, 1.00, 0.30, 0.95)   # xanh lá — trục Z (x=0)

const MINOR_THICK : float = 0.025
const MAJOR_THICK : float = 0.055
const AXIS_THICK  : float = 0.080

func _ready() -> void:
	_build_lines()
	_build_axis_labels()

func _build_lines() -> void:
	# Lines dọc theo X (mỗi giá trị Z) — minor + major + axis
	for z in range(-HALF_SIZE, HALF_SIZE + 1):
		var col : Color
		var thick : float
		if z == 0:
			col = AXIS_X_COL; thick = AXIS_THICK
		elif z % MAJOR_STEP == 0:
			col = MAJOR_COLOR; thick = MAJOR_THICK
		else:
			col = MINOR_COLOR; thick = MINOR_THICK
		_add_line(
			Vector3(-HALF_SIZE, Y_OFFSET, z),
			Vector3( HALF_SIZE, Y_OFFSET, z),
			col, thick)
	# Lines dọc theo Z (mỗi giá trị X)
	for x in range(-HALF_SIZE, HALF_SIZE + 1):
		var col : Color
		var thick : float
		if x == 0:
			col = AXIS_Z_COL; thick = AXIS_THICK
		elif x % MAJOR_STEP == 0:
			col = MAJOR_COLOR; thick = MAJOR_THICK
		else:
			col = MINOR_COLOR; thick = MINOR_THICK
		_add_line(
			Vector3(x, Y_OFFSET, -HALF_SIZE),
			Vector3(x, Y_OFFSET,  HALF_SIZE),
			col, thick)

func _add_line(a: Vector3, b: Vector3, color: Color, thickness: float) -> void:
	var box := MeshInstance3D.new()
	var diff : Vector3 = b - a
	var length : float = diff.length()
	if length < 0.001: return
	var bm := BoxMesh.new()
	# BoxMesh default size (1,1,1) → length theo X, độ dày Z (thin), Y mỏng.
	bm.size = Vector3(length, 0.005, thickness)
	box.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	box.material_override = mat
	box.position = (a + b) * 0.5
	# Nếu line song song trục Z → xoay 90° quanh Y để hộp dài theo Z thay vì X.
	if absf(diff.z) > absf(diff.x):
		box.rotation_degrees = Vector3(0, 90, 0)
	add_child(box)

func _build_axis_labels() -> void:
	# Labels X tại z = 0 (mỗi MAJOR_STEP)
	for x in range(-HALF_SIZE, HALF_SIZE + 1, MAJOR_STEP):
		_add_label(Vector3(x, Y_OFFSET + 0.05, 0.4), "X=%d" % x, AXIS_X_COL)
	# Labels Z tại x = 0 (mỗi MAJOR_STEP)
	for z in range(-HALF_SIZE, HALF_SIZE + 1, MAJOR_STEP):
		_add_label(Vector3(0.4, Y_OFFSET + 0.05, z), "Z=%d" % z, AXIS_Z_COL)

func _add_label(pos: Vector3, text: String, color: Color) -> void:
	var lbl := Label3D.new()
	lbl.text             = text
	lbl.font_size        = 36
	lbl.pixel_size       = 0.006
	lbl.outline_size     = 4
	lbl.outline_modulate = Color(0, 0, 0, 0.95)
	lbl.modulate         = color
	lbl.no_depth_test    = true
	lbl.billboard        = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.position         = pos
	add_child(lbl)
