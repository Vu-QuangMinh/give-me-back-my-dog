extends Node3D
class_name Campfire

# ═══════════════════════════════════════════════════════════
#  Campfire — đám lửa cháy procedural
#  ► 3 thanh củi (BoxMesh nâu) xếp chéo dưới đáy.
#  ► Flames: CPUParticles3D, sphere emit, gradient vàng → cam → đen,
#    additive blend → glow nhẹ.
#  ► Smoke: CPUParticles3D thứ 2, lifetime dài hơn, drift lên + ngang.
#  ► OmniLight3D màu cam, flicker bằng sin noise trong _process.
# ═══════════════════════════════════════════════════════════

const LOG_COLOR        : Color = Color(0.28, 0.16, 0.08)
const LIGHT_BASE_ENERGY: float = 3.0
const LIGHT_RANGE      : float = 9.0

# Tunable per-instance (set TRƯỚC add_child):
# fire_size_mult: nhân tất cả kích thước (radius emit, particle, light range, ember).
# black_smoke   : gradient khói thành đen → dùng cho lửa cháy xe/dầu/hóa chất.
# no_logs       : bỏ 3 thanh củi (không hợp lý với lửa trên xe).
@export var fire_size_mult : float = 1.0
@export var black_smoke    : bool  = false
@export var no_logs        : bool  = false

var _light     : OmniLight3D = null
var _ember     : MeshInstance3D = null   # core glow always-on
var _flicker_t : float        = 0.0

# Cache texture (cùng 1 cho fire + smoke) — radial gradient soft circle
# để particle quad không hiện đường viền vuông.
var _soft_circle_tex : GradientTexture2D = null

func _ready() -> void:
	_build_soft_circle_texture()
	if not no_logs:
		_build_logs()
	_build_ember_core()
	_build_fire_particles()
	_build_smoke_particles()
	_build_flicker_light()

func _build_soft_circle_texture() -> void:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
	g.colors  = PackedColorArray([
		Color(1, 1, 1, 1.0),     # tâm: trắng đặc
		Color(1, 1, 1, 0.45),    # giữa: bán trong
		Color(1, 1, 1, 0.0),     # rìa: trong suốt → không thấy cạnh quad
	])
	_soft_circle_tex = GradientTexture2D.new()
	_soft_circle_tex.gradient = g
	_soft_circle_tex.fill     = GradientTexture2D.FILL_RADIAL
	_soft_circle_tex.fill_from = Vector2(0.5, 0.5)
	_soft_circle_tex.fill_to   = Vector2(1.0, 0.5)
	_soft_circle_tex.width  = 64
	_soft_circle_tex.height = 64

func _build_logs() -> void:
	# 3 thanh củi xếp xuyên tâm tạo hình "tipi" thấp.
	for i in range(3):
		var box := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.7, 0.09, 0.09)
		box.mesh = bm
		var mat := StandardMaterial3D.new()
		mat.albedo_color = LOG_COLOR
		mat.roughness    = 0.95
		box.material_override = mat
		box.position           = Vector3(0, 0.05, 0)
		box.rotation_degrees   = Vector3(0, i * 60.0, 0)
		add_child(box)

# Glowing core dưới đáy lửa — luôn hiện rõ kể cả khi particle bị pixelate cull.
func _build_ember_core() -> void:
	_ember = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius          = 0.18 * fire_size_mult
	sm.height          = 0.30 * fire_size_mult
	sm.radial_segments = 12
	sm.rings           = 6
	_ember.mesh = sm
	var mat := StandardMaterial3D.new()
	mat.albedo_color    = Color(1.0, 0.55, 0.15)
	mat.emission_enabled = true
	mat.emission        = Color(1.0, 0.55, 0.15)
	mat.emission_energy_multiplier = 3.0
	mat.shading_mode    = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ember.material_override = mat
	_ember.position = Vector3(0, 0.16 * fire_size_mult, 0)
	add_child(_ember)

