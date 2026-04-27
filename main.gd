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
const ACTION_DELAY : float = 0.5   # giây giữa các action liên tiếp của enemy

# Mốc 6.3: DodgeBar minigame
const DodgeBarScene  = preload("res://dodge_bar.tscn")
# Mốc 7.1: Sonny charge bar (Boong)
const ChargeBarScene = preload("res://sonny_charge_bar.tscn")
# Mốc 8.1: Mike timing bar (Draw Shot)
const TimingBarScene = preload("res://mike_timing_bar.tscn")
# Mốc 7.3: Bomb fuse
const BOMB_FUSE_TURNS    : int = 2
const BOMB_AOE_DAMAGE    : int = 2
const SONNY_BOMBS_PER_FLOOR : int = 1

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
# yaw=180° → camera đứng phía TÂY của grid (sau lưng Sonny/Mike vốn spawn ở col=0,
# cạnh tây), nhìn về hướng ĐÔNG nơi enemies ở col=8-10. Player ở foreground, map
# trải dài về phía trước.
@export var camera_yaw_deg   : float = 180.0
@export var camera_distance  : float = 37.0

var rmb_dragging       : bool  = false
var window_zoom_factor : float = 1.0   # = min(width/REF_WIDTH, height/REF_HEIGHT)

@onready var camera        : Camera3D    = $Camera3D
@onready var debug_label   : Label       = $HUD/DebugLabel
@onready var hud                         = $GameHUD
@onready var combat_layer  : CanvasLayer = $CombatLayer

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
var valid_attack_targets : Array = []          # Array of Vector2i — enemy hex kề bên hiện tại có thể tấn công

# Mốc 7 — Sonny charge bar + bomb state
var sonny_charge_bar     : Node = null         # active charge bar instance (nếu đang giữ LMB)
var sonny_charge_target  : Node = null         # enemy đang bị Sonny "Boong"
var placing_bomb         : bool = false        # true khi Sonny đang chọn ô đặt bomb
var sonny_bombs_left     : int  = SONNY_BOMBS_PER_FLOOR

# Mốc 8 — Mike timing bar state
var mike_timing_bar      : Node = null
var mike_timing_target   : Node = null

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

# ── Hex line drawing & line-of-sight ────────────────────────
# Trả về list các hex từ (c1,r1) đến (c2,r2) bao gồm cả 2 đầu.
# Dùng cube interpolation + cube_round (chuẩn redblobgames).
func _hex_line(c1: int, r1: int, c2: int, r2: int) -> Array:
	var n : int = _hex_dist(c1, r1, c2, r2)
	var path : Array = []
	if n <= 0:
		path.append(Vector2i(c1, r1))
		return path
	var a : Vector3 = _to_cube_f(c1, r1)
	var b : Vector3 = _to_cube_f(c2, r2)
	# Epsilon nudge để ray đúng tâm cạnh không bị tie ngẫu nhiên
	a += Vector3(1e-6, 2e-6, -3e-6)
	b += Vector3(1e-6, 2e-6, -3e-6)
	for i in range(n + 1):
		var t : float = float(i) / float(n)
		var rounded : Vector3 = _cube_round(a.lerp(b, t))
		path.append(_from_cube_f(rounded))
	return path

func _to_cube_f(col: int, row: int) -> Vector3:
	var x : float = float(col)
	var z : float = float(row - (col - (col & 1)) / 2)
	var y : float = -x - z
	return Vector3(x, y, z)

func _from_cube_f(c: Vector3) -> Vector2i:
	var col : int = int(c.x)
	var row : int = int(c.z) + (col - (col & 1)) / 2
	return Vector2i(col, row)

func _cube_round(c: Vector3) -> Vector3:
	var rx : float = round(c.x)
	var ry : float = round(c.y)
	var rz : float = round(c.z)
	var dx : float = abs(rx - c.x)
	var dy : float = abs(ry - c.y)
	var dz : float = abs(rz - c.z)
	if dx > dy and dx > dz:
		rx = -ry - rz
	elif dy > dz:
		ry = -rx - rz
	else:
		rz = -rx - ry
	return Vector3(rx, ry, rz)

# Line-of-sight: từ (c1,r1) đến (c2,r2) — chỉ column chặn.
# Bỏ qua start và end. Fire pits + entities không chặn (entity sẽ hấp thụ projectile
# ở target, còn enemies trên đường đi không chặn nhau).
func _has_line_of_sight(c1: int, r1: int, c2: int, r2: int) -> bool:
	var path : Array = _hex_line(c1, r1, c2, r2)
	for i in range(1, path.size() - 1):
		var hex : Vector2i = path[i]
		if hex in column_tiles:
			return false
	return true

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
	_face_all_players_to_enemies()
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
	# Click avatar HUD → switch sang nhân vật đó
	hud.player_avatar_clicked.connect(_on_hud_avatar_clicked)

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
	if phase != Phase.PLAYER_TURN: return
	if players.is_empty(): return
	# Nút END TURN của HUD: kết thúc turn cho CẢ 2 player luôn, dù còn dư action.
	# (Phím D giữ behavior cũ: end current player, rotate sang next.)
	players_turned_this_round = []
	for i in range(players.size()):
		if players[i].hp > 0:
			players_turned_this_round.append(i)
	_start_enemy_turn()

func _on_hud_undo() -> void:
	if phase == Phase.PLAYER_TURN:
		_undo_move()

func _on_hud_reset() -> void:
	if phase == Phase.PLAYER_TURN:
		_reset_turn()

