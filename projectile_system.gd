class_name ProjectileSystem
extends Node

# ═══════════════════════════════════════════════════════════
#  ProjectileSystem — real-time bouncing projectile management.
#  ► Spawn/track projectiles, per-frame collision (wall/column/character).
#  ► Player reaction window (SPACE) cho Sonny redirect / Mike catch / dodge.
#  ► Bounce trace cho aim preview (compute_projectile_trace).
#  Needs main reference cho entity state, hex math, HUD update.
# ═══════════════════════════════════════════════════════════

const ProjectileScene = preload("res://projectile.tscn")

const PROJ_ENEMY_SPEED_SLOW   : float = 5.0
const PROJ_ENEMY_SPEED_NORMAL : float = 8.0
const PROJ_ENEMY_SPEED_FAST   : float = 14.0
const PROJECTILE_Y            : float = 1.10

# ─── State ──────────────────────────────────────────────────
var main : Node = null
var active_projectiles  : Array      = []
var _proj_last_col_hex  : Dictionary = {}    # instance_id → Vector2i
var _proj_last_char_hex : Dictionary = {}    # instance_id → Vector2i
var _proj_prev_pos      : Dictionary = {}    # instance_id → Vector3
var _proj_bounds_min    : Vector3    = Vector3.ZERO
var _proj_bounds_max    : Vector3    = Vector3.ZERO

func setup(main_ref: Node) -> void:
	main = main_ref

func compute_bounds(grid_origin: Vector3, grid_cols: int, grid_rows: int) -> void:
	_proj_bounds_min = Vector3(grid_origin.x - 0.6, PROJECTILE_Y, grid_origin.z - 0.6)
	_proj_bounds_max = Vector3(
		grid_origin.x + HexUtils.HEX_SIZE * 1.5 * float(grid_cols) + 0.6,
		PROJECTILE_Y,
		grid_origin.z + HexUtils.HEX_SIZE * sqrt(3.0) * float(grid_rows) + 0.6)

# ═══════════════════════════════════════════════════════════
#  PUBLIC API
# ═══════════════════════════════════════════════════════════

# Build BounceTracer3D + trace projectile path từ shooter đến target_pos.
# Trả { segs, hit_hexes }.
func compute_projectile_trace(shooter, target_pos: Vector3) -> Dictionary:
	var tracer := BounceTracer3D.new()
	tracer.bounds_min = _proj_bounds_min
	tracer.bounds_max = _proj_bounds_max
	tracer.columns = main.column_tiles.duplicate()
	var enemy_dict : Dictionary = {}
	for e in main.enemies:
		if is_instance_valid(e) and e.hp > 0:
			enemy_dict[Vector2i(e.grid_col, e.grid_row)] = true
	for i in range(main.players.size()):
		if main.players[i] != shooter:
			enemy_dict[main.player_positions[i]] = true
	tracer.entities = enemy_dict
	tracer.hex_to_world = main.hex_to_world
	tracer.world_to_hex = func(p: Vector3) -> Vector2i: return main.world_to_hex(p)
	tracer.launch_speed    = shooter.proj_launch_speed
	tracer.decay_rate      = shooter.proj_decay_rate
	tracer.min_speed       = shooter.proj_min_speed
	tracer.negative_bounce = shooter.proj_neg_bounce
	var shooter_pos : Vector3 = shooter.position
	var dir : Vector3 = Vector3(target_pos.x - shooter_pos.x, 0.0,
		target_pos.z - shooter_pos.z).normalized()
	var start : Vector3 = Vector3(shooter_pos.x, PROJECTILE_Y, shooter_pos.z)
	var exclude_hexes : Dictionary = {
		Vector2i(shooter.grid_col, shooter.grid_row): true
	}
	return tracer.trace(start, dir, false, exclude_hexes)

# Spawn + register projectile.
func fire(owner_nd: Node, start_pos: Vector3, direction: Vector3,
		damage: float, uses_decay: bool, neg_bounce: float,
		speed: float) -> Projectile3D:
	var proj : Projectile3D = ProjectileScene.instantiate()
	proj.proj_speed      = speed
	proj.proj_direction  = Vector3(direction.x, 0.0, direction.z).normalized()
	proj.proj_damage     = damage
	proj.negative_bounce = neg_bounce
	proj.owner_node      = owner_nd
	proj.uses_decay      = uses_decay
	main.add_child(proj)
	proj.position = Vector3(start_pos.x, PROJECTILE_Y, start_pos.z)
	active_projectiles.append(proj)
	proj.projectile_died.connect(_on_proj_died.bind(proj))
	return proj

