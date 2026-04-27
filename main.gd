extends Node3D

# ═══════════════════════════════════════════════════════════
#  3D PORT — Mốc 4 (movement + turn flow cơ bản)
#
#  Đã có:
#    - Camera 3D isometric, pitch [/], orbit RMB-drag, zoom -/= + wheel
#    - Hex grid 12×8 nâu, viền trắng, columns
#    - Player/Enemy CapsuleMesh placeholder + Label3D
#    - BFS valid moves cho current player, click-to-move
#    - Tab switch player, D end turn, U undo, K reset turn
#    - Tween 3D smooth movement
#    - Snapshot turn để undo/reset
#    - ESC thoát game
#
#  Chưa có:
#    - Combat (Q/W) — Mốc 6+
#    - Enemy turn AI — D hiện chỉ reset actions, chưa kích hoạt enemy
#    - HUD đầy đủ — Mốc 5
# ═══════════════════════════════════════════════════════════

const HexTileScene  = preload("res://hextile.tscn")
const HexTileScript = preload("res://hextile.gd")
const PlayerScript  = preload("res://Player.gd")
const PlayerScenes  : Dictionary = {
	"Sonny": preload("res://Sonny.tscn"),
	"Mike":  preload("res://Mike.tscn"),
}
const EnemyScript   = preload("res://enemy.gd")
const EnemyScene    = preload("res://enemy.tscn")

# ─── Hex grid ────────────────────────────────────────────────
const HEX_SIZE     : float = 1.0
const GRID_COLS    : int   = 12
const GRID_ROWS    : int   = 8
const GROUND_Y     : float = 0.2   # = HexTile.TILE_HEIGHT (mặt trên tile, nơi entities đứng)
const TWEEN_SPEED  : float = 0.18  # giây cho 1 lần move smooth

# ─── Camera rig ──────────────────────────────────────────────
const CAM_PITCH_MIN     : float = 30.0
const CAM_PITCH_MAX     : float = 60.0
const CAM_PITCH_STEP    : float = 1.5    # phím [ ]
const CAM_DIST_MIN      : float = 8.0
const CAM_DIST_MAX      : float = 60.0
const CAM_DIST_STEP     : float = 1.0    # phím - =
const CAM_YAW_DRAG      : float = 0.30   # độ/pixel khi RMB-drag (trục X)
const CAM_PITCH_DRAG    : float = 0.20   # độ/pixel khi RMB-drag (trục Y)

# Reference resolution → tỉ lệ zoom theo size window thực tế
# Game chạy fullscreen mặc định; monitor 1080p → zoom 1.0, 4K → zoom 2.0
const REF_WIDTH  : float = 1920.0
const REF_HEIGHT : float = 1080.0

@export var camera_pitch_deg : float = 41.0
# yaw=-90° → camera đứng phía nam (sau lưng Sonny/Mike vốn spawn ở row=1, cạnh nam),
# nhìn về hướng bắc (về phía enemies ở row cao hơn).
@export var camera_yaw_deg   : float = -90.0
@export var camera_distance  : float = 37.0

var rmb_dragging       : bool  = false
var window_zoom_factor : float = 1.0   # = min(width/REF_WIDTH, height/REF_HEIGHT)

@onready var camera      : Camera3D    = $Camera3D
@onready var debug_label : Label       = $HUD/DebugLabel
@onready var hud                       = $GameHUD

# Item icons cho HUD slot (Mốc 5: chỉ lv1 — upgrade system ở sau)
const ITEM_ICONS_BY_CHAR : Dictionary = {
	"Sonny": [
		preload("res://CharacterAsset/HUD/items/sonny/pan_lv1.png"),
		preload("res://CharacterAsset/HUD/items/sonny/bomb_lv1.png"),
	],
	"Mike": [
		preload("res://CharacterAsset/HUD/items/mike/slingshot_lv1.png"),
		preload("res://CharacterAsset/HUD/items/mike/hook_lv1.png"),
	],
}

# ─── Grid state ──────────────────────────────────────────────
var tiles          : Dictionary = {}   # Vector2i → HexTile
var column_tiles   : Dictionary = {}   # Vector2i → true
var fire_pit_tiles : Dictionary = {}   # Vector2i → true