func _on_hud_avatar_clicked(char_name: String) -> void:
	if phase != Phase.PLAYER_TURN: return
	if sonny_charge_bar != null or mike_timing_bar != null: return
	if placing_bomb: return
	var idx : int = player_names.find(char_name)
	if idx < 0 or idx == current_player_index: return
	if players[idx].hp <= 0: return
	current_player_index = idx
	_update_valid_moves()
	_refresh_tile_colors()
	_refresh_debug()
	_refresh_hud()

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

	var attack_set : Dictionary = {}
	for a in valid_attack_targets:
		attack_set[a] = true

	var cur_pos : Vector2i = Vector2i(-1, -1)
	if not players.is_empty():
		cur_pos = player_positions[current_player_index]

	# Bomb placement mode: highlight ô kề bên passable+empty (xanh "valid"),
	# hover sẽ đỏ chói "attack" để báo "đặt ở đây?". Override hoàn toàn logic
	# bình thường khi placing_bomb=true.
	if placing_bomb and not players.is_empty():
		var cur_p = players[current_player_index]
		for key in tiles:
			var tile = tiles[key]
			if key in column_tiles or key in fire_pit_tiles:
				tile.set_state("normal")
				continue
			var is_bomb_target : bool = (
				_hex_dist(cur_p.grid_col, cur_p.grid_row, key.x, key.y) == 1
				and is_valid_and_passable(key.x, key.y)
				and _get_enemy_at(key) == null
				and _get_player_at(key) < 0
			)
			if key == cur_pos:
				tile.set_state("selected")
			elif is_bomb_target and key == hover_hex:
				tile.set_state("attack")
			elif is_bomb_target:
				tile.set_state("valid")
			elif key in enemy_pos:
				tile.set_state("enemy")
			else:
				tile.set_state("normal")
		return

	# Highlight rule (theo yêu cầu user):
	#  ► Hover chỉ light-up nếu ô đó nằm trong valid_moves (xanh) hoặc là enemy có
	#    thể đánh (Sonny kề bên / Mike LOS clear).
	#  ► Hover trên ô không có gì (không movable, không enemy attackable) → KHÔNG light up.
	for key in tiles:
		var tile = tiles[key]
		if key in column_tiles or key in fire_pit_tiles:
			tile.set_state("normal")   # column/firepit tự giữ màu danh tính
		elif key in enemy_pos:
			# Hover lên enemy attackable → đỏ chói; không thì giữ enemy mặc định.
			if key == hover_hex and key in attack_set:
				tile.set_state("attack")
			else:
				tile.set_state("enemy")
		elif key == cur_pos:
			tile.set_state("selected")
		elif key in valid_set:
			# Movable: hover → "hover" (sáng), không thì giữ "valid" (xanh).
			if key == hover_hex:
				tile.set_state("hover")
			else:
				tile.set_state("valid")
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

func _face_player_to_nearest_enemy(idx: int) -> void:
	if idx < 0 or idx >= players.size(): return
	if enemies.is_empty(): return
	var p = players[idx]
	if p.hp <= 0: return
	var nearest : Node = null
	var best_d  : int  = 999
	for e in enemies:
		if not is_instance_valid(e): continue
		if e.hp <= 0: continue
		var d : int = _hex_dist(p.grid_col, p.grid_row, e.grid_col, e.grid_row)
		if d < best_d:
			best_d  = d
			nearest = e
	if nearest == null: return
	var p_pos : Vector3 = entity_position(p.grid_col, p.grid_row)
	var e_pos : Vector3 = entity_position(nearest.grid_col, nearest.grid_row)
	if absf(e_pos.x - p_pos.x) < 0.001 and absf(e_pos.z - p_pos.z) < 0.001:
		return
	# look_at quay -Z local sang điểm target. Models .glb từ Mixamo/Blender
	# thường face +Z (mesh forward) → cần xoay thêm 180° quanh Y để mặt thật
	# của model hướng về enemy.
	p.look_at(Vector3(e_pos.x, p_pos.y, e_pos.z), Vector3.UP)
	p.rotate_object_local(Vector3.UP, PI)

func _face_all_players_to_enemies() -> void:
	for i in range(players.size()):
		_face_player_to_nearest_enemy(i)

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
	valid_attack_targets = []   # luôn clear cùng để visual highlight đồng bộ
	if players.is_empty(): return
	if not players[current_player_index].can_act(): return   # hết action → không hiện ô xanh

	# Tile bị chặn = column + enemy + player khác (còn sống)
	var blocked : Dictionary = {}
	for key in column_tiles:
		blocked[key] = true
	for e in enemies:
		blocked[Vector2i(e.grid_col, e.grid_row)] = true
	for i in range(players.size()):
		if i != current_player_index and players[i].hp > 0:
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
	_update_valid_attack_targets()

# Enemy có thể tấn công:
#   - Sonny: chỉ đánh kề bên (range=1)
#   - Mike (uses_draw_shot): line-of-sight clear (column chặn). Mốc 8 sẽ thay
#     bằng draw shot có bounce; tạm Mốc 6 chỉ check straight-line không column.
# Gọi tự động ở cuối _update_valid_moves().
func _update_valid_attack_targets() -> void:
	valid_attack_targets = []
	if players.is_empty(): return
	var current = players[current_player_index]
	if not current.can_act(): return
	var pos : Vector2i = player_positions[current_player_index]
	for e in enemies:
		if _can_attack_target(pos.x, pos.y, e.grid_col, e.grid_row):
			valid_attack_targets.append(Vector2i(e.grid_col, e.grid_row))

