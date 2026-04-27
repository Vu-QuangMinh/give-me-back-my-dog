extends Node2D

# ═══════════════════════════════════════════════════════════
#  PRELOADS
# ═══════════════════════════════════════════════════════════

const HexTileScript    = preload("res://hextile.gd")
const HexTile          = preload("res://hextile.tscn")
const PlayerScene      = preload("res://player.tscn")
const EnemyScript      = preload("res://enemy.gd")
const EnemyScene       = preload("res://enemy.tscn")
const DodgeBarScene    = preload("res://dodge_bar.tscn")
const ProjectileScript      = preload("res://projectile.gd")
const MikeTimingBarScript   = preload("res://mike_timing_bar.gd")
const AimOverlayScript      = preload("res://aim_overlay.gd")
const SonnyChargeBarScript  = preload("res://sonny_charge_bar.gd")
const PlayerScript          = preload("res://Player.gd")

# ═══════════════════════════════════════════════════════════
#  CONSTANTS
# ═══════════════════════════════════════════════════════════

const HEX_SIZE     = 38.0
const GRID_COLS    = 12
const GRID_ROWS    = 8
const ACTION_DELAY = 0.5
const TWEEN_SPEED  = 0.18

# ═══════════════════════════════════════════════════════════
#  STATE
# ═══════════════════════════════════════════════════════════

var tiles          : Dictionary = {}
var column_tiles   : Dictionary = {}
var fire_pit_tiles : Dictionary = {}

var players              : Array = []
var player_positions     : Array = []   # populated from CHARACTER_PRESETS
var player_names         : Array = []   # populated from CHARACTER_PRESETS
var current_player_index : int   = 0
var enemies              : Array = []
var valid_moves          : Array = []

enum Phase { PLAYER_TURN, ENEMY_TURN, DODGE_PHASE, DEAD }
var phase        : Phase = Phase.PLAYER_TURN
var action_queue : Array = []
var action_timer : float = 0.0
var floor_cleared : bool = false
var enemy_turn_transition_timer  : float = -1.0
var players_turned_this_round    : Array = []

var attack_committed_this_round : bool       = false
var reset_turn_used             : bool       = false
var turn_snapshot               : Dictionary = {}

var attack_mode  : String = ""
var attack_tiles : Array  = []

# Attack bar
var active_attack_bar   : Node   = null
var pending_attack_mode : String = ""

# Dodge bar
var active_dodge_bar        : Node = null
var dodge_target_player_idx : int  = 0

# Live projectile tracking (Section 5B)
# Each entry: {node, source_idx, source_enemy, damage, speed, direction,
#              uses_decay, negative_bounce, is_god_owned,
#              redirect_count, is_supercharged, elapsed,
#              contact_est {pi:float}, reaction_done {pi:bool}, pass_through {pi:bool},
#              enemies_hit {hex:bool}, done}
var live_proj_states      : Array = []
var _last_proj_source_idx : int   = -1   # source_idx of most-recently-launched proj

# Sonny's charge bar (Boong Q)
var sonny_charging      : bool     = false
var sonny_charge_bar    : Node     = null
var sonny_charge_target : Vector2i = Vector2i.ZERO

# Mike's Draw Shot aiming
var mike_aiming         : bool    = false
var mike_aim_dir        : Vector2 = Vector2.RIGHT
var mike_shot_dir       : Vector2 = Vector2.RIGHT  # locked on left-click
var mike_shot_committed : bool    = false
var mike_timing_bar     : Node    = null
var mike_trajectory     : Array   = []  # [[from, to], ...] for preview draw
var aim_overlay         : Node2D  = null
var grid_pixel_bounds   : Rect2   = Rect2()

# Sonny Bomb (W)
var sonny_bomb_enemy : Node = null
var sonny_w_used     : bool = false
var bomb_mode        : bool = false

# Mike Grapple (W)
var mike_grappling : bool = false
var mike_w_uses    : int  = 1

# Mike caught-projectile bag (max 2; fires after Draw Shot)
var mike_caught_projectiles : Array = []

# ═══════════════════════════════════════════════════════════
#  UI NODES
# ═══════════════════════════════════════════════════════════

var hp_label      : Label = null
var actions_label : Label = null
var q_box_label   : Label = null
var turn_label    : Label = null
var dead_label    : Label = null
var timer_label   : Label = null
var undo_label    : Label = null
var reset_label   : Label = null
var end_turn_confirm_panel : Panel = null

var minutes_left  : int   = 180

# ═══════════════════════════════════════════════════════════
#  LIFECYCLE
# ═══════════════════════════════════════════════════════════

func _ready() -> void:
	if Engine.has_meta("world_map_state"):
		minutes_left = Engine.get_meta("world_map_state").get("minutes_left", 180)
	_build_grid()
	_compute_grid_bounds()
	_spawn_players()
	_spawn_enemies()
	_build_ui()
	_update_valid_moves()
	_refresh_tile_colors()
	_refresh_ui()
	_save_turn_snapshot()
	# Overlay drawn above all other nodes
	aim_overlay = Node2D.new()
	aim_overlay.set_script(AimOverlayScript)
	aim_overlay.z_as_relative = false
	aim_overlay.z_index = 100
	add_child(aim_overlay)

func _compute_grid_bounds() -> void:
	var offset = _grid_center_offset()
	var min_p  = Vector2(INF, INF)
	var max_p  = Vector2(-INF, -INF)
	for key in tiles:
		var p = _hex_to_pixel(key.x, key.y) + offset
		min_p.x = minf(min_p.x, p.x)
		min_p.y = minf(min_p.y, p.y)
		max_p.x = maxf(max_p.x, p.x)
		max_p.y = maxf(max_p.y, p.y)
	# Hex corners at 0°,60°,…: extends HEX_SIZE horizontally (pointy L/R) and
	# HEX_SIZE*sqrt(3)/2 vertically (flat top/bottom) from each center.
	var pad_x = HEX_SIZE
	var pad_y = HEX_SIZE * sqrt(3.0) / 2.0
	grid_pixel_bounds = Rect2(min_p - Vector2(pad_x, pad_y), max_p - min_p + Vector2(pad_x * 2, pad_y * 2))

# ═══════════════════════════════════════════════════════════
#  GRID BUILDING
# ═══════════════════════════════════════════════════════════

func _build_grid() -> void:
	var offset = _grid_center_offset()
	for col in range(GRID_COLS):
		for row in range(GRID_ROWS):
			var key  = Vector2i(col, row)
			var tile = HexTile.instantiate()
			add_child(tile)
			tile.setup(col, row, HexTileScript.Type.NORMAL)
			tile.position = _hex_to_pixel(col, row) + offset
			tiles[key] = tile

# ═══════════════════════════════════════════════════════════
#  ENTITY SPAWNING
# ═══════════════════════════════════════════════════════════

func _spawn_players() -> void:
	var offset = _grid_center_offset()
	for preset_name in PlayerScript.PLAYER_ORDER:
		var p = PlayerScene.instantiate()
		add_child(p)
		p.setup_from_preset(preset_name)
		player_names.append(preset_name)
		player_positions.append(Vector2i(p.grid_col, p.grid_row))
		p.position = _hex_to_pixel(p.grid_col, p.grid_row) + offset
		players.append(p)

func _spawn_enemies() -> void:
	var points = _get_spawn_points(2)
	for i in range(mini(2, points.size())):
		_spawn_enemy("grunt", points[i].x, points[i].y)

func _spawn_enemy(type_key: String, col: int, row: int) -> Node:
	var preset = EnemyScript.ENEMY_PRESETS[type_key]
	var enemy  = EnemyScene.instantiate()
	enemy.enemy_type       = preset.get("enemy_type",       type_key)
	enemy.display_label    = preset.get("display_label",    "?")
	enemy.max_hp           = preset.get("max_hp",           3)
	enemy.actions_per_turn = preset.get("actions_per_turn", 2)
	enemy.move_range       = preset.get("move_range",       2)
	enemy.body_color       = preset.get("body_color",       Color.WHITE)
	enemy.behavior         = preset.get("behavior",         EnemyScript.Behavior.AGGRESSIVE)
	enemy.immovable        = preset.get("immovable",        false)
	enemy.range_min        = preset.get("range_min",        2)
	enemy.range_max        = preset.get("range_max",        5)
	enemy.attacks          = preset.get("attacks",          [])
	add_child(enemy)
	enemy.setup(col, row)
	enemy.position = _hex_to_pixel(col, row) + _grid_center_offset()
	enemies.append(enemy)
	return enemy

func _get_spawn_points(count: int) -> Array:
	var candidates : Array = []
	for key in tiles:
		var too_close = false
		for pp in player_positions:
			if _hex_dist(key.x, key.y, pp.x, pp.y) < 4:
				too_close = true
				break
		if not too_close:
			candidates.append(key)
	candidates.shuffle()
	return candidates.slice(0, count)

# ═══════════════════════════════════════════════════════════
#  HEX MATH
# ═══════════════════════════════════════════════════════════

func _hex_to_pixel(col: int, row: int) -> Vector2:
	var x = HEX_SIZE * 1.5 * col
	var y = HEX_SIZE * sqrt(3.0) * (row + (0.5 if col % 2 == 1 else 0.0))
	return Vector2(x, y)

func _grid_center_offset() -> Vector2:
	var min_p = Vector2(INF, INF)
	var max_p = Vector2(-INF, -INF)
	for col in range(GRID_COLS):
		for row in range(GRID_ROWS):
			var p = _hex_to_pixel(col, row)
			min_p = min_p.min(p)
			max_p = max_p.max(p)
	var grid_center = (min_p + max_p) / 2.0
	return get_viewport_rect().size / 2.0 - grid_center

func _hex_dist(c1: int, r1: int, c2: int, r2: int) -> int:
	var to_cube = func(c, r):
		var x = c
		var z = r - (c - (c & 1)) / 2
		return Vector3i(x, -x - z, z)
	var a = to_cube.call(c1, r1)
	var b = to_cube.call(c2, r2)
	return maxi(maxi(abs(a.x - b.x), abs(a.y - b.y)), abs(a.z - b.z))

func _get_neighbors(col: int, row: int) -> Array:
	var dirs = [[1,0],[-1,0],[0,-1],[0,1],[1,-1],[-1,-1]] if col % 2 == 0 \
			 else [[1,0],[-1,0],[0,-1],[0,1],[1,1],[-1,1]]
	var result : Array = []
	for d in dirs:
		var nc = col + d[0]
		var nr = row + d[1]
		if nc >= 0 and nc < GRID_COLS and nr >= 0 and nr < GRID_ROWS:
			result.append(Vector2i(nc, nr))
	return result

func _pixel_to_hex(pixel: Vector2) -> Vector2i:
	var offset    = _grid_center_offset()
	var best_pos  = Vector2i(0, 0)
	var best_dist = INF
	for key in tiles:
		var tile_px = _hex_to_pixel(key.x, key.y) + offset
		var d = pixel.distance_to(tile_px)
		if d < best_dist:
			best_dist = d
			best_pos  = key
	return best_pos

func is_valid_and_passable(col: int, row: int) -> bool:
	var key = Vector2i(col, row)
	if not tiles.has(key):  return false
	if key in column_tiles: return false
	return true

