extends Node3D
class_name Projectile3D

# ═══════════════════════════════════════════════════════════
#  Projectile3D — Mốc 8.3.2
#
#  Bay theo path_segs đã pre-compute bởi BounceTracer3D, mỗi seg là
#  [start, end] Vector3 trên XZ plane. Speed = m/s tiêu thụ chiều dài
#  từng seg, sang seg tiếp theo. Hit hexes đã biết từ trace, emit
#  signal khi hit từng hex để main.gd apply damage.
#
#  Setup từ main.gd:
#    var p = ProjectileScene.instantiate()
#    p.segs       = trace_result["segs"]
#    p.hit_hexes  = trace_result["hit_hexes"]
#    p.speed      = 18.0
#    add_child(p)
#    p.position = segs[0][0]   # start
#    var hex = await p.projectile_finished
# ═══════════════════════════════════════════════════════════

signal projectile_finished(hit_hexes: Array)

const DEFAULT_SPEED : float = 18.0
const RADIUS        : float = 0.16

var segs        : Array = []
var hit_hexes   : Array = []
var speed       : float = DEFAULT_SPEED

var _seg_idx       : int   = 0
var _seg_progress  : float = 0.0
var _ball_mesh     : MeshInstance3D = null
var _ready_called  : bool  = false

func _ready() -> void:
	_ball_mesh = MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius          = RADIUS
	sphere.height          = RADIUS * 2.0
	sphere.radial_segments = 18
	sphere.rings           = 9
	_ball_mesh.mesh = sphere
	var mat := StandardMaterial3D.new()
	mat.albedo_color           = Color(1.00, 0.95, 0.55)
	mat.emission_enabled       = true
	mat.emission               = Color(1.00, 0.55, 0.10)
	mat.emission_energy_multiplier = 0.6
	_ball_mesh.material_override = mat
	add_child(_ball_mesh)

	# Trail particles: emit liên tục tại vị trí projectile, local_coords=false
	# nên particles stay world-space khi projectile bay → tạo trail behind ball.
	var particles := CPUParticles3D.new()
	particles.amount                = 24
	particles.lifetime              = 0.40
	particles.local_coords          = false
	particles.emitting              = true
	particles.one_shot              = false
	particles.gravity               = Vector3.ZERO
	particles.initial_velocity_min  = 0.0
	particles.initial_velocity_max  = 0.0
	particles.scale_amount_min      = 0.6
	particles.scale_amount_max      = 1.0
	# Curve scale từ 1 → 0 để particle co lại dần (fake fade)
	var scale_curve := Curve.new()
	scale_curve.add_point(Vector2(0.0, 1.0))
	scale_curve.add_point(Vector2(1.0, 0.0))
	particles.scale_amount_curve = scale_curve
	var trail_sphere := SphereMesh.new()
	trail_sphere.radius          = 0.06
	trail_sphere.height          = 0.12
	trail_sphere.radial_segments = 8
	trail_sphere.rings           = 4
	var trail_mat := StandardMaterial3D.new()
	trail_mat.shading_mode               = BaseMaterial3D.SHADING_MODE_UNSHADED
	trail_mat.albedo_color               = Color(1.00, 0.70, 0.20, 0.85)
	trail_mat.transparency               = BaseMaterial3D.TRANSPARENCY_ALPHA
	trail_mat.emission_enabled           = true
	trail_mat.emission                   = Color(1.00, 0.50, 0.10)
	trail_mat.emission_energy_multiplier = 0.5
	trail_sphere.material  = trail_mat
	particles.mesh         = trail_sphere
	add_child(particles)

	# Đặt position khởi đầu = đầu seg đầu tiên
	if segs.size() > 0:
		var s : Array = segs[0]
		position = s[0]
	_ready_called = true

func _process(delta: float) -> void:
	if not _ready_called: return
	if segs.is_empty():
		emit_signal("projectile_finished", hit_hexes)
		queue_free()
		return
	if _seg_idx >= segs.size():
		emit_signal("projectile_finished", hit_hexes)
		queue_free()
		return

	var seg : Array  = segs[_seg_idx]
	var seg_start : Vector3 = seg[0]
	var seg_end   : Vector3 = seg[1]
	var seg_len   : float   = seg_start.distance_to(seg_end)
	if seg_len < 0.001:
		_seg_idx     += 1
		_seg_progress = 0.0
		return
	_seg_progress += speed * delta
	var t : float = clampf(_seg_progress / seg_len, 0.0, 1.0)
	position = seg_start.lerp(seg_end, t)
	if _seg_progress >= seg_len:
		_seg_idx     += 1
		_seg_progress = 0.0
