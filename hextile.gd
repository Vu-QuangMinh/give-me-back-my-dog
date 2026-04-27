extends Node3D
class_name HexTile

# ═══════════════════════════════════════════════
#  3D hex tile — flat-top prism trên mặt phẳng XZ
#  Đáy ở Y=0, mặt trên ở Y=TILE_HEIGHT.
# ═══════════════════════════════════════════════

enum Type { NORMAL, COLUMN, FIRE_PIT }

const HEX_SIZE        : float = 1.0     # khớp với main.gd
const TILE_HEIGHT     : float = 0.2
const TILE_GAP        : float = 0.0     # 0 = các cạnh áp sát nhau
const COLUMN_HEIGHT   : float = 2.6

const COLOR_NORMAL   = Color(0.42, 0.30, 0.18)   # nâu trung
const COLOR_HOVER    = Color(0.58, 0.43, 0.27)   # nâu sáng
const COLOR_SELECTED = Color(0.30, 0.65, 0.55)   # ngọc xanh — tương phản nâu
const COLOR_VALID    = Color(0.28, 0.55, 0.32)   # xanh lá — ô đi được
const COLOR_ENEMY    = Color(0.50, 0.18, 0.18)   # đỏ gạch
const COLOR_ATTACK   = Color(0.82, 0.26, 0.20)   # đỏ chói — ô tấn công
const COLOR_COLUMN   = Color(0.30, 0.22, 0.14)   # nâu sậm — cột chặn
const COLOR_FIRE_PIT = Color(0.68, 0.32, 0.10)   # cam-đỏ — fire pit
const COLOR_LADDER   = Color(0.45, 0.55, 0.20)   # ô-liu

const COLOR_OUTLINE  = Color(1.0, 1.0, 1.0, 1.0) # viền trắng

var tile_type : Type = Type.NORMAL
var passable  : bool = true
var grid_col  : int  = 0
var grid_row  : int  = 0

var mesh_inst    : MeshInstance3D     = null
var material     : StandardMaterial3D = null
var column_mesh  : MeshInstance3D     = null
var outline_mesh : MeshInstance3D     = null

func _ready() -> void:
	if mesh_inst == null:
		_build_base_mesh()
	if outline_mesh == null:
		_build_outline()

func _build_base_mesh() -> void:
	var cyl := CylinderMesh.new()
	cyl.top_radius      = HEX_SIZE - TILE_GAP
	cyl.bottom_radius   = HEX_SIZE - TILE_GAP
	cyl.height          = TILE_HEIGHT
	cyl.radial_segments = 6
	cyl.rings           = 1

	mesh_inst = MeshInstance3D.new()
	mesh_inst.mesh     = cyl
	mesh_inst.position = Vector3(0.0, TILE_HEIGHT * 0.5, 0.0)
	# Godot's CylinderMesh đặt vertex đầu tiên ở +Z → pointy-top.
	# Xoay 30° quanh Y để thành flat-top khớp với hex math (col-spacing 1.5R).
	mesh_inst.rotation_degrees = Vector3(0.0, 30.0, 0.0)
	add_child(mesh_inst)

	material = StandardMaterial3D.new()
	material.albedo_color      = COLOR_NORMAL
	material.metallic_specular = 0.05
	material.roughness         = 1.0
	mesh_inst.material_override = material

func setup(col: int, row: int, t: Type = Type.NORMAL) -> void:
	grid_col  = col
	grid_row  = row
	tile_type = t
	passable  = (t != Type.COLUMN)
	if mesh_inst == null:
		_build_base_mesh()
	if outline_mesh == null:
		_build_outline()
	_apply_base_color()
	if t == Type.COLUMN and column_mesh == null:
		_build_column_pillar()
	elif t != Type.COLUMN and column_mesh != null:
		column_mesh.queue_free()
		column_mesh = null

func _build_column_pillar() -> void:
	var box := BoxMesh.new()
	box.size = Vector3(HEX_SIZE * 1.4, COLUMN_HEIGHT, HEX_SIZE * 1.4)

	column_mesh = MeshInstance3D.new()
	column_mesh.mesh     = box
	column_mesh.position = Vector3(0.0, TILE_HEIGHT + COLUMN_HEIGHT * 0.5, 0.0)

	var mat := StandardMaterial3D.new()
	mat.albedo_color      = COLOR_COLUMN.darkened(0.15)
	mat.metallic_specular = 0.05
	mat.roughness         = 1.0
	column_mesh.material_override = mat
	add_child(column_mesh)

func _build_outline() -> void:
	# Vòng line-strip 6 cạnh khớp với hex flat-top, nằm sát mặt trên tile
	var R   : float = HEX_SIZE - TILE_GAP
	var H   : float = R * sqrt(3.0) * 0.5
	var y   : float = TILE_HEIGHT + 0.002    # nhô lên xíu để tránh z-fight với top cap

	var verts := PackedVector3Array([
		Vector3( R,    y,  0.0),
		Vector3( R*0.5, y,  H),
		Vector3(-R*0.5, y,  H),
		Vector3(-R,    y,  0.0),
		Vector3(-R*0.5, y, -H),
		Vector3( R*0.5, y, -H),
		Vector3( R,    y,  0.0),   # đóng vòng
	])

	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts

	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_LINE_STRIP, arr)

	outline_mesh      = MeshInstance3D.new()
	outline_mesh.mesh = am

	var mat := StandardMaterial3D.new()
	mat.albedo_color = COLOR_OUTLINE
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	outline_mesh.material_override = mat

	add_child(outline_mesh)

func _apply_base_color() -> void:
	if material == null: return
	match tile_type:
		Type.NORMAL:   material.albedo_color = COLOR_NORMAL
		Type.COLUMN:   material.albedo_color = COLOR_COLUMN
		Type.FIRE_PIT: material.albedo_color = COLOR_FIRE_PIT

# ═══════════════════════════════════════════════
#  STATE — main.gd gọi mỗi khi cần update màu
# ═══════════════════════════════════════════════

func set_state(state: String) -> void:
	# Hazard tiles luôn giữ màu danh tính riêng
	if tile_type == Type.COLUMN or tile_type == Type.FIRE_PIT:
		_apply_base_color()
		return
	if material == null: return
	match state:
		"normal":   material.albedo_color = COLOR_NORMAL
		"hover":    material.albedo_color = COLOR_HOVER
		"selected": material.albedo_color = COLOR_SELECTED
		"valid":    material.albedo_color = COLOR_VALID
		"enemy":    material.albedo_color = COLOR_ENEMY
		"attack":   material.albedo_color = COLOR_ATTACK
		"ladder":   material.albedo_color = COLOR_LADDER
		_:          material.albedo_color = COLOR_NORMAL