func fire_enemy_projectile(enemy: Node, target_idx: int, attack: Dictionary) -> Projectile3D:
	var target_p = main.players[target_idx]
	var dir := Vector3(target_p.position.x - enemy.position.x, 0.0,
		target_p.position.z - enemy.position.z).normalized()
	var start := Vector3(enemy.position.x, PROJECTILE_Y, enemy.position.z)
	var dmg : float = float(attack.get("damage", 1))
	var speed_key : String = str(attack.get("speed", "normal"))
	var spd : float = {
		"slow":   PROJ_ENEMY_SPEED_SLOW,
		"fast":   PROJ_ENEMY_SPEED_FAST,
	}.get(speed_key, PROJ_ENEMY_SPEED_NORMAL)
	return fire(enemy, start, dir, dmg, false, 9999.0, spd)

func fire_mike_caught_projectiles_async(shooter: Node, direction: Vector3) -> void:
	var caught : Array = shooter.caught_projectiles.duplicate()
	shooter.caught_projectiles.clear()
	for cd in caught:
		await get_tree().create_timer(0.30).timeout
		if not is_instance_valid(shooter): break
		var start := Vector3(shooter.position.x, PROJECTILE_Y, shooter.position.z)
		fire(shooter, start, direction,
			float(cd.get("damage", 1.0)),
			bool(cd.get("uses_decay", false)),
			float(cd.get("neg_bounce", 9999.0)),
			float(cd.get("speed", PROJ_ENEMY_SPEED_NORMAL)))

# ═══════════════════════════════════════════════════════════
#  PER-FRAME COLLISION
# ═══════════════════════════════════════════════════════════

func process_projectiles(_delta: float) -> void:
	for proj in active_projectiles.duplicate():
		if not is_instance_valid(proj): continue
		var pid      : int     = proj.get_instance_id()
		var cur_pos  : Vector3 = proj.position
		var prev_pos : Vector3 = _proj_prev_pos.get(pid, cur_pos)
		_check_proj_wall(proj, prev_pos)
		if not is_instance_valid(proj): continue
		_check_proj_column(proj, cur_pos, prev_pos)
		if not is_instance_valid(proj): continue
		_check_proj_characters(proj, cur_pos, prev_pos)
		if is_instance_valid(proj):
			_proj_prev_pos[pid] = proj.position

func _on_proj_died(proj: Projectile3D) -> void:
	active_projectiles.erase(proj)
	var pid : int = proj.get_instance_id()
	_proj_last_col_hex.erase(pid)
	_proj_last_char_hex.erase(pid)
	_proj_prev_pos.erase(pid)

func _wall_crossing_point(from_pos: Vector3, to_pos: Vector3) -> Vector3:
	var t  : float = 1.0
	var dx : float = to_pos.x - from_pos.x
	var dz : float = to_pos.z - from_pos.z
	if dx > 0.0001 and to_pos.x > _proj_bounds_max.x:
		t = minf(t, (_proj_bounds_max.x - from_pos.x) / dx)
	elif dx < -0.0001 and to_pos.x < _proj_bounds_min.x:
		t = minf(t, (_proj_bounds_min.x - from_pos.x) / dx)
	if dz > 0.0001 and to_pos.z > _proj_bounds_max.z:
		t = minf(t, (_proj_bounds_max.z - from_pos.z) / dz)
	elif dz < -0.0001 and to_pos.z < _proj_bounds_min.z:
		t = minf(t, (_proj_bounds_min.z - from_pos.z) / dz)
	t = clampf(t, 0.0, 1.0)
	return Vector3(from_pos.x + t * dx, PROJECTILE_Y, from_pos.z + t * dz)

func _check_proj_wall(proj: Projectile3D, prev_pos: Vector3) -> void:
	var p := proj.position
	if p.x >= _proj_bounds_min.x and p.x <= _proj_bounds_max.x \
			and p.z >= _proj_bounds_min.z and p.z <= _proj_bounds_max.z:
		return
	var normal := Vector3.ZERO
	if   p.x < _proj_bounds_min.x: normal.x =  1.0
	elif p.x > _proj_bounds_max.x: normal.x = -1.0
	if   p.z < _proj_bounds_min.z: normal.z =  1.0
	elif p.z > _proj_bounds_max.z: normal.z = -1.0
	if normal.length_squared() < 0.001: normal = Vector3.RIGHT
	proj.position = _wall_crossing_point(prev_pos, p)
	proj.bounce_off_surface(normal.normalized())