# ═══════════════════════════════════════════════════════════
#  MOVEMENT & BFS
# ═══════════════════════════════════════════════════════════

func _update_valid_moves() -> void:
	var blocked : Dictionary = {}
	for key in column_tiles:
		blocked[key] = true
	for e in enemies:
		blocked[Vector2i(e.grid_col, e.grid_row)] = true
	for i in range(players.size()):
		if i != current_player_index:
			blocked[player_positions[i]] = true

	valid_moves = []
	var start_pos = player_positions[current_player_index]
	var visited   = {start_pos: true}
	var frontier  = [[start_pos, 0]]

	while frontier.size() > 0:
		var entry = frontier.pop_front()
		var pos   = entry[0]
		var steps = entry[1]
		for nb in _get_neighbors(pos.x, pos.y):
			if nb in visited: continue
			if nb in blocked: continue
			visited[nb] = true
			valid_moves.append(nb)
			if steps + 1 < players[current_player_index].move_range:
				frontier.append([nb, steps + 1])

func _move_entity_smooth(entity: Node, target_col: int, target_row: int) -> void:
	var offset    = _grid_center_offset()
	var target_px = _hex_to_pixel(target_col, target_row) + offset
	var tween     = create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(entity, "position", target_px, TWEEN_SPEED)

# ═══════════════════════════════════════════════════════════
#  TILE COLORS
# ═══════════════════════════════════════════════════════════

func _refresh_tile_colors() -> void:
	var enemy_pos : Dictionary = {}
	for e in enemies:
		enemy_pos[Vector2i(e.grid_col, e.grid_row)] = true

	var atk_set : Dictionary = {}
	for t in attack_tiles:
		atk_set[t] = true

	var cur_pos = player_positions[current_player_index]

	for key in tiles:
		var tile = tiles[key]
		if key in enemy_pos:
			tile.set_state("enemy")
		elif key in atk_set:
			tile.set_state("attack")
		elif key == cur_pos:
			tile.set_state("selected")
		elif key in valid_moves and attack_mode == "":
			tile.set_state("valid")
		else:
			tile.set_state("normal")

# ═══════════════════════════════════════════════════════════
#  ATTACK TARGETING
# ═══════════════════════════════════════════════════════════

func _get_attack_tiles_for_mode(mode: String, mouse_pixel: Vector2) -> Array:
	var current_player = players[current_player_index]
	var wd       = current_player.get_weapon_data()
	var atk_key  = "q" if mode == "Q" else "w"
	var atk_mode = wd.get(atk_key + "_mode", "single")

	if atk_mode == "crescent":
		return _get_crescent_tiles(mouse_pixel)
	elif atk_mode == "area":
		var target = _pixel_to_hex(mouse_pixel)
		if not _is_neighbor(player_positions[current_player_index], target):
			return []
		return _get_crush_area(target)
	elif atk_mode == "ranged":
		var range_val = wd.get(atk_key + "_range", 1)
		var target    = _pixel_to_hex(mouse_pixel)
		var dist      = _hex_dist(player_positions[current_player_index].x,
								  player_positions[current_player_index].y,
								  target.x, target.y)
		if dist >= 1 and dist <= range_val and tiles.has(target):
			return [target]
		return []
	else:
		# single — must be adjacent
		var target = _pixel_to_hex(mouse_pixel)
		if _is_neighbor(player_positions[current_player_index], target) and tiles.has(target):
			return [target]
		return []

func _get_crescent_tiles(mouse_pixel: Vector2) -> Array:
	var offset    = _grid_center_offset()
	var pcx       = _hex_to_pixel(player_positions[current_player_index].x,
								  player_positions[current_player_index].y) + offset
	var mouse_ang = atan2(mouse_pixel.y - pcx.y, mouse_pixel.x - pcx.x)
	var neighbors = _get_neighbors(player_positions[current_player_index].x,
								   player_positions[current_player_index].y)

	neighbors.sort_custom(func(a, b):
		var ax = _hex_to_pixel(a.x, a.y) + offset
		var bx = _hex_to_pixel(b.x, b.y) + offset
		var aa = atan2(ax.y - pcx.y, ax.x - pcx.x)
		var ba = atan2(bx.y - pcx.y, bx.x - pcx.x)
		var da = abs(angle_difference(aa, mouse_ang))
		var db = abs(angle_difference(ba, mouse_ang))
		return da < db
	)

	var result : Array = []
	for nb in neighbors:
		if tiles.has(nb):
			result.append(nb)
		if result.size() >= 3:
			break
	return result

func _get_crush_area(target: Vector2i) -> Array:
	var area : Array = [target]
	for nb in _get_neighbors(target.x, target.y):
		if nb == player_positions[current_player_index]: continue
		if tiles.has(nb):
			area.append(nb)
	return area

func _is_neighbor(a: Vector2i, b: Vector2i) -> bool:
	return b in _get_neighbors(a.x, a.y)

# ═══════════════════════════════════════════════════════════
#  DAMAGE FORMULA
# ═══════════════════════════════════════════════════════════

func _calculate_damage(base_dmg: float, hit_type: String, _target) -> int:
	var dmg = base_dmg
	match hit_type:
		"miss": dmg *= 0.50
	return int(round(dmg))

# ═══════════════════════════════════════════════════════════
#  COMBAT — EXECUTE ATTACK
# ═══════════════════════════════════════════════════════════

func _execute_attack(mode: String, hit_type: String) -> void:
	var current_player = players[current_player_index]
	var wd       = current_player.get_weapon_data()
	var atk_key  = "q" if mode == "Q" else "w"
	var base_dmg = float(wd.get(atk_key + "_dmg", 1))
	var effect   = wd.get(atk_key + "_effect", "")
	var atk_mode = wd.get(atk_key + "_mode", "single")

	if hit_type == "miss":
		current_player.perfection = 0
	elif hit_type == "crit":
		current_player.perfection = mini(current_player.perfection + 1, current_player.perfection_cap)

	# ── Ranged: spawn projectile via unified system ──────────
	if atk_mode == "ranged" and not attack_tiles.is_empty():
		var target_tile  = attack_tiles[0]
		var captured_idx = current_player_index
		var captured_dmg = _calculate_damage(base_dmg, hit_type, null)
		var offset       = _grid_center_offset()
		var from_world   = current_player.position
		var to_world     = _hex_to_pixel(target_tile.x, target_tile.y) + offset
		var dir          = (to_world - from_world).normalized()

		attack_committed_this_round = true
		current_player.has_attacked = true
		current_player.use_action()
		attack_mode  = ""
		attack_tiles = []

		_launch_projectile(captured_idx, null, captured_dmg, from_world, dir)
		_update_valid_moves()
		_refresh_tile_colors()
		_refresh_ui()
		return

	# ── Melee / crescent / area ───────────────────────────────
	for t in attack_tiles:
		var target = _get_enemy_at(t)
		if target == null: continue
		var dmg = _calculate_damage(base_dmg, hit_type, target)
		_deal_damage_to_enemy(target, dmg, effect)

	attack_committed_this_round = true
	current_player.has_attacked = true
	current_player.use_action()
	attack_mode  = ""
	attack_tiles = []
	phase = Phase.PLAYER_TURN
	_update_valid_moves()
	_refresh_tile_colors()
	_refresh_ui()

	if enemies.is_empty():
		_on_floor_cleared()

func _deal_damage_to_enemy(enemy: Node, dmg: int, effect: String) -> void:
	match effect:
		"push1":
			_apply_push(enemy, 1, player_positions[current_player_index])
		"bleed":
			enemy.bleed_stacks += 1

	if enemy not in enemies: return

	enemy.take_damage(dmg)
	_spawn_damage_float(enemy.position, dmg)

	if enemy.hp <= 0:
		_on_enemy_killed(enemy)

func _on_enemy_killed(enemy: Node) -> void:
	if enemy.enemy_type == "bomb":
		var bomb_pos = Vector2i(enemy.grid_col, enemy.grid_row)
		enemies.erase(enemy)
		if enemy == sonny_bomb_enemy:
			sonny_bomb_enemy = null
		# Keep visual node alive through TWEEN_SPEED so push animation completes first
		var t = create_tween()
		t.tween_interval(TWEEN_SPEED)
		t.tween_callback(func():
			if is_instance_valid(enemy):
				enemy.queue_free()
			_trigger_bomb_explosion(bomb_pos)
		)
		return
	enemies.erase(enemy)
	enemy.queue_free()
	_update_valid_moves()
	_refresh_tile_colors()

func _get_enemy_at(pos: Vector2i) -> Node:
	for e in enemies:
		if Vector2i(e.grid_col, e.grid_row) == pos:
			return e
	return null

func _get_player_at(pos: Vector2i) -> int:
	for i in range(players.size()):
		if player_positions[i] == pos:
			return i
	return -1

func _get_nearest_enemy_to(p: Node) -> Node:
	var nearest : Node = null
	var min_d          = 9999
	for e in enemies:
		var d = _hex_dist(e.grid_col, e.grid_row, p.grid_col, p.grid_row)
		if d < min_d:
			min_d   = d
			nearest = e
	return nearest

# ── Projectile ────────────────────────────────────────────────────────────────


func _finalize_ranged_turn(player_idx: int) -> void:
	if enemies.is_empty():
		_on_floor_cleared()
		return
	current_player_index = player_idx
	_update_valid_moves()
	_refresh_tile_colors()
	_refresh_ui()

# ── Mike's Draw Shot ──────────────────────────────────────────────────────────

func _build_entity_map() -> Dictionary:
	var emap : Dictionary = {}
	for e in enemies:
		emap[Vector2i(e.grid_col, e.grid_row)] = e
	for i in range(players.size()):
		emap[player_positions[i]] = players[i]
	return emap

func _make_tracer() -> BounceTracer:
	var t              = BounceTracer.new()
	t.bounds           = grid_pixel_bounds
	t.columns          = column_tiles
	t.entities         = _build_entity_map()
	t.launch_speed     = CURRENT_PROJ_LAUNCH_SPEED
	t.decay_rate       = CURRENT_PROJ_DECAY_RATE
	t.min_speed        = CURRENT_PROJ_LAUNCH_SPEED * 0.03
	t.negative_bounce  = CURRENT_PROJ_NEGATIVE_BOUNCE
	t.hex_to_pixel     = func(c: int, r: int) -> Vector2:
		return _hex_to_pixel(c, r) + _grid_center_offset()
	t.pixel_to_hex     = _pixel_to_hex
	return t

func _compute_mike_trajectory() -> void:
	if not mike_aiming: return
	var exclude = {player_positions[current_player_index]: true}
	var bc   = players[current_player_index].get_bounce_count()
	var path = _make_tracer().trace(
		players[current_player_index].position, mike_aim_dir, bc, false, exclude)
	mike_trajectory = path.segs
	aim_overlay.trajectory = mike_trajectory
	aim_overlay.queue_redraw()

func _spawn_mike_timing_bar(click_pixel: Vector2) -> void:
	var mike = players[current_player_index]
	var bar  = MikeTimingBarScript.new()
	bar.setup(mike_shot_dir, click_pixel)
	# Position the bar above Mike, offset in the shot direction
	bar.position = mike.position + Vector2(0, -60)
	add_child(bar)
	bar.timing_resolved.connect(_on_mike_timing_resolved)
	mike_timing_bar = bar
	_refresh_ui()

