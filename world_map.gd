extends Node2D

# ─── Layout ──────────────────────────────────────────────────────────────────
const KM_TOTAL     = 100.0
const MAP_MARGIN_X = 120.0
const MAP_MARGIN_Y = 90.0
const NODE_RADIUS  = 18.0
const Y_KM_RANGE   = 22.0    # ± km vertical scatter → ±half drawable height

# ─── Spawning ────────────────────────────────────────────────────────────────
const MIN_DIST_KM  = 10
const MAX_DIST_KM  = 15
const MIN_APART_KM = 4.5     # minimum Euclidean km between any two nodes
const MAX_RESAMPLE = 25

# Type pool: ~60 % enemy, 10 % each for the rest
const TYPE_POOL = [
	"enemy","enemy","enemy","enemy","enemy","enemy",
	"miniboss","event","fountain","shop"
]

# ─── Colors (all nodes are blue as requested) ────────────────────────────────
const COL_NORMAL  = Color(0.30, 0.55, 1.00)   # blue — unvisited selectable
const COL_VISITED = Color(0.18, 0.28, 0.55)   # dim blue — already cleared
const COL_END     = Color(0.90, 0.25, 0.25)   # red — boss / end stage
const COL_LINE    = Color(0.50, 0.50, 0.50, 0.55)

# ─── State ───────────────────────────────────────────────────────────────────
var nodes        : Array = []   # Array[Dictionary] — see _make_node()
var connections  : Array = []   # Array[{from_id, to_id}]
var current_id   : int   = 0
var minutes_left : int   = 180
var next_id      : int   = 2    # 0 = start, 1 = end stage

# ─── UI ──────────────────────────────────────────────────────────────────────
var timer_label : Label = null
var dist_label  : Label = null

# ─────────────────────────────────────────────────────────────────────────────
func _ready() -> void:
	_load_or_init()
	_build_ui()
	_refresh_ui()
	queue_redraw()

# ─────────────────────────────────────────────────────────────────────────────
#  STATE PERSISTENCE (Engine.meta survives scene changes, not game restarts)
# ─────────────────────────────────────────────────────────────────────────────
func _load_or_init() -> void:
	var just_cleared = false
	if Engine.has_meta("world_map_state"):
		var s = Engine.get_meta("world_map_state")
		just_cleared = s.get("just_cleared", false)
		if s.has("nodes"):
			nodes        = s["nodes"]
			connections  = s["connections"]
			current_id   = s["current_id"]
			minutes_left = s["minutes_left"]
			next_id      = s["next_id"]
		else:
			_init_fresh()
	else:
		_init_fresh()

	if just_cleared:
		_reveal_next_nodes()

	_update_selectable()
	_save_state()

func _init_fresh() -> void:
	next_id = 2
	nodes = [
		_make_node(0, Vector2(0.0,      0.0), "start", true),
		_make_node(1, Vector2(KM_TOTAL, 0.0), "boss",  true),
	]
	nodes[0]["visited"] = true
	connections  = []
	current_id   = 0
	minutes_left = 180

func _save_state() -> void:
	Engine.set_meta("world_map_state", {
		"nodes":        nodes,
		"connections":  connections,
		"current_id":   current_id,
		"minutes_left": minutes_left,
		"next_id":      next_id,
		"just_cleared": false,
	})

func _make_node(id: int, pos_km: Vector2, type: String, revealed: bool) -> Dictionary:
	return {
		"id":         id,
		"pos_km":     pos_km,
		"type":       type,
		"revealed":   revealed,
		"visited":    false,
		"selectable": false,
	}

# ─────────────────────────────────────────────────────────────────────────────
#  NODE SPAWNING
# ─────────────────────────────────────────────────────────────────────────────
func _reveal_next_nodes() -> void:
	var cur_node = _node_by_id(current_id)
	if cur_node.is_empty(): return
	var cur_pos  = cur_node["pos_km"] as Vector2
	var dist_end = cur_pos.distance_to(Vector2(KM_TOTAL, 0.0))

	if dist_end <= 5.0:
		_wire_end_stage()
		return

	var to_spawn = 2
	if dist_end <= 10.0:
		to_spawn = 1
		_wire_end_stage()

	var spawned = 0
	var tries   = 0
	while spawned < to_spawn and tries < 60:
		tries += 1
		var pos = _sample_pos(cur_pos, dist_end)
		if pos == Vector2(-1.0, -1.0): continue
		var n = _make_node(next_id, pos, _pick_type(), true)
		nodes.append(n)
		connections.append({"from_id": current_id, "to_id": next_id})
		next_id += 1
		spawned += 1