# Có đánh được không? Dùng cho cả valid_attack_targets và click time check.
func _can_attack_target(from_col: int, from_row: int, to_col: int, to_row: int) -> bool:
	if players.is_empty(): return false
	var current = players[current_player_index]
	var d : int = _hex_dist(from_col, from_row, to_col, to_row)
	if d <= 0: return false
	if current.uses_draw_shot:
		# Mike: bất kỳ range với LOS clear (column chặn)
		return _has_line_of_sight(from_col, from_row, to_col, to_row)
	# Sonny: chỉ kề bên
	return d == 1

func _move_entity_smooth(entity: Node, target_col: int, target_row: int) -> void:
	var target_pos := entity_position(target_col, target_row)
	var tween      := create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(entity, "position", target_pos, TWEEN_SPEED)

func _move_player(dest: Vector2i) -> void:
	var current_player = players[current_player_index]
	if not current_player.can_act(): return
	var src : Vector2i = player_positions[current_player_index]
	var dist : int = _hex_dist(src.x, src.y, dest.x, dest.y)
	player_positions[current_player_index] = dest
	current_player.grid_col = dest.x
	current_player.grid_row = dest.y
	current_player.tiles_traveled_this_turn += 1
	# Run animation suốt thời gian tween + buffer để animation hiện rõ.
	if current_player.has_method("play_run"):
		current_player.play_run()
	var move_pos : Vector3 = entity_position(dest.x, dest.y)
	# Tween duration scale theo distance (khoảng 0.25s/hex), tối thiểu 0.30s
	# để run animation kịp chạy 1 chu kỳ rõ ràng trước khi về idle.
	var move_dur : float = maxf(0.30, 0.25 * float(dist))
	var tween    := create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(current_player, "position", move_pos, move_dur)
	# Buffer 0.15s sau tween rồi mới về idle, để run anim không bị cắt sớm.
	tween.tween_interval(0.15)
	if current_player.has_method("play_idle"):
		tween.tween_callback(current_player.play_idle)
	current_player.use_action()
	_face_all_players_to_enemies()   # quay mặt về địch gần nhất
	_update_valid_moves()
	_refresh_tile_colors()
	_refresh_debug()
	_refresh_hud()

# ═══════════════════════════════════════════════════════════
#  COMBAT — PLAYER ATTACK (Mốc 6.1: melee cơ bản, chưa có minigame)
# ═══════════════════════════════════════════════════════════

# ─── LMB press / release dispatch ───────────────────────────

func _handle_lmb_press(mouse_pos: Vector2) -> void:
	if phase != Phase.PLAYER_TURN: return
	if players.is_empty(): return
	if sonny_charge_bar != null: return   # đang charge — bỏ qua press khác
	if mike_timing_bar != null: return    # đang aim — bỏ qua
	var hex : Vector2i = mouse_to_hex(mouse_pos)
	if hex.x < 0: return
	# Bomb placement mode (Sonny W) — click vào ô kề bên hợp lệ
	if placing_bomb:
		_place_bomb_at(hex)
		return
	# Click vào player KHÁC (còn sống) → switch sang nhân vật đó
	var clicked_player_idx : int = _get_player_at(hex)
	if clicked_player_idx >= 0 and clicked_player_idx != current_player_index \
			and players[clicked_player_idx].hp > 0:
		current_player_index = clicked_player_idx
		_update_valid_moves()
		_refresh_tile_colors()
		_refresh_debug()
		_refresh_hud()
		return
	var target_enemy : Node = _get_enemy_at(hex)
	var current_player          = players[current_player_index]
	# Click enemy + còn action + đánh được:
	#   - Sonny (uses_draw_shot=false): mở charge bar (HOLD)
	#   - Mike  (uses_draw_shot=true) : mở timing bar (HOLD + DRAG)
	if target_enemy != null and current_player.can_act() \
			and _can_attack_target(current_player.grid_col,
				current_player.grid_row, hex.x, hex.y):
		if current_player.uses_draw_shot:
			_start_mike_timing(target_enemy, mouse_pos)
		else:
			_start_sonny_charge(target_enemy)
		return
	if hex in valid_moves:
		_move_player(hex)

func _handle_lmb_release() -> void:
	if sonny_charge_bar != null and is_instance_valid(sonny_charge_bar):
		sonny_charge_bar.resolve()
	elif mike_timing_bar != null and is_instance_valid(mike_timing_bar):
		mike_timing_bar.resolve()

# Gọi từ _input(InputEventMouseMotion). Nếu Mike đang aim, update drag.
func _handle_mouse_motion(mouse_pos: Vector2) -> void:
	if mike_timing_bar != null and is_instance_valid(mike_timing_bar):
		mike_timing_bar.update_drag(mouse_pos)

# ═══════════════════════════════════════════════════════════
#  SONNY CHARGE BAR — Mốc 7.2 (Q / Boong)
# ═══════════════════════════════════════════════════════════

func _start_sonny_charge(target_enemy: Node) -> void:
	var current_player = players[current_player_index]
	if not current_player.can_act(): return
	var bar = ChargeBarScene.instantiate()
	bar.is_holding = true   # bắt đầu hold ngay (LMB đang được nhấn)
	bar.charge_resolved.connect(_on_charge_resolved.bind(target_enemy))
	camera.add_child(bar)
	bar.position = Vector3(0.0, -0.18, -1.2)
	sonny_charge_bar    = bar
	sonny_charge_target = target_enemy