func _on_mike_timing_resolved(result: String) -> void:
	mike_timing_bar     = null
	mike_shot_committed = false
	mike_aiming         = false
	attack_mode         = ""
	mike_trajectory     = []
	aim_overlay.trajectory = []
	aim_overlay.queue_redraw()

	var captured_idx = current_player_index
	var wd           = players[captured_idx].get_weapon_data()
	var base_dmg     = float(wd.get("q_dmg", 1))
	var dmg_type = "hit" if result == "perfect" else ("hit" if result == "hit" else "miss")
	var dmg      = _calculate_damage(base_dmg, dmg_type, null)

	attack_committed_this_round = true
	players[captured_idx].has_attacked = true
	players[captured_idx].use_action()

	if result == "miss":
		# Design spec: miss = "Oops!" shown, no projectile fires, action consumed
		_spawn_float_text(players[captured_idx].position + Vector2(0, -50),
			"Oops!", Color(0.9, 0.5, 0.3))
		phase = Phase.PLAYER_TURN
		_finalize_ranged_turn(captured_idx)
		return

	_fire_mike_projectile(captured_idx, dmg)
	_fire_mike_stored_projectiles(captured_idx)

func _fire_mike_projectile(source_idx: int, dmg: int) -> void:
	var from_world : Vector2 = players[source_idx].position
	_launch_projectile(source_idx, null, dmg, from_world, mike_shot_dir)

# ── Sonny's Charge Bar (Boong Q) ─────────────────────────────────────────────

func _spawn_sonny_charge_bar(target_tile: Vector2i) -> void:
	var sonny   = players[current_player_index]
	var offset  = _grid_center_offset()
	var s_px    = _hex_to_pixel(sonny.grid_col, sonny.grid_row) + offset
	var t_px    = _hex_to_pixel(target_tile.x, target_tile.y)  + offset
	var dir     = (t_px - s_px).normalized()
	# Offset bar 28px perpendicular so it doesn't cover the sprites
	var perp    = Vector2(-dir.y, dir.x)
	var bar_pos = (s_px + t_px) * 0.5 + perp * 28.0

	sonny_charge_target = target_tile
	sonny_charging      = true
	phase               = Phase.DODGE_PHASE

	var bar = SonnyChargeBarScript.new()
	bar.setup(dir.angle())
	bar.position   = bar_pos
	bar.is_holding = true   # mouse button is still held from the click that spawned this
	bar.z_index    = 90
	add_child(bar)
	bar.charge_resolved.connect(_on_sonny_charge_resolved)
	sonny_charge_bar = bar

	attack_mode  = ""
	attack_tiles = []
	_refresh_tile_colors()
	_refresh_ui()

func _on_sonny_charge_resolved(result: String) -> void:
	sonny_charging   = false
	sonny_charge_bar = null
	phase            = Phase.PLAYER_TURN

	var cur      = players[current_player_index]
	var base_dmg = 1.0

	match result:
		"perfect":
			cur.perfection = mini(cur.perfection + 1, cur.perfection_cap)
			var dmg = _calculate_damage(base_dmg, "hit", null) + 1   # +1 flat from perfect
			_spawn_float_text(cur.position + Vector2(0, -50), "PERFECT! BOONG!", Color(0.3, 1.0, 0.5))
			_do_charge_hit(sonny_charge_target, dmg)
		"normal":
			var dmg = _calculate_damage(base_dmg, "hit", null)
			_spawn_float_text(cur.position + Vector2(0, -50), "BOONG!", Color(0.9, 0.85, 0.3))
			_do_charge_hit(sonny_charge_target, dmg)
		"miss":
			attack_committed_this_round = true
			cur.has_attacked = true
			cur.use_action()
			_spawn_float_text(cur.position + Vector2(0, -50), "MISS!", Color(0.9, 0.4, 0.4))
			_update_valid_moves()
			_refresh_tile_colors()
			_refresh_ui()

func _do_charge_hit(target_tile: Vector2i, dmg: int) -> void:
	var target = _get_enemy_at(target_tile)
	if target:
		_deal_damage_to_enemy(target, dmg, "push1")
	attack_committed_this_round = true
	players[current_player_index].has_attacked = true
	players[current_player_index].use_action()
	_update_valid_moves()
	_refresh_tile_colors()
	_refresh_ui()
	if enemies.is_empty():
		_on_floor_cleared()

func _enemy_ranged_attack(enemy: Node, target_idx: int, atk: Dictionary) -> void:
	current_player_index = target_idx
	_refresh_ui()
	var target_player = players[target_idx]
	var dir : Vector2 = (target_player.position - enemy.position).normalized()
	var nb  : float   = atk.get("negative_bounce", -1.0)

	var hit_details : Array = atk.get("hit_details", [])
	if hit_details.is_empty():
		var spd : float = PROJ_ENEMY_SPEEDS.get(atk.get("speed", "medium"), PROJ_ENEMY_SPEEDS["medium"])
		_launch_projectile(-1, enemy, atk.get("damage", 1.0), enemy.position, dir,
			0, false, nb, spd)
	else:
		for hd : Dictionary in hit_details:
			var delay : float = hd.get("delay", 0.0)
			var dmg   : float = hd.get("damage", atk.get("damage", 1.0))
			var spd   : float = PROJ_ENEMY_SPEEDS.get(
				hd.get("speed", atk.get("speed", "medium")), PROJ_ENEMY_SPEEDS["medium"])
			var start : Vector2 = enemy.position
			if delay <= 0.001:
				_launch_projectile(-1, enemy, dmg, start, dir, 0, false, nb, spd)
			else:
				var t := create_tween()
				t.tween_interval(delay)
				t.tween_callback(func():
					if is_instance_valid(enemy) and not players.is_empty():
						_launch_projectile(-1, enemy, dmg, enemy.position, dir, 0, false, nb, spd)
				)

# ═══════════════════════════════════════════════════════════
#  CHARACTER SWITCHING
# ═══════════════════════════════════════════════════════════

func _switch_player_to_other() -> void:
	var other_idx = (current_player_index + 1) % players.size()
	var other     = players[other_idx]
	if other.hp <= 0: return
	if mike_aiming: _cancel_mike_aim()
	attack_mode    = ""
	attack_tiles   = []
	bomb_mode      = false
	mike_grappling = false
	current_player_index = other_idx
	_update_valid_moves()
	_refresh_tile_colors()
	_refresh_ui()

func _handle_w_key(current_player: Node) -> void:
	match current_player.get_w_mode():
		"bomb":
			if sonny_w_used: return
			bomb_mode    = true
			attack_mode  = "W"
			attack_tiles = _get_adj_bomb_tiles(current_player)
			_refresh_tile_colors()
			_refresh_ui()
		"grapple":
			if mike_w_uses <= 0: return
			mike_grappling = true
			attack_mode    = "W"
			attack_tiles   = _get_grapple_targets()
			_refresh_tile_colors()
			_refresh_ui()

# ═══════════════════════════════════════════════════════════
#  SONNY BOMB
# ═══════════════════════════════════════════════════════════

func _get_adj_bomb_tiles(p: Node) -> Array:
	var occupied : Dictionary = {}
	for pl in players: occupied[Vector2i(pl.grid_col, pl.grid_row)] = true
	for e  in enemies: occupied[Vector2i(e.grid_col,  e.grid_row)]  = true
	var result : Array = []
	for nb in _get_neighbors(p.grid_col, p.grid_row):
		if nb in occupied: continue
		if not is_valid_and_passable(nb.x, nb.y): continue
		result.append(nb)
	return result

func _place_bomb(target: Vector2i) -> void:
	sonny_bomb_enemy = _spawn_enemy("bomb", target.x, target.y)
	sonny_w_used  = true
	bomb_mode     = false
	attack_mode   = ""
	attack_tiles  = []
	attack_committed_this_round = true
	players[current_player_index].has_attacked = true
	players[current_player_index].use_action()
	_update_valid_moves()
	_refresh_tile_colors()
	_refresh_ui()

func _trigger_bomb_explosion(bomb_pos: Vector2i) -> void:
	var offset   = _grid_center_offset()
	var affected = [bomb_pos] + _get_neighbors(bomb_pos.x, bomb_pos.y)
	for hex in affected:
		var e = _get_enemy_at(hex)
		if e:
			_deal_damage_to_enemy(e, 2, "")
		for pi in range(players.size()):
			if Vector2i(players[pi].grid_col, players[pi].grid_row) == hex:
				var real = players[pi].take_damage(2)
				if real > 0:
					_spawn_damage_float(players[pi].position, real)
	_spawn_float_text(
		_hex_to_pixel(bomb_pos.x, bomb_pos.y) + offset + Vector2(0, -30),
		"BOOM!", Color(1.0, 0.55, 0.1)
	)
	_update_valid_moves()
	_refresh_tile_colors()
	_refresh_ui()
	for p in players:
		if p.hp <= 0:
			_on_player_died()
			return
	if enemies.is_empty():
		_on_floor_cleared()

# ═══════════════════════════════════════════════════════════
#  MIKE GRAPPLE
# ═══════════════════════════════════════════════════════════

func _get_grapple_targets() -> Array:
	var result : Array = []
	for e in enemies:
		result.append(Vector2i(e.grid_col, e.grid_row))
	for i in range(players.size()):
		if i != current_player_index:
			result.append(player_positions[i])
	return result

func _execute_grapple(clicked_hex: Vector2i) -> void:
	var mike     = players[current_player_index]
	var mike_hex = Vector2i(mike.grid_col, mike.grid_row)
	if clicked_hex == mike_hex: return

	# ── 1. Ray-cast the hook along aim direction ──────────────────────────
	var offset   := _grid_center_offset()
	var mike_px  := _hex_to_pixel(mike_hex.x, mike_hex.y) + offset
	var aim_px   := _hex_to_pixel(clicked_hex.x, clicked_hex.y) + offset
	var dir      : Vector2 = (aim_px - mike_px).normalized()

	var visited  : Dictionary = {}
	visited[mike_hex] = true
	var cur_px   : Vector2 = mike_px
	var step_px  : float   = HEX_SIZE * 0.4
	var max_dist : float   = (GRID_COLS + GRID_ROWS) * HEX_SIZE * 2.0

	var hooked_enemy      : Node = null
	var hooked_player_idx : int  = -1

	var dist_walked : float = 0.0
	while dist_walked < max_dist:
		cur_px      += dir * step_px
		dist_walked += step_px
		var hex : Vector2i = _pixel_to_hex(cur_px)
		if not tiles.has(hex): break      # left the grid
		if hex in visited: continue
		visited[hex] = true

		var e = _get_enemy_at(hex)
		if e != null:
			if e == sonny_bomb_enemy: continue   # phase through Sonny's bomb
			hooked_enemy = e
			break

		var pi = _get_player_at(hex)
		if pi >= 0 and pi != current_player_index:
			hooked_player_idx = pi
			break

	# ── 2. Nothing hit → refund the use ──────────────────────────────────
	if hooked_enemy == null and hooked_player_idx < 0:
		mike_grappling = false
		attack_mode    = ""
		attack_tiles   = []
		_refresh_tile_colors()
		_refresh_ui()
		return

	# ── 3. Apply grab damage ──────────────────────────────────────────────
	if hooked_enemy != null:
		hooked_enemy.take_damage(1)
		_spawn_damage_float(hooked_enemy.position, 1)
		if hooked_enemy.hp <= 0:
			_on_enemy_killed(hooked_enemy)
			_finish_grapple()
			return
	# Sonny: 0 damage on grab — no action needed

	# ── 4. Pull target toward Mike ────────────────────────────────────────
	if hooked_enemy != null:
		_pull_entity_toward(hooked_enemy, mike_hex, false, -1)
	else:
		_pull_entity_toward(players[hooked_player_idx], mike_hex, true, hooked_player_idx)

	_finish_grapple()