func _wire_end_stage() -> void:
	for c in connections:
		if c["from_id"] == current_id and c["to_id"] == 1:
			return
	connections.append({"from_id": current_id, "to_id": 1})

func _sample_pos(from_pos: Vector2, dist_to_end: float) -> Vector2:
	for _r in range(MAX_RESAMPLE):
		var dist  = randf_range(MIN_DIST_KM, minf(MAX_DIST_KM, dist_to_end - 0.5))
		if dist < MIN_DIST_KM: dist = MIN_DIST_KM
		var angle = _weighted_angle_rad()
		var cand  = from_pos + Vector2(cos(angle), sin(angle)) * dist

		if cand.x <= 0.0 or cand.x >= KM_TOTAL: continue
		if absf(cand.y) >= Y_KM_RANGE - 2.0: continue

		var ok = true
		for n in nodes:
			if cand.distance_to(n["pos_km"]) < MIN_APART_KM:
				ok = false; break
		if not ok: continue

		# Soft repulsion density cap — lower threshold = more spread out
		var rep = 0.0
		for n in nodes:
			var d = cand.distance_to(n["pos_km"])
			if d > 0.01: rep += 1.0 / (d * d)
		if rep > 3.5: continue

		return cand
	return Vector2(-1.0, -1.0)

func _weighted_angle_rad() -> float:
	var r    = randf()
	var sign = 1.0 if randf() < 0.5 else -1.0
	var deg: float
	if r < 0.70:
		deg = randf_range(0.0, 45.0)
	elif r < 0.85:
		deg = randf_range(45.0, 90.0)
	else:
		deg = randf_range(90.0, 135.0)
	return deg_to_rad(sign * deg)

func _pick_type() -> String:
	return TYPE_POOL[randi() % TYPE_POOL.size()]

func _update_selectable() -> void:
	for n in nodes:
		n["selectable"] = false
	for c in connections:
		if c["from_id"] == current_id:
			var n = _node_by_id(c["to_id"])
			if not n.is_empty() and not n.get("visited", true):
				n["selectable"] = true

func _node_by_id(id: int) -> Dictionary:
	for n in nodes:
		if n["id"] == id:
			return n
	return {}

# ─────────────────────────────────────────────────────────────────────────────
#  COORDINATE MAPPING
# ─────────────────────────────────────────────────────────────────────────────
func _km_to_screen(pos_km: Vector2) -> Vector2:
	var vp  = get_viewport_rect().size
	var w   = vp.x - MAP_MARGIN_X * 2.0
	var h   = vp.y - MAP_MARGIN_Y * 2.0
	var sx  = MAP_MARGIN_X + (pos_km.x / KM_TOTAL) * w
	var sy  = vp.y * 0.5 + pos_km.y * (h * 0.5 / Y_KM_RANGE)
	return Vector2(sx, sy)