func _on_charge_resolved(result: String, target_enemy: Node) -> void:
	sonny_charge_bar    = null
	sonny_charge_target = null
	if not is_instance_valid(target_enemy):
		_refresh_debug()
		return
	var current_player = players[current_player_index]
	var base_dmg : int = current_player.get_q_dmg()
	var dmg      : int = 0
	match result:
		"perfect": dmg = int(round(base_dmg * 1.5 + 0.4))   # 1×1.5≈2, 2×1.5=3
		"normal":  dmg = base_dmg
		"miss":    dmg = 0
	if dmg > 0:
		if current_player.has_method("play_attack"):
			current_player.play_attack()
		target_enemy.take_damage(dmg)
		_spawn_damage_popup(target_enemy.position + Vector3(0, 1.8, 0),
			"-%d" % dmg, Color(1.0, 0.55, 0.30))
		if target_enemy.hp <= 0:
			_kill_enemy(target_enemy)
		else:
			if hud != null:
				hud.update_enemy_hp(target_enemy.get_instance_id(),
					target_enemy.hp, target_enemy.max_hp)
	else:
		_spawn_damage_popup(target_enemy.position + Vector3(0, 1.8, 0),
			"MISS!", Color(0.7, 0.7, 0.7))
	current_player.use_action()
	current_player.has_attacked = true
	attack_committed_this_round = true
	_update_valid_moves()
	_refresh_tile_colors()
	_refresh_debug()
	_refresh_hud()
	_check_floor_clear()

# ═══════════════════════════════════════════════════════════
#  MIKE TIMING BAR — Mốc 8.1/8.2 (Draw Shot)
# ═══════════════════════════════════════════════════════════

func _start_mike_timing(target_enemy: Node, mouse_pos: Vector2) -> void:
	var current = players[current_player_index]
	if not current.can_act(): return
	var bar = TimingBarScene.instantiate()
	bar.timing_resolved.connect(_on_mike_timing_resolved.bind(target_enemy))
	camera.add_child(bar)
	bar.position = Vector3(0.0, -0.18, -1.2)
	bar.setup(mouse_pos)   # drag_anchor = vị trí chuột lúc click
	mike_timing_bar    = bar
	mike_timing_target = target_enemy

func _on_mike_timing_resolved(result: String, target_enemy: Node) -> void:
	mike_timing_bar    = null
	mike_timing_target = null
	if not is_instance_valid(target_enemy):
		_refresh_debug()
		return
	var current = players[current_player_index]
	var base_dmg : int = current.get_q_dmg()
	var dmg      : int = 0
	match result:
		"perfect": dmg = int(round(base_dmg * 1.5 + 0.4))
		"hit":     dmg = base_dmg
		"miss":    dmg = 0
	if dmg > 0:
		if current.has_method("play_attack"):
			current.play_attack()
		target_enemy.take_damage(dmg)
		_spawn_damage_popup(target_enemy.position + Vector3(0, 1.8, 0),
			"-%d" % dmg, Color(1.0, 0.55, 0.30))
		if target_enemy.hp <= 0:
			_kill_enemy(target_enemy)
		else:
			if hud != null:
				hud.update_enemy_hp(target_enemy.get_instance_id(),
					target_enemy.hp, target_enemy.max_hp)
	else:
		_spawn_damage_popup(target_enemy.position + Vector3(0, 1.8, 0),
			"MISS!", Color(0.7, 0.7, 0.7))
	current.use_action()
	current.has_attacked = true
	attack_committed_this_round = true
	_update_valid_moves()
	_refresh_tile_colors()
	_refresh_debug()
	_refresh_hud()
	_check_floor_clear()

# ═══════════════════════════════════════════════════════════
#  SONNY BOMB — Mốc 7.3 (W key)
# ═══════════════════════════════════════════════════════════

# W key: toggle bomb placement mode (Sonny only, có bomb còn lại, còn action).
func _toggle_bomb_placement() -> void:
	if phase != Phase.PLAYER_TURN: return
	if players.is_empty(): return
	var current = players[current_player_index]
	if current.uses_draw_shot: return       # Mike không có bomb
	if not current.can_act(): return
	if sonny_bombs_left <= 0: return
	if sonny_charge_bar != null: return
	placing_bomb = not placing_bomb
	_refresh_tile_colors()
	_refresh_debug()

func _place_bomb_at(hex: Vector2i) -> void:
	if not placing_bomb: return
	var current = players[current_player_index]
	var d : int = _hex_dist(current.grid_col, current.grid_row, hex.x, hex.y)
	if d != 1: return
	if not is_valid_and_passable(hex.x, hex.y): return
	if _get_enemy_at(hex) != null: return
	if _get_player_at(hex) >= 0: return

	var bomb = _spawn_enemy("bomb", hex.x, hex.y)
	bomb.fuse_turns = BOMB_FUSE_TURNS
	# Fuse countdown Label3D trên đầu bomb
	var fuse_label := Label3D.new()
	fuse_label.name                = "FuseLabel"
	fuse_label.text                = "FUSE %d" % bomb.fuse_turns
	fuse_label.font_size           = 56
	fuse_label.pixel_size          = 0.005
	fuse_label.outline_size        = 6
	fuse_label.outline_modulate    = Color(0, 0, 0, 0.95)
	fuse_label.modulate            = Color(1.0, 0.5, 0.1)
	fuse_label.position            = Vector3(0, 1.7, 0)
	fuse_label.no_depth_test       = true
	fuse_label.billboard           = BaseMaterial3D.BILLBOARD_ENABLED
	bomb.add_child(fuse_label)
	# HUD register — bomb hiện trong enemy panel với label "B"
	if hud != null:
		hud.register_enemy(bomb.get_instance_id(), "BOMB", bomb.hp, bomb.max_hp,
			bomb.display_label, bomb.body_color)
	sonny_bombs_left -= 1
	placing_bomb       = false
	current.use_action()
	attack_committed_this_round = true
	_update_valid_moves()
	_refresh_tile_colors()
	_refresh_debug()
	_refresh_hud()

