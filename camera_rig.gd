class_name CameraRig
extends Node

# ═══════════════════════════════════════════════════════════
#  CameraRig — orbit camera state + math + control inputs.
#  Holds Camera3D ref + pitch/yaw/distance/anchor.
#  main.gd creates 1 instance, delegates qua _cam.X.
# ═══════════════════════════════════════════════════════════

# ─── Constants ──────────────────────────────────────────────
const PITCH_MIN  : float = 30.0
const PITCH_MAX  : float = 60.0
const PITCH_STEP : float = 1.5
const DIST_MIN   : float = 8.0
const DIST_MAX   : float = 60.0
const DIST_STEP  : float = 1.0
const YAW_DRAG   : float = 0.30
const PITCH_DRAG : float = 0.20
const PAN_SPEED  : float = 10.0
const PAN_BOUND  : float = 25.0
const REF_WIDTH  : float = 1920.0
const REF_HEIGHT : float = 1080.0

# ─── State ──────────────────────────────────────────────────
var camera       : Camera3D = null
var pitch_deg    : float    = 41.0
var yaw_deg      : float    = 180.0
var distance     : float    = 37.0
var anchor       : Vector3  = Vector3.ZERO
var window_zoom  : float    = 1.0
var rmb_dragging : bool     = false

func setup(cam: Camera3D) -> void:
	camera = cam

# ─── Core camera math ───────────────────────────────────────

func update_transform() -> void:
	if camera == null: return
	var p : float = deg_to_rad(pitch_deg)
	var y : float = deg_to_rad(yaw_deg)
	var effective_dist : float = distance / window_zoom
	var offset : Vector3 = Vector3(
		effective_dist * cos(p) * cos(y),
		effective_dist * sin(p),
		effective_dist * cos(p) * sin(y)
	)
	camera.global_position = anchor + offset
	camera.look_at(anchor, Vector3.UP)

func set_anchor(world_pos: Vector3) -> void:
	anchor = Vector3(world_pos.x, 0.0, world_pos.z)
	update_transform()

# Recompute zoom factor từ window size (dùng khi viewport_resized).
func recompute_zoom_factor(size: Vector2) -> void:
	var sx : float = size.x / REF_WIDTH
	var sy : float = size.y / REF_HEIGHT
	window_zoom = maxf(0.05, minf(sx, sy))
	update_transform()

# ─── Adjustment helpers (input dispatchers gọi) ────────────

func adjust_pitch(delta_deg: float) -> void:
	pitch_deg = clampf(pitch_deg + delta_deg, PITCH_MIN, PITCH_MAX)
	update_transform()

func adjust_distance(delta: float) -> void:
	distance = clampf(distance + delta, DIST_MIN, DIST_MAX)
	update_transform()

# RMB-drag → yaw + pitch theo mouse relative.
func handle_rmb_drag(rel: Vector2) -> void:
	yaw_deg = wrapf(yaw_deg + rel.x * YAW_DRAG, -360.0, 360.0)
	pitch_deg = clampf(pitch_deg + rel.y * PITCH_DRAG, PITCH_MIN, PITCH_MAX)
	update_transform()

# Arrow keys pan: dir.x = strafe (-1/+1), dir.y = forward/back (-1/+1).
func pan(dir_2d: Vector2, delta: float) -> void:
	if dir_2d == Vector2.ZERO: return
	var y : float = deg_to_rad(yaw_deg)
	var forward : Vector3 = -Vector3(cos(y), 0, sin(y))
	var right   : Vector3 =  Vector3(sin(y), 0, -cos(y))
	var dir : Vector3 = (forward * -dir_2d.y + right * dir_2d.x).normalized()
	anchor += dir * PAN_SPEED * delta
	anchor.x = clampf(anchor.x, -PAN_BOUND, PAN_BOUND)
	anchor.z = clampf(anchor.z, -PAN_BOUND, PAN_BOUND)
	update_transform()

# ─── Mouse → world ─────────────────────────────────────────

func mouse_to_ground(mouse_pos: Vector2, ground_y: float = 0.2) -> Vector3:
	if camera == null: return Vector3(NAN, NAN, NAN)
	var origin : Vector3 = camera.project_ray_origin(mouse_pos)
	var normal : Vector3 = camera.project_ray_normal(mouse_pos)
	if absf(normal.y) < 0.0001:
		return Vector3(NAN, NAN, NAN)
	var t : float = (ground_y - origin.y) / normal.y
	if t < 0.0:
		return Vector3(NAN, NAN, NAN)
	return origin + normal * t