func _build_fire_particles() -> void:
	var fire := CPUParticles3D.new()
	fire.emitting                = true
	fire.amount                  = 120
	fire.lifetime                = 0.8
	fire.local_coords            = false
	fire.emission_shape          = CPUParticles3D.EMISSION_SHAPE_SPHERE
	fire.emission_sphere_radius  = 0.22 * fire_size_mult
	fire.direction               = Vector3.UP
	fire.spread                  = 22.0
	fire.initial_velocity_min    = 1.2 * fire_size_mult
	fire.initial_velocity_max    = 2.2 * fire_size_mult
	fire.gravity                 = Vector3.ZERO
	fire.scale_amount_min        = 0.5 * fire_size_mult
	fire.scale_amount_max        = 0.9 * fire_size_mult
	# Particle co lại theo lifetime (lửa tan dần khi bay lên).
	var sc := Curve.new()
	sc.add_point(Vector2(0.0, 1.0))
	sc.add_point(Vector2(1.0, 0.15))
	fire.scale_amount_curve = sc
	# Gradient: vàng sáng → cam → đỏ tối → trong suốt.
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.30, 0.70, 1.0])
	grad.colors  = PackedColorArray([
		Color(1.00, 0.95, 0.45, 1.0),
		Color(1.00, 0.55, 0.10, 1.0),
		Color(0.70, 0.15, 0.05, 0.8),
		Color(0.20, 0.05, 0.00, 0.0),
	])
	fire.color_ramp = grad
	# QuadMesh + billboard + radial soft-circle texture → particle là đốm
	# tròn mềm, không thấy đường viền vuông của quad.
	var quad := QuadMesh.new()
	quad.size = Vector2(0.40 * fire_size_mult, 0.40 * fire_size_mult)
	var mat := StandardMaterial3D.new()
	mat.shading_mode     = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency     = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode       = BaseMaterial3D.BLEND_MODE_ADD
	mat.billboard_mode   = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.albedo_color     = Color.WHITE
	mat.albedo_texture   = _soft_circle_tex
	mat.vertex_color_use_as_albedo = true
	quad.material = mat
	fire.mesh = quad
	fire.position.y = 0.10 * fire_size_mult
	add_child(fire)

func _build_smoke_particles() -> void:
	var smoke := CPUParticles3D.new()
	smoke.emitting                = true
	smoke.amount                  = 60 if black_smoke else 30
	smoke.lifetime                = 3.5 if black_smoke else 2.5
	smoke.local_coords            = false
	smoke.emission_shape          = CPUParticles3D.EMISSION_SHAPE_SPHERE
	smoke.emission_sphere_radius  = 0.10 * fire_size_mult
	smoke.direction               = Vector3.UP
	smoke.spread                  = 18.0
	smoke.initial_velocity_min    = 0.4 * fire_size_mult
	smoke.initial_velocity_max    = 0.8 * fire_size_mult
	smoke.gravity                 = Vector3(0.15, 0.25, 0.0)   # drift lên + nghiêng
	smoke.scale_amount_min        = 0.5 * fire_size_mult
	smoke.scale_amount_max        = 1.0 * fire_size_mult
	# Khói nở rộng theo lifetime.
	var sc := Curve.new()
	sc.add_point(Vector2(0.0, 0.35))
	sc.add_point(Vector2(1.0, 1.6))
	smoke.scale_amount_curve = sc
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	if black_smoke:
		grad.colors = PackedColorArray([
			Color(0.04, 0.04, 0.04, 0.92),
			Color(0.02, 0.02, 0.02, 0.55),
			Color(0.00, 0.00, 0.00, 0.00),
		])
	else:
		grad.colors = PackedColorArray([
			Color(0.30, 0.28, 0.25, 0.55),
			Color(0.18, 0.18, 0.18, 0.30),
			Color(0.08, 0.08, 0.08, 0.00),
		])
	smoke.color_ramp = grad
	var quad := QuadMesh.new()
	quad.size = Vector2(0.55 * fire_size_mult, 0.55 * fire_size_mult)
	var mat := StandardMaterial3D.new()
	mat.shading_mode     = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency     = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode   = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.albedo_color     = Color.WHITE
	mat.albedo_texture   = _soft_circle_tex
	mat.vertex_color_use_as_albedo = true
	quad.material = mat
	smoke.mesh = quad
	smoke.position.y = 0.45 * fire_size_mult  # bay từ phía trên flames
	add_child(smoke)

func _build_flicker_light() -> void:
	_light = OmniLight3D.new()
	_light.position           = Vector3(0, 0.35 * fire_size_mult, 0)
	_light.light_color        = Color(1.0, 0.55, 0.20)
	_light.light_energy       = LIGHT_BASE_ENERGY
	_light.omni_range         = LIGHT_RANGE * fire_size_mult
	_light.omni_attenuation   = 1.5
	_light.shadow_enabled     = false
	add_child(_light)

func _process(delta: float) -> void:
	if _light == null: return
	_flicker_t += delta * 9.0
	# 2 sin tần số khác nhau → flicker tự nhiên không đều.
	var noise : float = sin(_flicker_t) * 0.18 + sin(_flicker_t * 1.7 + 0.6) * 0.12
	_light.light_energy = LIGHT_BASE_ENERGY + noise