func _finish_grapple() -> void:
	mike_w_uses   -= 1
	mike_grappling = false
	attack_mode    = ""
	attack_tiles   = []
	attack_committed_this_round = true
	players[current_player_index].has_attacked = true
	players[current_player_index].use_action()
	_update_valid_moves()
	_refresh_tile_colors()
	_refresh_ui()
	if enemies.is_empty():
		_on_floor_cleared()

# Drag `target` one hex at a time toward `toward_hex`, respecting full collision.
func _pull_entity_toward(target: Node, toward_hex: Vector2i,
		is_player: bool, player_idx: int) -> void:
	var max_steps : int = GRID_COLS + GRID_ROWS
	for _i in range(max_steps):
		var cur_hex := Vector2i(target.grid_col, target.grid_row)
		if _hex_dist(cur_hex.x, cur_hex.y, toward_hex.x, toward_hex.y) <= 1:
			break  # already adjacent to Mike — can't go further

		# Best neighbor aligned toward Mike
		var next_hex := _pull_next_step(cur_hex, toward_hex)
		if next_hex == Vector2i(-1, -1): break

		# Stop short of Mike's tile
		if next_hex == toward_hex: break

		# Blocked by column
		if next_hex in column_tiles:
			target.take_damage(1)
			_spawn_damage_float(target.position, 1)
			if not is_player and target.hp <= 0: _on_enemy_killed(target)
			break

		# Blocked by impassable / out-of-bounds tile
		if not tiles.has(next_hex) or not is_valid_and_passable(next_hex.x, next_hex.y):
			target.take_damage(1)
			_spawn_damage_float(target.position, 1)
			if not is_player and target.hp <= 0: _on_enemy_killed(target)
			break

		# Blocked by Sonny's bomb — bomb takes 1 damage and explodes
		var e_at := _get_enemy_at(next_hex)
		if e_at != null and e_at == sonny_bomb_enemy:
			e_at.take_damage(1)
			_spawn_damage_float(e_at.position, 1)
			if e_at.hp <= 0: _on_enemy_killed(e_at)
			target.take_damage(1)
			_spawn_damage_float(target.position, 1)
			if not is_player and target.hp <= 0: _on_enemy_killed(target)
			break

		# Blocked by any other character
		if e_at != null or _get_player_at(next_hex) >= 0:
			target.take_damage(1)
			_spawn_damage_float(target.position, 1)
			if not is_player and target.hp <= 0: _on_enemy_killed(target)
			break

		# Clear — move one step
		target.grid_col = next_hex.x
		target.grid_row = next_hex.y
		if is_player:
			player_positions[player_idx] = next_hex
		_move_entity_smooth(target, next_hex.x, next_hex.y)

# Neighbor of from_hex that is most aligned toward toward_hex.
func _pull_next_step(from_hex: Vector2i, toward_hex: Vector2i) -> Vector2i:
	var from_px   := _hex_to_pixel(from_hex.x, from_hex.y)
	var toward_px := _hex_to_pixel(toward_hex.x, toward_hex.y)
	var dir       : Vector2 = (toward_px - from_px).normalized()
	var best      := Vector2i(-1, -1)
	var best_dot  := -INF
	for nb : Vector2i in _get_neighbors(from_hex.x, from_hex.y):
		var nb_px  := _hex_to_pixel(nb.x, nb.y)
		var nb_dir : Vector2 = (nb_px - from_px).normalized()
		var dot    : float   = dir.dot(nb_dir)
		if dot > best_dot:
			best_dot = dot
			best     = nb
	return best

func _best_adj_hex_of(center: Vector2i, mover_hex: Vector2i) -> Vector2i:
	var occupied : Dictionary = {}
	for p in players: occupied[Vector2i(p.grid_col, p.grid_row)] = true
	for e in enemies: occupied[Vector2i(e.grid_col, e.grid_row)] = true
	var best      = Vector2i(-1, -1)
	var best_dist = 999
	for nb in _get_neighbors(center.x, center.y):
		if nb in occupied: continue
		if not is_valid_and_passable(nb.x, nb.y): continue
		var d = _hex_dist(nb.x, nb.y, mover_hex.x, mover_hex.y)
		if d < best_dist:
			best_dist = d
			best      = nb
	return best

# ═══════════════════════════════════════════════════════════
#  PROJECTILE SYSTEM — Section 5B
# ═══════════════════════════════════════════════════════════

const PROJ_LAUNCH_SPEED    : float = 600.0   # px/s — ≈12 hex unobstructed range
const PROJ_DECAY_RATE      : float = 0.85    # exponential decay per second
const PROJ_NEGATIVE_BOUNCE : float = 200.0   # flat px/s subtracted on impact (player projectiles)
const PROJ_MIN_SPEED       : float = PROJ_LAUNCH_SPEED * 0.03   # 18 px/s disappear threshold
const PROJ_REACT_PERFECT   : float = 0.20    # ±0.2 s from contact = perfect
const PROJ_REACT_OK        : float = 0.40    # ±0.4 s from contact = ok / dodge
const PROJ_ENEMY_SPEEDS    : Dictionary = {
	"slow": 120.0, "medium": 220.0, "fast": 360.0, "very_fast": 500.0, "ultra_fast": 700.0
}

# Modifier-affected runtime copies — equal to base consts until items change them
var CURRENT_PROJ_LAUNCH_SPEED    : float = PROJ_LAUNCH_SPEED
var CURRENT_PROJ_DECAY_RATE      : float = PROJ_DECAY_RATE
var CURRENT_PROJ_NEGATIVE_BOUNCE : float = PROJ_NEGATIVE_BOUNCE

# ─── Geometry helpers ─────────────────────────────────────────────────────────

# Returns t ∈ [0,1] for segment A→B intersecting segment C→D, or -1.
func _seg_t(a: Vector2, b: Vector2, c: Vector2, d: Vector2) -> float:
	var r   := b - a
	var s   := d - c
	var rxs := r.x * s.y - r.y * s.x
	if absf(rxs) < 0.001: return -1.0
	var t := ((c.x - a.x) * s.y - (c.y - a.y) * s.x) / rxs
	var u := ((c.x - a.x) * r.y - (c.y - a.y) * r.x) / rxs
	if t >= 0.0 and t <= 1.0 and u >= 0.0 and u <= 1.0: return t
	return -1.0

# Outward normal of the first hex edge crossed by segment prev→new (inward crossings only).
# Flat-top hex, vertex radius = hex_size. Returns Vector2.ZERO if no inward crossing.
func _hex_crossing_normal(hex_center: Vector2, hex_size: float,
		prev_pos: Vector2, new_pos: Vector2) -> Vector2:
	var best_t      := 2.0
	var best_normal := Vector2.ZERO
	var motion      := new_pos - prev_pos
	for i in 6:
		var v0 := hex_center + Vector2(cos(deg_to_rad(i * 60.0)),       sin(deg_to_rad(i * 60.0)))       * hex_size
		var v1 := hex_center + Vector2(cos(deg_to_rad((i + 1) * 60.0)), sin(deg_to_rad((i + 1) * 60.0))) * hex_size
		var t  := _seg_t(prev_pos, new_pos, v0, v1)
		if t < 0.0 or t >= best_t: continue
		var n  := ((v0 + v1) * 0.5 - hex_center).normalized()
		if motion.dot(n) >= 0.0: continue   # outward crossing — skip
		best_t      = t
		best_normal = n
	return best_normal

# Returns t ∈ [0,1] for first inward hex-border crossing along ray pos+dir*max_dist, or -1.
func _hex_ray_t(hex_center: Vector2, hex_size: float,
		pos: Vector2, dir: Vector2, max_dist: float) -> float:
	var ray_end := pos + dir * max_dist
	var best    := -1.0
	for i in 6:
		var v0 := hex_center + Vector2(cos(deg_to_rad(i * 60.0)),       sin(deg_to_rad(i * 60.0)))       * hex_size
		var v1 := hex_center + Vector2(cos(deg_to_rad((i + 1) * 60.0)), sin(deg_to_rad((i + 1) * 60.0))) * hex_size
		var t  := _seg_t(pos, ray_end, v0, v1)
		if t < 0.0: continue
		var n  := ((v0 + v1) * 0.5 - hex_center).normalized()
		if dir.dot(n) >= 0.0: continue   # outward — skip
		if best < 0.0 or t < best: best = t
	return best

# ─── Launch ───────────────────────────────────────────────────────────────────
# source_idx              = player index who fired (-1 for enemy).
# source_enemy            = enemy node that fired (null if player).
# override_negative_bounce = if >= 0, overrides the per-source default.
# enemy_speed             = px/s for enemy projectiles (ignored for player projectiles).
func _launch_projectile(source_idx: int, source_enemy: Node,
		damage: float, start_pos: Vector2, direction: Vector2,
		redirect_count: int = 0, is_supercharged: bool = false,
		override_negative_bounce: float = -1.0,
		enemy_speed: float = 0.0) -> void:
	var uses_decay := source_idx >= 0
	var init_speed : float
	if uses_decay:
		init_speed = CURRENT_PROJ_LAUNCH_SPEED
	elif enemy_speed > 0.0:
		init_speed = enemy_speed
	else:
		init_speed = PROJ_ENEMY_SPEEDS["medium"]

	var neg_bounce : float
	if override_negative_bounce >= 0.0:
		neg_bounce = override_negative_bounce
	elif uses_decay:
		neg_bounce = CURRENT_PROJ_NEGATIVE_BOUNCE
	else:
		neg_bounce = 9999.0

	var proj := Node2D.new()
	proj.set_script(ProjectileScript)
	proj.z_index         = 50
	proj.redirect_count  = redirect_count
	proj.is_supercharged = is_supercharged
	proj.position        = start_pos
	add_child(proj)

	var reaction_done : Dictionary = {}
	var pass_through  : Dictionary = {}
	if source_idx >= 0:
		reaction_done[source_idx] = true
		pass_through[source_idx]  = true

	live_proj_states.append({
		"node":            proj,
		"source_idx":      source_idx,
		"source_enemy":    source_enemy,
		"damage":          damage,
		"speed":           init_speed,
		"direction":       direction.normalized(),
		"uses_decay":      uses_decay,
		"negative_bounce": neg_bounce,
		"is_god_owned":    false,
		"redirect_count":  redirect_count,
		"is_supercharged": is_supercharged,
		"elapsed":         0.0,
		"contact_est":     {},
		"player_crossed":  {},
		"reaction_done":   reaction_done,
		"pass_through":    pass_through,
		"enemies_hit":     {},
		"done":            false,
	})
	_last_proj_source_idx = source_idx
	phase = Phase.DODGE_PHASE