# Sau mỗi enemy turn, decrement fuse + explode bomb hết hạn.
func _tick_bombs_after_enemy_turn() -> void:
	var to_explode : Array = []
	for e in enemies.duplicate():
		if not is_instance_valid(e): continue
		if e.enemy_type != "bomb": continue
		e.fuse_turns -= 1
		var label = e.get_node_or_null("FuseLabel")
		if label:
			label.text = "FUSE %d" % maxi(e.fuse_turns, 0)
		if e.fuse_turns <= 0:
			to_explode.append(e)
	for bomb in to_explode:
		await _explode_bomb(bomb)

# Bomb nổ: AOE = bomb tile + 6 ô kề. Damage tất cả entities (enemies + players).
func _explode_bomb(bomb: Node) -> void:
	var bomb_col : int = bomb.grid_col
	var bomb_row : int = bomb.grid_row
	var center   : Vector3 = bomb.position
	_spawn_damage_popup(center + Vector3(0, 1.5, 0), "BOOM!",
		Color(1.0, 0.55, 0.10))
	var aoe : Array = [Vector2i(bomb_col, bomb_row)]
	for nb in _get_neighbors(bomb_col, bomb_row):
		aoe.append(nb)
	for hex in aoe:
		var e_in : Node = _get_enemy_at(hex)
		if e_in != null and e_in != bomb:
			e_in.take_damage(BOMB_AOE_DAMAGE)
			_spawn_damage_popup(e_in.position + Vector3(0, 1.8, 0),
				"-%d" % BOMB_AOE_DAMAGE, Color(1.0, 0.55, 0.30))
			if e_in.hp <= 0:
				_kill_enemy(e_in)
			else:
				if hud != null:
					hud.update_enemy_hp(e_in.get_instance_id(),
						e_in.hp, e_in.max_hp)
		var p_idx : int = _get_player_at(hex)
		if p_idx >= 0:
			_apply_damage_to_player(p_idx, BOMB_AOE_DAMAGE, "hit")
	_kill_enemy(bomb)
	_check_floor_clear()
	await get_tree().create_timer(0.3).timeout

# Player tấn công melee enemy kề bên: damage = q_dmg của weapon hiện tại.
# Mốc 7 thay Sonny bằng charge_bar minigame (xem _start_sonny_charge);
# hàm này còn dùng cho Mike (uses_draw_shot) — instant click attack.
func _player_attack_enemy(enemy: Node) -> void:
	var current_player = players[current_player_index]
	if not current_player.can_act(): return
	if current_player.has_method("play_attack"):
		current_player.play_attack()
	var dmg : int = current_player.get_q_dmg()
	enemy.take_damage(dmg)
	current_player.use_action()
	current_player.has_attacked = true
	attack_committed_this_round = true
	# Damage popup phía trên enemy capsule (cao ~1.6m so với chân)
	_spawn_damage_popup(enemy.position + Vector3(0, 1.8, 0),
		"-%d" % dmg, Color(1.0, 0.55, 0.30))
	if enemy.hp <= 0:
		_kill_enemy(enemy)
	else:
		if hud != null:
			hud.update_enemy_hp(enemy.get_instance_id(), enemy.hp, enemy.max_hp)
	_update_valid_moves()
	_refresh_tile_colors()
	_refresh_debug()
	_refresh_hud()
	_check_floor_clear()

func _kill_enemy(enemy: Node) -> void:
	if hud != null:
		hud.remove_enemy(enemy.get_instance_id())
	enemies.erase(enemy)
	_play_death_animation(enemy, true)   # true → queue_free khi xong

# Khi hết enemies → floor clear. Mốc 9 sẽ wire vào world_map transition.
func _check_floor_clear() -> void:
	if enemies.is_empty():
		sonny_bombs_left = SONNY_BOMBS_PER_FLOOR   # reset bombs cho floor mới
		print("[FLOOR CLEAR] All enemies defeated. (TODO Mốc 9: world map transition)")

# ─── Polish helpers (Mốc 6.5) ───────────────────────────────

# Floating damage text — Label3D billboard, float lên + fade ra trong 0.9s.
func _spawn_damage_popup(world_pos: Vector3, text: String, color: Color) -> void:
	var label := Label3D.new()
	label.text             = text
	label.font_size        = 96
	label.pixel_size       = 0.006
	label.outline_size     = 12
	label.outline_modulate = Color(0, 0, 0, 0.95)
	label.modulate         = color
	label.no_depth_test    = true
	label.billboard        = BaseMaterial3D.BILLBOARD_ENABLED
	label.position         = world_pos
	add_child(label)
	var tween := create_tween().set_parallel(true)
	tween.tween_property(label, "position:y", world_pos.y + 1.4, 0.95) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "modulate:a", 0.0, 0.95) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	# chain() để callback chạy SAU khi tween kết thúc, không song song
	tween.chain().tween_callback(label.queue_free)

