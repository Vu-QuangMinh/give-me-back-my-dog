class_name BounceTracer3D
extends RefCounted

# ═══════════════════════════════════════════════════════════
#  BounceTracer3D — Mốc 8.3.1 (port từ bounce.gd 2D)
#
#  Pre-compute đường bay của projectile trên XZ plane (Y giữ cố định).
#  Bounce off:
#    - Wall (mép grid: bounds_min/max XZ)
#    - Column hex (vertical cylinder)
#    - Entity hex (player/enemy) — stop_on_hit hoặc bounce
#  Speed giảm theo exponential decay; mỗi bounce trừ negative_bounce.
#
#  Setup:
#    var t = BounceTracer3D.new()
#    t.bounds_min = Vector3(min_x, 0, min_z)
#    t.bounds_max = Vector3(max_x, 0, max_z)
#    t.columns    = column_tiles_dict       # Vector2i → true
#    t.entities   = entity_pos_dict         # Vector2i → true
#    t.hex_to_world = func(c, r) -> Vector3
#    t.world_to_hex = func(p)    -> Vector2i
#    var result = t.trace(start, dir)
#
#  Returns: { segs: Array[[Vector3, Vector3]], hit_hexes: Array[Vector2i] }
# ═══════════════════════════════════════════════════════════

const SIM_DT       : float = 1.0 / 60.0
const MAX_SIM_SECS : float = 6.0

var bounds_min      : Vector3    = Vector3.ZERO
var bounds_max      : Vector3    = Vector3.ZERO
var columns         : Dictionary = {}
var entities        : Dictionary = {}
var hex_to_world    : Callable
var world_to_hex    : Callable

var launch_speed    : float = 18.0   # world units / sec
var decay_rate      : float = 0.85
var min_speed       : float = 1.0
var negative_bounce : float = 5.0    # speed loss per bounce

func trace(start: Vector3, direction: Vector3,
		stop_on_hit: bool = true,
		exclude_hexes: Dictionary = {}) -> Dictionary:
	var segs         : Array     = []
	var hit_hexes    : Array     = []
	var pos          : Vector3   = Vector3(start.x, start.y, start.z)
	var dir          : Vector3   = Vector3(direction.x, 0.0, direction.z).normalized()
	var speed        : float     = launch_speed
	var seg_start    : Vector3   = pos
	var ents_hit     : Dictionary = {}
	var sim_time     : float     = 0.0
	var last_col_hex : Vector2i  = Vector2i(-9999, -9999)

	if dir.length_squared() < 0.0001:
		segs.append([seg_start, pos])
		return { "segs": segs, "hit_hexes": hit_hexes }

	while sim_time < MAX_SIM_SECS:
		speed    *= exp(-decay_rate * SIM_DT)
		sim_time += SIM_DT
		if speed < min_speed:
			segs.append([seg_start, pos])
			break

		var new_pos : Vector3 = pos + dir * speed * SIM_DT

		# ── Wall (mép grid XZ) ────────────────────────────────
		if not _in_bounds(new_pos):
			var normal : Vector3 = _wall_normal(new_pos)
			segs.append([seg_start, pos])
			dir          = dir.bounce(normal).normalized()
			speed       -= negative_bounce
			seg_start    = pos
			last_col_hex = Vector2i(-9999, -9999)
			if speed < min_speed: break
			continue

		pos = new_pos
		var cur_hex : Vector2i = world_to_hex.call(pos)

		# ── Column ───────────────────────────────────────────
		if (cur_hex in columns) and cur_hex != last_col_hex:
			var col_center : Vector3 = hex_to_world.call(cur_hex.x, cur_hex.y)
			var n : Vector3 = Vector3(pos.x - col_center.x, 0.0, pos.z - col_center.z)
			if n.length_squared() < 0.0001:
				n = Vector3.FORWARD
			n = n.normalized()
			segs.append([seg_start, pos])
			dir          = dir.bounce(n).normalized()
			speed       -= negative_bounce
			seg_start    = pos
			last_col_hex = cur_hex
			if speed < min_speed: break
			continue
		if cur_hex not in columns:
			last_col_hex = Vector2i(-9999, -9999)

		# ── Entity (player/enemy) ────────────────────────────
		if (cur_hex in entities) and not (cur_hex in ents_hit) and not (cur_hex in exclude_hexes):
			ents_hit[cur_hex] = true
			hit_hexes.append(cur_hex)
			if stop_on_hit:
				segs.append([seg_start, pos])
				break
			# Bounce off entity
			var ent_center : Vector3 = hex_to_world.call(cur_hex.x, cur_hex.y)
			var n : Vector3 = Vector3(pos.x - ent_center.x, 0.0, pos.z - ent_center.z)
			if n.length_squared() < 0.0001:
				n = Vector3.FORWARD
			n = n.normalized()
			segs.append([seg_start, pos])
			dir       = dir.bounce(n).normalized()
			speed    -= negative_bounce
			seg_start = pos
			if speed < min_speed: break

	if segs.is_empty():
		segs.append([seg_start, pos])
	return { "segs": segs, "hit_hexes": hit_hexes }

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