# ─── Wall normal helpers ──────────────────────────────────────────────────────
func _proj_wall_normal(pos: Vector2) -> Vector2:
	var n := Vector2.ZERO
	if   pos.x < grid_pixel_bounds.position.x:                            n.x =  1.0
	elif pos.x > grid_pixel_bounds.position.x + grid_pixel_bounds.size.x: n.x = -1.0
	if   pos.y < grid_pixel_bounds.position.y:                            n.y =  1.0
	elif pos.y > grid_pixel_bounds.position.y + grid_pixel_bounds.size.y: n.y = -1.0
	return n.normalized() if n != Vector2.ZERO else Vector2.RIGHT

func _clamp_to_bounds(pos: Vector2) -> Vector2:
	return Vector2(
		clampf(pos.x, grid_pixel_bounds.position.x,
			grid_pixel_bounds.position.x + grid_pixel_bounds.size.x),
		clampf(pos.y, grid_pixel_bounds.position.y,
			grid_pixel_bounds.position.y + grid_pixel_bounds.size.y)
	)

# ─── Per-frame physics loop ──────────────────────────────────────────────────
func _process_live_projectiles(delta: float) -> void:
	if phase == Phase.DEAD: return

	for state in live_proj_states.duplicate():
		if state.done: continue
		var proj : Node = state.node
		if not is_instance_valid(proj):
			state.done = true
			continue

		state.elapsed += delta
		var prev_pos  : Vector2 = proj.position

		# ── 1. Decay ─────────────────────────────────────────────────────────
		if state.uses_decay:
			state.speed *= exp(-CURRENT_PROJ_DECAY_RATE * delta)
		if state.speed < PROJ_MIN_SPEED:
			_proj_finalize(state)
			continue

		var new_pos : Vector2 = prev_pos + (state.direction as Vector2) * (state.speed as float) * delta

		# ── 2. Wall collision ─────────────────────────────────────────────────
		if not grid_pixel_bounds.has_point(new_pos):
			new_pos = _clamp_to_bounds(new_pos)
			var wall_n := _proj_wall_normal(new_pos)
			if state.is_supercharged:
				_proj_supercharge_explode(state.damage, new_pos)
				_proj_die(state)
				continue
			state.direction  = state.direction.bounce(wall_n)
			state.speed     -= state.negative_bounce
			if state.speed < PROJ_MIN_SPEED:
				_proj_finalize(state)
			continue

		# ── 3. Column collision ───────────────────────────────────────────────
		var new_hex := _pixel_to_hex(new_pos)
		if new_hex in column_tiles:
			var col_px := _hex_to_pixel(new_hex.x, new_hex.y) + _grid_center_offset()
			var col_d  := new_pos - col_px
			var col_n  := col_d.normalized() if col_d.length_squared() > 0.01 else Vector2.UP
			if state.is_supercharged:
				_proj_supercharge_explode(state.damage, prev_pos)
				_proj_die(state)
				continue
			state.direction  = state.direction.bounce(col_n)
			state.speed     -= state.negative_bounce
			if state.speed < PROJ_MIN_SPEED:
				_proj_finalize(state)
			continue

		# ── 4. Move ───────────────────────────────────────────────────────────
		proj.position = new_pos
		var cur_hex   := _pixel_to_hex(proj.position)

		# ── 5. Enemy hit ──────────────────────────────────────────────────────
		if not state.enemies_hit.get(cur_hex, false):
			var hit_enemy = _get_enemy_at(cur_hex)
			var is_own : bool = hit_enemy == state.source_enemy and not (state.is_god_owned as bool)
			if hit_enemy != null and hit_enemy in enemies and not is_own:
				state.enemies_hit[cur_hex] = true
				var e_px := _hex_to_pixel(cur_hex.x, cur_hex.y) + _grid_center_offset()
				var e_d  : Vector2 = (proj.position as Vector2) - e_px
				var en   : Vector2 = e_d.normalized() if e_d.length_squared() > 0.01 else Vector2.UP
				if state.is_supercharged:
					_proj_supercharge_explode(state.damage, proj.position)
					_proj_die(state)
					continue
				_deal_damage_to_enemy(hit_enemy, int(state.damage), "")
				if state.done: continue
				if not is_instance_valid(proj): continue
				state.direction  = state.direction.bounce(en)
				state.speed     -= state.negative_bounce
				if state.speed < PROJ_MIN_SPEED:
					_proj_finalize(state)
				continue

		# ── 6. Player contact ─────────────────────────────────────────────────
		for pi in range(players.size()):
			if state.done: break
			if state.reaction_done.get(pi, false): continue
			if state.pass_through.get(pi, false):  continue
			if pi == state.source_idx and not state.is_god_owned: continue

			var hex_ctr : Vector2 = players[pi].position

			# A) Already physically crossed: wait for SPACE or timing-window expiry
			if state.player_crossed.get(pi, false):
				if (state.elapsed as float) - (state.contact_est[pi] as float) > PROJ_REACT_OK:
					state.reaction_done[pi] = true
					_proj_apply_miss(state, pi)
				continue

			# B) Update approach estimate for SPACE timing (before first crossing)
			var lookahead : float = PROJ_REACT_OK * (state.speed as float) + HEX_SIZE * 2.0
			var ray_t : float = _hex_ray_t(hex_ctr, HEX_SIZE, proj.position,
					state.direction as Vector2, lookahead)
			if ray_t >= 0.0:
				var dist : float = lookahead * ray_t
				state.contact_est[pi] = state.elapsed + dist / maxf(state.speed as float, 1.0)

			# C) Enemy projectile: physical crossing → immediate damage + bounce/die
			if not state.uses_decay:
				var en := _hex_crossing_normal(hex_ctr, HEX_SIZE, prev_pos, proj.position)
				if en != Vector2.ZERO:
					state.reaction_done[pi] = true
					_proj_apply_miss(state, pi)
					if state.done: break
					if not is_instance_valid(proj): break
					state.direction  = (state.direction as Vector2).bounce(en)
					state.speed     -= state.negative_bounce as float
					proj.position    = prev_pos
					if (state.speed as float) < PROJ_MIN_SPEED:
						_proj_finalize(state)
					break

			# D) Player projectile: tile-based entry, radial normal (matches BounceTracer)
			else:
				if cur_hex == player_positions[pi]:
					var p_d  : Vector2 = (proj.position as Vector2) - hex_ctr
					var pn   : Vector2 = p_d.normalized() if p_d.length_squared() > 0.01 else Vector2.UP
					state.player_crossed[pi] = true
					state.contact_est[pi]    = state.elapsed
					state.direction  = (state.direction as Vector2).bounce(pn)
					state.speed     -= state.negative_bounce as float
					if (state.speed as float) < PROJ_MIN_SPEED:
						state.reaction_done[pi] = true
						_proj_apply_miss(state, pi)
						if not state.done:
							_proj_finalize(state)
					break


# ─── SPACE press ─────────────────────────────────────────────────────────────
func _handle_proj_space_press(mouse_pos: Vector2) -> void:
	var best_state : Dictionary = {}
	var best_char  : int        = -1
	var best_err   : float      = INF

	for state in live_proj_states:
		if state.done: continue
		for pi in state.contact_est.keys():
			if state.reaction_done.get(pi, false): continue
			if state.pass_through.get(pi, false):  continue
			if pi == state.source_idx and not state.is_god_owned: continue
			var error : float = (state.elapsed as float) - (state.contact_est[pi] as float)
			if absf(error) <= PROJ_REACT_OK + 0.05 and absf(error) < best_err:
				best_err   = absf(error)
				best_char  = pi
				best_state = state

	if best_char < 0: return

	best_state.reaction_done[best_char] = true
	_proj_resolve_reaction(best_state, best_char,
		best_state.elapsed - best_state.contact_est[best_char], mouse_pos)


# ─── Reaction resolution ──────────────────────────────────────────────────────
func _proj_resolve_reaction(state: Dictionary, char_idx: int,
		timing_error: float, mouse_pos: Vector2) -> void:
	var abs_err  : float = absf(timing_error)
	var is_own   : bool  = (state.source_idx == char_idx and not (state.is_god_owned as bool))
	var is_sonny : bool  = (player_names[char_idx] == "Sonny")
	var is_mike  : bool  = (player_names[char_idx] == "Mike")
	var p_pos    : Vector2 = players[char_idx].position

	if abs_err <= PROJ_REACT_PERFECT:
		# ── Perfect ──────────────────────────────────────────────────────────
		if is_sonny:
			_proj_sonny_redirect(state, char_idx, mouse_pos)
		elif is_mike:
			_spawn_float_text(p_pos + Vector2(0, -50), "PERFECT DODGE!", Color(0.3, 1.0, 0.5))
			if is_own:
				_proj_stop(state)
			else:
				_proj_mike_catch(state, char_idx)
	elif abs_err <= PROJ_REACT_OK:
		# ── OK / dodge — pass through, no damage ─────────────────────────────
		state.pass_through[char_idx] = true
		_spawn_float_text(p_pos + Vector2(0, -50), "DODGED!", Color(0.9, 0.9, 0.3))
	else:
		# ── Miss ──────────────────────────────────────────────────────────────
		_proj_apply_miss(state, char_idx)


# ─── Sonny perfect redirect ───────────────────────────────────────────────────
func _proj_sonny_redirect(state: Dictionary, char_idx: int, mouse_pos: Vector2) -> void:
	var p_world  : Vector2 = players[char_idx].position
	var to_mouse : Vector2 = mouse_pos - p_world
	var new_dir  : Vector2 = to_mouse.normalized() if to_mouse.length() > 8.0 else Vector2.RIGHT

	if is_instance_valid(state.node):
		state.node.position = p_world

	# Speed bonus counteracts the negative_bounce cost of a normal collision
	state.speed     += (state.negative_bounce as float) * 0.5
	state.direction  = new_dir

	state.redirect_count += 1
	if is_instance_valid(state.node):
		state.node.redirect_count = state.redirect_count
		if state.redirect_count >= 3:
			state.is_supercharged      = true
			state.node.is_supercharged = true
		state.node.queue_redraw()

	_spawn_float_text(p_world + Vector2(0, -50), "REDIRECT!", Color(0.3, 1.0, 0.5))

	# God ownership: projectile now hits everyone including Sonny and Mike.
	# All tracking is reset for the new trajectory — no player immunity.
	state.is_god_owned   = true
	state.contact_est    = {}
	state.player_crossed = {}
	state.reaction_done  = {}
	state.pass_through   = {}
	state.enemies_hit    = {}
	state.elapsed        = 0.0


# ─── Mike catch ───────────────────────────────────────────────────────────────
func _proj_mike_catch(state: Dictionary, char_idx: int) -> void:
	var p_pos : Vector2 = players[char_idx].position
	if mike_caught_projectiles.size() >= 2:
		_spawn_float_text(p_pos + Vector2(0, -70), "Bag is full!", Color(1.0, 0.3, 0.3))
	else:
		mike_caught_projectiles.append({ "damage": state.damage as float })
		_spawn_float_text(p_pos + Vector2(0, -70), "Caught it!", Color(0.3, 1.0, 0.5))
	_proj_die(state)
	_refresh_ui()