# Animation chết: scale xuống + sink + fade. queue_free nếu free_after=true
# (enemies). Player giữ node lại (chỉ ẩn) — free_after=false.
func _play_death_animation(entity: Node, free_after: bool) -> void:
	var orig_y : float = entity.position.y
	var tween := create_tween().set_parallel(true)
	tween.tween_property(entity, "scale", Vector3(0.15, 0.15, 0.15), 0.45) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(entity, "position:y", orig_y - 0.6, 0.45) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	# Fade material alpha — cần TRANSPARENCY_ALPHA mode
	var model = entity.get_node_or_null("ModelPlaceholder")
	if model and model is MeshInstance3D and model.material_override is StandardMaterial3D:
		var mat : StandardMaterial3D = model.material_override
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		tween.tween_property(mat, "albedo_color:a", 0.0, 0.45)
	if free_after:
		tween.chain().tween_callback(entity.queue_free)
	else:
		tween.chain().tween_callback(func(): entity.visible = false)

# ═══════════════════════════════════════════════════════════
#  ENEMY TURN (Mốc 6.2)
#  ► Sau khi cả 2 player end turn → enemy AI tuần tự.
#  ► Mỗi enemy: tick_turn → plan_action mỗi action_per_turn lượt:
#      "attack"     → spawn DodgeBar (melee) hoặc tự apply damage (ranged stub)
#      "move"       → di chuyển 1 ô về phía player gần nhất
#      "move_away"  → ngược lại (RANGER khi quá gần)
#      "idle"       → bỏ qua (DUMMY)
#  ► ACTION_DELAY giữa các action liên tiếp.
#  ► Hết queue → reset player turn round mới.
# ═══════════════════════════════════════════════════════════

func _start_enemy_turn() -> void:
	phase = Phase.ENEMY_TURN
	valid_moves = []
	valid_attack_targets = []
	_refresh_tile_colors()
	_refresh_debug()
	_run_enemy_turn()

func _run_enemy_turn() -> void:
	# Iterate trên copy để xoá enemy giữa chừng (do player counter-attack…) không vỡ
	for enemy in enemies.duplicate():
		if not is_instance_valid(enemy): continue
		if enemy.hp <= 0: continue
		if enemy.enemy_type == "bomb": continue   # bomb không tự act trong enemy turn
		if _all_players_dead(): break
		await _run_enemy_actions(enemy)
		await get_tree().create_timer(ACTION_DELAY * 0.4).timeout

	# Decrement fuse + nổ bomb hết hạn (Mốc 7.3)
	await _tick_bombs_after_enemy_turn()

	if _all_players_dead():
		phase = Phase.DEAD
		_refresh_debug()
		return

	# Reset cho round player mới
	for p in players:
		if p.hp > 0:
			p.reset_turn()
	players_turned_this_round = []
	# Chọn player còn sống đầu tiên
	current_player_index = 0
	for i in range(players.size()):
		if players[i].hp > 0:
			current_player_index = i
			break
	phase = Phase.PLAYER_TURN
	_save_turn_snapshot()
	_face_all_players_to_enemies()   # quay lại sau khi enemy đã di chuyển
	_update_valid_moves()
	_refresh_tile_colors()
	_refresh_debug()
	_refresh_hud()

func _run_enemy_actions(enemy: Node) -> void:
	enemy.tick_turn()
	enemy.has_attacked_this_turn = false
	for i in range(enemy.actions_per_turn):
		if enemy.hp <= 0: return
		if _all_players_dead(): return
		var target_idx : int = _find_nearest_player_to(enemy)
		if target_idx < 0: return
		var p = players[target_idx]
		var action : String = enemy.plan_action(
			p.grid_col, p.grid_row, GRID_COLS, GRID_ROWS)
		match action:
			"attack":
				await _enemy_perform_attack(enemy, target_idx)
				await get_tree().create_timer(ACTION_DELAY * 0.5).timeout
			"move":
				_enemy_move_toward(enemy, target_idx)
				await get_tree().create_timer(ACTION_DELAY).timeout
			"move_away":
				_enemy_move_away(enemy, target_idx)
				await get_tree().create_timer(ACTION_DELAY).timeout
			"idle":
				return

func _enemy_move_toward(enemy: Node, target_idx: int) -> void:
	var p = players[target_idx]
	var occupied : Dictionary = _build_occupied(enemy)
	var dest : Vector2i = enemy.best_move_toward(p.grid_col, p.grid_row, occupied, self)
	if dest.x < 0: return
	enemy.grid_col = dest.x
	enemy.grid_row = dest.y
	_move_entity_smooth(enemy, dest.x, dest.y)
	_update_valid_moves()
	_refresh_tile_colors()

func _enemy_move_away(enemy: Node, target_idx: int) -> void:
	var p = players[target_idx]
	var occupied : Dictionary = _build_occupied(enemy)
	var dest : Vector2i = enemy.best_move_away(p.grid_col, p.grid_row, occupied, self)
	if dest.x < 0: return
	enemy.grid_col = dest.x
	enemy.grid_row = dest.y
	_move_entity_smooth(enemy, dest.x, dest.y)
	_update_valid_moves()
	_refresh_tile_colors()