func _check_proj_column(proj: Projectile3D, cur_pos: Vector3, _prev_pos: Vector3) -> void:
	var pid      : int      = proj.get_instance_id()
	var cur_hex  : Vector2i = main.world_to_hex(cur_pos)
	var last_col : Vector2i = _proj_last_col_hex.get(pid, Vector2i(-9999, -9999))
	if cur_hex in main.column_tiles:
		if cur_hex != last_col:
			_proj_last_col_hex[pid] = cur_hex
			var col_c : Vector3 = main.hex_to_world(cur_hex.x, cur_hex.y)
			var n : Vector3 = Vector3(cur_pos.x - col_c.x, 0.0, cur_pos.z - col_c.z)
			if n.length_squared() < 0.0001: n = Vector3.FORWARD
			proj.bounce_off_surface(n.normalized())
	else:
		_proj_last_col_hex.erase(pid)

func _check_proj_characters(proj: Projectile3D, cur_pos: Vector3, _prev_pos: Vector3) -> void:
	var pid     : int      = proj.get_instance_id()
	var cur_hex : Vector2i = main.world_to_hex(cur_pos)
	var last    : Vector2i = _proj_last_char_hex.get(pid, Vector2i(-9999, -9999))

	var hit_enemy : Node = main._get_enemy_at(cur_hex)
	if hit_enemy != null and hit_enemy != proj.owner_node and cur_hex != last:
		_proj_last_char_hex[pid] = cur_hex
		_handle_enemy_proj_hit(proj, hit_enemy)
		return

	for i in range(main.players.size()):
		if main.player_positions[i] == cur_hex \
				and main.players[i] != proj.owner_node and cur_hex != last:
			_proj_last_char_hex[pid] = cur_hex
			_handle_player_proj_contact_async(proj, i)
			return

	if cur_hex != last:
		_proj_last_char_hex.erase(pid)

# ═══════════════════════════════════════════════════════════
#  HIT HANDLERS
# ═══════════════════════════════════════════════════════════

func _handle_enemy_proj_hit(proj: Projectile3D, enemy: Node) -> void:
	if proj.is_supercharged:
		_supercharged_explosion(proj, Vector2i(enemy.grid_col, enemy.grid_row))
		return
	enemy.take_damage(proj.proj_damage)
	main._spawn_damage_popup(enemy.position + Vector3(0, 1.8, 0),
		"-%d" % int(proj.proj_damage), Color(1.0, 0.55, 0.30))
	if enemy.hp <= 0:
		main._kill_enemy(enemy)
	elif main.hud != null:
		main.hud.update_enemy_hp(enemy.get_instance_id(), enemy.hp, enemy.max_hp)
	main._check_floor_clear()
	if is_instance_valid(proj) and not proj._dead:
		var e_center : Vector3 = main.hex_to_world(enemy.grid_col, enemy.grid_row)
		var n : Vector3 = Vector3(proj.position.x - e_center.x, 0.0,
			proj.position.z - e_center.z)
		if n.length_squared() < 0.0001: n = Vector3.FORWARD
		proj.bounce_off_surface(n.normalized())