# ─── Entities ────────────────────────────────────────────────
var players              : Array = []          # Array of Player nodes
var player_positions     : Array = []          # Array of Vector2i
var player_names         : Array = []          # Array of String
var current_player_index : int   = 0
var enemies              : Array = []          # Array of Enemy nodes

# ─── Turn state ──────────────────────────────────────────────
enum Phase { PLAYER_TURN, ENEMY_TURN, DODGE_PHASE, DEAD }
var phase                       : Phase      = Phase.PLAYER_TURN
var valid_moves                 : Array      = []     # Array of Vector2i — BFS reachable từ current player
var players_turned_this_round   : Array      = []     # idx đã end turn trong round hiện tại

var attack_committed_this_round : bool       = false  # khoá undo sau khi attack/dùng action không thể hoàn
var reset_turn_used             : bool       = false
var turn_snapshot               : Dictionary = {}     # state ở đầu round để undo/reset

# ─── Hover ──────────────────────────────────────────────────
var hover_hex     : Vector2i = Vector2i(-1, -1)

var camera_anchor : Vector3 = Vector3.ZERO
var grid_origin   : Vector3 = Vector3.ZERO

# ═══════════════════════════════════════════════════════════
#  HEX MATH (XZ plane)
# ═══════════════════════════════════════════════════════════

func hex_to_world(col: int, row: int) -> Vector3:
	var x : float = HEX_SIZE * 1.5 * col
	var z : float = HEX_SIZE * sqrt(3.0) * (row + (0.5 if col % 2 == 1 else 0.0))
	return Vector3(x, 0.0, z) + grid_origin

func world_to_hex(p: Vector3) -> Vector2i:
	var best     : Vector2i = Vector2i(-1, -1)
	var best_d2  : float    = INF
	for c in range(GRID_COLS):
		for r in range(GRID_ROWS):
			var hp : Vector3 = hex_to_world(c, r)
			var dx : float   = p.x - hp.x
			var dz : float   = p.z - hp.z
			var d2 : float   = dx * dx + dz * dz
			if d2 < best_d2:
				best_d2 = d2
				best    = Vector2i(c, r)
	# Chỉ trả nếu thực sự gần hex (< HEX_SIZE) để tránh chọn sai khi click ngoài lưới
	if best_d2 > HEX_SIZE * HEX_SIZE * 1.2:
		return Vector2i(-1, -1)
	return best

func _grid_center_offset() -> Vector3:
	var min_p := Vector3(INF, 0.0, INF)
	var max_p := Vector3(-INF, 0.0, -INF)
	for c in range(GRID_COLS):
		for r in range(GRID_ROWS):
			var p : Vector3 = Vector3(
				HEX_SIZE * 1.5 * c,
				0.0,
				HEX_SIZE * sqrt(3.0) * (r + (0.5 if c % 2 == 1 else 0.0))
			)
			if p.x < min_p.x: min_p.x = p.x
			if p.z < min_p.z: min_p.z = p.z
			if p.x > max_p.x: max_p.x = p.x
			if p.z > max_p.z: max_p.z = p.z
	return -(min_p + max_p) * 0.5

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

func is_valid_and_passable(col: int, row: int) -> bool:
	var key = Vector2i(col, row)
	if not tiles.has(key):  return false
	if key in column_tiles: return false
	return true

# ═══════════════════════════════════════════════════════════
#  LIFECYCLE
# ═══════════════════════════════════════════════════════════

func _ready() -> void:
	grid_origin   = _grid_center_offset()
	camera_anchor = Vector3.ZERO
	_build_grid()
	_setup_demo_columns()   # TODO Mốc 9: xoá khi main_test có scenarios riêng
	_spawn_players()
	_spawn_enemies()
	_update_valid_moves()
	_save_turn_snapshot()
	_refresh_tile_colors()
	get_viewport().size_changed.connect(_on_viewport_resized)
	_on_viewport_resized()  # set zoom + cập nhật camera lần đầu
	_init_hud()
	_refresh_debug()

# ═══════════════════════════════════════════════════════════
#  HUD WIRING (Mốc 5)
#  ► Combat-driven update (HP damage, HYPE perfection, dialogue
#    enemy intent) sẽ được nối ở Mốc 6+.
# ═══════════════════════════════════════════════════════════