# ─── Fire Mike's stored projectiles after a successful Draw Shot ───────────────
func _fire_mike_stored_projectiles(source_idx: int) -> void:
	if mike_caught_projectiles.is_empty(): return
	var delay := 0.3
	for caught in mike_caught_projectiles:
		var t   := create_tween()
		var dmg : float = caught["damage"]
		t.tween_interval(delay)
		t.tween_callback(func():
			if players.is_empty(): return
			_launch_projectile(source_idx, null, dmg,
				players[source_idx].position, mike_shot_dir)
		)
		delay += 0.3
	mike_caught_projectiles.clear()
	_refresh_ui()


# ─── Miss / damage ────────────────────────────────────────────────────────────
func _proj_apply_miss(state: Dictionary, char_idx: int) -> void:
	if state.is_supercharged:
		_proj_supercharge_explode(state.damage, players[char_idx].position)
		_proj_die(state)
		return

	var real_dmg : float = players[char_idx].take_damage(state.damage)
	_spawn_damage_float(players[char_idx].position, real_dmg)
	_spawn_float_text(players[char_idx].position + Vector2(0, -50),
		"HIT! -" + str(real_dmg) + " HP", Color(1.0, 0.3, 0.3))
	if players[char_idx].hp <= 0:
		_on_player_died()


# ─── Stop projectile (Mike perfect dodge of own projectile) ──────────────────
func _proj_stop(state: Dictionary) -> void:
	_proj_die(state)


# ─── Projectile dies with no explosion ───────────────────────────────────────
func _proj_die(state: Dictionary) -> void:
	if state.done: return
	state.done = true
	if is_instance_valid(state.node): state.node.queue_free()
	live_proj_states.erase(state)
	if live_proj_states.is_empty() and phase == Phase.DODGE_PHASE:
		_proj_transition()


# ─── Speed-death finalization (may trigger supercharge explosion) ─────────────
func _proj_finalize(state: Dictionary) -> void:
	if state.done: return
	state.done = true
	var last_pos : Vector2 = state.node.position if is_instance_valid(state.node) else Vector2.ZERO
	if is_instance_valid(state.node): state.node.queue_free()
	if state.is_supercharged:
		_proj_supercharge_explode(state.damage, last_pos)
	live_proj_states.erase(state)
	if live_proj_states.is_empty() and phase == Phase.DODGE_PHASE:
		_proj_transition()


# ─── Supercharged explosion ───────────────────────────────────────────────────
func _proj_supercharge_explode(damage: float, impact_world: Vector2) -> void:
	var impact_hex := _pixel_to_hex(impact_world)
	var affected   := [impact_hex] + _get_neighbors(impact_hex.x, impact_hex.y)
	_spawn_float_text(impact_world + Vector2(0, -30), "SUPERCHARGED!", Color(1.0, 0.4, 0.1))
	for hex in affected:
		var dmg := damage + (1.0 if hex == impact_hex else 0.0)
		var enemy := _get_enemy_at(hex)
		if enemy:
			_deal_damage_to_enemy(enemy, int(dmg), "")
		for pi in range(players.size()):
			if player_positions[pi] == hex:
				var real : float = players[pi].take_damage(dmg)
				_spawn_damage_float(players[pi].position, real)
				if players[pi].hp <= 0:
					_on_player_died()
					return


# ─── Phase transition after all projectiles done ─────────────────────────────
func _proj_transition() -> void:
	if enemies.is_empty():
		_on_floor_cleared()
		return
	_refresh_ui()
	if _last_proj_source_idx >= 0:
		phase = Phase.PLAYER_TURN
		_finalize_ranged_turn(_last_proj_source_idx)
	else:
		phase        = Phase.ENEMY_TURN
		action_timer = ACTION_DELAY


# ═══════════════════════════════════════════════════════════
#  PUSH
# ═══════════════════════════════════════════════════════════

func _apply_push(target: Node, push_val: int, from_pos: Vector2i) -> void:
	if push_val <= 0: return
	var dest = _push_destination(from_pos, Vector2i(target.grid_col, target.grid_row))
	if dest == Vector2i(-1, -1): return

	if not tiles.has(dest) or dest in column_tiles:
		target.take_damage(push_val)
		_spawn_damage_float(target.position, push_val)
		if target.hp <= 0: _on_enemy_killed(target)
		return

	var player_idx = _get_player_at(dest)
	if player_idx >= 0:
		target.take_damage(push_val)
		_spawn_damage_float(target.position, push_val)
		var p = players[player_idx]
		var real = p.take_damage(push_val)
		_spawn_damage_float(p.position, real)
		if target.hp <= 0: _on_enemy_killed(target)
		if p.hp <= 0:
			_on_player_died()
			return
		# Transfer push to the player
		var p_dest = _push_destination(from_pos, dest)
		if p_dest != Vector2i(-1, -1) and tiles.has(p_dest) \
		   and not (p_dest in column_tiles) \
		   and _get_enemy_at(p_dest) == null \
		   and _get_player_at(p_dest) < 0:
			p.grid_col = p_dest.x
			p.grid_row = p_dest.y
			player_positions[player_idx] = p_dest
			_move_entity_smooth(p, p_dest.x, p_dest.y)
		else:
			var wall_dmg = p.take_damage(push_val)
			_spawn_damage_float(p.position, wall_dmg)
			if p.hp <= 0:
				_on_player_died()
		return

	var blocker = _get_enemy_at(dest)
	if blocker:
		target.take_damage(1)
		blocker.take_damage(1)
		_spawn_damage_float(target.position, 1)
		_spawn_damage_float(blocker.position, 1)
		if blocker.hp <= 0: _on_enemy_killed(blocker)
		if target.hp  <= 0: _on_enemy_killed(target)
	else:
		target.grid_col = dest.x
		target.grid_row = dest.y
		_move_entity_smooth(target, dest.x, dest.y)

func _push_destination(from_pos: Vector2i, target_pos: Vector2i) -> Vector2i:
	var from_px   = _hex_to_pixel(from_pos.x,   from_pos.y)
	var target_px = _hex_to_pixel(target_pos.x, target_pos.y)
	var dir       = (target_px - from_px).normalized()
	var best      = Vector2i(-1, -1)
	var best_dot  = -INF
	for nb in _get_neighbors(target_pos.x, target_pos.y):
		if nb == from_pos: continue
		var nb_px  = _hex_to_pixel(nb.x, nb.y)
		var nb_dir = (nb_px - target_px).normalized()
		var dot    = dir.dot(nb_dir)
		if dot > best_dot:
			best_dot = dot
			best     = nb
	return best

# ═══════════════════════════════════════════════════════════
#  FLOOR CLEAR
# ═══════════════════════════════════════════════════════════

func _on_floor_cleared() -> void:
	if floor_cleared: return
	floor_cleared  = true
	sonny_w_used   = false
	mike_w_uses    = 1
	mike_caught_projectiles.clear()
	if sonny_bomb_enemy != null and sonny_bomb_enemy in enemies:
		enemies.erase(sonny_bomb_enemy)
		sonny_bomb_enemy.queue_free()
		sonny_bomb_enemy = null
	for p in players:
		p.floor_cleared = true
	phase = Phase.PLAYER_TURN
	_update_valid_moves()
	_refresh_tile_colors()
	_spawn_float_text(
		get_viewport_rect().size / 2.0 + Vector2(-80, -40),
		"FLOOR CLEARED!",
		Color(0.4, 1.0, 0.5)
	)
	_refresh_ui()
	var t = create_tween()
	t.tween_interval(1.5)
	t.tween_callback(_go_to_world_map)

func _go_to_world_map() -> void:
	var s : Dictionary = {}
	if Engine.has_meta("world_map_state"):
		s = Engine.get_meta("world_map_state")
	s["just_cleared"] = true
	Engine.set_meta("world_map_state", s)
	get_tree().change_scene_to_file("res://world_map.tscn")

# ═══════════════════════════════════════════════════════════
#  UI
# ═══════════════════════════════════════════════════════════

func _build_ui() -> void:
	var vp = get_viewport_rect().size

	timer_label          = Label.new()
	timer_label.position = Vector2(10.0, 10.0)
	timer_label.modulate = Color(1.0, 0.90, 0.30)
	add_child(timer_label)

	turn_label          = Label.new()
	turn_label.position = Vector2(vp.x / 2.0 - 70, 10)
	turn_label.modulate = Color(0.9, 0.85, 1.0)
	add_child(turn_label)

	hp_label          = Label.new()
	hp_label.position = Vector2(10, vp.y - 104)
	add_child(hp_label)

	actions_label          = Label.new()
	actions_label.position = Vector2(10, vp.y - 80)
	add_child(actions_label)

	q_box_label          = Label.new()
	q_box_label.position = Vector2(10, vp.y - 56)
	q_box_label.modulate = Color(0.7, 0.9, 1.0)
	add_child(q_box_label)

	dead_label          = Label.new()
	dead_label.position = Vector2(vp.x / 2.0 - 120, vp.y / 2.0 - 40)
	dead_label.visible  = false
	dead_label.modulate = Color(1.0, 0.2, 0.2)
	add_child(dead_label)

	undo_label          = Label.new()
	undo_label.position = Vector2(10, vp.y - 32)
	undo_label.text     = "[U] Undo move"
	add_child(undo_label)

	reset_label          = Label.new()
	reset_label.position = Vector2(180, vp.y - 32)
	reset_label.text     = "[K] Reset turn (1 use)"
	add_child(reset_label)

	_build_end_turn_confirm()

func _build_end_turn_confirm() -> void:
	var vp = get_viewport_rect().size
	var w = 460.0; var h = 170.0
	end_turn_confirm_panel = Panel.new()
	end_turn_confirm_panel.position = Vector2(vp.x / 2.0 - w / 2.0, vp.y / 2.0 - h / 2.0)
	end_turn_confirm_panel.size = Vector2(w, h)
	end_turn_confirm_panel.visible = false
	end_turn_confirm_panel.z_as_relative = false
	end_turn_confirm_panel.z_index = 200
	add_child(end_turn_confirm_panel)

	var msg = Label.new()
	msg.name = "MsgLabel"
	msg.position = Vector2(20, 18)
	msg.size = Vector2(420, 72)
	msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	end_turn_confirm_panel.add_child(msg)

	var yes_btn = Button.new()
	yes_btn.text = "Yes — End Turn  [Y]"
	yes_btn.position = Vector2(20, 110)
	yes_btn.size = Vector2(195, 42)
	yes_btn.pressed.connect(_on_end_turn_confirm_yes)
	end_turn_confirm_panel.add_child(yes_btn)

	var no_btn = Button.new()
	no_btn.text = "No — Keep Playing  [N]"
	no_btn.position = Vector2(240, 110)
	no_btn.size = Vector2(200, 42)
	no_btn.pressed.connect(_on_end_turn_confirm_no)
	end_turn_confirm_panel.add_child(no_btn)

