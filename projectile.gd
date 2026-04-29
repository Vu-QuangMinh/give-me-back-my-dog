extends Node3D
class_name Projectile3D

# ═══════════════════════════════════════════════════════════
#  Projectile3D — real-time physics projectile
#
#  Moves every frame via _process(). Collision detection is
#  handled externally by main.gd (_process_projectiles).
#
#  Setup (from main.gd):
#    var proj = ProjectileScene.instantiate()
#    proj.proj_speed      = <speed>
#    proj.proj_direction  = <dir>     # normalized XZ
#    proj.proj_damage     = <dmg>
#    proj.negative_bounce = <nb>      # 5.0 player, 9999 enemy
#    proj.owner_node      = <owner>   # null = god-owned
#    proj.uses_decay      = true/false
#    add_child(proj)
#    proj.position = start_pos
# ═══════════════════════════════════════════════════════════

signal projectile_died()

const PROJ_RADIUS : float = 0.16
const DECAY_RATE  : float = 0.85   # must equal PROJECTILE_DECAY_RATE in main.gd
const MIN_SPEED   : float = 0.54   # = 18.0 * 0.03

# ─── Physics (set before adding to scene tree) ────────────
var proj_speed      : float   = 18.0
var proj_direction  : Vector3 = Vector3.ZERO   # normalized, Y=0
var proj_damage     : float   = 1.0
var negative_bounce : float   = 5.0
var owner_node      : Node    = null            # null = god-owned (hits everyone)
var uses_decay      : bool    = true
var redirect_count  : int     = 0
var is_supercharged : bool    = false

# ─── Internal ─────────────────────────────────────────────
var _dead        : bool  = false
var _ball_mat    : StandardMaterial3D = null
var _blink_t     : float = 0.0

# ═══════════════════════════════════════════════════════════
#  LIFECYCLE
# ═══════════════════════════════════════════════════════════

func _ready() -> void:
	_build_visuals()

func _process(delta: float) -> void:
	if _dead: return
	if uses_decay:
		proj_speed *= exp(-DECAY_RATE * delta)
		if proj_speed < MIN_SPEED:
			die()
			return
	position += proj_direction * proj_speed * delta
	if is_supercharged and _ball_mat != null:
		_blink_t += delta
		_ball_mat.emission_energy_multiplier = 3.0 if fmod(_blink_t, 0.2) < 0.1 else 1.0

# ═══════════════════════════════════════════════════════════
#  COLLISION RESPONSES (called by main.gd)
# ═══════════════════════════════════════════════════════════

# Wall or column: reflect direction, subtract speed penalty.
func bounce_off_surface(normal: Vector3) -> void:
	if _dead: return
	proj_direction = proj_direction.bounce(normal).normalized()
	proj_direction.y = 0.0
	proj_speed -= negative_bounce
	if proj_speed < MIN_SPEED:
		die()

# Sonny perfect redirect: new direction toward mouse, speed bonus, god-owned.
func redirect_to(new_dir: Vector3) -> void:
	if _dead: return
	proj_direction = Vector3(new_dir.x, 0.0, new_dir.z).normalized()
	proj_speed    += negative_bounce * 0.5     # speed bonus per §5B
	owner_node     = null                       # god-owned from here on
	redirect_count += 1
	if redirect_count >= 3:
		is_supercharged = true
		_set_supercharged_visuals()

func die() -> void:
	if _dead: return
	_dead = true
	emit_signal("projectile_died")
	queue_free()

# ═══════════════════════════════════════════════════════════
#  VISUALS
# ═══════════════════════════════════════════════════════════

func _build_visuals() -> void:
	var sphere := SphereMesh.new()
	sphere.radius          = PROJ_RADIUS
	sphere.height          = PROJ_RADIUS * 2.0
	sphere.radial_segments = 18
	sphere.rings           = 9
	var mi := MeshInstance3D.new()
	mi.mesh = sphere
	_ball_mat = StandardMaterial3D.new()
	_ball_mat.albedo_color               = Color(1.00, 0.95, 0.55)
	_ball_mat.emission_enabled           = true
	_ball_mat.emission                   = Color(1.00, 0.55, 0.10)
	_ball_mat.emission_energy_multiplier = 0.6
	mi.material_override = _ball_mat
	add_child(mi)

	var particles := CPUParticles3D.new()
	particles.amount               = 24
	particles.lifetime             = 0.40
	particles.local_coords         = false
	particles.emitting             = true
	particles.one_shot             = false
	particles.gravity              = Vector3.ZERO
	particles.initial_velocity_min = 0.0
	particles.initial_velocity_max = 0.0
	particles.scale_amount_min     = 0.6
	particles.scale_amount_max     = 1.0
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

func _set_supercharged_visuals() -> void:
	if _ball_mat == null: return
	_ball_mat.albedo_color               = Color(1.0, 0.15, 0.10)
	_ball_mat.emission                   = Color(1.0, 0.10, 0.00)
	_ball_mat.emission_energy_multiplier = 2.0