func _init_hud() -> void:
	if hud == null: return
	# 4 nút → các hàm đã có sẵn trong main.gd
	hud.end_turn_pressed.connect(_on_hud_end_turn)
	hud.undo_pressed.connect(_on_hud_undo)
	hud.reset_pressed.connect(_on_hud_reset)
	hud.backpack_pressed.connect(_on_hud_backpack)

	# Nạp state ban đầu cho 2 player
	for i in range(players.size()):
		var p_name : String = player_names[i]
		var p              = players[i]
		hud.register_player(p_name, p.hp, p.max_hp, ITEM_ICONS_BY_CHAR.get(p_name, []))
		hud.set_actions(p_name, p.actions_left, p.actions_per_turn)
	hud.set_active("Sonny", current_player_index < players.size() and player_names[current_player_index] == "Sonny")
	hud.set_active("Mike",  current_player_index < players.size() and player_names[current_player_index] == "Mike")

	# Enemies hiện có
	for e in enemies:
		hud.register_enemy(e.get_instance_id(), e.display_label, e.hp, e.max_hp,
			e.display_label, e.body_color)

	# HYPE bar khởi đầu = perfection của player đang active
	if not players.is_empty():
		var cur = players[current_player_index]
		hud.set_hype_from_perfection(cur.perfection, cur.perfection_cap)

func _refresh_hud() -> void:
	if hud == null: return
	for i in range(players.size()):
		var p_name : String = player_names[i]
		var p              = players[i]
		hud.set_hp(p_name, p.hp, p.max_hp)
		hud.set_actions(p_name, p.actions_left, p.actions_per_turn)
		hud.set_active(p_name, i == current_player_index)
	if not players.is_empty():
		var cur = players[current_player_index]
		hud.set_hype_from_perfection(cur.perfection, cur.perfection_cap)
	for e in enemies:
		if is_instance_valid(e):
			hud.update_enemy_hp(e.get_instance_id(), e.hp, e.max_hp)

func _on_hud_end_turn() -> void:
	if phase == Phase.PLAYER_TURN:
		_end_player_turn()

func _on_hud_undo() -> void:
	if phase == Phase.PLAYER_TURN:
		_undo_move()

func _on_hud_reset() -> void:
	if phase == Phase.PLAYER_TURN:
		_reset_turn()

func _on_hud_backpack() -> void:
	# Mốc 5 stub — backpack scene sẽ build sau Mốc 8/9
	print("[HUD] Backpack pressed (stub)")

func _on_viewport_resized() -> void:
	var size : Vector2 = get_viewport().get_visible_rect().size
	var sx : float = size.x / REF_WIDTH
	var sy : float = size.y / REF_HEIGHT
	# Lấy min để cả 2 chiều của reference vẫn fit (không bị crop quá)
	window_zoom_factor = maxf(0.05, minf(sx, sy))
	_update_camera()
	_refresh_debug()

# ═══════════════════════════════════════════════════════════
#  GRID BUILDING
# ═══════════════════════════════════════════════════════════

func _build_grid() -> void:
	for col in range(GRID_COLS):
		for row in range(GRID_ROWS):
			var key  : Vector2i = Vector2i(col, row)
			var tile           = HexTileScene.instantiate()
			add_child(tile)
			tile.setup(col, row, HexTileScript.Type.NORMAL)
			tile.position = hex_to_world(col, row)
			tiles[key] = tile

func _setup_demo_columns() -> void:
	# DEMO: vài column để verify rendering — sẽ thay bằng scenario data ở Mốc 9
	for cr in [Vector2i(4, 3), Vector2i(7, 4), Vector2i(5, 6)]:
		if tiles.has(cr):
			tiles[cr].setup(cr.x, cr.y, HexTileScript.Type.COLUMN)
			column_tiles[cr] = true

func _refresh_tile_colors() -> void:
	var enemy_pos : Dictionary = {}
	for e in enemies:
		enemy_pos[Vector2i(e.grid_col, e.grid_row)] = true

	var valid_set : Dictionary = {}
	for v in valid_moves:
		valid_set[v] = true

	var cur_pos : Vector2i = Vector2i(-1, -1)
	if not players.is_empty():
		cur_pos = player_positions[current_player_index]

	for key in tiles:
		var tile = tiles[key]
		if key in column_tiles or key in fire_pit_tiles:
			tile.set_state("normal")   # column/firepit tự giữ màu danh tính
		elif key in enemy_pos:
			tile.set_state("enemy")
		elif key == cur_pos:
			tile.set_state("selected")
		elif key in valid_set:
			tile.set_state("valid")
		elif key == hover_hex:
			tile.set_state("hover")
		else:
			tile.set_state("normal")

