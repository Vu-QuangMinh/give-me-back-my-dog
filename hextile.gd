extends Node3D
class_name HexTile

# ═══════════════════════════════════════════════
#  3D hex tile — flat-top prism trên mặt phẳng XZ
#  Đáy ở Y=0, mặt trên ở Y=TILE_HEIGHT.
# ═══════════════════════════════════════════════

enum Type { NORMAL, COLUMN, FIRE_PIT, GRASS, CEMENT, ASPHALT }

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
const COLOR_MAGE_AIM = Color(0.92, 0.50, 0.10)   # cam — mage aim aura

# Tint nhân với grass/cement/asphalt texture (giữ nét texture nhưng vẫn highlight state).
const COLOR_GRASS_NORMAL   = Color(1.00, 1.00, 1.00)
const COLOR_GRASS_HOVER    = Color(1.20, 1.10, 0.85)
const COLOR_GRASS_SELECTED = Color(0.65, 1.40, 1.20)
const COLOR_GRASS_VALID    = Color(0.75, 1.40, 0.75)
const COLOR_GRASS_ENEMY    = Color(1.40, 0.75, 0.70)
const COLOR_GRASS_ATTACK   = Color(1.60, 0.55, 0.45)

const COLOR_OUTLINE  = Color(1.0, 1.0, 1.0, 1.0) # viền trắng

var tile_type : Type = Type.NORMAL
var passable  : bool = true
var grid_col  : int  = 0
var grid_row  : int  = 0

var mesh_inst    : MeshInstance3D     = null
var material     : StandardMaterial3D = null
var column_mesh  : MeshInstance3D     = null
var outline_mesh : MeshInstance3D     = null
var coord_label  : Label3D            = null

# Static cache: tất cả tile cùng type share 1 ImageTexture (đỡ build N lần).
static var _grass_texture   : ImageTexture = null
static var _cement_texture  : ImageTexture = null
static var _asphalt_texture : ImageTexture = null

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
	if coord_label == null:
		_build_coord_label()
	else:
		coord_label.text = _format_coord(grid_col, grid_row)
	# Texture-based types (GRASS/CEMENT/ASPHALT): gắn procedural texture.
	# Type khác: clear texture.
	if material:
		match t:
			Type.GRASS:   material.albedo_texture = _build_grass_texture()
			Type.CEMENT:  material.albedo_texture = _build_cement_texture()
			Type.ASPHALT: material.albedo_texture = _build_asphalt_texture()
			_:            material.albedo_texture = null
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

# Số thứ tự "<COL_LETTER>,<row>" lên mặt trên ô hex — user dùng để chỉ định
# công việc cho ô cụ thể (vd "ô F,3 đặt cây"). Col → A..L (26 chữ cái cho cols
# 0..25, AA-... cho cols >25). Label3D nằm phẳng (rotation X=-90) trên mặt
# tile, đọc được từ camera pitch ~41°.
func _build_coord_label() -> void:
	coord_label = Label3D.new()
	coord_label.text             = _format_coord(grid_col, grid_row)
	coord_label.font_size        = 64
	coord_label.pixel_size       = 0.005
	coord_label.outline_size     = 6
	coord_label.outline_modulate = Color(0, 0, 0, 0.95)
	coord_label.modulate         = Color(1.0, 1.0, 1.0, 0.95)
	coord_label.no_depth_test    = true
	coord_label.position         = Vector3(0.0, TILE_HEIGHT + 0.005, 0.0)
	coord_label.rotation_degrees = Vector3(-90.0, 0.0, 0.0)   # nằm phẳng trên mặt tile
	add_child(coord_label)

static func _format_coord(col: int, row: int) -> String:
	return "%s,%d" % [_col_to_letter(col), row]

static func _col_to_letter(col: int) -> String:
	if col < 0: return "?"
	if col < 26:
		return String.chr(65 + col)            # A..Z
	# 26+: AA, AB, ... (Excel-style). Grid 12 col hiện chưa cần nhưng để safe.
	return _col_to_letter(col / 26 - 1) + String.chr(65 + (col % 26))

# Procedural grass texture — cellular noise → green color ramp. Build 1 lần,
# share cho mọi grass tile qua static var.
static func _build_grass_texture() -> ImageTexture:
	if _grass_texture != null: return _grass_texture
	var size : int = 64
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_CELLULAR
	noise.frequency  = 0.18
	noise.cellular_distance_function = FastNoiseLite.DISTANCE_EUCLIDEAN_SQUARED
	noise.cellular_return_type       = FastNoiseLite.RETURN_DISTANCE
	noise.seed = 42
	var img : Image = Image.create(size, size, false, Image.FORMAT_RGB8)
	for y in size:
		for x in size:
			var v : float = clampf((noise.get_noise_2d(float(x), float(y)) + 1.0) * 0.5, 0.0, 1.0)
			# Green range: dark → mid-bright. Slight randomness cho speckle.
			var spec : float = randf() * 0.05
			var r : float = 0.18 + v * 0.30 + spec
			var g : float = 0.42 + v * 0.32 + spec
			var b : float = 0.12 + v * 0.18 + spec
			img.set_pixel(x, y, Color(r, g, b))
	_grass_texture = ImageTexture.create_from_image(img)
	return _grass_texture