func _handle_player_proj_contact_async(proj: Projectile3D, player_idx: int) -> void:
	if not is_instance_valid(proj): return
	proj.set_process(false)
	var prev_phase = main.phase
	main.phase = main.Phase.DODGE_PHASE

	var contact_t : float = Time.get_ticks_msec() / 1000.0
	var result    : String = ""

	var pre_rel : float = contact_t - main._space_pressed_at
	if   pre_rel >= 0.0 and pre_rel <= 0.20: result = "perfect"
	elif pre_rel >= 0.0 and pre_rel <= 0.40: result = "ok"

	if result == "":
		var old_press : float = main._space_pressed_at
		var waited    : float = 0.0
		while waited < 0.40:
			await get_tree().process_frame
			waited += get_process_delta_time()
			if main._space_pressed_at != old_press:
				var post_rel : float = main._space_pressed_at - contact_t
				if   post_rel >= 0.0 and post_rel <= 0.20: result = "perfect"; break
				elif post_rel >= 0.0 and post_rel <= 0.40: result = "ok";      break
				old_press = main._space_pressed_at

	if result == "": result = "miss"

	if not is_instance_valid(proj):
		main.phase = prev_phase
		return

	var player = main.players[player_idx]
	var is_sonny : bool = not player.uses_draw_shot
	var head_pos : Vector3 = player.position + Vector3(0, 1.9, 0)

	match result:
		"perfect":
			if is_sonny:
				var _mike : Node = null
				for _p in main.players:
					if _p.uses_draw_shot: _mike = _p; break
				proj.negative_bounce = _mike.proj_neg_bounce    if _mike else 5.0
				proj.proj_speed      = minf(proj.proj_speed,
					_mike.proj_launch_speed if _mike else 18.0)
				proj.uses_decay      = true
				var mouse_dir : Vector3 = Vector3(
					main.hover_world_pos.x - player.position.x, 0.0,
					main.hover_world_pos.z - player.position.z)
				if mouse_dir.length_squared() < 0.001:
					mouse_dir = -proj.proj_direction
				proj.redirect_to(mouse_dir)
				proj.set_process(true)
				main._spawn_damage_popup(head_pos, "REDIRECT!", Color(0.31, 1.00, 0.51))
				player.perfection = mini(player.perfection + 1, player.perfection_cap)
				main._refresh_hud()
			else:
				if proj.owner_node != player:
					if player.caught_projectiles.size() < player.caught_capacity:
						player.caught_projectiles.append({
							"damage":     proj.proj_damage,
							"speed":      proj.proj_speed,
							"neg_bounce": player.proj_neg_bounce,
							"uses_decay": proj.uses_decay,
						})
						main._spawn_damage_popup(head_pos, "CAUGHT!", Color(0.31, 1.00, 0.51))
					else:
						main._spawn_damage_popup(head_pos, "BAG FULL!", Color(1.0, 0.4, 0.2))
				else:
					main._spawn_damage_popup(head_pos, "DODGE!", Color(0.95, 0.90, 0.30))
				proj.die()
				player.perfection = mini(player.perfection + 1, player.perfection_cap)
				main._refresh_hud()
		"ok":
			main._spawn_damage_popup(head_pos, "DODGE!", Color(0.95, 0.90, 0.30))
			player.perfection = mini(player.perfection + 1, player.perfection_cap)
			var pid : int = proj.get_instance_id()
			_proj_last_char_hex.erase(pid)
			proj.set_process(true)
			main._refresh_hud()
			main.phase = prev_phase
			return
		"miss":
			if proj.is_supercharged:
				_supercharged_explosion(proj, main.player_positions[player_idx])
				main.phase = prev_phase
				return
			main._apply_damage_to_player(player_idx, int(proj.proj_damage), "hit")
			if is_instance_valid(proj) and not proj._dead:
				var p_center : Vector3 = main.hex_to_world(
					main.player_positions[player_idx].x,
					main.player_positions[player_idx].y)
				var n : Vector3 = Vector3(proj.position.x - p_center.x, 0.0,
					proj.position.z - p_center.z)
				if n.length_squared() < 0.0001: n = Vector3.FORWARD
				proj.bounce_off_surface(n.normalized())
				if is_instance_valid(proj) and not proj._dead:
					proj.set_process(true)

	main.phase = prev_phase

# Supercharged AoE explosion (Sonny 3 redirects).
func _supercharged_explosion(proj: Projectile3D, impact_hex: Vector2i) -> void:
	var center_w : Vector3 = main.hex_to_world(impact_hex.x, impact_hex.y)
	main._spawn_damage_popup(center_w + Vector3(0, 2.0, 0),
		"SUPERCHARGE!", Color(1.0, 0.2, 0.05))
	var aoe : Array = [impact_hex] + main._get_neighbors(impact_hex.x, impact_hex.y)
	for hex in aoe:
		var extra_dmg : int = 1 if hex == impact_hex else 0
		var total_dmg : int = int(proj.proj_damage) + extra_dmg
		var e : Node = main._get_enemy_at(hex)
		if e != null:
			e.take_damage(total_dmg)
			main._spawn_damage_popup(e.position + Vector3(0, 1.8, 0),
				"-%d" % total_dmg, Color(1.0, 0.2, 0.05))
			if e.hp <= 0: main._kill_enemy(e)
			elif main.hud != null: main.hud.update_enemy_hp(
				e.get_instance_id(), e.hp, e.max_hp)
		var p_idx : int = main._get_player_at(hex)
		if p_idx >= 0:
			main._apply_damage_to_player(p_idx, total_dmg, "hit")
	proj.die()
	main._check_floor_clear()