# ═══════════════════════════════════════════════════════════
#  ENTITY SPAWNING
# ═══════════════════════════════════════════════════════════

# Vị trí thế giới cho entity (player/enemy) đứng trên ô (col, row).
# Đặt Y = GROUND_Y để chân entity tiếp xúc mặt trên tile.
func entity_position(col: int, row: int) -> Vector3:
	var p : Vector3 = hex_to_world(col, row)
	p.y = GROUND_Y
	return p

func _spawn_players() -> void:
	for preset_name in PlayerScript.PLAYER_ORDER:
		var p = PlayerScenes[preset_name].instantiate()
		add_child(p)
		p.setup_from_preset(preset_name)
		player_names.append(preset_name)
		player_positions.append(Vector2i(p.grid_col, p.grid_row))
		p.position = entity_position(p.grid_col, p.grid_row)
		players.append(p)

func _spawn_enemies() -> void:
	# Demo Mốc 3: vài enemy để xem entity 3D — sẽ thay bằng scenario data ở Mốc 9
	var demo : Array = [
		{"type": "grunt",  "col":  8, "row": 2},
		{"type": "grunt",  "col":  9, "row": 5},
		{"type": "archer", "col": 10, "row": 3},
	]
	for entry in demo:
		var key := Vector2i(entry["col"], entry["row"])
		if key in column_tiles: continue
		_spawn_enemy(entry["type"], entry["col"], entry["row"])

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
	enemy.position = entity_position(col, row)
	enemies.append(enemy)
	return enemy

# ═══════════════════════════════════════════════════════════
#  MOVEMENT & VALID MOVES
# ═══════════════════════════════════════════════════════════

func _update_valid_moves() -> void:
	valid_moves = []
	if players.is_empty(): return
	if not players[current_player_index].can_act(): return   # hết action → không hiện ô xanh

	# Tile bị chặn = column + enemy + player khác
	var blocked : Dictionary = {}
	for key in column_tiles:
		blocked[key] = true
	for e in enemies:
		blocked[Vector2i(e.grid_col, e.grid_row)] = true
	for i in range(players.size()):
		if i != current_player_index:
			blocked[player_positions[i]] = true

	# BFS từ vị trí current player, giới hạn `move_range` bước
	var start_pos = player_positions[current_player_index]
	var visited   : Dictionary = {start_pos: true}
	var frontier  : Array      = [[start_pos, 0]]
	var max_range = players[current_player_index].move_range

	while frontier.size() > 0:
		var entry = frontier.pop_front()
		var pos   : Vector2i = entry[0]
		var steps : int      = entry[1]
		for nb in _get_neighbors(pos.x, pos.y):
			if nb in visited: continue
			if nb in blocked: continue
			visited[nb] = true
			valid_moves.append(nb)
			if steps + 1 < max_range:
				frontier.append([nb, steps + 1])

func _move_entity_smooth(entity: Node, target_col: int, target_row: int) -> void:
	var target_pos := entity_position(target_col, target_row)
	var tween      := create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(entity, "position", target_pos, TWEEN_SPEED)

func _move_player(dest: Vector2i) -> void:
	var current_player = players[current_player_index]
	if not current_player.can_act(): return
	player_positions[current_player_index] = dest
	current_player.grid_col = dest.x
	current_player.grid_row = dest.y
	current_player.tiles_traveled_this_turn += 1
	_move_entity_smooth(current_player, dest.x, dest.y)
	current_player.use_action()
	_update_valid_moves()
	_refresh_tile_colors()
	_refresh_debug()
	_refresh_hud()

# ═══════════════════════════════════════════════════════════
#  TURN FLOW (Mốc 4 — chưa có enemy turn thật)
# ═══════════════════════════════════════════════════════════

func _switch_player_to_other() -> void:
	if players.size() < 2: return
	var other_idx = (current_player_index + 1) % players.size()
	if players[other_idx].hp <= 0: return
	current_player_index = other_idx
	_update_valid_moves()
	_refresh_tile_colors()
	_refresh_debug()
	_refresh_hud()

