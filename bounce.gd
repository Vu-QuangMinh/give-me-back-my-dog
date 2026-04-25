class_name BounceTracer
extends RefCounted

## Physics-simulation projectile path tracer.
## Simulates exponential speed decay at 60 fps, matching the real projectile exactly.
## Used only for Mike's aim preview — real projectiles move in main.gd _process().
##
## Setup:
##   var t            = BounceTracer.new()
##   t.bounds         = grid_pixel_bounds   # Rect2 map walls
##   t.columns        = column_tiles        # Dictionary[Vector2i, Any]
##   t.entities       = entity_map          # Dictionary[Vector2i, Any]
##   t.launch_speed   = PROJ_LAUNCH_SPEED
##   t.decay_rate     = PROJ_DECAY_RATE
##   t.min_speed      = PROJ_MIN_SPEED
##   t.negative_bounce = PROJ_NEGATIVE_BOUNCE
##   t.hex_to_pixel   = func(c,r) -> Vector2
##   t.pixel_to_hex   = func(v)   -> Vector2i
##
## Returns: {segs: Array[[Vector2,Vector2]], hit_hexes: Array[Vector2i]}

const SIM_DT       : float = 1.0 / 60.0
const MAX_SIM_SECS : float = 12.0

var bounds          : Rect2      = Rect2()
var columns         : Dictionary = {}
var entities        : Dictionary = {}
var step            : float      = 8.0   # unused, kept for API compatibility
var hex_to_pixel    : Callable
var pixel_to_hex    : Callable

var launch_speed    : float = 600.0
var decay_rate      : float = 0.85
var min_speed       : float = 18.0
var negative_bounce : float = 200.0


func trace(start: Vector2, direction: Vector2,
		_bounce_count: int = 1, stop_on_hit: bool = true,
		exclude_hexes: Dictionary = {}) -> Dictionary:

	var segs         : Array    = []
	var hit_hexes    : Array    = []
	var pos          : Vector2  = start
	var dir          : Vector2  = direction.normalized()
	var speed        : float    = launch_speed
	var seg_start    : Vector2  = start
	var ents_hit     : Dictionary = {}
	var sim_time     : float    = 0.0
	var last_col_hex : Vector2i = Vector2i(-9999, -9999)

	while sim_time < MAX_SIM_SECS:
		speed    *= exp(-decay_rate * SIM_DT)
		sim_time += SIM_DT

		if speed < min_speed:
			segs.append([seg_start, pos])
			break

		var new_pos : Vector2 = pos + dir * speed * SIM_DT

		# ── Wall ─────────────────────────────────────────────────
		if not bounds.has_point(new_pos):
			var normal = _wall_normal(new_pos)
			segs.append([seg_start, pos])
			dir          = dir.bounce(normal)
			speed       -= negative_bounce
			seg_start    = pos
			last_col_hex = Vector2i(-9999, -9999)
			if speed < min_speed:
				break
			continue

		pos = new_pos
		var cur_hex : Vector2i = pixel_to_hex.call(pos)

		# ── Column ───────────────────────────────────────────────
		if (cur_hex in columns) and cur_hex != last_col_hex:
			var col_center : Vector2 = hex_to_pixel.call(cur_hex.x, cur_hex.y)
			var n : Vector2 = pos - col_center
			n = n.normalized() if n.length_squared() > 0.01 else Vector2.UP
			segs.append([seg_start, pos])
			dir          = dir.bounce(n)
			speed       -= negative_bounce
			seg_start    = pos
			last_col_hex = cur_hex
			if speed < min_speed:
				break
			continue
		if cur_hex not in columns:
			last_col_hex = Vector2i(-9999, -9999)

		# ── Entity ───────────────────────────────────────────────
		if (cur_hex in entities) and not (cur_hex in ents_hit) and not (cur_hex in exclude_hexes):
			ents_hit[cur_hex] = true
			hit_hexes.append(cur_hex)
			if stop_on_hit:
				segs.append([seg_start, pos])
				break
			var ent_center : Vector2 = hex_to_pixel.call(cur_hex.x, cur_hex.y)
			var n : Vector2 = pos - ent_center
			n = n.normalized() if n.length_squared() > 0.01 else Vector2.UP
			segs.append([seg_start, pos])
			dir       = dir.bounce(n)
			speed    -= negative_bounce
			seg_start = pos
			if speed < min_speed:
				break

	if segs.is_empty():
		segs.append([seg_start, pos])

	return {segs = segs, hit_hexes = hit_hexes}


func _wall_normal(pos: Vector2) -> Vector2:
	var n := Vector2.ZERO
	if   pos.x < bounds.position.x:                          n.x =  1.0
	elif pos.x > bounds.position.x + bounds.size.x:          n.x = -1.0
	if   pos.y < bounds.position.y:                          n.y =  1.0
	elif pos.y > bounds.position.y + bounds.size.y:          n.y = -1.0
	return n.normalized() if n != Vector2.ZERO else Vector2.RIGHT