# Procedural cement / sidewalk — light grey với speckle nhẹ.
static func _build_cement_texture() -> ImageTexture:
	if _cement_texture != null: return _cement_texture
	var size : int = 64
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_VALUE
	noise.frequency  = 0.35
	noise.seed = 11
	var img : Image = Image.create(size, size, false, Image.FORMAT_RGB8)
	for y in size:
		for x in size:
			var v : float = clampf((noise.get_noise_2d(float(x), float(y)) + 1.0) * 0.5, 0.0, 1.0)
			# Light grey base 0.62 + variation ±0.10 + speckle.
			var spec : float = (randf() - 0.5) * 0.04
			var c : float = 0.55 + v * 0.15 + spec
			img.set_pixel(x, y, Color(c, c, c))
	_cement_texture = ImageTexture.create_from_image(img)
	return _cement_texture

# Procedural asphalt / mặt đường — dark grey với pebble noise.
static func _build_asphalt_texture() -> ImageTexture:
	if _asphalt_texture != null: return _asphalt_texture
	var size : int = 64
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_PERLIN
	noise.frequency  = 0.6
	noise.seed = 23
	var img : Image = Image.create(size, size, false, Image.FORMAT_RGB8)
	for y in size:
		for x in size:
			var v : float = clampf((noise.get_noise_2d(float(x), float(y)) + 1.0) * 0.5, 0.0, 1.0)
			# Dark grey base 0.22 + small variation + pebble speckle.
			var spec : float = (randf() - 0.5) * 0.06
			var c : float = 0.18 + v * 0.10 + spec
			img.set_pixel(x, y, Color(c, c, c))
	_asphalt_texture = ImageTexture.create_from_image(img)
	return _asphalt_texture

func _apply_base_color() -> void:
	if material == null: return
	match tile_type:
		Type.NORMAL:   material.albedo_color = COLOR_NORMAL
		Type.COLUMN:   material.albedo_color = COLOR_COLUMN
		Type.FIRE_PIT: material.albedo_color = COLOR_FIRE_PIT
		Type.GRASS:    material.albedo_color = COLOR_GRASS_NORMAL
		Type.CEMENT:   material.albedo_color = COLOR_GRASS_NORMAL    # tint trắng → texture pure
		Type.ASPHALT:  material.albedo_color = COLOR_GRASS_NORMAL

# ═══════════════════════════════════════════════
#  STATE — main.gd gọi mỗi khi cần update màu
# ═══════════════════════════════════════════════

func set_state(state: String) -> void:
	# Hazard tiles luôn giữ màu danh tính riêng
	if tile_type == Type.COLUMN or tile_type == Type.FIRE_PIT:
		_apply_base_color()
		return
	if material == null: return
	# Texture types (GRASS/CEMENT/ASPHALT): tint nhẹ multiplicative để giữ
	# texture rõ nét; same tint dictionary works on bất kỳ base color.
	if tile_type == Type.GRASS or tile_type == Type.CEMENT or tile_type == Type.ASPHALT:
		match state:
			"normal":   material.albedo_color = COLOR_GRASS_NORMAL
			"hover":    material.albedo_color = COLOR_GRASS_HOVER
			"selected": material.albedo_color = COLOR_GRASS_SELECTED
			"valid":    material.albedo_color = COLOR_GRASS_VALID
			"enemy":    material.albedo_color = COLOR_GRASS_ENEMY
			"attack":   material.albedo_color = COLOR_GRASS_ATTACK
			"ladder":   material.albedo_color = COLOR_GRASS_NORMAL
			_:          material.albedo_color = COLOR_GRASS_NORMAL
		return
	match state:
		"normal":   material.albedo_color = COLOR_NORMAL
		"hover":    material.albedo_color = COLOR_HOVER
		"selected": material.albedo_color = COLOR_SELECTED
		"valid":    material.albedo_color = COLOR_VALID
		"enemy":    material.albedo_color = COLOR_ENEMY
		"attack":   material.albedo_color = COLOR_ATTACK
		"ladder":   material.albedo_color = COLOR_LADDER
		"mage_aim": material.albedo_color = COLOR_MAGE_AIM
		_:          material.albedo_color = COLOR_NORMAL