func _end_player_turn() -> void:
	if current_player_index not in players_turned_this_round:
		players_turned_this_round.append(current_player_index)
	# Tìm player tiếp theo chưa end turn
	var next_idx : int = -1
	for i in range(1, players.size() + 1):
		var idx = (current_player_index + i) % players.size()
		if idx not in players_turned_this_round:
			next_idx = idx
			break
	if next_idx == -1:
		# Tất cả đã hết lượt → reset round (tạm bỏ qua enemy turn cho đến Mốc 6)
		players_turned_this_round = []
		for p in players:
			p.reset_turn()
		current_player_index = 0
		_save_turn_snapshot()
	else:
		current_player_index = next_idx
	_update_valid_moves()
	_refresh_tile_colors()
	_refresh_debug()
	_refresh_hud()

# ─── Snapshot / Undo / Reset ────────────────────────────────

func _save_turn_snapshot() -> void:
	var pos_copy  : Array = []
	var grid_copy : Array = []
	var perf_copy : Array = []
	for i in range(players.size()):
		pos_copy.append(player_positions[i])
		grid_copy.append({"col": players[i].grid_col, "row": players[i].grid_row})
		perf_copy.append(players[i].perfection)
	turn_snapshot = {
		"player_positions":  pos_copy,
		"player_grids":      grid_copy,
		"player_perfection": perf_copy,
	}
	attack_committed_this_round = false
	reset_turn_used             = false

func _undo_move() -> void:
	# Cho phép hoàn movement nếu chưa tấn công round này
	if attack_committed_this_round: return
	if turn_snapshot.is_empty(): return
	for i in range(players.size()):
		var g = turn_snapshot["player_grids"][i]
		players[i].grid_col = g["col"]
		players[i].grid_row = g["row"]
		player_positions[i] = turn_snapshot["player_positions"][i]
		players[i].position = entity_position(g["col"], g["row"])
		players[i].reset_turn()
	players_turned_this_round = []
	current_player_index = 0
	_update_valid_moves()
	_refresh_tile_colors()
	_refresh_debug()
	_refresh_hud()

func _reset_turn() -> void:
	# 1 lần / round, kể cả sau khi đã attack
	if reset_turn_used: return
	if turn_snapshot.is_empty(): return
	reset_turn_used = true
	for i in range(players.size()):
		var g = turn_snapshot["player_grids"][i]
		players[i].grid_col = g["col"]
		players[i].grid_row = g["row"]
		player_positions[i] = turn_snapshot["player_positions"][i]
		players[i].position = entity_position(g["col"], g["row"])
		players[i].reset_turn()
		players[i].perfection = turn_snapshot["player_perfection"][i]
	players_turned_this_round   = []
	current_player_index        = 0
	attack_committed_this_round = false
	_update_valid_moves()
	_refresh_tile_colors()
	_refresh_debug()
	_refresh_hud()

# ─── Lookups ────────────────────────────────────────────────

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

# ═══════════════════════════════════════════════════════════
#  CAMERA RIG
# ═══════════════════════════════════════════════════════════

func _update_camera() -> void:
	var pitch : float = deg_to_rad(camera_pitch_deg)
	var yaw   : float = deg_to_rad(camera_yaw_deg)
	# Window to → effective_dist nhỏ → camera lại gần → objects to lên
	var effective_dist : float = camera_distance / window_zoom_factor
	var offset : Vector3 = Vector3(
		effective_dist * cos(pitch) * cos(yaw),
		effective_dist * sin(pitch),
		effective_dist * cos(pitch) * sin(yaw)
	)
	camera.global_position = camera_anchor + offset
	camera.look_at(camera_anchor, Vector3.UP)

func set_camera_anchor(world_pos: Vector3) -> void:
	camera_anchor = Vector3(world_pos.x, 0.0, world_pos.z)
	_update_camera()

# ═══════════════════════════════════════════════════════════
#  MOUSE → WORLD / HEX
# ═══════════════════════════════════════════════════════════

func mouse_to_ground(mouse_pos: Vector2) -> Vector3:
	var origin : Vector3 = camera.project_ray_origin(mouse_pos)
	var normal : Vector3 = camera.project_ray_normal(mouse_pos)
	if absf(normal.y) < 0.0001:
		return Vector3(NAN, NAN, NAN)
	# Pick lên mặt trên của tile (Y = GROUND_Y) cho cảm giác trực quan
	var t : float = (GROUND_Y - origin.y) / normal.y
	if t < 0.0:
		return Vector3(NAN, NAN, NAN)
	return origin + normal * t

