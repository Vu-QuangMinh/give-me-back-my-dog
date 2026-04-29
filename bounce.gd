class_name BounceTracer3D
extends RefCounted

# ═══════════════════════════════════════════════════════════
#  BounceTracer3D — preview simulation for Mike's aim overlay.
#
#  Matches the real projectile physics exactly:
#    - Exponential speed decay
#    - Column / entity bounce: hex-assignment detection;
#      normal = (pos − hex_center).normalized()
#    - Wall (grid bounds) bounce with exact crossing point
# ═══════════════════════════════════════════════════════════

const SIM_DT       : float = 1.0 / 60.0
const MAX_SIM_SECS : float = 6.0

var bounds_min      : Vector3    = Vector3.ZERO
var bounds_max      : Vector3    = Vector3.ZERO
var columns         : Dictionary = {}
var entities        : Dictionary = {}
var hex_to_world    : Callable
var world_to_hex    : Callable

var launch_speed    : float = 18.0
var decay_rate      : float = 0.85
var min_speed       : float = 0.54   # = 18.0 * 0.03 — must match Projectile3D.MIN_SPEED
var negative_bounce : float = 5.0
var hex_size        : float = 1.0    # circumradius of one hex (edge length for regular hex)

func trace(start: Vector3, direction: Vector3,
		stop_on_hit: bool = true,
		exclude_hexes: Dictionary = {}) -> Dictionary:
	var segs         : Array    = []
	var hit_hexes    : Array    = []
	var pos          : Vector3  = Vector3(start.x, start.y, start.z)
	var dir          : Vector3  = Vector3(direction.x, 0.0, direction.z).normalized()
	var speed        : float    = launch_speed
	var seg_start    : Vector3  = pos
	var ents_hit     : Dictionary = {}
	var sim_time     : float    = 0.0
	var last_col_hex : Vector2i = Vector2i(-9999, -9999)

	if dir.length_squared() < 0.0001:
		segs.append([seg_start, pos])
		return { "segs": segs, "hit_hexes": hit_hexes }

	while sim_time < MAX_SIM_SECS:
		speed    *= exp(-decay_rate * SIM_DT)
		sim_time += SIM_DT
		if speed < min_speed:
			segs.append([seg_start, pos])
			break

		var old_pos : Vector3  = pos
		var new_pos : Vector3  = pos + dir * speed * SIM_DT

		# ── Wall (grid boundary) ──────────────────────────────
		if not _in_bounds(new_pos):
			var normal   : Vector3 = _wall_normal(new_pos)
			var crossing : Vector3 = _wall_crossing(pos, new_pos)
			segs.append([seg_start, crossing])
			dir          = dir.bounce(normal).normalized()
			speed       -= negative_bounce
			pos          = crossing
			seg_start    = crossing
			last_col_hex = Vector2i(-9999, -9999)
			if speed < min_speed: break
			continue

		pos = new_pos
		var cur_hex : Vector2i = world_to_hex.call(pos)

		# ── Column ───────────────────────────────────────────
		if cur_hex in columns:
			if cur_hex != last_col_hex:
				last_col_hex = cur_hex
				var col_c : Vector3 = hex_to_world.call(cur_hex.x, cur_hex.y)
				var n : Vector3 = Vector3(pos.x - col_c.x, 0.0, pos.z - col_c.z)
				if n.length_squared() < 0.0001: n = Vector3.FORWARD
				segs.append([seg_start, pos])
				dir       = dir.bounce(n.normalized()).normalized()
				speed    -= negative_bounce
				seg_start = pos
				if speed < min_speed: break
			continue
		last_col_hex = Vector2i(-9999, -9999)

		# ── Entity (enemy / player) ───────────────────────────
		if (cur_hex in entities) and not (cur_hex in ents_hit) and not (cur_hex in exclude_hexes):
			ents_hit[cur_hex] = true
			hit_hexes.append(cur_hex)
			var ent_c : Vector3 = hex_to_world.call(cur_hex.x, cur_hex.y)
			var n : Vector3 = Vector3(pos.x - ent_c.x, 0.0, pos.z - ent_c.z)
			if n.length_squared() < 0.0001: n = Vector3.FORWARD
			segs.append([seg_start, pos])
			if stop_on_hit:
				break
			dir       = dir.bounce(n.normalized()).normalized()
			speed    -= negative_bounce
			seg_start = pos
			if speed < min_speed: break

	if segs.is_empty():
		segs.append([seg_start, pos])
	return { "segs": segs, "hit_hexes": hit_hexes }

# ── Helpers ───────────────────────────────────────────────

# Exact world position where segment old_pos→new_pos first crosses the grid boundary.
func _wall_crossing(old_pos: Vector3, new_pos: Vector3) -> Vector3:
	var t  : float = 1.0
	var dx : float = new_pos.x - old_pos.x
	var dz : float = new_pos.z - old_pos.z
	if dx > 0.0001 and new_pos.x > bounds_max.x:
		t = minf(t, (bounds_max.x - old_pos.x) / dx)
	elif dx < -0.0001 and new_pos.x < bounds_min.x:
		t = minf(t, (bounds_min.x - old_pos.x) / dx)
	if dz > 0.0001 and new_pos.z > bounds_max.z:
		t = minf(t, (bounds_max.z - old_pos.z) / dz)
	elif dz < -0.0001 and new_pos.z < bounds_min.z:
		t = minf(t, (bounds_min.z - old_pos.z) / dz)
	t = clampf(t, 0.0, 1.0)
	return Vector3(old_pos.x + t * dx, old_pos.y, old_pos.z + t * dz)

func _in_bounds(p: Vector3) -> bool:
	return p.x >= bounds_min.x and p.x <= bounds_max.x \
		and p.z >= bounds_min.z and p.z <= bounds_max.z

func _wall_normal(p: Vector3) -> Vector3:
	var n : Vector3 = Vector3.ZERO
	if   p.x < bounds_min.x: n.x =  1.0
	elif p.x > bounds_max.x: n.x = -1.0
	if   p.z < bounds_min.z: n.z =  1.0
	elif p.z > bounds_max.z: n.z = -1.0
	if n.length_squared() < 0.0001:
		return Vector3.RIGHT
	return n.normalized()