func _build_occupied(exclude_enemy: Node) -> Dictionary:
	var occupied : Dictionary = {}
	for e in enemies:
		if e == exclude_enemy: continue
		occupied[Vector2i(e.grid_col, e.grid_row)] = true
	for i in range(players.size()):
		if players[i].hp > 0:
			occupied[player_positions[i]] = true
	return occupied

func _enemy_perform_attack(enemy: Node, target_idx: int) -> void:
	var attack : Dictionary = enemy.get_current_attack()
	if attack.is_empty(): return
	# Mọi enemy attack (cả melee range=1 và ranged range>1) hiện DodgeBar để
	# player có cơ hội né. Mốc 9+ sẽ thay ranged attack bằng projectile bounce
	# system (port từ bounce.gd). Hiện tại ranged dùng cùng DodgeBar.
	await _telegraph_attack(target_idx)
	await _trigger_dodge_bar(enemy, target_idx, attack)
	enemy.advance_attack()

# Flash ô target 3 nhịp đỏ ↔ thường (~0.4s) để player thấy ai sắp bị đánh.
func _telegraph_attack(target_idx: int) -> void:
	if target_idx < 0 or target_idx >= player_positions.size(): return
	var pos : Vector2i = player_positions[target_idx]
	var tile = tiles.get(pos)
	if tile == null: return
	for i in 3:
		tile.set_state("attack")
		await get_tree().create_timer(0.07).timeout
		tile.set_state("selected")
		await get_tree().create_timer(0.07).timeout
	tile.set_state("attack")
	await get_tree().create_timer(0.10).timeout
	# Restore tile state về đúng — không cần manual, tile bị "selected" hoặc
	# "attack" sẽ được override khi _refresh_tile_colors chạy lần sau.

func _trigger_dodge_bar(enemy: Node, target_idx: int, attack: Dictionary) -> void:
	phase = Phase.DODGE_PHASE
	var bar = DodgeBarScene.instantiate()
	# Note: enemy preset có "perfect_window"/"ok_window" là TIME windows (sec),
	# không phải bar-fractions. 2D version cũng không truyền cho dodge_bar →
	# dùng defaults ZONE_PERFECT=0.04 (4% bar half-width) / ZONE_DODGE=0.08
	# (8%) cho zone size hợp lý.
	bar.setup(enemy.dodge_line, 1.0)
	# Attach vào camera với local transform → bar luôn ở trước mặt người chơi.
	# Z=-1.2 (gần), Y=-0.18 (chỉ dưới center). Bar sau scale 0.2 + tilt 25°
	# hiện ~20% bề rộng view.
	camera.add_child(bar)
	bar.position = Vector3(0.0, -0.18, -1.2)
	var result : String = await bar.bar_finished
	var dmg : int = int(attack.get("damage", 1))
	_apply_damage_to_player(target_idx, dmg, result)
	phase = Phase.ENEMY_TURN

func _apply_damage_to_player(target_idx: int, dmg: int, result: String = "hit") -> void:
	if target_idx < 0 or target_idx >= players.size(): return
	var p = players[target_idx]
	var head_pos : Vector3 = p.position + Vector3(0, 1.9, 0)
	match result:
		"perfect":
			p.perfection = mini(p.perfection + 1, p.perfection_cap)
			_spawn_damage_popup(head_pos, "PERFECT!", Color(0.31, 1.00, 0.51))
		"dodged":
			p.perfection = mini(p.perfection + 1, p.perfection_cap)
			_spawn_damage_popup(head_pos, "DODGE!", Color(0.95, 0.90, 0.30))
		_:  # "hit" hoặc bất cứ gì khác
			p.take_damage(dmg)
			_spawn_damage_popup(head_pos, "-%d HP" % dmg, Color(1.0, 0.30, 0.30))
			if p.hp <= 0:
				_play_death_animation(p, false)   # ẩn capsule có animation
	# HUD update
	if hud != null:
		hud.set_hp(player_names[target_idx], p.hp, p.max_hp)
		# HYPE bar dùng perfection của player đang active
		if current_player_index < players.size():
			var cur = players[current_player_index]
			hud.set_hype_from_perfection(cur.perfection, cur.perfection_cap)

func _find_nearest_player_to(enemy: Node) -> int:
	var best_idx : int = -1
	var best_d   : int = 999
	for i in range(players.size()):
		if players[i].hp <= 0: continue
		var d : int = _hex_dist(enemy.grid_col, enemy.grid_row,
								players[i].grid_col, players[i].grid_row)
		if d < best_d:
			best_d   = d
			best_idx = i
	return best_idx

func _all_players_dead() -> bool:
	for p in players:
		if p.hp > 0: return false
	return true

# ═══════════════════════════════════════════════════════════
#  RESTART (Mốc 6.4)
# ═══════════════════════════════════════════════════════════

func _restart_game() -> void:
	get_tree().reload_current_scene()

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
	# Tìm player tiếp theo chưa end turn (và còn sống)
	var next_idx : int = -1
	for i in range(1, players.size() + 1):
		var idx = (current_player_index + i) % players.size()
		if idx not in players_turned_this_round and players[idx].hp > 0:
			next_idx = idx
			break
	if next_idx == -1:
		# Tất cả đã hết lượt → enemy turn (Mốc 6.2)
		_start_enemy_turn()
		return
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
	# Pass 1: Capsule-aware picking — nếu ray đi qua capsule của entity nào,
	# trả về hex của entity đó (tránh bug ray xuyên capsule rồi hit ground sau lưng).
	var origin : Vector3 = camera.project_ray_origin(mouse_pos)
	var normal : Vector3 = camera.project_ray_normal(mouse_pos)
	var entity_hex : Vector2i = _pick_entity_hex(origin, normal)
	if entity_hex.x >= 0:
		return entity_hex
	# Pass 2: standard ray-plane intersection at GROUND_Y
	var hit : Vector3 = mouse_to_ground(mouse_pos)
	if is_nan(hit.x):
		return Vector2i(-1, -1)
	return world_to_hex(hit)