func mouse_to_hex(mouse_pos: Vector2) -> Vector2i:
	var hit : Vector3 = mouse_to_ground(mouse_pos)
	if is_nan(hit.x):
		return Vector2i(-1, -1)
	return world_to_hex(hit)

# ═══════════════════════════════════════════════════════════
#  INPUT
# ═══════════════════════════════════════════════════════════

func _input(event: InputEvent) -> void:
	# ESC = thoát game (đặc biệt cần khi đang fullscreen)
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		get_tree().quit()
		return

	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_BRACKETLEFT:
				camera_pitch_deg = clampf(
					camera_pitch_deg - CAM_PITCH_STEP, CAM_PITCH_MIN, CAM_PITCH_MAX)
				_update_camera(); _refresh_debug()
			KEY_BRACKETRIGHT:
				camera_pitch_deg = clampf(
					camera_pitch_deg + CAM_PITCH_STEP, CAM_PITCH_MIN, CAM_PITCH_MAX)
				_update_camera(); _refresh_debug()
			KEY_MINUS:
				camera_distance = clampf(
					camera_distance + CAM_DIST_STEP, CAM_DIST_MIN, CAM_DIST_MAX)
				_update_camera(); _refresh_debug()
			KEY_EQUAL:
				camera_distance = clampf(
					camera_distance - CAM_DIST_STEP, CAM_DIST_MIN, CAM_DIST_MAX)
				_update_camera(); _refresh_debug()
			KEY_TAB:
				if phase == Phase.PLAYER_TURN:
					_switch_player_to_other()
			KEY_D:
				if phase == Phase.PLAYER_TURN:
					_end_player_turn()
			KEY_U:
				if phase == Phase.PLAYER_TURN:
					_undo_move()
			KEY_K:
				if phase == Phase.PLAYER_TURN:
					_reset_turn()

	# ── Cuộn chuột → zoom (lên = zoom in, xuống = zoom out) ──
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			camera_distance = clampf(
				camera_distance - CAM_DIST_STEP, CAM_DIST_MIN, CAM_DIST_MAX)
			_update_camera(); _refresh_debug()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			camera_distance = clampf(
				camera_distance + CAM_DIST_STEP, CAM_DIST_MIN, CAM_DIST_MAX)
			_update_camera(); _refresh_debug()

	# ── RMB giữ + drag → orbit camera quanh focus point ───────
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		rmb_dragging = event.pressed

	if event is InputEventMouseMotion:
		if rmb_dragging:
			camera_yaw_deg = wrapf(
				camera_yaw_deg + event.relative.x * CAM_YAW_DRAG, -360.0, 360.0)
			camera_pitch_deg = clampf(
				camera_pitch_deg + event.relative.y * CAM_PITCH_DRAG,
				CAM_PITCH_MIN, CAM_PITCH_MAX)
			_update_camera()
			_refresh_debug()
			return   # bỏ qua hover update khi đang xoay
		var hex : Vector2i = mouse_to_hex(event.position)
		if hex != hover_hex:
			hover_hex = hex
			_refresh_tile_colors()
			_refresh_debug()

	if event is InputEventMouseButton \
			and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if phase == Phase.PLAYER_TURN:
			var hex : Vector2i = mouse_to_hex(event.position)
			if hex in valid_moves:
				_move_player(hex)

func _refresh_debug() -> void:
	if not debug_label: return
	if players.is_empty():
		debug_label.text = "pitch %.0f° yaw %.0f° dist %.0f  hover=%s" \
			% [camera_pitch_deg, camera_yaw_deg, camera_distance, str(hover_hex)]
		return
	var cur = players[current_player_index]
	debug_label.text = "[%s] HP %d/%d  Actions %d/%d   |   LMB=move  Tab=switch  D=end  U=undo  K=reset   |   pitch %.0f° dist %.0f" \
		% [
			player_names[current_player_index],
			cur.hp, cur.max_hp,
			cur.actions_left, cur.actions_per_turn,
			camera_pitch_deg, camera_distance
		]