func _show_end_turn_confirm() -> void:
	var cur = players[current_player_index]
	var act = cur.actions_left
	var msg = end_turn_confirm_panel.get_node("MsgLabel") as Label
	msg.text = player_names[current_player_index] + " still has " \
		+ str(act) + " action" + ("s" if act != 1 else "") + " left.\nEnd turn anyway?"
	end_turn_confirm_panel.visible = true

func _on_end_turn_confirm_yes() -> void:
	end_turn_confirm_panel.visible = false
	_end_player_turn()

func _on_end_turn_confirm_no() -> void:
	end_turn_confirm_panel.visible = false

func _refresh_ui() -> void:
	if not hp_label: return

	if timer_label:
		timer_label.text = "Time: %d min" % minutes_left

	var sonny = players[0]
	var mike  = players[1]
	var sh  = "♥".repeat(sonny.hp) + "♡".repeat(maxi(0, sonny.max_hp - sonny.hp))
	var mh  = "♥".repeat(mike.hp)  + "♡".repeat(maxi(0, mike.max_hp  - mike.hp))
	var bag = " [balls: " + str(mike_caught_projectiles.size()) + "]" \
			  if not mike_caught_projectiles.is_empty() else ""
	hp_label.text = "Sonny: " + sh + "   Mike: " + mh + bag

	var cur = players[current_player_index]
	if cur.floor_cleared:
		actions_label.text = player_names[current_player_index] + "  Actions: ∞"
	else:
		actions_label.text = player_names[current_player_index] + "  Actions: " \
							 + str(cur.actions_left) + "/2"

	var wd = cur.get_weapon_data()
	if sonny_charging:
		q_box_label.text = "Hold click to charge — RELEASE to strike!"
	elif mike_aiming and not mike_shot_committed:
		q_box_label.text = "[Q] Draw Shot — aim with mouse, LEFT CLICK to fire    [R-click] Cancel"
	elif mike_shot_committed:
		q_box_label.text = "Hold & drag backward — RELEASE to fire!"
	elif bomb_mode:
		q_box_label.text = "[W] BOMB — click adjacent tile to place    [R-click] Cancel"
	elif mike_grappling:
		q_box_label.text = "[W] GRAPPLE — click any target to pull    [R-click] Cancel"
	else:
		var w_name = wd.get("w_name", "")
		var w_uses = ""
		if w_name != "":
			if player_names[current_player_index] == "Sonny":
				w_uses = " (" + ("0" if sonny_w_used else "1") + " left)"
			else:
				w_uses = " (" + str(mike_w_uses) + " left)"
		var w_hint = ("    [W] " + w_name + w_uses) if w_name != "" else ""
		q_box_label.text = "[Q] " + wd.get("q_name", "Q") + " — " + wd.get("q_desc", "") \
						 + w_hint + "    [Tab] Switch    [D] End turn"

	match phase:
		Phase.PLAYER_TURN:
			turn_label.text = "▶ " + player_names[current_player_index] + "'s Turn"
		Phase.ENEMY_TURN:
			turn_label.text = "Enemy Turn"
		Phase.DODGE_PHASE:
			if sonny_charging:
				turn_label.text = "— Charge the Boong! —"
			elif mike_shot_committed:
				turn_label.text = "Draw & release!"
			else:
				turn_label.text = "— Press SPACE to dodge —"
		Phase.DEAD:
			turn_label.text = ""

	var is_player_phase = (phase == Phase.PLAYER_TURN and enemy_turn_transition_timer < 0.0)
	if undo_label:
		undo_label.visible  = is_player_phase
		undo_label.modulate = Color(0.7, 0.9, 1.0) if not attack_committed_this_round \
							  else Color(0.35, 0.35, 0.35)
	if reset_label:
		reset_label.visible  = is_player_phase
		reset_label.modulate = Color(1.0, 0.8, 0.4) if not reset_turn_used \
							   else Color(0.35, 0.35, 0.35)

func _show_death_screen() -> void:
	if dead_label:
		dead_label.text    = "YOU DIED\nPress ENTER to restart"
		dead_label.visible = true

# ═══════════════════════════════════════════════════════════
#  INPUT
# ═══════════════════════════════════════════════════════════

func _input(event: InputEvent) -> void:
	if enemy_turn_transition_timer > 0.0: return
	if phase == Phase.DEAD:
		if event is InputEventKey and event.keycode == KEY_ENTER and event.pressed:
			_restart()
		return

	if end_turn_confirm_panel and end_turn_confirm_panel.visible:
		if event is InputEventKey and event.pressed:
			match event.keycode:
				KEY_Y: _on_end_turn_confirm_yes()
				KEY_N, KEY_ESCAPE: _on_end_turn_confirm_no()
		return

	# Sonny's charge bar — intercept mouse release while holding
	if sonny_charging and sonny_charge_bar != null:
		if event is InputEventMouseButton \
		  and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
			sonny_charge_bar.is_holding = false
			sonny_charge_bar.resolve()
		return

	# Mike's timing drag — intercept while timing bar is live
	if mike_shot_committed and mike_timing_bar != null:
		if event is InputEventMouseButton \
		  and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			mike_timing_bar.queue_free()
			mike_timing_bar     = null
			mike_shot_committed = false
			mike_aiming         = false
			attack_mode         = ""
			mike_trajectory     = []
			aim_overlay.trajectory = []
			aim_overlay.queue_redraw()
			phase = Phase.PLAYER_TURN
			_refresh_tile_colors()
			_refresh_ui()
			return
		if event is InputEventMouseMotion:
			# Direction is LOCKED on left-click — only drag offset affects timing ball
			mike_timing_bar.update_drag(event.position)
		elif event is InputEventMouseButton \
		  and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
			mike_timing_bar.resolve()
		return  # block all other input until resolved

	# Projectile reaction — SPACE during live projectile flight (Section 5B)
	if phase == Phase.DODGE_PHASE and not live_proj_states.is_empty():
		if event is InputEventKey and event.pressed and event.keycode == KEY_SPACE:
			_handle_proj_space_press(get_viewport().get_mouse_position())
			return

	if phase == Phase.PLAYER_TURN:
		_handle_player_input(event)

func _cancel_mike_aim() -> void:
	mike_aiming    = false
	attack_mode    = ""
	mike_trajectory = []
	aim_overlay.trajectory = []
	aim_overlay.queue_redraw()
	_refresh_tile_colors()

func _handle_player_input(event: InputEvent) -> void:
	var current_player = players[current_player_index]
	if current_player.hp <= 0: return

	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_Q:
				if not current_player.can_act(): return
				if current_player.has_attacked: return
				if current_player.disarmed: return
				if players[current_player_index].uses_draw_shot:
					# Toggle Draw Shot aim mode
					if mike_aiming:
						_cancel_mike_aim()
					else:
						mike_aiming = true
						attack_mode = "Q"
						_compute_mike_trajectory()
						_refresh_ui()
				else:
					attack_mode  = "" if attack_mode == "Q" else "Q"
					attack_tiles = []
					_refresh_tile_colors()
			KEY_D:
				var cur_d = players[current_player_index]
				if cur_d.actions_left > 0 and not cur_d.floor_cleared:
					_show_end_turn_confirm()
				else:
					_end_player_turn()
			KEY_U:
				_undo_move()
			KEY_K:
				_reset_turn()
			KEY_TAB:
				_switch_player_to_other()
			KEY_W:
				if not current_player.can_act(): return
				if current_player.has_attacked: return
				if not current_player.disarmed:
					_handle_w_key(current_player)

	if event is InputEventMouseMotion:
		if players[current_player_index].uses_draw_shot and mike_aiming:
			var mike_px   = players[current_player_index].position
			var to_mouse  = event.position - mike_px
			if to_mouse.length() > 8.0:
				# Shot direction is OPPOSITE of pull-back (bow logic)
				mike_aim_dir = to_mouse.normalized()
			_compute_mike_trajectory()
		elif attack_mode != "" and attack_mode != "W":
			attack_tiles = _get_attack_tiles_for_mode(attack_mode, event.position)
			_refresh_tile_colors()

	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			if players[current_player_index].uses_draw_shot and mike_aiming:
				# Commit the shot and start timing
				mike_shot_dir       = mike_aim_dir
				mike_shot_committed = true
				phase               = Phase.DODGE_PHASE
				_spawn_mike_timing_bar(event.position)
			else:
				_handle_left_click(event.position)
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			if mike_aiming:
				_cancel_mike_aim()
			attack_mode    = ""
			attack_tiles   = []
			bomb_mode      = false
			mike_grappling = false
			_refresh_tile_colors()

func _handle_left_click(click_pos: Vector2) -> void:
	if attack_mode == "W":
		var clicked = _pixel_to_hex(click_pos)
		if clicked in attack_tiles:
			if bomb_mode:
				_place_bomb(clicked)
			elif mike_grappling:
				_execute_grapple(clicked)
		return
	if attack_mode != "":
		attack_tiles = _get_attack_tiles_for_mode(attack_mode, click_pos)
		if attack_tiles.is_empty():
			_spawn_float_text(click_pos + Vector2(-50, -20), "Invalid target!", Color(1, 0.4, 0.4))
		else:
			var cur    = players[current_player_index]
			var q_mode = cur.get_weapon_data().get("q_mode", "")
			if attack_mode == "Q" and q_mode == "charge_bar":
				_spawn_sonny_charge_bar(attack_tiles[0])
			else:
				_spawn_attack_bar(attack_mode)
	else:
		var clicked = _pixel_to_hex(click_pos)
		if clicked in valid_moves:
			_move_player(clicked)

func _move_player(dest: Vector2i) -> void:
	if not players[current_player_index].can_act(): return
	player_positions[current_player_index] = dest
	var current_player = players[current_player_index]
	current_player.grid_col = dest.x
	current_player.grid_row = dest.y
	current_player.tiles_traveled_this_turn += 1
	_move_entity_smooth(current_player, dest.x, dest.y)

	current_player.use_action()
	_update_valid_moves()
	_refresh_tile_colors()
	_refresh_ui()

# ═══════════════════════════════════════════════════════════
#  ATTACK BAR (player attacking)
# ═══════════════════════════════════════════════════════════

func _spawn_attack_bar(mode: String) -> void:
	pending_attack_mode = mode
	phase = Phase.DODGE_PHASE

	var current_player = players[current_player_index]
	var bar = DodgeBarScene.instantiate()
	bar.setup(0.75, 1.0)
	bar.position = current_player.position + Vector2(0, -60)
	add_child(bar)
	bar.bar_finished.connect(_on_attack_bar_resolved)
	active_attack_bar = bar

func _on_attack_bar_resolved(result: String) -> void:
	active_attack_bar = null
	phase = Phase.PLAYER_TURN

	match result:
		"perfect":
			_execute_attack(pending_attack_mode, "hit")
		"dodged":
			_execute_attack(pending_attack_mode, "hit")
		"hit":
			_execute_attack(pending_attack_mode, "miss")

	pending_attack_mode = ""
	_refresh_ui()

# ═══════════════════════════════════════════════════════════
#  DODGE BAR (enemy attacking player)
# ═══════════════════════════════════════════════════════════