# ─────────────────────────────────────────────────────────────────────────────
#  DRAWING
# ─────────────────────────────────────────────────────────────────────────────
func _draw() -> void:
	# Connection lines (drawn first, under nodes)
	for c in connections:
		var a = _node_by_id(c["from_id"])
		var b = _node_by_id(c["to_id"])
		if a.is_empty() or b.is_empty(): continue
		if not b.get("revealed", false): continue
		draw_line(_km_to_screen(a["pos_km"]), _km_to_screen(b["pos_km"]), COL_LINE, 2.0)

	# Nodes
	var font = ThemeDB.fallback_font
	for n in nodes:
		if not n.get("revealed", false): continue
		var p       = _km_to_screen(n["pos_km"])
		var visited = n.get("visited", false)
		var sel     = n.get("selectable", false)
		var is_cur  = (n["id"] == current_id)
		var is_end  = (n["id"] == 1)

		# Soft white glow on selectable nodes
		if sel:
			draw_circle(p, NODE_RADIUS + 5.0, Color(1.0, 1.0, 1.0, 0.22))

		# Gold ring on current position
		if is_cur:
			draw_circle(p, NODE_RADIUS + 5.0, Color(0.95, 0.85, 0.20, 0.80), false, 3.0)

		# Fill
		var col = COL_END if is_end else (COL_VISITED if visited else COL_NORMAL)
		draw_circle(p, NODE_RADIUS, col)

		# Single-char label inside the circle
		var lbl = _type_letter(n["type"])
		draw_string(font, p + Vector2(-5.0, 5.0), lbl,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.WHITE)

func _type_letter(t: String) -> String:
	match t:
		"start":    return "S"
		"boss":     return "!"
		"enemy":    return "E"
		"miniboss": return "M"
		"event":    return "?"
		"fountain": return "H"
		"shop":     return "$"
	return "?"

# ─────────────────────────────────────────────────────────────────────────────
#  INPUT — click a selectable node to enter combat
# ─────────────────────────────────────────────────────────────────────────────
func _input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton): return
	if not (event.button_index == MOUSE_BUTTON_LEFT and event.pressed): return

	for n in nodes:
		if not n.get("selectable", false): continue
		if event.position.distance_to(_km_to_screen(n["pos_km"])) <= NODE_RADIUS + 5.0:
			_enter_node(n)
			return

func _enter_node(n: Dictionary) -> void:
	var old_id = current_id

	# Deduct travel time: 1 min per 2 km
	var cur = _node_by_id(current_id)
	if not cur.is_empty():
		var dist_km  = (cur["pos_km"] as Vector2).distance_to(n["pos_km"])
		minutes_left = maxi(0, minutes_left - int(dist_km / 2.0))

	n["visited"]    = true
	n["selectable"] = false
	current_id = n["id"]

	# Hide sibling nodes that were offered but not chosen.
	# Boss node (id=1) is never hidden — just its stale connection is removed;
	# _wire_end_stage() re-connects it from the new position next floor clear.
	var sibling_ids : Array = []
	for c in connections:
		if c["from_id"] == old_id and c["to_id"] != n["id"]:
			sibling_ids.append(c["to_id"])
	for sid in sibling_ids:
		if sid == 1: continue   # boss is always visible
		var sib = _node_by_id(sid)
		if not sib.is_empty():
			sib["revealed"]   = false
			sib["selectable"] = false
	var kept : Array = []
	for c in connections:
		if not (c["from_id"] == old_id and c["to_id"] in sibling_ids):
			kept.append(c)
	connections = kept

	_save_state()
	get_tree().change_scene_to_file("res://main.tscn")

# ─────────────────────────────────────────────────────────────────────────────
#  UI
# ─────────────────────────────────────────────────────────────────────────────
func _build_ui() -> void:
	var vp = get_viewport_rect().size

	timer_label          = Label.new()
	timer_label.position = Vector2(10.0, 10.0)
	timer_label.modulate = Color(1.0, 0.90, 0.30)
	add_child(timer_label)

	dist_label          = Label.new()
	dist_label.position = Vector2(vp.x - 230.0, 10.0)
	dist_label.modulate = Color(0.70, 0.90, 1.00)
	add_child(dist_label)

	var hint          = Label.new()
	hint.text         = "Click a highlighted node to enter combat"
	hint.position     = Vector2(vp.x * 0.5 - 160.0, vp.y - 36.0)
	hint.modulate     = Color(0.60, 0.60, 0.60)
	add_child(hint)

func _refresh_ui() -> void:
	if timer_label:
		timer_label.text = "Time remaining: %d min" % minutes_left
	if dist_label:
		var cur = _node_by_id(current_id)
		if not cur.is_empty():
			var d = (cur["pos_km"] as Vector2).distance_to(Vector2(KM_TOTAL, 0.0))
			dist_label.text = "Distance to end: %.1f km" % d