# Tìm entity (enemy hoặc player) có capsule gần ray nhất.
# Capsule = trụ đứng tại (entity.x, *, entity.z), bán kính PICK_RADIUS.
# Trả Vector2i(grid_col, grid_row) hoặc (-1,-1) nếu không có entity nào trong tầm.
func _pick_entity_hex(origin: Vector3, dir: Vector3) -> Vector2i:
	const PICK_RADIUS : float = 0.45   # bán kính trục capsule (hơi nhỏ hơn HEX_SIZE/2)
	const PICK_Y_MIN  : float = -0.10   # ray phải đi qua dải Y này (capsule bottom)
	const PICK_Y_MAX  : float = 2.20    # đến top capsule
	var best   : Vector2i = Vector2i(-1, -1)
	var best_t : float    = INF

	var dxz2 : float = dir.x * dir.x + dir.z * dir.z
	if dxz2 < 0.0001:
		return best   # ray thẳng đứng → không pick được capsule

	# Gom alive entities
	var entities : Array = []
	for e in enemies:
		if is_instance_valid(e) and e.hp > 0:
			entities.append(e)
	for p in players:
		if p.hp > 0:
			entities.append(p)

	for ent in entities:
		var ep : Vector3 = entity_position(ent.grid_col, ent.grid_row)
		# t (parameter trong ray gốc) tại điểm gần trục capsule nhất.
		# Capsule là trục đứng → khoảng cách 3D = khoảng cách XZ.
		var t : float = ((ep.x - origin.x) * dir.x + (ep.z - origin.z) * dir.z) / dxz2
		if t < 0.0: continue   # entity sau lưng camera
		var cx : float = origin.x + t * dir.x
		var cz : float = origin.z + t * dir.z
		var d2 : float = (cx - ep.x) * (cx - ep.x) + (cz - ep.z) * (cz - ep.z)
		if d2 > PICK_RADIUS * PICK_RADIUS: continue
		# 3D verify: Y của ray tại t phải nằm trong capsule volume
		# → tránh false-positive khi 2D shadow trùng nhưng ray bay vượt đầu/dưới chân capsule.
		var cy : float = origin.y + t * dir.y
		if cy < PICK_Y_MIN or cy > PICK_Y_MAX: continue
		if t < best_t:
			best_t = t
			best   = Vector2i(ent.grid_col, ent.grid_row)
	return best

# ═══════════════════════════════════════════════════════════
#  INPUT
# ═══════════════════════════════════════════════════════════

func _input(event: InputEvent) -> void:
	# ESC = cancel bomb mode trước, sau đó mới quit game
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		if placing_bomb:
			placing_bomb = false
			_refresh_tile_colors()
			_refresh_debug()
			return
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
			KEY_W:
				if phase == Phase.PLAYER_TURN:
					_toggle_bomb_placement()
			KEY_ENTER, KEY_KP_ENTER:
				if phase == Phase.DEAD:
					_restart_game()

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
		# Mike đang aim → drag chuột cập nhật drag_center của timing bar.
		_handle_mouse_motion(event.position)
		var hex : Vector2i = mouse_to_hex(event.position)
		if hex != hover_hex:
			hover_hex = hex
			_refresh_tile_colors()
			_refresh_debug()

	# LMB press / release — split để Sonny giữ-thả LMB cho Boong charge bar.
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_handle_lmb_press(event.position)
		else:
			_handle_lmb_release()

func _refresh_debug() -> void:
	if not debug_label: return
	if phase == Phase.DEAD:
		debug_label.text = "[DEAD] All heroes fallen. Press ENTER to restart."
		return
	if players.is_empty():
		debug_label.text = "pitch %.0f° yaw %.0f° dist %.0f  hover=%s" \
			% [camera_pitch_deg, camera_yaw_deg, camera_distance, str(hover_hex)]
		return
	if placing_bomb:
		debug_label.text = "[PLACING BOMB] click ô kề bên (passable) để đặt — ESC = cancel"
		return
	var cur = players[current_player_index]
	var phase_str : String
	match phase:
		Phase.PLAYER_TURN: phase_str = "PLAYER"
		Phase.ENEMY_TURN:  phase_str = "ENEMY"
		Phase.DODGE_PHASE: phase_str = "DODGE!"
		_:                 phase_str = "?"
	# Hints khác nhau cho Sonny (Boong + bomb) vs Mike (ranged)
	var hints : String
	if cur.uses_draw_shot:
		hints = "LMB=move/shoot  Tab=swap  D=end  SPACE=dodge"
	else:
		hints = "LMB=move/Boong(hold)  W=Bomb(%d)  Tab=swap  D=end  SPACE=dodge" \
			% sonny_bombs_left
	debug_label.text = "[%s] %s HP %d/%d  Act %d/%d   |   %s   |   pitch %.0f° dist %.0f" \
		% [
			phase_str,
			player_names[current_player_index],
			cur.hp, cur.max_hp,
			cur.actions_left, cur.actions_per_turn,
			hints,
			camera_pitch_deg, camera_distance
		]