func _spawn_dodge_bar(enemy: Node, target_player_idx: int) -> void:
	phase = Phase.DODGE_PHASE
	dodge_target_player_idx = target_player_idx
	current_player_index    = target_player_idx
	_refresh_ui()

	var target_player = players[target_player_idx]
	var bar = DodgeBarScene.instantiate()
	bar.setup(enemy.dodge_line, 1.0)
	bar.position = enemy.position + Vector2(0, -50)
	add_child(bar)
	bar.bar_finished.connect(_on_dodge_resolved)
	active_dodge_bar = bar

func _on_dodge_resolved(result: String) -> void:
	active_dodge_bar = null
	phase = Phase.ENEMY_TURN

	var target_player = players[dodge_target_player_idx]
	var px_pos = target_player.position

	match result:
		"perfect":
			_spawn_float_text(px_pos + Vector2(0, -50), "PERFECT!", Color(0.3, 1.0, 0.5))
		"dodged":
			_spawn_float_text(px_pos + Vector2(0, -50), "DODGED!", Color(0.9, 0.9, 0.3))
		"hit":
			var dmg = target_player.take_damage(1)
			_spawn_float_text(px_pos + Vector2(0, -50), "HIT! -" + str(dmg) + " HP", Color(1.0, 0.3, 0.3))
			if target_player.hp <= 0:
				_on_player_died()
				return

	action_timer = ACTION_DELAY
	_refresh_ui()

# ═══════════════════════════════════════════════════════════
#  TURN MANAGEMENT
# ═══════════════════════════════════════════════════════════

func _end_player_turn() -> void:
	attack_mode  = ""
	attack_tiles = []
	if current_player_index not in players_turned_this_round:
		players_turned_this_round.append(current_player_index)
	# Find the next player who hasn't had their turn this round
	var next_idx : int = -1
	for i in range(1, players.size() + 1):
		var idx = (current_player_index + i) % players.size()
		if idx not in players_turned_this_round:
			next_idx = idx
			break
	if next_idx == -1:
		# All players have acted → enemy phase after brief delay
		current_player_index = 0
		_begin_enemy_turn()
	else:
		current_player_index = next_idx
		_start_player_turn()

func _begin_enemy_turn() -> void:
	enemy_turn_transition_timer = ACTION_DELAY

# ─── Undo / Reset ────────────────────────────────────────────────────────────

func _save_turn_snapshot() -> void:
	var pos_copy  : Array = []
	var grid_copy : Array = []
	var perf_copy : Array = []
	for i in range(players.size()):
		pos_copy.append(player_positions[i])
		grid_copy.append({"col": players[i].grid_col, "row": players[i].grid_row})
		perf_copy.append(players[i].perfection)
	var enemy_copy : Array = []
	for e in enemies:
		enemy_copy.append({
			"type":         e.enemy_type,
			"col":          e.grid_col,
			"row":          e.grid_row,
			"hp":           e.hp,
			"bleed_stacks": e.bleed_stacks,
		})
	turn_snapshot = {
		"player_positions": pos_copy,
		"player_grids":     grid_copy,
		"player_perfection": perf_copy,
		"enemies":          enemy_copy,
		"mike_w_uses":      mike_w_uses,
		"sonny_w_used":     sonny_w_used,
	}
	attack_committed_this_round = false

func _undo_move() -> void:
	if attack_committed_this_round: return
	if turn_snapshot.is_empty(): return
	var offset = _grid_center_offset()
	for i in range(players.size()):
		var g = turn_snapshot["player_grids"][i]
		players[i].grid_col = g["col"]
		players[i].grid_row = g["row"]
		player_positions[i] = turn_snapshot["player_positions"][i]
		players[i].position = _hex_to_pixel(g["col"], g["row"]) + offset
		players[i].reset_turn()
	players_turned_this_round = []
	current_player_index = 0
	_start_player_turn()

func _reset_turn() -> void:
	if reset_turn_used: return
	if turn_snapshot.is_empty(): return
	reset_turn_used = true
	var offset = _grid_center_offset()
	# Restore player positions and stats
	for i in range(players.size()):
		var g = turn_snapshot["player_grids"][i]
		players[i].grid_col = g["col"]
		players[i].grid_row = g["row"]
		player_positions[i] = turn_snapshot["player_positions"][i]
		players[i].position = _hex_to_pixel(g["col"], g["row"]) + offset
		players[i].reset_turn()
		players[i].perfection = turn_snapshot["player_perfection"][i]
	mike_w_uses = turn_snapshot["mike_w_uses"]
	sonny_w_used = turn_snapshot["sonny_w_used"]
	# Destroy all current enemies and respawn from snapshot
	for e in enemies.duplicate():
		e.queue_free()
	enemies.clear()
	sonny_bomb_enemy = null
	for snap in turn_snapshot["enemies"]:
		var e = _spawn_enemy(snap["type"], snap["col"], snap["row"])
		e.hp = snap["hp"]
		e.bleed_stacks = snap["bleed_stacks"]
		e.refresh_hp_bar()
		if snap["type"] == "bomb":
			sonny_bomb_enemy = e
	attack_committed_this_round = false
	players_turned_this_round = []
	current_player_index = 0
	_start_player_turn()

func _start_player_turn() -> void:
	phase = Phase.PLAYER_TURN
	_update_valid_moves()
	_refresh_tile_colors()
	_refresh_ui()
	_tick_bleed()

func _decrement_timer() -> void:
	minutes_left = maxi(0, minutes_left - 1)
	if Engine.has_meta("world_map_state"):
		var s = Engine.get_meta("world_map_state")
		s["minutes_left"] = minutes_left
		Engine.set_meta("world_map_state", s)

func _start_enemy_turn() -> void:
	phase        = Phase.ENEMY_TURN
	attack_mode  = ""
	attack_tiles = []
	_refresh_tile_colors()

	enemies.sort_custom(func(a, b):
		var da = _nearest_player_dist(a)
		var db = _nearest_player_dist(b)
		if da != db: return da < db
		if a.grid_row != b.grid_row: return a.grid_row < b.grid_row
		return a.grid_col < b.grid_col
	)

	action_queue = []
	for e in enemies:
		e.has_attacked_this_turn = false
		if e.actions_per_turn > 0:
			action_queue.append([e, e.actions_per_turn])
	action_timer = ACTION_DELAY

func _nearest_player_dist(enemy: Node) -> int:
	var min_d = 9999
	for p in players:
		var d = _hex_dist(enemy.grid_col, enemy.grid_row, p.grid_col, p.grid_row)
		if d < min_d: min_d = d
	return min_d

func _nearest_player_idx(enemy: Node) -> int:
	var min_d = 9999
	var idx   = 0
	for i in range(players.size()):
		var d = _hex_dist(enemy.grid_col, enemy.grid_row, players[i].grid_col, players[i].grid_row)
		if d < min_d:
			min_d = d
			idx   = i
	return idx

func _tick_bleed() -> void:
	for e in enemies.duplicate():
		if e.bleed_stacks > 0:
			e.take_damage(e.bleed_stacks)
			_spawn_damage_float(e.position, e.bleed_stacks)
			if e.hp <= 0:
				_on_enemy_killed(e)

func _process(delta: float) -> void:
	if enemy_turn_transition_timer > 0.0:
		enemy_turn_transition_timer -= delta
		if enemy_turn_transition_timer <= 0.0:
			enemy_turn_transition_timer = -1.0
			_start_enemy_turn()
	elif phase == Phase.ENEMY_TURN:
		_process_enemy_turn(delta)
	if not live_proj_states.is_empty():
		_process_live_projectiles(delta)

func _process_enemy_turn(delta: float) -> void:
	if action_queue.is_empty():
		players_turned_this_round = []
		for p in players:
			p.reset_turn()
		if not players[0].floor_cleared:
			_decrement_timer()
		_save_turn_snapshot()
		_start_player_turn()
		return

	action_timer -= delta
	if action_timer > 0: return
	action_timer = ACTION_DELAY

	var entry = action_queue[0]
	var enemy = entry[0]

	# Skip enemies that died mid-queue
	if enemy not in enemies:
		action_queue.pop_front()
		return

	# Build occupied set
	var occupied : Dictionary = {}
	for p in players:
		occupied[Vector2i(p.grid_col, p.grid_row)] = true
	for e in enemies:
		if e != enemy:
			occupied[Vector2i(e.grid_col, e.grid_row)] = true

	var nearest_idx = _nearest_player_idx(enemy)
	var nearest     = players[nearest_idx]
	var action      = enemy.plan_action(nearest.grid_col, nearest.grid_row, GRID_COLS, GRID_ROWS)

	match action:
		"move":
			var best = enemy.best_move_toward(nearest.grid_col, nearest.grid_row, occupied, self)
			if best != Vector2i(-1, -1):
				enemy.grid_col = best.x
				enemy.grid_row = best.y
				_move_entity_smooth(enemy, best.x, best.y)
				_refresh_tile_colors()
			entry[1] -= 1
			if entry[1] <= 0:
				action_queue.pop_front()

		"move_away":
			var best = enemy.best_move_away(nearest.grid_col, nearest.grid_row, occupied, self)
			if best != Vector2i(-1, -1):
				enemy.grid_col = best.x
				enemy.grid_row = best.y
				_move_entity_smooth(enemy, best.x, best.y)
				_refresh_tile_colors()
			entry[1] -= 1
			if entry[1] <= 0:
				action_queue.pop_front()

		"attack":
			if not enemy.has_attacked_this_turn:
				var atk = enemy.get_current_attack()
				if atk.get("range", 1) > 1:
					_enemy_ranged_attack(enemy, nearest_idx, atk)
				else:
					_spawn_dodge_bar(enemy, nearest_idx)
				enemy.advance_attack()
				enemy.has_attacked_this_turn = true
				entry[1] -= 1
				if entry[1] <= 0:
					action_queue.pop_front()
				return
			else:
				# Already attacked — consume remaining action as idle
				entry[1] -= 1
				if entry[1] <= 0:
					action_queue.pop_front()

		"idle":
			action_queue.pop_front()

	_update_valid_moves()
	_refresh_tile_colors()

# ═══════════════════════════════════════════════════════════
#  DEATH & RESTART
# ═══════════════════════════════════════════════════════════

func _on_player_died() -> void:
	phase = Phase.DEAD
	_show_death_screen()

func _restart() -> void:
	get_tree().reload_current_scene()

# ═══════════════════════════════════════════════════════════
#  FLOAT TEXT
# ═══════════════════════════════════════════════════════════

func _spawn_damage_float(world_pos: Vector2, amount: int) -> void:
	var label    = Label.new()
	label.text   = "-" + str(amount) if amount > 0 else "0"
	label.position = world_pos + Vector2(-10, -40)
	label.modulate = Color(1.0, 0.3, 0.3)
	add_child(label)
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "position:y", world_pos.y - 80, 0.8)
	tween.tween_property(label, "modulate:a", 0.0,              0.8)
	tween.chain().tween_callback(label.queue_free)

func _spawn_float_text(world_pos: Vector2, text: String, color: Color) -> void:
	var label    = Label.new()
	label.text   = text
	label.position = world_pos
	label.modulate = color
	add_child(label)
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "position:y", world_pos.y - 50, 1.0)
	tween.tween_property(label, "modulate:a", 0.0,              1.0)
	tween.chain().tween_callback(label.queue_free)
