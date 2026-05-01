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

# Map decorations — .glb scene preload theo key (FLOOR_SCENARIOS.decorations
# tham chiếu bằng key string). .glb cần được Godot import (mở editor 1 lần).
const DECO_SCENES : Dictionary = {
	"house": preload("res://Map/Level Asset/Level 1/House.glb"),
	"tree":  preload("res://Map/Tree.glb"),
	"fire":  preload("res://campfire.tscn"),
}

# ─── Hex grid ────────────────────────────────────────────────
const HEX_SIZE     : float = 1.0
const GRID_COLS    : int   = 12
const GRID_ROWS    : int   = 8
const GROUND_Y     : float = 0.2   # = HexTile.TILE_HEIGHT (mặt trên tile, nơi entities đứng)
const TWEEN_SPEED  : float = 0.18  # giây cho 1 lần move smooth
const ACTION_DELAY   : float = 0.5   # giây giữa các action liên tiếp của enemy
const CHARGE_SPEED   : float = 8.0   # bulldozer world-units/sec during charge

# Mốc 6.3: DodgeBar minigame
const DodgeBarScene  = preload("res://dodge_bar.tscn")
# Mốc 7.1: Sonny charge bar (Boong)
const ChargeBarScene = preload("res://sonny_charge_bar.tscn")
# Mốc 8.1: Mike timing bar (Draw Shot)
const TimingBarScene = preload("res://mike_timing_bar.tscn")
# Mốc 8.3: Bouncing projectile cho Mike's Draw Shot
const ProjectileScene = preload("res://projectile.tscn")
# Fixed speeds for enemy-fired projectiles (no decay; tuning is enemy-side)
const PROJ_ENEMY_SPEED_SLOW   : float = 5.0
const PROJ_ENEMY_SPEED_NORMAL : float = 8.0
const PROJ_ENEMY_SPEED_FAST   : float = 14.0
const PROJECTILE_Y            : float = 1.10   # độ cao bay (giữa thân character)

# Mốc 9.1: Floor scenarios — composition mỗi floor (column layout + enemies).
# `current_floor` index vào array; floor cuối là boss.
const FLOOR_SCENARIOS : Array = [
	# Floor 0 — intro: 2 grunts, no columns
	{
		"name":    "Floor 1",
		"is_boss": false,
		"columns": [],
		"decorations": [
			# House mới: X=-5, Z=-11 (lùi xa sau grid để không che ô hex front).
			# Y=0.2 = TILE_HEIGHT → nền nhà ngang bằng mặt trên ô hex.
			{ "scene": "house", "pos": Vector3(-5.0, 0.2, -11.0), "scale": 1.0, "rot_y_deg": 0.0 },
		],
		"random_trees": 3,    # cây random trên hex tiles trống (tree = obstacle)
		"random_fires": 2,    # đám lửa random trên hex tiles trống (fire = -1 HP khi đi qua)
		"randomize_enemy_positions": true,
		"enemies": [
			{ "type": "grunt",     "col": 7, "row": 2 },
			{ "type": "grunt",     "col": 8, "row": 5 },
			{ "type": "assassin",  "col": 0, "row": 0 },   # dùng model Squirrel
			{ "type": "bulldozer", "col": 0, "row": 0 },   # dùng model Bull
			{ "type": "dasher",    "col": 0, "row": 0 },   # nhanh, mỏng máu
			{ "type": "gunner",    "col": 0, "row": 0 },   # ranged sniper
		],
	},
	# Floor 1 — basic: + 1 archer + 1 column
	{
		"name":    "Floor 2",
		"is_boss": false,
		"columns": [Vector2i(5, 4)],
		"enemies": [
			{ "type": "grunt",  "col": 7, "row": 2 },
			{ "type": "grunt",  "col": 8, "row": 5 },
			{ "type": "archer", "col": 10, "row": 3 },
		],
	},
	# Floor 2 — ranged-heavy: 2 archers + 2 columns
	{
		"name":    "Floor 3",
		"is_boss": false,
		"columns": [Vector2i(4, 3), Vector2i(7, 4)],
		"enemies": [
			{ "type": "grunt",  "col": 6, "row": 1 },
			{ "type": "archer", "col": 9, "row": 2 },
			{ "type": "archer", "col": 10, "row": 5 },
		],
	},
	# Floor 3 — assassin: 1 assassin + 1 archer + 3 columns
	{
		"name":    "Floor 4",
		"is_boss": false,
		"columns": [Vector2i(4, 3), Vector2i(7, 4), Vector2i(5, 6)],
		"enemies": [
			{ "type": "archer",   "col": 8,  "row": 2 },
			{ "type": "assassin", "col": 9,  "row": 4 },
			{ "type": "grunt",    "col": 10, "row": 6 },
		],
	},
	# Floor 4 (BOSS) — mini-boss: 2 grunts + 1 archer + 2 assassins
	{
		"name":    "BOSS",
		"is_boss": true,
		"columns": [Vector2i(5, 3), Vector2i(8, 4)],
		"enemies": [
			{ "type": "grunt",    "col": 6,  "row": 1 },
			{ "type": "grunt",    "col": 6,  "row": 6 },
			{ "type": "archer",   "col": 10, "row": 3 },
			{ "type": "assassin", "col": 9,  "row": 5 },
			{ "type": "assassin", "col": 8,  "row": 2 },
		],
	},
]

# Floor hiện tại — đọc từ Engine.meta nếu có (sang scene thì giữ tiến độ),
# else 0 (floor đầu).
var current_floor : int = 0

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
var fire_pit_tiles : Dictionary = {}   # Vector2i → true (đi qua được, -1 HP)
var tree_tiles     : Dictionary = {}   # Vector2i → true (obstacle, ko đi qua được)

# ─── Entities ────────────────────────────────────────────────
var players              : Array = []          # Array of Player nodes
var player_positions     : Array = []          # Array of Vector2i
var player_names         : Array = []          # Array of String
var current_player_index : int   = 0
var enemies              : Array = []          # Array of Enemy nodes
var valid_attack_targets : Array = []          # Array of Vector2i — enemy hex kề bên hiện tại có thể tấn công

# Mốc 7 — Sonny charge bar + bomb state
var sonny_charge_bar    : Node = null   # active charge bar instance (nếu đang giữ LMB)
var sonny_charge_target : Node = null   # enemy đang bị Sonny "Boong"

# Mốc 8 — Mike timing bar state
var mike_timing_bar        : Node    = null
var mike_timing_target_pos : Vector3 = Vector3.ZERO  # free direction Vector3
var mike_aim_overlay       : Node    = null   # AimOverlay3D — preview projectile path

# ─── Projectile runtime state ────────────────────────────────
var active_projectiles  : Array      = []    # Array[Projectile3D]
var _bz_lock_lines      : Dictionary = {}    # bz instance_id → MeshInstance3D
var _mage_aim_hexes     : Dictionary = {}    # Vector2i → true; all hexes under active mage aura
var _entity_tweens      : Dictionary = {}    # entity instance_id → Tween
var _proj_last_col_hex  : Dictionary = {}    # instance_id → Vector2i (last column bounced)
var _proj_last_char_hex : Dictionary = {}    # instance_id → Vector2i (last char hex entered)
var _proj_prev_pos      : Dictionary = {}    # instance_id → Vector3  (world pos previous frame)
var _proj_bounds_min    : Vector3    = Vector3.ZERO
var _proj_bounds_max    : Vector3    = Vector3.ZERO
# Reaction timing — SPACE press timestamp
var _space_pressed_at   : float = -100.0

# ─── Turn state ──────────────────────────────────────────────
enum Phase { PLAYER_TURN, ENEMY_TURN, DODGE_PHASE, DEAD, FLOOR_CLEAR, VICTORY }
var phase                       : Phase      = Phase.PLAYER_TURN
var valid_moves                 : Array      = []     # Array of Vector2i — BFS reachable từ current player
var players_turned_this_round   : Array      = []     # idx đã end turn trong round hiện tại

var attack_committed_this_round : bool       = false  # khoá undo sau khi attack/dùng action không thể hoàn
var reset_turn_used             : bool       = false
var turn_snapshot               : Dictionary = {}     # state ở đầu round để undo/reset

# ─── Hover ──────────────────────────────────────────────────
var hover_hex       : Vector2i = Vector2i(-1, -1)
var hover_world_pos : Vector3  = Vector3(NAN, NAN, NAN)   # mouse world XZ — cho Mike aim preview free direction

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

func _to_cube_i(col: int, row: int) -> Vector3i:
	var x := col
	var z := row - (col - (col & 1)) / 2
	return Vector3i(x, -x - z, z)

func _from_cube_i(cube: Vector3i) -> Vector2i:
	var col := cube.x
	var row := cube.z + (col - (col & 1)) / 2
	return Vector2i(col, row)

func _cube_rotate_60_cw(d: Vector3i) -> Vector3i:
	return Vector3i(-d.z, -d.x, -d.y)

func _cube_rotate_60_ccw(d: Vector3i) -> Vector3i:
	return Vector3i(-d.y, -d.z, -d.x)

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
	if key in tree_tiles:   return false
	return true

# ═══════════════════════════════════════════════════════════
#  LIFECYCLE
# ═══════════════════════════════════════════════════════════

func _ready() -> void:
	# Mốc 9: đọc current_floor từ Engine.meta (giữ tiến độ qua scene change).
	if Engine.has_meta("current_floor"):
		current_floor = int(Engine.get_meta("current_floor"))
	grid_origin   = _grid_center_offset()
	camera_anchor = Vector3.ZERO
	_proj_bounds_min = Vector3(grid_origin.x - 0.6, PROJECTILE_Y,
		grid_origin.z - 0.6)
	_proj_bounds_max = Vector3(
		grid_origin.x + HEX_SIZE * 1.5 * float(GRID_COLS) + 0.6, PROJECTILE_Y,
		grid_origin.z + HEX_SIZE * sqrt(3.0) * float(GRID_ROWS) + 0.6)
	_build_grid()
	_build_sidewalk()       # mặt phẳng vỉa hè quanh grid
	_setup_demo_columns()   # Mốc 9.1: load từ FLOOR_SCENARIOS[current_floor]
	_setup_decorations()    # Mốc 9.1: load .glb decorations (cây, etc.)
	_setup_coord_grid()     # Debug overlay (F4 toggle)
	_spawn_players()
	# Place trees/fires TRƯỚC khi spawn enemies → enemy._random_enemy_spawn_tile
	# sẽ skip tile có cây/lửa (xem filter trong hàm đó).
	_place_border_trees()   # cây cố định row 0/7
	_scatter_random_trees() # cây random hex tiles trống (obstacle)
	_scatter_random_fires() # đám lửa random hex tiles trống (-1 HP)
	_spawn_enemies()
	_face_all_players_to_enemies()
	_face_all_enemies_to_players()
	_update_valid_moves()
	_save_turn_snapshot()
	_refresh_tile_colors()
	get_viewport().size_changed.connect(_on_viewport_resized)
	_on_viewport_resized()  # set zoom + cập nhật camera lần đầu
	_init_hud()
	_spawn_time_of_day_ui()
	_refresh_debug()

# ═══════════════════════════════════════════════════════════
#  TIME OF DAY (slider giờ + Day/Night toggle)
# ═══════════════════════════════════════════════════════════

var _time_of_day : TimeOfDay = null
var _time_hour_label : Label = null
var _time_toggle_btn : Button = null

func _spawn_time_of_day_ui() -> void:
	var sun_node = get_node_or_null("Sun") as DirectionalLight3D
	if sun_node == null:
		print("[TimeOfDay] không tìm thấy Sun node — skip")
		return
	var env_node = get_node_or_null("WorldEnvironment") as WorldEnvironment
	var env_resource : Environment = null
	if env_node and env_node.environment:
		env_resource = env_node.environment
	_time_of_day = TimeOfDay.new()
	_time_of_day.name = "TimeOfDay"
	add_child(_time_of_day)
	_time_of_day.setup(sun_node, env_resource)

	# UI ─────────────────────────────────────
	var layer := CanvasLayer.new()
	layer.layer = 6   # trên HUD (5)
	layer.name = "TimeOfDayUI"
	add_child(layer)

	var bg := PanelContainer.new()
	bg.anchor_left = 0.0; bg.anchor_top = 1.0
	bg.anchor_right = 0.0; bg.anchor_bottom = 1.0
	bg.offset_left = 20.0
	bg.offset_top  = -100.0
	bg.offset_right = 380.0
	bg.offset_bottom = -20.0
	layer.add_child(bg)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	bg.add_child(vb)

	# Top row: hour label + toggle button
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	vb.add_child(top)

	_time_hour_label = Label.new()
	_time_hour_label.text = "12:00"   # slider default 6 + day base 6 = 12:00
	_time_hour_label.custom_minimum_size = Vector2(80, 24)
	_time_hour_label.add_theme_color_override("font_color", Color(1, 1, 0.85))
	top.add_child(_time_hour_label)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(spacer)

	_time_toggle_btn = Button.new()
	_time_toggle_btn.text = "Ngày"
	_time_toggle_btn.toggle_mode = true
	_time_toggle_btn.custom_minimum_size = Vector2(80, 24)
	top.add_child(_time_toggle_btn)

	# Slider 0..12
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 12.0
	slider.step = 0.1
	slider.value = 6.0
	slider.custom_minimum_size = Vector2(340, 28)
	vb.add_child(slider)

	# Wire signals
	slider.value_changed.connect(_on_time_slider_changed)
	_time_toggle_btn.toggled.connect(_on_time_toggle)

	# Init lighting với value mặc định
	_time_of_day.set_value(slider.value)

func _on_time_slider_changed(v: float) -> void:
	if _time_of_day == null: return
	_time_of_day.set_value(v)
	_refresh_time_label(v)

# Map slider 0..12 → giờ thực:
#   Day:   6:00 → 18:00 (slider 0 = 6, slider 12 = 18)
#   Night: 18:00 → 6:00 hôm sau (qua 23:59 → 00:00 → 6:00)
func _refresh_time_label(v: float) -> void:
	if _time_hour_label == null: return
	var base : float = 6.0
	if _time_of_day != null and _time_of_day.is_night:
		base = 18.0
	var total : float = fmod(base + v, 24.0)
	var h : int = int(total)
	var m : int = int((total - h) * 60.0)
	_time_hour_label.text = "%02d:%02d" % [h, m]

func _on_time_toggle(pressed: bool) -> void:
	if _time_of_day == null: return
	_time_of_day.set_night(pressed)
	if _time_toggle_btn:
		_time_toggle_btn.text = "Đêm" if pressed else "Ngày"
	_refresh_time_label(_time_of_day.slider_value)

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
	if not players.is_empty() and players[current_player_index].placing_bomb: return
	var idx : int = player_names.find(char_name)
	if idx < 0 or idx == current_player_index: return
	if players[idx].hp <= 0: return
	_clear_action_modes()
	current_player_index = idx
	_update_valid_moves()
	_refresh_tile_colors()
	_refresh_debug()
	_refresh_hud()

func _on_hud_backpack() -> void:
	# Mốc 5 stub — backpack scene sẽ build sau Mốc 8/9
	print("[HUD] Backpack pressed (stub)")

func _on_viewport_resized() -> void:
	# Dùng kích thước OS window thay vì viewport size — khi pixelate_root
	# wrap main.tscn vào SubViewport (vd 480×270), camera zoom phải tính
	# theo screen thật (1920×1080) chứ không phải SubViewport low-res.
	var size : Vector2 = Vector2(get_window().size)
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
	# Layout map theo row:
	#   Row 0 (A-L)         → GRASS  (cỏ rìa)
	#   Row 1 (A-L)         → CEMENT (vỉa hè)
	#   Row 2               → NORMAL (đất)
	#   Row 3, 4, 5         → ASPHALT (mặt đường nhựa)
	#   Row 6 (A-L)         → CEMENT (vỉa hè)
	#   Row 7 (A-I, col≤8)  → GRASS  (cỏ rìa, J-L vẫn NORMAL)
	for col in range(GRID_COLS):
		for row in range(GRID_ROWS):
			var key  : Vector2i = Vector2i(col, row)
			var tile           = HexTileScene.instantiate()
			add_child(tile)
			var t = HexTileScript.Type.NORMAL
			if row == 0:
				t = HexTileScript.Type.GRASS
			elif row == 1 or row == 6:
				t = HexTileScript.Type.CEMENT
			elif row == 3 or row == 4 or row == 5:
				t = HexTileScript.Type.ASPHALT
			elif row == GRID_ROWS - 1 and col <= 8:
				t = HexTileScript.Type.GRASS
			tile.setup(col, row, t)
			tile.position = hex_to_world(col, row)
			tiles[key] = tile

# Vỉa hè: mặt phẳng xám rộng phủ quanh hex grid. Đặt nhà/cây/decoration lên đó.
const SIDEWALK_SIZE  : Vector2 = Vector2(40.0, 30.0)
const SIDEWALK_COLOR : Color   = Color(0.55, 0.55, 0.55)
const SIDEWALK_Y     : float   = 0.0

func _build_sidewalk() -> void:
	var plane := MeshInstance3D.new()
	plane.name = "Sidewalk"
	var pm := PlaneMesh.new()
	pm.size = SIDEWALK_SIZE
	plane.mesh = pm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = SIDEWALK_COLOR
	mat.roughness    = 0.92
	plane.material_override = mat
	plane.position = Vector3(0.0, SIDEWALK_Y, 0.0)
	add_child(plane)

func _setup_demo_columns() -> void:
	# Mốc 9.1: load columns từ FLOOR_SCENARIOS theo current_floor.
	var scenario : Dictionary = _current_scenario()
	var cols : Array = scenario.get("columns", [])
	for cr in cols:
		if tiles.has(cr):
			tiles[cr].setup(cr.x, cr.y, HexTileScript.Type.COLUMN)
			column_tiles[cr] = true

var _coord_grid : Node3D = null

func _setup_coord_grid() -> void:
	# Spawn lưới tọa độ debug — mặc định ON. F4 toggle.
	var grid_script = load("res://coord_grid.gd")
	_coord_grid = Node3D.new()
	_coord_grid.set_script(grid_script)
	_coord_grid.name = "CoordGrid"
	add_child(_coord_grid)

func _setup_decorations() -> void:
	# Instance .glb scenes (cỏ, nhà, etc.) ở vị trí world cố định.
	# Decorations chỉ trang trí, không tham gia gameplay (không block, không LOS).
	_ensure_deco_holder()
	var scenario : Dictionary = _current_scenario()
	var decos : Array = scenario.get("decorations", [])
	for d in decos:
		var key : String = d.get("scene", "")
		if not DECO_SCENES.has(key): continue
		# Campfire build mesh+particles trong _ready → KHÔNG duplicate được
		# (sẽ build 2 lần, particles bị reset). Instantiate fresh.
		# .glb (house/grass) thì cache prefab + duplicate (share resources).
		var inst : Node3D
		var s : float = d.get("scale", 1.0)
		if key == "fire":
			inst = DECO_SCENES[key].instantiate() as Node3D
			# Particles dùng world coords → Node3D.scale KHÔNG ảnh hưởng size
			# emit/quad/light. Pass scale từ scenario sang fire_size_mult
			# (đã handle multiply lên mọi param trong campfire.gd).
			if inst:
				inst.set("fire_size_mult", s)
			s = 1.0   # đừng apply Node3D scale nữa, tránh double-scale logs/ember
		else:
			var prefab : Node3D = _get_deco_prefab(key)
			if prefab == null: continue
			inst = prefab.duplicate() as Node3D
		if inst == null: continue
		inst.visible = true
		inst.position = d.get("pos", Vector3.ZERO)
		inst.scale = Vector3(s, s, s)
		inst.rotation_degrees = Vector3(0, d.get("rot_y_deg", 0.0), 0)
		add_child(inst)
		print("[deco] %s spawned at %s" % [key, str(inst.position)])
		if key == "house":
			_try_ignite_house_car(inst)
	# Grass scatter — spawn grass.glb trên N% hex tiles NORMAL (mỗi tile 1 cụm).
	var pct : int = int(scenario.get("grass_scatter_pct", 0))
	if pct > 0:
		_scatter_grass(pct)

# ─── Grass scatter ──────────────────────────────────────────
# Vừa fit hex tile (HEX_SIZE=1.0). Lod_bias thấp + visibility range
# giảm cost render khi nhiều cụm trên màn hình.
const GRASS_LOD_BIAS         : float = 0.25
const GRASS_VIS_RANGE_END    : float = 30.0
const GRASS_VIS_RANGE_MARGIN : float = 6.0
const GRASS_HEX_FIT_RATIO    : float = 0.85   # 85% đường kính hex

func _scatter_grass(pct: int) -> void:
	var prefab : Node3D = _get_deco_prefab("grass")
	if prefab == null: return
	var bbox : AABB = _measure_combined_aabb(prefab)
	var max_dim : float = maxf(bbox.size.x, bbox.size.z)
	if max_dim < 0.001:
		print("[grass] AABB invalid — skip scatter")
		return
	# Scale cụm cỏ vừa fit hex (đường kính hex ≈ 2*HEX_SIZE).
	var fit_scale : float = (HEX_SIZE * 2.0 * GRASS_HEX_FIT_RATIO) / max_dim
	var spawned : int = 0
	for key in tiles.keys():
		var tile = tiles[key]
		if tile.tile_type != HexTileScript.Type.NORMAL: continue
		if randf() * 100.0 > pct: continue
		var inst : Node3D = prefab.duplicate() as Node3D
		if inst == null: continue
		inst.visible = true
		var p : Vector3 = hex_to_world(int(key.x), int(key.y))
		p.y = GROUND_Y   # mặt trên hex tile (= HexTile.TILE_HEIGHT)
		inst.position = p
		inst.scale = Vector3(fit_scale, fit_scale, fit_scale)
		inst.rotation_degrees = Vector3(0, randf() * 360.0, 0)
		_apply_grass_runtime_opts(inst)
		add_child(inst)
		spawned += 1
	print("[grass] scattered %d clumps (pct=%d, fit_scale=%.3f)" % [spawned, pct, fit_scale])

# ─── Random trees / fires + border trees ────────────────────
const TREE_HEX_FIT_RATIO    : float = 0.825
const FIRE_HEX_SIZE_MULT    : float = 0.65

# Cây cố định ở rìa map: row 7 (B,D,F,H,J,L) + row 0 (E,G,I,K).
const BORDER_TREE_TILES : Array = [
	# Row 7 — top edge
	Vector2i( 1, 7), Vector2i( 3, 7), Vector2i( 5, 7),
	Vector2i( 7, 7), Vector2i( 9, 7), Vector2i(11, 7),
	# Row 0 — bottom edge
	Vector2i( 4, 0), Vector2i( 6, 0), Vector2i( 8, 0), Vector2i(10, 0),
]

var _random_used_tiles : Dictionary = {}    # tile → true (tránh chồng tree/fire)

# N hex tile NORMAL trống (tránh player, enemies, tile đã dùng, tree, fire).
func _pick_free_tiles(count: int) -> Array:
	if count <= 0: return []
	var occupied : Dictionary = _random_used_tiles.duplicate()
	for pos in player_positions:
		occupied[pos] = true
	for e in enemies:
		if is_instance_valid(e):
			occupied[Vector2i(e.grid_col, e.grid_row)] = true
	var candidates : Array = []
	for key in tiles.keys():
		if tiles[key].tile_type != HexTileScript.Type.NORMAL: continue
		if occupied.has(key): continue
		if tree_tiles.has(key): continue
		if fire_pit_tiles.has(key): continue
		candidates.append(key)
	candidates.shuffle()
	var picked : Array = candidates.slice(0, mini(count, candidates.size()))
	for k in picked:
		_random_used_tiles[k] = true
	return picked

func _scatter_random_trees() -> void:
	var scenario : Dictionary = _current_scenario()
	var count : int = int(scenario.get("random_trees", 0))
	if count <= 0: return
	var prefab : Node3D = _get_deco_prefab("tree")
	if prefab == null: return
	var bbox : AABB = _measure_combined_aabb(prefab)
	var max_dim : float = maxf(bbox.size.x, bbox.size.z)
	if max_dim < 0.001: return
	var fit_scale : float = (HEX_SIZE * 2.0 * TREE_HEX_FIT_RATIO) / max_dim
	var picked : Array = _pick_free_tiles(count)
	for key in picked:
		var inst : Node3D = prefab.duplicate() as Node3D
		if inst == null: continue
		inst.visible = true
		var p : Vector3 = hex_to_world(int(key.x), int(key.y))
		p.y = GROUND_Y
		inst.position = p
		inst.scale = Vector3(fit_scale, fit_scale, fit_scale)
		inst.rotation_degrees = Vector3(0, randf() * 360.0, 0)
		add_child(inst)
		tree_tiles[key] = true   # obstacle
	print("[tree] random %d cây (fit_scale=%.3f)" % [picked.size(), fit_scale])

func _scatter_random_fires() -> void:
	var scenario : Dictionary = _current_scenario()
	var count : int = int(scenario.get("random_fires", 0))
	if count <= 0: return
	if not DECO_SCENES.has("fire"): return
	var picked : Array = _pick_free_tiles(count)
	for key in picked:
		var inst : Node3D = DECO_SCENES["fire"].instantiate() as Node3D
		if inst == null: continue
		inst.set("fire_size_mult", FIRE_HEX_SIZE_MULT)
		var p : Vector3 = hex_to_world(int(key.x), int(key.y))
		p.y = GROUND_Y
		inst.position = p
		add_child(inst)
		fire_pit_tiles[key] = true   # -1 HP khi đi qua
	print("[fire] random %d ngọn lửa" % picked.size())

func _place_border_trees() -> void:
	var prefab : Node3D = _get_deco_prefab("tree")
	if prefab == null: return
	var bbox : AABB = _measure_combined_aabb(prefab)
	var max_dim : float = maxf(bbox.size.x, bbox.size.z)
	if max_dim < 0.001: return
	var fit_scale : float = (HEX_SIZE * 2.0 * TREE_HEX_FIT_RATIO) / max_dim
	var placed : int = 0
	for key in BORDER_TREE_TILES:
		if not tiles.has(key): continue
		if tree_tiles.has(key): continue
		var inst : Node3D = prefab.duplicate() as Node3D
		if inst == null: continue
		inst.visible = true
		var p : Vector3 = hex_to_world(int(key.x), int(key.y))
		p.y = GROUND_Y
		inst.position = p
		inst.scale = Vector3(fit_scale, fit_scale, fit_scale)
		inst.rotation_degrees = Vector3(0, randf() * 360.0, 0)
		add_child(inst)
		tree_tiles[key] = true
		_random_used_tiles[key] = true
		placed += 1
	print("[tree/border] %d cây edge rows (fit_scale=%.3f)" % [placed, fit_scale])

# ─── Fire-pit step damage ───────────────────────────────────
const FIRE_STEP_DAMAGE : int = 1

func _is_fire_pit_at(col: int, row: int) -> bool:
	return Vector2i(col, row) in fire_pit_tiles

func _check_fire_step_player(player_idx: int) -> void:
	if player_idx < 0 or player_idx >= players.size(): return
	var pos : Vector2i = player_positions[player_idx]
	if not _is_fire_pit_at(pos.x, pos.y): return
	_apply_damage_to_player(player_idx, FIRE_STEP_DAMAGE, "hit")

func _check_fire_step_enemy(enemy: Node) -> void:
	if not is_instance_valid(enemy): return
	if not _is_fire_pit_at(enemy.grid_col, enemy.grid_row): return
	enemy.take_damage(FIRE_STEP_DAMAGE)
	_spawn_damage_popup(enemy.position + Vector3(0, 1.8, 0),
		"-%d FIRE" % FIRE_STEP_DAMAGE, Color(1.0, 0.55, 0.20))
	if enemy.hp <= 0:
		_kill_enemy(enemy)
	elif hud != null:
		hud.update_enemy_hp(enemy.get_instance_id(), enemy.hp, enemy.max_hp)

# Đếm số ô fire pit trên đường đi src→dest (bỏ qua start, tính cả dest).
# Mỗi ô lửa đi qua = -FIRE_STEP_DAMAGE HP (đi qua cũng cháy, không chỉ đứng).
func _count_fires_on_path(src: Vector2i, dest: Vector2i) -> int:
	if src == dest: return 0
	var path : Array = _hex_line(src.x, src.y, dest.x, dest.y)
	var fires : int = 0
	for i in range(1, path.size()):   # skip src
		if path[i] in fire_pit_tiles:
			fires += 1
	return fires

func _apply_fire_path_damage_player(player_idx: int, src: Vector2i, dest: Vector2i) -> void:
	if player_idx < 0 or player_idx >= players.size(): return
	var fires : int = _count_fires_on_path(src, dest)
	if fires <= 0: return
	_apply_damage_to_player(player_idx, FIRE_STEP_DAMAGE * fires, "hit")

func _apply_fire_path_damage_enemy(enemy: Node, src: Vector2i, dest: Vector2i) -> void:
	if not is_instance_valid(enemy): return
	var fires : int = _count_fires_on_path(src, dest)
	if fires <= 0: return
	var dmg : int = FIRE_STEP_DAMAGE * fires
	enemy.take_damage(dmg)
	_spawn_damage_popup(enemy.position + Vector3(0, 1.8, 0),
		"-%d FIRE" % dmg, Color(1.0, 0.55, 0.20))
	if enemy.hp <= 0:
		_kill_enemy(enemy)
	elif hud != null:
		hud.update_enemy_hp(enemy.get_instance_id(), enemy.hp, enemy.max_hp)

# Recursive: gather AABB của tất cả MeshInstance3D children, merge thành 1 AABB
# tổng. Prefab phải đã trong scene tree → global_transform chính xác.
func _measure_combined_aabb(root: Node) -> AABB:
	var collected : Array = []
	_collect_mesh_aabbs(root, collected)
	if collected.is_empty(): return AABB()
	var combined : AABB = collected[0]
	for i in range(1, collected.size()):
		combined = combined.merge(collected[i])
	return combined

func _collect_mesh_aabbs(node: Node, out: Array) -> void:
	if node is MeshInstance3D:
		var mi : MeshInstance3D = node
		out.append(mi.global_transform * mi.get_aabb())
	for c in node.get_children():
		_collect_mesh_aabbs(c, out)

# ─── Car ignition ───────────────────────────────────────────
# Scan node names trong autumn_house tìm node giống "ô tô".
# Match case-insensitive với keyword phổ biến. Nếu không thấy → in cây
# node ra console để user kiểm tra.
const CAR_KEYWORDS : Array = [
	"car", "auto", "sedan", "suv", "truck", "vehicle",
]

func _try_ignite_house_car(house: Node3D) -> void:
	var car : Node3D = _find_node_by_keywords(house, CAR_KEYWORDS)
	if car == null:
		print("[fire/car] không tìm thấy node ô tô — cây node của house:")
		_print_subtree(house, 0)
		return
	# Đo AABB world-space của car và mọi mesh con bên trong.
	var aabb : AABB = _measure_combined_aabb(car)
	var max_dim : float = maxf(aabb.size.x, maxf(aabb.size.y, aabb.size.z))
	if max_dim < 0.001:
		print("[fire/car] tìm thấy '%s' nhưng AABB rỗng" % car.name)
		return
	var center : Vector3 = aabb.position + aabb.size * 0.5
	# Spawn Campfire ở tâm car, scale theo dimensions car để bao trùm.
	var fire : Node3D = DECO_SCENES["fire"].instantiate() as Node3D
	if fire == null: return
	fire.position = center
	# fire_size_mult ≈ kích thước lớn nhất của car → flames spread bao trùm.
	fire.set("fire_size_mult", max_dim * 1.1)
	fire.set("black_smoke",    true)
	fire.set("no_logs",        true)
	add_child(fire)
	print("[fire/car] đốt '%s' tại %s, max_dim=%.2f, mult=%.2f" \
			% [car.name, str(center), max_dim, max_dim * 1.1])

func _find_node_by_keywords(root: Node, keywords: Array) -> Node3D:
	var stack : Array = [root]
	while not stack.is_empty():
		var n : Node = stack.pop_back()
		if n is Node3D:
			var nm : String = String(n.name).to_lower()
			for kw in keywords:
				if kw in nm:
					return n
		for c in n.get_children():
			stack.append(c)
	return null

func _print_subtree(node: Node, depth: int) -> void:
	var indent : String = "  ".repeat(depth)
	print("%s%s [%s]" % [indent, node.name, node.get_class()])
	for c in node.get_children():
		_print_subtree(c, depth + 1)

# Áp dụng tối ưu lên mọi MeshInstance3D bên trong instance:
# ► lod_bias thấp → ưu tiên LOD đơn giản hơn (hiệu lực nếu .glb có LOD
#   được generate ở import, default Godot 4 = ON).
# ► visibility_range_end → cull instance khi camera xa, giảm draw call.
# Lưu ý: lod_bias chỉ giảm poly khi DISTANCE xa. Để giảm 80% poly thực sự
# ở mọi khoảng cách, cần Blender Decimate trước khi export .glb.
func _apply_grass_runtime_opts(node: Node) -> void:
	if node is MeshInstance3D:
		var mi : MeshInstance3D = node
		mi.lod_bias                    = GRASS_LOD_BIAS
		mi.visibility_range_end        = GRASS_VIS_RANGE_END
		mi.visibility_range_end_margin = GRASS_VIS_RANGE_MARGIN
	for c in node.get_children():
		_apply_grass_runtime_opts(c)

# Cache prefabs (1 cây từ forest) làm con của _deco_holder ẩn → tránh leak
# khi scene main reload (holder free thì prefab free theo).
var _deco_prefabs : Dictionary = {}
var _deco_holder  : Node3D     = null

func _ensure_deco_holder() -> void:
	if _deco_holder and is_instance_valid(_deco_holder): return
	_deco_holder = Node3D.new()
	_deco_holder.name = "DecoPrefabHolder"
	_deco_holder.visible = false
	add_child(_deco_holder)

func _get_deco_prefab(key: String) -> Node3D:
	if _deco_prefabs.has(key):
		return _deco_prefabs[key]
	if not DECO_SCENES.has(key): return null
	var prefab : Node3D = DECO_SCENES[key].instantiate() as Node3D
	if prefab:
		prefab.visible = false
		_deco_holder.add_child(prefab)
	_deco_prefabs[key] = prefab
	return prefab

func _current_scenario() -> Dictionary:
	var idx : int = clampi(current_floor, 0, FLOOR_SCENARIOS.size() - 1)
	return FLOOR_SCENARIOS[idx]

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

	if not players.is_empty():
		var _cur = players[current_player_index]
		# Grapple mode (Mike W): tô đỏ tất cả enemy như potential targets.
		if _cur.grappling:
			for key in tiles:
				var tile = tiles[key]
				if key in column_tiles or key in fire_pit_tiles:
					tile.set_state("normal")
				elif key == cur_pos:
					tile.set_state("selected")
				elif key in enemy_pos:
					tile.set_state("attack")
				else:
					tile.set_state("normal")
			_update_grapple_preview()
			return

		# Bomb placement mode: highlight ô kề bên passable+empty.
		if _cur.placing_bomb:
			_clear_aim_preview()
			for key in tiles:
				var tile = tiles[key]
				if key in column_tiles or key in fire_pit_tiles:
					tile.set_state("normal")
					continue
				var is_bomb_target : bool = (
					_hex_dist(_cur.grid_col, _cur.grid_row, key.x, key.y) == 1
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
	# Aim preview cho Mike — update khi state đổi (move/switch/hover).
	# Tự gate trong _update_aim_preview (chỉ chạy khi Mike active + hover enemy + LOS clear).
	_update_aim_preview()
	_mage_refresh_aim_hexes()

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

# Quay enemy về player gần nhất (theo grid_col/grid_row → world pos).
# Reuse _face_player_to_position vì Mixamo flip logic generic — cả player +
# enemy LP models đều face +Z.
func _face_enemy_to_nearest_player(enemy: Node) -> void:
	if not is_instance_valid(enemy): return
	if players.is_empty(): return
	var best_idx : int = -1
	var best_d   : int = 9999
	for i in range(players.size()):
		if players[i].hp <= 0: continue
		var d : int = _hex_dist(enemy.grid_col, enemy.grid_row,
				players[i].grid_col, players[i].grid_row)
		if d < best_d:
			best_d = d
			best_idx = i
	if best_idx < 0: return
	_face_player_to_position(enemy, players[best_idx].position)

func _face_all_enemies_to_players() -> void:
	for e in enemies:
		_face_enemy_to_nearest_player(e)

# Quay player về một vị trí world XZ cụ thể (target attack hiện tại). Dùng
# trước khi play_attack để animation đánh hướng đúng vào địch đang đánh.
func _face_player_to_position(p: Node, target_pos: Vector3) -> void:
	if p == null or not is_instance_valid(p): return
	var p_pos : Vector3 = p.position
	if absf(target_pos.x - p_pos.x) < 0.001 \
			and absf(target_pos.z - p_pos.z) < 0.001:
		return
	# look_at quay -Z local sang điểm target. Models .glb từ Mixamo/Blender
	# face +Z, nên xoay 180° quanh Y bù lại (cùng cơ chế _face_to_nearest_enemy).
	p.look_at(Vector3(target_pos.x, p_pos.y, target_pos.z), Vector3.UP)
	p.rotate_object_local(Vector3.UP, PI)

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
	# Mốc 9.1: load enemies từ FLOOR_SCENARIOS theo current_floor.
	var scenario : Dictionary = _current_scenario()
	var spawn_list : Array = scenario.get("enemies", [])
	var randomize : bool = bool(scenario.get("randomize_enemy_positions", false))
	var used_tiles : Dictionary = {}
	for entry in spawn_list:
		var col : int = int(entry["col"])
		var row : int = int(entry["row"])
		if randomize:
			var picked : Vector2i = _random_enemy_spawn_tile(used_tiles)
			if picked.x >= 0:
				col = picked.x
				row = picked.y
				used_tiles[picked] = true
		var key := Vector2i(col, row)
		if key in column_tiles: continue
		_spawn_enemy(entry["type"], col, row)

# Random tile NORMAL trống, cách player ≥ 3 hex (không spawn quá gần).
const ENEMY_SPAWN_MIN_DIST : int = 3
func _random_enemy_spawn_tile(used: Dictionary) -> Vector2i:
	# Spawn trên mọi tile gameplay walkable: NORMAL (đất), CEMENT (vỉa hè),
	# ASPHALT (đường nhựa). Skip GRASS (rìa map), COLUMN, FIRE_PIT, ô có cây.
	var candidates : Array = []
	for k in tiles.keys():
		var t = tiles[k].tile_type
		if t != HexTileScript.Type.NORMAL \
				and t != HexTileScript.Type.CEMENT \
				and t != HexTileScript.Type.ASPHALT:
			continue
		if k in column_tiles: continue
		if k in tree_tiles: continue        # ko spawn trên ô có cây
		if k in fire_pit_tiles: continue    # ko spawn trên bãi lửa
		if used.has(k): continue
		var skip : bool = false
		for pos in player_positions:
			if _hex_dist(k.x, k.y, pos.x, pos.y) < ENEMY_SPAWN_MIN_DIST:
				skip = true
				break
		if skip: continue
		candidates.append(k)
	if candidates.is_empty(): return Vector2i(-1, -1)
	return candidates.pick_random()

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

	# Tile bị chặn = column + tree (obstacle) + enemy + player khác (còn sống)
	var blocked : Dictionary = {}
	for key in column_tiles:
		blocked[key] = true
	for key in tree_tiles:
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
	# Sonny attack mode: also highlight adjacent players as targets
	if current.attack_mode and not current.uses_draw_shot:
		for i in range(players.size()):
			if i == current_player_index or players[i].hp <= 0: continue
			var ph : Vector2i = player_positions[i]
			if _can_attack_target(pos.x, pos.y, ph.x, ph.y):
				valid_attack_targets.append(ph)

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
	var target_pos : Vector3 = entity_position(target_col, target_row)
	var eid : int = entity.get_instance_id()
	if eid in _entity_tweens and is_instance_valid(_entity_tweens[eid]):
		_entity_tweens[eid].kill()
	# Bật walk anim trước khi tween (entity nào có anim_set_walking — vd Crab/Squirrel/Bull).
	if entity.has_method("anim_set_walking"):
		entity.anim_set_walking(true)
	var tween : Tween = create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(entity, "position", target_pos, TWEEN_SPEED)
	if entity.has_method("anim_set_walking"):
		tween.tween_callback(func(): entity.anim_set_walking(false))
	_entity_tweens[eid] = tween

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
	_apply_fire_path_damage_player(current_player_index, src, dest)   # ô lửa trên đường đi: -1 HP/ô
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
	var current_player = players[current_player_index]
	# Bomb placement mode (Sonny W) — click vào ô kề bên hợp lệ
	if current_player.placing_bomb:
		_place_bomb_at(hex)
		return
	# Grapple mode (Mike W) — click vào hex bất kỳ → fire hook
	if current_player.grappling:
		_grapple_at(hex)
		return
	# Mike aim mode owns all clicks — commit shot direction, no character switch.
	if current_player.uses_draw_shot and current_player.aiming:
		var world_pos : Vector3 = mouse_to_ground(mouse_pos)
		if not is_nan(world_pos.x):
			var mike_pos : Vector3 = current_player.position
			if absf(world_pos.x - mike_pos.x) > 0.01 \
					or absf(world_pos.z - mike_pos.z) > 0.01:
				current_player.aiming = false
				_start_mike_timing(world_pos, mouse_pos)
		return   # consume LMB while aiming (no movement, no switch)
	# Sonny attack mode owns all clicks — commit attack on valid target, no character switch.
	if not current_player.uses_draw_shot and current_player.attack_mode:
		var target : Node = _get_enemy_at(hex)
		if target == null:
			var pidx : int = _get_player_at(hex)
			if pidx >= 0 and pidx != current_player_index and players[pidx].hp > 0:
				target = players[pidx]
		if target != null and _can_attack_target(current_player.grid_col,
				current_player.grid_row, hex.x, hex.y):
			_start_sonny_charge(target)
		return   # consume all clicks while in attack mode (no switch, no movement)
	# Click vào player KHÁC (còn sống) → switch sang nhân vật đó
	var clicked_player_idx : int = _get_player_at(hex)
	if clicked_player_idx >= 0 and clicked_player_idx != current_player_index \
			and players[clicked_player_idx].hp > 0:
		_clear_action_modes()
		current_player_index = clicked_player_idx
		_update_valid_moves()
		_refresh_tile_colors()
		_refresh_debug()
		_refresh_hud()
		return
	# Mike not aiming — LMB moves on valid tiles.
	if current_player.uses_draw_shot:
		if hex in valid_moves:
			_move_player(hex)
		return
	# Sonny: click enemy kề bên → charge bar.
	var target_enemy : Node = _get_enemy_at(hex)
	if target_enemy != null and current_player.can_act() \
			and _can_attack_target(current_player.grid_col,
				current_player.grid_row, hex.x, hex.y):
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

func _start_sonny_charge(target: Node) -> void:
	var current_player = players[current_player_index]
	if not current_player.can_act(): return
	var bar = ChargeBarScene.instantiate()
	bar.is_holding = true   # bắt đầu hold ngay (LMB đang được nhấn)
	bar.charge_resolved.connect(_on_charge_resolved.bind(target))
	camera.add_child(bar)
	bar.position = Vector3(0.0, -0.18, -1.2)
	sonny_charge_bar    = bar
	sonny_charge_target = target

func _on_charge_resolved(result: String, target: Node) -> void:
	sonny_charge_bar    = null
	sonny_charge_target = null
	players[current_player_index].attack_mode = false
	if not is_instance_valid(target):
		_refresh_debug()
		return
	var current_player = players[current_player_index]
	var base_dmg : int = current_player.get_q_dmg()
	var dmg      : int = 0
	match result:
		"perfect": dmg = int(round(base_dmg * 1.5 + 0.4))
		"normal":  dmg = base_dmg
		"miss":    dmg = 0
	_face_player_to_position(current_player, target.position)
	if current_player.has_method("play_attack"):
		current_player.play_attack()
	var target_player_idx : int = players.find(target)
	if target_player_idx >= 0:
		# Target is a player (Mike)
		if dmg > 0:
			_apply_damage_to_player(target_player_idx, dmg)
		else:
			_spawn_damage_popup(target.position + Vector3(0, 1.8, 0),
				"MISS!", Color(0.7, 0.7, 0.7))
	else:
		# Target is an enemy
		if dmg > 0:
			_push_enemy(target, current_player.grid_col, current_player.grid_row, 1)
			if is_instance_valid(target) and target.hp > 0:
				target.take_damage(dmg)
				_maybe_interrupt_mage_cast(target)
				_spawn_damage_popup(target.position + Vector3(0, 1.8, 0),
					"-%d" % dmg, Color(1.0, 0.55, 0.30))
				if target.hp <= 0:
					_kill_enemy(target)
				elif hud != null:
					hud.update_enemy_hp(target.get_instance_id(), target.hp, target.max_hp)
		else:
			_spawn_damage_popup(target.position + Vector3(0, 1.8, 0),
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

# Q key: toggle aim mode cho Mike. Chỉ khi aim mode = true thì preview line
# hiện + click LMB sẽ fire. Outside aim mode, click LMB chỉ move (tránh bắn
# nhầm khi đi).
# Helper: clear mọi action mode khi switch player hoặc end turn.
func _clear_action_modes() -> void:
	for p in players:
		p.placing_bomb  = false
		p.grappling     = false
		p.aiming        = false
		p.attack_mode   = false
	_clear_aim_preview()

func _toggle_mike_aim_mode() -> void:
	if phase != Phase.PLAYER_TURN: return
	if players.is_empty(): return
	var current = players[current_player_index]
	if not current.uses_draw_shot: return
	if current.shot_used: return          # safety: Q disabled after shot fires
	if mike_timing_bar != null: return    # timing bar active, cannot toggle
	current.aiming = not current.aiming
	if not current.aiming:
		_clear_aim_preview()
	_refresh_tile_colors()                # trigger _update_aim_preview ở cuối
	_refresh_debug()

func _toggle_sonny_attack_mode() -> void:
	if phase != Phase.PLAYER_TURN: return
	if players.is_empty(): return
	var current = players[current_player_index]
	if current.uses_draw_shot: return
	if not current.can_act(): return
	if sonny_charge_bar != null: return
	current.attack_mode = not current.attack_mode
	_update_valid_moves()
	_refresh_tile_colors()
	_refresh_debug()

func _start_mike_timing(target_pos: Vector3, mouse_pos: Vector2) -> void:
	var current = players[current_player_index]
	if not current.can_act(): return
	var bar = TimingBarScene.instantiate()
	bar.timing_resolved.connect(_on_mike_timing_resolved.bind(target_pos))
	camera.add_child(bar)
	bar.position = Vector3(0.0, -0.18, -1.2)
	bar.setup(mouse_pos)
	mike_timing_bar        = bar
	mike_timing_target_pos = target_pos
	# Aim preview: trace + vẽ overlay theo direction đã lock
	var trace_result : Dictionary = _compute_projectile_trace(current, target_pos)
	if mike_aim_overlay == null:
		mike_aim_overlay = AimOverlay3D.new()
		add_child(mike_aim_overlay)
	mike_aim_overlay.show_path(trace_result["segs"])

func _update_grapple_preview() -> void:
	if players.is_empty():
		_clear_aim_preview()
		return
	var current = players[current_player_index]
	if not current.grappling:
		_clear_aim_preview()
		return
	if hover_hex.x < 0 or hover_hex == Vector2i(current.grid_col, current.grid_row):
		_clear_aim_preview()
		return
	var src : Vector2i = Vector2i(current.grid_col, current.grid_row)
	var path : Array   = _hex_line(src.x, src.y, hover_hex.x, hover_hex.y)
	# Default endpoint: hovered hex center
	var ep : Vector3 = entity_position(hover_hex.x, hover_hex.y)
	ep.y = PROJECTILE_Y
	# If first entity is in path, snap line to them
	for i in range(1, path.size()):
		var h : Vector2i = path[i]
		var e : Node = _get_enemy_at(h)
		if e != null:
			var p3 : Vector3 = entity_position(e.grid_col, e.grid_row)
			ep = Vector3(p3.x, PROJECTILE_Y, p3.z)
			break
		var pidx : int = _get_player_at(h)
		if pidx >= 0 and pidx != current_player_index:
			var p3 : Vector3 = entity_position(players[pidx].grid_col, players[pidx].grid_row)
			ep = Vector3(p3.x, PROJECTILE_Y, p3.z)
			break
	var sp : Vector3 = Vector3(current.position.x, PROJECTILE_Y, current.position.z)
	if mike_aim_overlay == null:
		mike_aim_overlay = AimOverlay3D.new()
		add_child(mike_aim_overlay)
	mike_aim_overlay.show_path([[sp, ep]])

# Hover preview cho Mike: khi Mike active + cursor trên ground (mouse_to_ground
# return valid Vector3), vẽ đường projectile dự kiến từ Mike đến điểm cursor.
# Free direction — không lock vào hex center, update mỗi frame mouse motion.
func _update_aim_preview() -> void:
	# Không update khi timing bar đang active (path đã lock từ click)
	if mike_timing_bar != null: return
	if phase != Phase.PLAYER_TURN:
		_clear_aim_preview()
		return
	if players.is_empty():
		_clear_aim_preview()
		return
	var current = players[current_player_index]
	if not current.uses_draw_shot:
		_clear_aim_preview()
		return
	if not current.can_act():
		_clear_aim_preview()
		return
	# Chỉ vẽ preview khi đang aim mode (Q đã bật)
	if not current.aiming:
		_clear_aim_preview()
		return
	# Cursor world position phải hợp lệ (ray hit ground plane)
	if is_nan(hover_world_pos.x):
		_clear_aim_preview()
		return
	# Cursor cũng không nên ở chính ô của Mike (no self-fire)
	var mike_pos : Vector3 = current.position
	if absf(hover_world_pos.x - mike_pos.x) < 0.01 \
			and absf(hover_world_pos.z - mike_pos.z) < 0.01:
		_clear_aim_preview()
		return
	var trace_result : Dictionary = _compute_projectile_trace(current, hover_world_pos)
	if mike_aim_overlay == null:
		mike_aim_overlay = AimOverlay3D.new()
		add_child(mike_aim_overlay)
	mike_aim_overlay.show_path(trace_result["segs"])

func _clear_aim_preview() -> void:
	if mike_aim_overlay != null and is_instance_valid(mike_aim_overlay):
		mike_aim_overlay.queue_free()
		mike_aim_overlay = null

func _on_mike_timing_resolved(result: String, target_pos: Vector3) -> void:
	mike_timing_bar = null
	# Clear aim preview overlay (cả khi miss)
	if mike_aim_overlay != null and is_instance_valid(mike_aim_overlay):
		mike_aim_overlay.queue_free()
		mike_aim_overlay = null
	var current = players[current_player_index]
	var base_dmg : int = current.get_q_dmg()
	var dmg      : int = 0
	match result:
		"perfect": dmg = int(round(base_dmg * 1.5 + 0.4))
		"hit":     dmg = base_dmg
		"miss":    dmg = 0
	current.use_action()
	current.has_attacked = true
	attack_committed_this_round = true
	current.shot_used = true
	if dmg > 0:
		_face_player_to_position(current, target_pos)
		if current.has_method("play_attack"):
			current.play_attack()
		var dir := Vector3(target_pos.x - current.position.x, 0.0,
			target_pos.z - current.position.z).normalized()
		var start := Vector3(current.position.x, PROJECTILE_Y, current.position.z)
		_fire_projectile(current, start, dir, float(dmg), true,
				current.proj_neg_bounce, current.proj_launch_speed)
		# Fire any caught projectiles 0.3s apart in the same direction
		if not current.caught_projectiles.is_empty():
			_fire_mike_caught_projectiles_async(current, dir)
	else:
		_spawn_damage_popup(current.position + Vector3(0, 1.8, 0),
			"MISS!", Color(0.7, 0.7, 0.7))
	_update_valid_moves()
	_refresh_tile_colors()
	_refresh_debug()
	_refresh_hud()
	_check_floor_clear()

# ═══════════════════════════════════════════════════════════
#  PROJECTILE FIRE — Mốc 8.3.3
# ═══════════════════════════════════════════════════════════

# Build BounceTracer3D với grid bounds + columns + enemy positions, trace từ
# shooter đến target_pos (free Vector3 trên XZ plane). Trả { segs, hit_hexes }.
func _compute_projectile_trace(shooter, target_pos: Vector3) -> Dictionary:
	var tracer := BounceTracer3D.new()
	tracer.bounds_min = Vector3(
		grid_origin.x - 0.6,
		PROJECTILE_Y,
		grid_origin.z - 0.6)
	tracer.bounds_max = Vector3(
		grid_origin.x + HEX_SIZE * 1.5 * float(GRID_COLS) + 0.6,
		PROJECTILE_Y,
		grid_origin.z + HEX_SIZE * sqrt(3.0) * float(GRID_ROWS) + 0.6)
	tracer.columns = column_tiles.duplicate()
	var enemy_dict : Dictionary = {}
	for e in enemies:
		if is_instance_valid(e) and e.hp > 0:
			enemy_dict[Vector2i(e.grid_col, e.grid_row)] = true
	for i in range(players.size()):
		if players[i] != shooter:
			enemy_dict[player_positions[i]] = true
	tracer.entities = enemy_dict
	tracer.hex_to_world = self.hex_to_world
	tracer.world_to_hex = func(p: Vector3) -> Vector2i: return world_to_hex(p)
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
	# stop_on_hit = false → projectile bounce off enemy (giống wall/column);
	# multiple enemies trên path đều ăn damage; speed decay tự dừng sau vài bounce.
	return tracer.trace(start, dir, false, exclude_hexes)


# ═══════════════════════════════════════════════════════════
#  PROJECTILE SYSTEM — real-time physics
# ═══════════════════════════════════════════════════════════

# Spawn and register a projectile. Returns the node.
func _fire_projectile(owner_nd: Node, start_pos: Vector3, direction: Vector3,
		damage: float, uses_decay: bool, neg_bounce: float,
		speed: float) -> Projectile3D:
	var proj : Projectile3D = ProjectileScene.instantiate()
	proj.proj_speed      = speed
	proj.proj_direction  = Vector3(direction.x, 0.0, direction.z).normalized()
	proj.proj_damage     = damage
	proj.negative_bounce = neg_bounce
	proj.owner_node      = owner_nd
	proj.uses_decay      = uses_decay
	add_child(proj)
	proj.position = Vector3(start_pos.x, PROJECTILE_Y, start_pos.z)
	active_projectiles.append(proj)
	proj.projectile_died.connect(_on_proj_died.bind(proj))
	return proj

func _on_proj_died(proj: Projectile3D) -> void:
	active_projectiles.erase(proj)
	var pid : int = proj.get_instance_id()
	_proj_last_col_hex.erase(pid)
	_proj_last_char_hex.erase(pid)
	_proj_prev_pos.erase(pid)

# Enemy fires a projectile at target player using attack dict data.
func _fire_enemy_projectile(enemy: Node, target_idx: int, attack: Dictionary) -> Projectile3D:
	var target_p = players[target_idx]
	var dir := Vector3(target_p.position.x - enemy.position.x, 0.0,
		target_p.position.z - enemy.position.z).normalized()
	var start := Vector3(enemy.position.x, PROJECTILE_Y, enemy.position.z)
	var dmg    : float = float(attack.get("damage", 1))
	var speed_key : String = str(attack.get("speed", "normal"))
	var spd : float = {
		"slow":   PROJ_ENEMY_SPEED_SLOW,
		"fast":   PROJ_ENEMY_SPEED_FAST,
	}.get(speed_key, PROJ_ENEMY_SPEED_NORMAL)
	var proj : Projectile3D = _fire_projectile(enemy, start, dir, dmg, false, 9999.0, spd)
	var stacks := int(attack.get("poison_stacks", 0))
	if stacks > 0:
		proj.proj_poison_stacks = stacks
		proj.paint_poison()
	return proj

# Fire Mike's caught projectiles 0.3s apart in the shot direction (background).
func _fire_mike_caught_projectiles_async(shooter: Node, direction: Vector3) -> void:
	var caught: Array = shooter.caught_projectiles.duplicate()
	shooter.caught_projectiles.clear()
	for cd in caught:
		await get_tree().create_timer(0.30).timeout
		if not is_instance_valid(shooter): break
		var start := Vector3(shooter.position.x, PROJECTILE_Y, shooter.position.z)
		_fire_projectile(shooter, start, direction,
			float(cd.get("damage", 1.0)),
			bool(cd.get("uses_decay", false)),
			float(cd.get("neg_bounce", 9999.0)),
			float(cd.get("speed", PROJ_ENEMY_SPEED_NORMAL)))

# Per-frame: wall → column → character collision for all active projectiles.
func _process_projectiles(_delta: float) -> void:
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
		# Save after all repositioning so prev_pos next frame reflects the circle crossing.
		if is_instance_valid(proj):
			_proj_prev_pos[pid] = proj.position

# Exact point where segment from_pos→to_pos first enters the circle (radius, center XZ).

# Exact world position where the segment from_pos→to_pos crosses the grid boundary.
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

func _check_proj_column(proj: Projectile3D,
		cur_pos: Vector3, _prev_pos: Vector3) -> void:
	var pid      : int      = proj.get_instance_id()
	var cur_hex  : Vector2i = world_to_hex(cur_pos)
	var last_col : Vector2i = _proj_last_col_hex.get(pid, Vector2i(-9999, -9999))
	if cur_hex in column_tiles:
		if cur_hex != last_col:
			_proj_last_col_hex[pid] = cur_hex
			var col_c : Vector3 = hex_to_world(cur_hex.x, cur_hex.y)
			var n : Vector3 = Vector3(cur_pos.x - col_c.x, 0.0, cur_pos.z - col_c.z)
			if n.length_squared() < 0.0001: n = Vector3.FORWARD
			proj.bounce_off_surface(n.normalized())
	else:
		_proj_last_col_hex.erase(pid)

func _check_proj_characters(proj: Projectile3D,
		cur_pos: Vector3, _prev_pos: Vector3) -> void:
	var pid     : int      = proj.get_instance_id()
	var cur_hex : Vector2i = world_to_hex(cur_pos)
	var last    : Vector2i = _proj_last_char_hex.get(pid, Vector2i(-9999, -9999))

	# Check enemies
	var hit_enemy : Node = _get_enemy_at(cur_hex)
	if hit_enemy != null and hit_enemy != proj.owner_node and cur_hex != last:
		_proj_last_char_hex[pid] = cur_hex
		_handle_enemy_proj_hit(proj, hit_enemy)
		return

	# Check players
	for i in range(players.size()):
		if player_positions[i] == cur_hex and players[i] != proj.owner_node and cur_hex != last:
			_proj_last_char_hex[pid] = cur_hex
			_handle_player_proj_contact_async(proj, i)   # background coroutine
			return

	if cur_hex != last:
		_proj_last_char_hex.erase(pid)

# Enemy hit: damage + bounce off hex border (or explode if supercharged).
func _handle_enemy_proj_hit(proj: Projectile3D, enemy: Node) -> void:
	if proj.is_supercharged:
		_supercharged_explosion(proj, Vector2i(enemy.grid_col, enemy.grid_row))
		return
	enemy.take_damage(proj.proj_damage)
	_maybe_interrupt_mage_cast(enemy)
	_spawn_damage_popup(enemy.position + Vector3(0, 1.8, 0),
		"-%d" % int(proj.proj_damage), Color(1.0, 0.55, 0.30))
	var poison := proj.consume_poison()
	if poison > 0:
		enemy.poison_stacks += poison
		_spawn_damage_popup(enemy.position + Vector3(0, 2.4, 0),
			"POISON x%d" % enemy.poison_stacks, Color(0.30, 0.85, 0.20))
	if enemy.hp <= 0:
		_kill_enemy(enemy)
	elif hud != null:
		hud.update_enemy_hp(enemy.get_instance_id(), enemy.hp, enemy.max_hp)
	_check_floor_clear()
	if is_instance_valid(proj) and not proj._dead:
		var e_center : Vector3 = hex_to_world(enemy.grid_col, enemy.grid_row)
		var n : Vector3 = Vector3(proj.position.x - e_center.x, 0.0, proj.position.z - e_center.z)
		if n.length_squared() < 0.0001: n = Vector3.FORWARD
		proj.bounce_off_surface(n.normalized())

# Player contact: freeze projectile, open ±0.4s SPACE window, resolve reaction.
func _handle_player_proj_contact_async(proj: Projectile3D, player_idx: int) -> void:
	if not is_instance_valid(proj): return
	proj.set_process(false)   # freeze while reaction window is open
	var prev_phase : Phase = phase   # remember so we restore correctly (PLAYER or ENEMY turn)
	phase = Phase.DODGE_PHASE

	var contact_t : float = Time.get_ticks_msec() / 1000.0
	var result    : String = ""

	# Pre-contact SPACE press check
	var pre_rel : float = contact_t - _space_pressed_at   # > 0 means space before contact
	if   pre_rel >= 0.0 and pre_rel <= 0.20: result = "perfect"
	elif pre_rel >= 0.0 and pre_rel <= 0.40: result = "ok"

	# Post-contact window: wait up to 0.4s for a fresh SPACE press
	if result == "":
		var old_press : float = _space_pressed_at
		var waited    : float = 0.0
		while waited < 0.40:
			await get_tree().process_frame
			waited += get_process_delta_time()
			if _space_pressed_at != old_press:
				var post_rel : float = _space_pressed_at - contact_t
				if   post_rel >= 0.0 and post_rel <= 0.20: result = "perfect"; break
				elif post_rel >= 0.0 and post_rel <= 0.40: result = "ok";      break
				old_press = _space_pressed_at

	if result == "": result = "miss"

	if not is_instance_valid(proj):
		phase = prev_phase
		return

	var player = players[player_idx]
	var is_sonny : bool = not player.uses_draw_shot
	var head_pos : Vector3 = player.position + Vector3(0, 1.9, 0)

	match result:
		"perfect":
			if is_sonny:
				# Normalize to player-like physics so enemy projectiles redirect correctly
				# (enemy projs have neg_bounce=9999 and no decay, which would break redirect)
				var _mike : Node = null
				for _p in players:
					if _p.uses_draw_shot: _mike = _p; break
				proj.negative_bounce = _mike.proj_neg_bounce    if _mike else 5.0
				proj.proj_speed      = minf(proj.proj_speed, _mike.proj_launch_speed if _mike else 18.0)
				proj.uses_decay      = true
				# Sonny: redirect toward mouse cursor
				var mouse_dir : Vector3 = Vector3(
					hover_world_pos.x - player.position.x, 0.0,
					hover_world_pos.z - player.position.z)
				if mouse_dir.length_squared() < 0.001:
					mouse_dir = -proj.proj_direction
				proj.redirect_to(mouse_dir)
				proj.set_process(true)
				_spawn_damage_popup(head_pos, "REDIRECT!", Color(0.31, 1.00, 0.51))
				player.perfection = mini(player.perfection + 1, player.perfection_cap)
				_refresh_hud()
			else:
				# Mike: catch/delete projectile
				if proj.owner_node != player:
					if player.caught_projectiles.size() < player.caught_capacity:
						player.caught_projectiles.append({
							"damage":     proj.proj_damage,
							"speed":      proj.proj_speed,
							"neg_bounce": player.proj_neg_bounce,
							"uses_decay": proj.uses_decay,
						})
						_spawn_damage_popup(head_pos, "CAUGHT!", Color(0.31, 1.00, 0.51))
					else:
						_spawn_damage_popup(head_pos, "BAG FULL!", Color(1.0, 0.4, 0.2))
				else:
					_spawn_damage_popup(head_pos, "DODGE!", Color(0.95, 0.90, 0.30))
				proj.die()
				player.perfection = mini(player.perfection + 1, player.perfection_cap)
				_refresh_hud()
		"ok":
			# Both characters: projectile passes through, no damage.
			_spawn_damage_popup(head_pos, "DODGE!", Color(0.95, 0.90, 0.30))
			player.perfection = mini(player.perfection + 1, player.perfection_cap)
			# Unfreeze and clear hit hex so it passes through this player
			var pid : int = proj.get_instance_id()
			_proj_last_char_hex.erase(pid)
			proj.set_process(true)
			_refresh_hud()
			phase = prev_phase
			return
		"miss":
			# Normal collision: deal damage, bounce (or die if enemy proj).
			if proj.is_supercharged:
				_supercharged_explosion(proj, player_positions[player_idx])
				phase = prev_phase
				return
			_apply_damage_to_player(player_idx, int(proj.proj_damage), "hit")
			var poison := proj.consume_poison()
			if poison > 0:
				var pp = players[player_idx]
				pp.poison_stacks += poison
				_spawn_damage_popup(pp.position + Vector3(0, 2.4, 0),
					"POISON x%d" % pp.poison_stacks, Color(0.30, 0.85, 0.20))
			if is_instance_valid(proj) and not proj._dead:
				var p_center : Vector3 = hex_to_world(player_positions[player_idx].x, player_positions[player_idx].y)
				var n : Vector3 = Vector3(proj.position.x - p_center.x, 0.0, proj.position.z - p_center.z)
				if n.length_squared() < 0.0001: n = Vector3.FORWARD
				proj.bounce_off_surface(n.normalized())
				if is_instance_valid(proj) and not proj._dead:
					proj.set_process(true)

	phase = prev_phase

# Supercharged AoE explosion (3 redirects).
func _supercharged_explosion(proj: Projectile3D, impact_hex: Vector2i) -> void:
	var center_w : Vector3 = hex_to_world(impact_hex.x, impact_hex.y)
	_spawn_damage_popup(center_w + Vector3(0, 2.0, 0), "SUPERCHARGE!", Color(1.0, 0.2, 0.05))
	var aoe : Array = [impact_hex] + _get_neighbors(impact_hex.x, impact_hex.y)
	for hex in aoe:
		var extra_dmg : int = 1 if hex == impact_hex else 0
		var total_dmg : int = int(proj.proj_damage) + extra_dmg
		var e : Node = _get_enemy_at(hex)
		if e != null:
			e.take_damage(total_dmg)
			_spawn_damage_popup(e.position + Vector3(0, 1.8, 0),
				"-%d" % total_dmg, Color(1.0, 0.2, 0.05))
			if e.hp <= 0: _kill_enemy(e)
			elif hud != null: hud.update_enemy_hp(e.get_instance_id(), e.hp, e.max_hp)
		var p_idx : int = _get_player_at(hex)
		if p_idx >= 0:
			_apply_damage_to_player(p_idx, total_dmg, "hit")
	proj.die()
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
	if current.bombs_left <= 0: return
	if sonny_charge_bar != null: return
	current.placing_bomb = not current.placing_bomb
	_refresh_tile_colors()
	_refresh_debug()

func _place_bomb_at(hex: Vector2i) -> void:
	var current = players[current_player_index]
	if not current.placing_bomb: return
	var d : int = _hex_dist(current.grid_col, current.grid_row, hex.x, hex.y)
	if d != 1: return
	if not is_valid_and_passable(hex.x, hex.y): return
	if _get_enemy_at(hex) != null: return
	if _get_player_at(hex) >= 0: return

	var bomb = _spawn_enemy("bomb", hex.x, hex.y)
	# HUD register — bomb hiện trong enemy panel với label "B"
	if hud != null:
		hud.register_enemy(bomb.get_instance_id(), "BOMB", bomb.hp, bomb.max_hp,
			bomb.display_label, bomb.body_color)
	current.bombs_left  -= 1
	current.placing_bomb = false
	current.use_action()
	attack_committed_this_round = true
	_update_valid_moves()
	_refresh_tile_colors()
	_refresh_debug()
	_refresh_hud()

# ═══════════════════════════════════════════════════════════
#  MIKE GRAPPLE GUN — Mốc 8.3.4 (W key)
#  ► Hook bay theo straight hex line từ Mike đến hex được click,
#    XUYÊN qua walls/columns (không bounce). Entity đầu tiên trong line
#    bị kéo 1 ô về phía Mike.
#  ► 2 lần / floor, reset khi floor clear.
# ═══════════════════════════════════════════════════════════

func _toggle_grapple_mode() -> void:
	if phase != Phase.PLAYER_TURN: return
	if players.is_empty(): return
	var current = players[current_player_index]
	if not current.uses_draw_shot: return        # chỉ Mike
	if not current.can_act(): return
	if current.grapples_left <= 0: return
	if mike_timing_bar != null: return
	current.grappling = not current.grappling
	_refresh_tile_colors()
	_refresh_debug()

func _grapple_at(hex: Vector2i) -> void:
	var current = players[current_player_index]
	if not current.grappling: return
	var src : Vector2i = Vector2i(current.grid_col, current.grid_row)
	if hex == src: return

	# Find first character (player hoặc enemy khác) trong straight hex line.
	var path : Array = _hex_line(src.x, src.y, hex.x, hex.y)
	var pull_target : Node    = null
	var pull_idx_in_path : int = -1
	for i in range(1, path.size()):   # skip src
		var h : Vector2i = path[i]
		var e : Node = _get_enemy_at(h)
		if e != null:
			pull_target = e
			pull_idx_in_path = i
			break
		var p_idx : int = _get_player_at(h)
		if p_idx >= 0 and p_idx != current_player_index:
			pull_target = players[p_idx]
			pull_idx_in_path = i
			break

	current.grappling     = false
	current.grapples_left -= 1
	current.use_action()
	attack_committed_this_round = true

	# Visual: spawn animated line từ Mike đến target hoặc clicked hex.
	var line_start : Vector3 = Vector3(current.position.x, PROJECTILE_Y,
		current.position.z)
	var line_end : Vector3
	if pull_target != null:
		line_end = Vector3(pull_target.position.x, PROJECTILE_Y,
			pull_target.position.z)
	else:
		var hex_world : Vector3 = entity_position(hex.x, hex.y)
		line_end = Vector3(hex_world.x, PROJECTILE_Y, hex_world.z)
	_spawn_grapple_line(line_start, line_end)

	if pull_target != null and pull_idx_in_path > 1:
		# Pull up to 3 hexes toward Mike; take the farthest reachable hex.
		var max_pull  : int     = mini(3, pull_idx_in_path - 1)
		var pull_dest : Vector2i = Vector2i(-1, -1)
		for step in range(max_pull, 0, -1):
			var candidate : Vector2i = path[pull_idx_in_path - step]
			if is_valid_and_passable(candidate.x, candidate.y) \
					and _get_enemy_at(candidate) == null \
					and _get_player_at(candidate) < 0:
				pull_dest = candidate
				break
		if pull_dest.x >= 0:
			_apply_grapple_pull(pull_target, pull_dest)
			_spawn_damage_popup(pull_target.position + Vector3(0, 1.8, 0),
				"GRAPPLED!", Color(0.50, 0.95, 1.00))
		else:
			_spawn_damage_popup(pull_target.position + Vector3(0, 1.8, 0),
				"BLOCKED", Color(0.7, 0.7, 0.7))
	else:
		# Không trúng ai
		_spawn_damage_popup(current.position + Vector3(0, 1.8, 0),
			"MISS GRAPPLE", Color(0.7, 0.7, 0.7))

	_update_valid_moves()
	_refresh_tile_colors()
	_refresh_debug()
	_refresh_hud()

# Move entity to dest hex (smooth tween) + cập nhật state.
func _apply_grapple_pull(entity: Node, dest: Vector2i) -> void:
	var src : Vector2i = Vector2i(entity.grid_col, entity.grid_row)
	entity.grid_col = dest.x
	entity.grid_row = dest.y
	_move_entity_smooth(entity, dest.x, dest.y)
	# Nếu là player, update player_positions + apply fire damage; else apply enemy fire dmg.
	var is_player : bool = false
	for i in range(players.size()):
		if players[i] == entity:
			player_positions[i] = dest
			_apply_fire_path_damage_player(i, src, dest)
			is_player = true
			break
	if not is_player:
		_apply_fire_path_damage_enemy(entity, src, dest)

# Visual: BoxMesh thin nối start↔end, hold 0.20s rồi fade alpha 0.30s.
func _spawn_grapple_line(start: Vector3, end: Vector3) -> void:
	var dir : Vector3 = end - start
	var len : float   = dir.length()
	if len < 0.01: return
	dir = dir.normalized()
	var box_mesh := BoxMesh.new()
	box_mesh.size = Vector3(len, 0.05, 0.05)
	var mi := MeshInstance3D.new()
	mi.mesh = box_mesh
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.55, 0.85, 1.00, 0.95)
	mi.material_override = mat
	mi.position = (start + end) * 0.5
	mi.rotation = Vector3(0.0, atan2(-dir.z, dir.x), 0.0)
	add_child(mi)
	var tw := create_tween()
	tw.tween_interval(0.20)
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.30)
	tw.tween_callback(mi.queue_free)

# Bomb nổ khi HP = 0: AOE = bomb tile + 6 ô kề. Damage tất cả entities (enemies + players).
func _explode_bomb(bomb: Node) -> void:
	var bomb_col : int = bomb.grid_col
	var bomb_row : int = bomb.grid_row
	var center   : Vector3 = bomb.position
	_spawn_damage_popup(center + Vector3(0, 1.5, 0), "BOOM!",
		Color(1.0, 0.55, 0.10))
	var _bomb_dmg : int = 2
	for _p in players:
		if not _p.uses_draw_shot:
			_bomb_dmg = _p.bomb_aoe_damage; break
	var aoe : Array = [Vector2i(bomb_col, bomb_row)]
	for nb in _get_neighbors(bomb_col, bomb_row):
		aoe.append(nb)
	for hex in aoe:
		var e_in : Node = _get_enemy_at(hex)
		if e_in != null and e_in != bomb:
			e_in.take_damage(_bomb_dmg)
			_spawn_damage_popup(e_in.position + Vector3(0, 1.8, 0),
				"-%d" % _bomb_dmg, Color(1.0, 0.55, 0.30))
			if e_in.hp <= 0:
				_do_kill_enemy(e_in)
			else:
				if hud != null:
					hud.update_enemy_hp(e_in.get_instance_id(),
						e_in.hp, e_in.max_hp)
		var p_idx : int = _get_player_at(hex)
		if p_idx >= 0:
			_apply_damage_to_player(p_idx, _bomb_dmg, "hit")
	_do_kill_enemy(bomb)
	_check_floor_clear()
	await get_tree().create_timer(0.3).timeout

# Player tấn công melee enemy kề bên: damage = q_dmg của weapon hiện tại.
# Mốc 7 thay Sonny bằng charge_bar minigame (xem _start_sonny_charge);
# hàm này còn dùng cho Mike (uses_draw_shot) — instant click attack.
func _player_attack_enemy(enemy: Node) -> void:
	var current_player = players[current_player_index]
	if not current_player.can_act(): return
	_face_player_to_position(current_player, enemy.position)
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

# Push enemy 1 hex away from (from_col, from_row). Push resolves before damage (design §11).
# Collision: wall/column → pushed target takes push_value dmg; enemy collision → both take 1 dmg.
func _push_enemy(enemy: Node, from_col: int, from_row: int, push_value: int) -> void:
	if push_value <= 0 or not is_instance_valid(enemy): return
	var to_cube := func(c: int, r: int) -> Vector3i:
		var x := c; var z := r - (c - (c & 1)) / 2
		return Vector3i(x, -x - z, z)
	var cube_from : Vector3i = to_cube.call(from_col, from_row)
	var cube_self : Vector3i = to_cube.call(enemy.grid_col, enemy.grid_row)
	var cube_dest : Vector3i = cube_self + (cube_self - cube_from)
	var dc : int = cube_dest.x
	var dr : int = cube_dest.z + (dc - (dc & 1)) / 2
	var dest := Vector2i(dc, dr)

	if not is_valid_and_passable(dest.x, dest.y):
		enemy.take_damage(push_value)
		_spawn_damage_popup(enemy.position + Vector3(0, 1.8, 0),
			"-%d" % push_value, Color(1.0, 0.3, 0.3))
		if enemy.hp <= 0:
			_kill_enemy(enemy)
		elif hud != null:
			hud.update_enemy_hp(enemy.get_instance_id(), enemy.hp, enemy.max_hp)
		return

	var other_enemy : Node = _get_enemy_at(dest)
	var other_p_idx : int  = _get_player_at(dest)
	if other_enemy != null or other_p_idx >= 0:
		enemy.take_damage(1)
		_spawn_damage_popup(enemy.position + Vector3(0, 1.8, 0),
			"-1", Color(1.0, 0.3, 0.3))
		if enemy.hp <= 0:
			_kill_enemy(enemy)
		elif hud != null:
			hud.update_enemy_hp(enemy.get_instance_id(), enemy.hp, enemy.max_hp)
		if other_enemy != null:
			other_enemy.take_damage(1)
			_spawn_damage_popup(other_enemy.position + Vector3(0, 1.8, 0),
				"-1", Color(1.0, 0.3, 0.3))
			if is_instance_valid(other_enemy):
				if other_enemy.hp <= 0:
					_kill_enemy(other_enemy)
				elif hud != null:
					hud.update_enemy_hp(other_enemy.get_instance_id(), other_enemy.hp, other_enemy.max_hp)
			if push_value > 1 and is_instance_valid(other_enemy) and other_enemy.hp > 0:
				_push_enemy(other_enemy, enemy.grid_col, enemy.grid_row, push_value - 1)
		elif other_p_idx >= 0:
			_apply_damage_to_player(other_p_idx, 1, "hit")
		return

	var src : Vector2i = Vector2i(enemy.grid_col, enemy.grid_row)
	enemy.grid_col = dest.x
	enemy.grid_row = dest.y
	_move_entity_smooth(enemy, dest.x, dest.y)
	_apply_fire_path_damage_enemy(enemy, src, dest)   # mỗi ô lửa đi qua: -1 HP

# Push a player by giving the "from" hex so direction = dest - player_hex.
func _push_player(player_idx: int, from_col: int, from_row: int, push_value: int) -> void:
	if push_value <= 0: return
	var p = players[player_idx]
	var cube_from := _to_cube_i(from_col, from_row)
	var cube_self := _to_cube_i(p.grid_col, p.grid_row)
	var cube_dest : Vector3i = cube_self + (cube_self - cube_from)
	var dest := _from_cube_i(cube_dest)
	if not is_valid_and_passable(dest.x, dest.y):
		_apply_damage_to_player(player_idx, push_value, "hit")
		return
	var blocker_e : Node = _get_enemy_at(dest)
	var blocker_p : int  = _get_player_at(dest)
	if blocker_e != null or blocker_p >= 0:
		_apply_damage_to_player(player_idx, 1, "hit")
		if blocker_e != null:
			blocker_e.take_damage(1)
			_spawn_damage_popup(blocker_e.position + Vector3(0, 1.8, 0), "-1", Color(1.0, 0.3, 0.3))
			if is_instance_valid(blocker_e) and blocker_e.hp <= 0:
				_kill_enemy(blocker_e)
		return
	player_positions[player_idx] = dest
	p.grid_col = dest.x
	p.grid_row = dest.y
	_move_entity_smooth(p, dest.x, dest.y)

func _kill_enemy(enemy: Node) -> void:
	if enemy.enemy_type == "bomb":
		_explode_bomb(enemy)   # runs as background coroutine
		return
	_do_kill_enemy(enemy)

func _do_kill_enemy(enemy: Node) -> void:
	if hud != null:
		hud.remove_enemy(enemy.get_instance_id())
	enemies.erase(enemy)
	_play_death_animation(enemy, true)   # true → queue_free khi xong

# Khi hết enemies → floor clear. Mốc 9 sẽ wire vào world_map transition.
func _check_floor_clear() -> void:
	if not enemies.is_empty(): return
	if phase == Phase.FLOOR_CLEAR or phase == Phase.VICTORY: return
	for p in players:
		p.reset_floor_state()
	var scenario : Dictionary = _current_scenario()
	var is_boss : bool = scenario.get("is_boss", false)
	if is_boss:
		phase = Phase.VICTORY
		await get_tree().create_timer(0.6).timeout   # đợi enemy fade animation
		_show_modal("VICTORY!", "Boss defeated. Click to play again",
			Color(0.31, 1.00, 0.51), _restart_from_floor_zero)
	else:
		phase = Phase.FLOOR_CLEAR
		await get_tree().create_timer(0.6).timeout
		var floor_name : String = scenario.get("name", "Floor")
		_show_modal("%s CLEARED" % floor_name, "Click to continue",
			Color(0.31, 1.00, 0.51), _next_floor)
	_refresh_debug()

func _next_floor() -> void:
	current_floor = mini(current_floor + 1, FLOOR_SCENARIOS.size() - 1)
	Engine.set_meta("current_floor", current_floor)
	get_tree().reload_current_scene()

func _restart_from_floor_zero() -> void:
	current_floor = 0
	Engine.set_meta("current_floor", 0)
	get_tree().reload_current_scene()

# Spawn modal CanvasLayer overlay với title + hint label, dim background.
# Click bất kỳ → gọi callback. ENTER cũng trigger thông qua _input handler.
var _modal_callback : Callable = Callable()
var _modal_layer    : CanvasLayer = null

func _show_modal(title: String, hint: String, title_color: Color,
		on_click: Callable) -> void:
	if _modal_layer != null and is_instance_valid(_modal_layer):
		_modal_layer.queue_free()
	_modal_callback = on_click
	_modal_layer = CanvasLayer.new()
	_modal_layer.layer = 20   # trên HUD (5) và CombatLayer (10)
	add_child(_modal_layer)

	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.65)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	bg.gui_input.connect(_on_modal_clicked)
	_modal_layer.add_child(bg)

	var title_lbl := Label.new()
	title_lbl.text = title
	title_lbl.add_theme_font_size_override("font_size", 96)
	title_lbl.add_theme_color_override("font_color", title_color)
	title_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	title_lbl.add_theme_constant_override("outline_size", 12)
	title_lbl.set_anchors_preset(Control.PRESET_CENTER)
	title_lbl.offset_left   = -500.0
	title_lbl.offset_top    = -120.0
	title_lbl.offset_right  =  500.0
	title_lbl.offset_bottom =  -20.0
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	bg.add_child(title_lbl)

	var hint_lbl := Label.new()
	hint_lbl.text = hint
	hint_lbl.add_theme_font_size_override("font_size", 36)
	hint_lbl.add_theme_color_override("font_color", Color(1, 0.95, 0.7))
	hint_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	hint_lbl.add_theme_constant_override("outline_size", 6)
	hint_lbl.set_anchors_preset(Control.PRESET_CENTER)
	hint_lbl.offset_left   = -500.0
	hint_lbl.offset_top    =   30.0
	hint_lbl.offset_right  =  500.0
	hint_lbl.offset_bottom =  100.0
	hint_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint_lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	bg.add_child(hint_lbl)

func _on_modal_clicked(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT \
			and event.pressed:
		_trigger_modal_callback()

func _trigger_modal_callback() -> void:
	if _modal_callback.is_null(): return
	var cb : Callable = _modal_callback
	_modal_callback = Callable()
	if _modal_layer != null and is_instance_valid(_modal_layer):
		_modal_layer.queue_free()
		_modal_layer = null
	cb.call()

# ─── Polish helpers (Mốc 6.5) ───────────────────────────────

# Floating damage text — Label3D billboard, float lên + fade ra trong 0.9s.
func _spawn_damage_popup(world_pos: Vector3, text: String, color: Color) -> void:
	var label := Label3D.new()
	label.text             = text
	label.font_size        = 64
	label.pixel_size       = 0.003   # was 0.006 → 50% smaller text
	label.outline_size     = 8
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
	_clear_action_modes()
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

	if _all_players_dead():
		phase = Phase.DEAD
		_refresh_debug()
		await get_tree().create_timer(0.6).timeout
		_show_modal("GAME OVER", "All heroes fallen. Click to restart",
			Color(1.0, 0.30, 0.30), _restart_from_floor_zero)
		return

	# Tick poison and burn stacks for each living player.
	for i in range(players.size()):
		var p = players[i]
		if p.hp > 0 and p.poison_stacks > 0:
			var dmg : int = p.poison_stacks
			p.poison_stacks -= 1
			_apply_damage_to_player(i, dmg, "hit")
			_spawn_damage_popup(p.position + Vector3(0, 2.4, 0),
				"POISON -%d HP" % dmg, Color(0.40, 0.85, 0.20))
		if p.hp > 0 and p.burn_stacks > 0:
			var dmg : int = p.burn_stacks
			p.burn_stacks -= 1
			_apply_damage_to_player(i, dmg, "hit")
			_spawn_damage_popup(p.position + Vector3(0, 2.4, 0),
				"BURN -%d HP" % dmg, Color(0.92, 0.50, 0.10))
	if _all_players_dead():
		phase = Phase.DEAD
		_refresh_debug()
		await get_tree().create_timer(0.6).timeout
		_show_modal("GAME OVER", "All heroes fallen. Click to restart",
			Color(1.0, 0.30, 0.30), _restart_from_floor_zero)
		return

	# Reset cho round player mới
	for p in players:
		if p.hp > 0:
			p.reset_turn()
	players_turned_this_round = []
	for p in players:
		p.shot_used = false
		p.aiming    = false
	_clear_aim_preview()
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
	var poison_dmg : int = enemy.tick_poison()
	if poison_dmg > 0:
		enemy.take_damage(poison_dmg)
		_spawn_damage_popup(enemy.position + Vector3(0, 1.8, 0),
			"POISON -%d HP" % poison_dmg, Color(0.30, 0.85, 0.20))
		if hud != null:
			hud.update_enemy_hp(enemy.get_instance_id(), enemy.hp, enemy.max_hp)
		if enemy.hp <= 0:
			_kill_enemy(enemy)
			return
	enemy.has_attacked_this_turn = false
	# Mage: pending eruption fires free before the normal action this turn.
	if enemy.enemy_type == "mage" and enemy.pending_eruption:
		await _mage_erupt_async(enemy)
		if not is_instance_valid(enemy) or enemy.hp <= 0: return
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
			"charge":
				await _bulldozer_charge_async(enemy)
				return  # charge consumed both actions
			"lock_on":
				_bulldozer_try_lock(enemy)
				if enemy.lock_target_idx < 0:
					# Lock failed — spend remaining action moving
					_enemy_move_toward(enemy, target_idx)
					await get_tree().create_timer(ACTION_DELAY).timeout
			"aim":
				_mage_set_aim(enemy, target_idx)
				await get_tree().create_timer(ACTION_DELAY).timeout
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
	var src : Vector2i = Vector2i(enemy.grid_col, enemy.grid_row)
	var dest : Vector2i = enemy.best_move_toward(p.grid_col, p.grid_row, occupied, self)
	if dest.x < 0: return
	enemy.grid_col = dest.x
	enemy.grid_row = dest.y
	_move_entity_smooth(enemy, dest.x, dest.y)
	_face_enemy_to_nearest_player(enemy)   # quay mặt sau khi di chuyển
	_apply_fire_path_damage_enemy(enemy, src, dest)   # mỗi ô lửa đi qua: -1 HP
	_update_valid_moves()
	_refresh_tile_colors()

func _enemy_move_away(enemy: Node, target_idx: int) -> void:
	var p = players[target_idx]
	var occupied : Dictionary = _build_occupied(enemy)
	var src : Vector2i = Vector2i(enemy.grid_col, enemy.grid_row)
	var dest : Vector2i = enemy.best_move_away(p.grid_col, p.grid_row, occupied, self)
	if dest.x < 0: return
	enemy.grid_col = dest.x
	enemy.grid_row = dest.y
	_move_entity_smooth(enemy, dest.x, dest.y)
	_face_enemy_to_nearest_player(enemy)   # quay mặt sau khi di chuyển
	_apply_fire_path_damage_enemy(enemy, src, dest)   # mỗi ô lửa đi qua: -1 HP
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
	var attack_range : int = int(attack.get("range", 1))
	await _telegraph_attack(target_idx)
	if attack_range > 1:
		# Ranged: fire a real projectile; player reacts with SPACE in real-time.
		var proj = _fire_enemy_projectile(enemy, target_idx, attack)
		await proj.projectile_died
		if attack.get("single_use", false) and is_instance_valid(enemy):
			enemy.ranged_used = true
	else:
		# Melee: spawn DodgeBar.
		await _trigger_dodge_bar(enemy, target_idx, attack)
	if is_instance_valid(enemy):
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
	var dual      : bool  = bool(attack.get("dual_bar", false))
	var mults     : Array = attack.get("speed_mults", [])
	var lines     : Array = attack.get("timing_lines", [])
	var dmg       : int   = int(attack.get("damage", 1))
	var bar_count : int   = 2 if dual else 1
	for i in bar_count:
		var bar   = DodgeBarScene.instantiate()
		var line  : float = lines[i] if i < lines.size() else enemy.dodge_line
		var mult  : float = mults[i] if i < mults.size() else 1.0
		bar.setup(line, mult)
		camera.add_child(bar)
		bar.position = Vector3(0.0, -0.18, -1.2)
		var result : String = await bar.bar_finished
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
				# Clear any Bulldozer lock targeting this player
				for bz in enemies:
					if is_instance_valid(bz) and bz.lock_target_idx == target_idx:
						bz.lock_target_idx = -1
	# HUD update
	if hud != null:
		hud.set_hp(player_names[target_idx], p.hp, p.max_hp)
		# HYPE bar dùng perfection của player đang active
		if current_player_index < players.size():
			var cur = players[current_player_index]
			hud.set_hype_from_perfection(cur.perfection, cur.perfection_cap)

# ═══════════════════════════════════════════════════════════
#  MAGE — telegraph + eruption cycle
# ═══════════════════════════════════════════════════════════

# Returns the hexes that will be hit when this mage erupts (locked at aim time).
func _mage_get_affected_hexes(enemy: Node) -> Array:
	var tc : int = enemy.eruption_target_col
	var tr : int = enemy.eruption_target_row
	if tc < 0 or enemy.eruption_attack_idx >= enemy.attacks.size(): return []
	var atk : Dictionary = enemy.attacks[enemy.eruption_attack_idx]
	if atk.get("is_beam", false):
		var line : Array = _hex_line(enemy.grid_col, enemy.grid_row, tc, tr)
		if not line.is_empty(): line.pop_front()  # exclude mage's own hex
		return line
	else:
		return [Vector2i(tc, tr)] + _get_neighbors(tc, tr)

# Repaint all active mage aim auras on top of the normal tile colors.
func _mage_refresh_aim_hexes() -> void:
	_mage_aim_hexes.clear()
	for e in enemies:
		if not is_instance_valid(e): continue
		if e.enemy_type != "mage" or not e.pending_eruption: continue
		for h in _mage_get_affected_hexes(e):
			_mage_aim_hexes[h] = true
	for h in _mage_aim_hexes:
		var tile = tiles.get(h)
		if tile: tile.set_state("mage_aim")

# Called when a mage takes its "aim" action.
func _mage_set_aim(enemy: Node, target_idx: int) -> void:
	var p = players[target_idx]
	if not _has_line_of_sight(enemy.grid_col, enemy.grid_row, p.grid_col, p.grid_row):
		_enemy_move_toward(enemy, target_idx)
		return
	enemy.eruption_attack_idx = enemy.attack_index
	enemy.eruption_target_col = p.grid_col
	enemy.eruption_target_row = p.grid_row
	enemy.pending_eruption    = true
	enemy.advance_attack()
	_refresh_tile_colors()  # includes _mage_refresh_aim_hexes at the end
	_spawn_damage_popup(enemy.position + Vector3(0, 2.2, 0), "AIM!", Color(0.92, 0.50, 0.10))

# Free action at start of mage's turn: 3-2-1 countdown then erupt.
func _mage_erupt_async(enemy: Node) -> void:
	var hexes : Array = _mage_get_affected_hexes(enemy)
	enemy.pending_eruption    = false
	enemy.eruption_target_col = -1
	enemy.eruption_target_row = -1
	if hexes.is_empty():
		_refresh_tile_colors()
		return
	# 3-2-1 countdown over the affected area center
	var center_w : Vector3 = hex_to_world(hexes[0].x, hexes[0].y)
	for n in [3, 2, 1]:
		_spawn_damage_popup(center_w + Vector3(0, 2.5, 0), str(n), Color(0.92, 0.50, 0.10))
		await get_tree().create_timer(0.3).timeout
	# Find players standing on affected hexes
	var caught : Array = []
	for i in range(players.size()):
		if players[i].hp <= 0: continue
		if player_positions[i] in hexes:
			caught.append(i)
	# Clear aura before resolution
	_refresh_tile_colors()
	if caught.is_empty():
		return
	# Single shared DodgeBar for all caught players
	var atk  : Dictionary = enemy.attacks[enemy.eruption_attack_idx]
	var dmg  : int        = int(atk.get("damage", 1))
	var burn : int        = int(atk.get("burn_stacks", 0))
	phase = Phase.DODGE_PHASE
	var bar = DodgeBarScene.instantiate()
	bar.setup(enemy.dodge_line, 1.0)
	camera.add_child(bar)
	bar.position = Vector3(0.0, -0.18, -1.2)
	var result : String = await bar.bar_finished
	phase = Phase.ENEMY_TURN
	for idx in caught:
		var head_pos : Vector3 = players[idx].position + Vector3(0, 1.9, 0)
		_apply_damage_to_player(idx, dmg, result)
		if burn > 0:
			players[idx].burn_stacks += burn
			_spawn_damage_popup(head_pos + Vector3(0, 0.6, 0),
				"BURN x%d" % players[idx].burn_stacks, Color(0.92, 0.50, 0.10))

# Interrupt a mage's queued cast when it takes damage or is pushed.
func _maybe_interrupt_mage_cast(enemy: Node) -> void:
	if not is_instance_valid(enemy): return
	if enemy.enemy_type != "mage": return
	if enemy.interrupt_cast():
		_refresh_tile_colors()
		_spawn_damage_popup(enemy.position + Vector3(0, 2.2, 0),
			"INTERRUPTED!", Color(0.80, 0.80, 0.80))

# ═══════════════════════════════════════════════════════════
#  BULLDOZER — lock-on + charge
# ═══════════════════════════════════════════════════════════

# Persistent red line from each locked Bulldozer to its target, updated every frame.
func _update_bz_lock_lines() -> void:
	var active_ids : Dictionary = {}
	for bz in enemies:
		if not is_instance_valid(bz): continue
		if bz.enemy_type != "bulldozer": continue
		if bz.lock_target_idx < 0 or bz.lock_target_idx >= players.size(): continue
		var p = players[bz.lock_target_idx]
		if p.hp <= 0: continue
		var bz_id : int = bz.get_instance_id()
		active_ids[bz_id] = true
		if bz_id not in _bz_lock_lines:
			var mi := MeshInstance3D.new()
			var mesh := BoxMesh.new()
			mesh.size = Vector3(1.0, 0.04, 0.04)
			mi.mesh = mesh
			var mat := StandardMaterial3D.new()
			mat.albedo_color               = Color(1.0, 0.08, 0.08, 0.85)
			mat.transparency               = BaseMaterial3D.TRANSPARENCY_ALPHA
			mat.shading_mode               = BaseMaterial3D.SHADING_MODE_UNSHADED
			mi.material_override = mat
			add_child(mi)
			_bz_lock_lines[bz_id] = mi
		var line : MeshInstance3D = _bz_lock_lines[bz_id]
		var from_w : Vector3 = Vector3(bz.position.x, GROUND_Y + 0.4, bz.position.z)
		var to_w   : Vector3 = Vector3(p.position.x,  GROUND_Y + 0.4, p.position.z)
		var diff   : Vector3 = to_w - from_w
		var length : float   = diff.length()
		if length > 0.01:
			line.position  = (from_w + to_w) * 0.5
			line.scale     = Vector3(length, 1.0, 1.0)
			line.rotation  = Vector3(0.0, -atan2(diff.z, diff.x), 0.0)
			line.visible   = true
		else:
			line.visible = false
	# Remove lines for bulldozers that no longer have a lock.
	for id in _bz_lock_lines.keys():
		if id not in active_ids:
			_bz_lock_lines[id].queue_free()
			_bz_lock_lines.erase(id)

# Scan for the nearest player within 4 hexes WITH line-of-sight.
# Sets enemy.lock_target_idx if found; leaves it -1 otherwise.
func _bulldozer_try_lock(enemy: Node) -> void:
	var best_idx : int = -1
	var best_d   : int = 999
	for i in range(players.size()):
		if players[i].hp <= 0: continue
		var d : int = _hex_dist(enemy.grid_col, enemy.grid_row,
								players[i].grid_col, players[i].grid_row)
		if d <= 4 and d < best_d \
				and _has_line_of_sight(enemy.grid_col, enemy.grid_row,
									   players[i].grid_col, players[i].grid_row):
			best_d   = d
			best_idx = i
	enemy.lock_target_idx = best_idx

# SPACE parry window for Bulldozer charge contact (same timing as projectile §5B).
# Returns "perfect", "ok", or "miss".
func _bulldozer_parry_async() -> String:
	var contact_t : float = Time.get_ticks_msec() / 1000.0
	var pre_rel   : float = contact_t - _space_pressed_at
	if pre_rel >= 0.0 and pre_rel <= 0.20: return "perfect"
	if pre_rel >= 0.0 and pre_rel <= 0.40: return "ok"
	var old_press : float = _space_pressed_at
	var waited    : float = 0.0
	while waited < 0.40:
		await get_tree().process_frame
		waited += get_process_delta_time()
		if _space_pressed_at != old_press:
			var post_rel : float = _space_pressed_at - contact_t
			if post_rel >= 0.0 and post_rel <= 0.20: return "perfect"
			if post_rel >= 0.0 and post_rel <= 0.40: return "ok"
			old_press = _space_pressed_at
	return "miss"

# Full charge: straight-line movement toward locked target.
func _bulldozer_charge_async(bz: Node) -> void:
	var lock_idx : int = bz.lock_target_idx
	if lock_idx < 0 or lock_idx >= players.size() or players[lock_idx].hp <= 0:
		bz.lock_target_idx = -1
		return

	# "CHARGE!" telegraph label
	var lbl := Label3D.new()
	lbl.text             = "CHARGE!"
	lbl.font_size        = 80
	lbl.pixel_size       = 0.0013
	lbl.outline_size     = 8
	lbl.outline_modulate = Color(0.0, 0.0, 0.0, 1.0)
	lbl.modulate         = Color(1.0, 0.08, 0.08)
	lbl.no_depth_test    = true
	lbl.billboard        = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.position         = Vector3(0.0, 2.4, 0.0)
	bz.add_child(lbl)
	await get_tree().create_timer(0.5).timeout
	if is_instance_valid(lbl): lbl.queue_free()
	if not is_instance_valid(bz) or bz.hp <= 0: return

	# Snapshot charge direction from start toward target (straight world-space line).
	var target_p         = players[lock_idx]
	var bz_start         : Vector3  = bz.position
	var target_w         : Vector3  = hex_to_world(target_p.grid_col, target_p.grid_row)
	target_w.y = bz_start.y
	var raw_dir          : Vector3  = target_w - bz_start
	raw_dir.y = 0.0
	var total_dist       : float    = raw_dir.length()
	if total_dist < 0.01: return
	var dir              : Vector3  = raw_dir.normalized()

	# Nearest cube hex direction (for ±60° push math)
	var step_path        : Array    = _hex_line(bz.grid_col, bz.grid_row,
												 target_p.grid_col, target_p.grid_row)
	var charge_dir_cube  : Vector3i = Vector3i(1, -1, 0)  # fallback
	if step_path.size() >= 2:
		charge_dir_cube = _to_cube_i(step_path[1].x, step_path[1].y) \
						- _to_cube_i(step_path[0].x, step_path[0].y)

	# Kill any in-progress movement tween so it won't fight with direct position writes.
	var bz_eid : int = bz.get_instance_id()
	if bz_eid in _entity_tweens and is_instance_valid(_entity_tweens[bz_eid]):
		_entity_tweens[bz_eid].kill()
		_entity_tweens.erase(bz_eid)

	var traveled         : float      = 0.0
	var prev_hex         : Vector2i   = Vector2i(bz.grid_col, bz.grid_row)
	var side_counter     : int        = 0
	var parried_players  : Dictionary = {}
	var stopped          : bool       = false

	while traveled < total_dist and not stopped \
			and is_instance_valid(bz) and bz.hp > 0:
		await get_tree().process_frame
		traveled = minf(traveled + CHARGE_SPEED * get_process_delta_time(), total_dist)
		bz.position = bz_start + dir * traveled

		var cur_hex : Vector2i = world_to_hex(bz.position)
		if cur_hex.x < 0: cur_hex = prev_hex  # between hexes — stay on last known

		if cur_hex == prev_hex: continue
		prev_hex = cur_hex
		# NOTE: bz.grid_col/row updated only when bz actually enters the hex (below).

		# Column blocks charge — bz bounces back, takes damage.
		if cur_hex in column_tiles:
			bz.take_damage(1)
			_spawn_damage_popup(bz.position + Vector3(0, 1.8, 0), "-1", Color(1.0, 0.3, 0.3))
			if bz.hp <= 0: _kill_enemy(bz)
			stopped = true
			break

		# Locked target's hex — parry window, damage on miss, push along charge dir.
		if cur_hex == player_positions[lock_idx]:
			var result : String = "miss"
			if lock_idx not in parried_players:
				parried_players[lock_idx] = true
				var pp : Phase = phase
				phase = Phase.DODGE_PHASE
				result = await _bulldozer_parry_async()
				phase = pp
			if result == "miss":
				_apply_damage_to_player(lock_idx, 1, "hit")
			var fp : Vector2i = _from_cube_i(_to_cube_i(cur_hex.x, cur_hex.y) - charge_dir_cube)
			_push_player(lock_idx, fp.x, fp.y, 1)
			# Only enter if push succeeded (player vacated the hex).
			if player_positions[lock_idx] != cur_hex:
				bz.grid_col = cur_hex.x
				bz.grid_row = cur_hex.y
			stopped = true
			break

		# _get_enemy_at uses grid_col/row; since we haven't updated bz yet, it won't find bz.
		var hit_e : Node = _get_enemy_at(cur_hex)

		# Immovable enemy blocks charge.
		if hit_e != null and hit_e.immovable:
			bz.take_damage(1)
			_spawn_damage_popup(bz.position + Vector3(0, 1.8, 0), "-1", Color(1.0, 0.3, 0.3))
			if bz.hp <= 0: _kill_enemy(bz)
			stopped = true
			break

		# Non-target enemy — 1 dmg, push ±60°, enter if hex clears.
		if hit_e != null:
			hit_e.take_damage(1)
			_spawn_damage_popup(hit_e.position + Vector3(0, 1.8, 0), "-1", Color(1.0, 0.55, 0.30))
			if hit_e.hp <= 0: _kill_enemy(hit_e)
			var pd : Vector3i = _cube_rotate_60_ccw(charge_dir_cube) if side_counter % 2 == 0 \
								 else _cube_rotate_60_cw(charge_dir_cube)
			side_counter += 1
			if is_instance_valid(hit_e) and hit_e.hp > 0:
				var fp : Vector2i = _from_cube_i(_to_cube_i(cur_hex.x, cur_hex.y) - pd)
				_push_enemy(hit_e, fp.x, fp.y, 1)
			if _get_enemy_at(cur_hex) != null or _get_player_at(cur_hex) >= 0:
				bz.take_damage(1)
				_spawn_damage_popup(bz.position + Vector3(0, 1.8, 0), "-1", Color(1.0, 0.3, 0.3))
				if bz.hp <= 0: _kill_enemy(bz)
				stopped = true
				break
			bz.grid_col = cur_hex.x
			bz.grid_row = cur_hex.y
			continue

		# Non-locked player — parry window, 1 dmg on miss, push ±60°.
		var hit_p : int = _get_player_at(cur_hex)
		if hit_p >= 0:
			var result : String = "miss"
			if hit_p not in parried_players:
				parried_players[hit_p] = true
				var pp : Phase = phase
				phase = Phase.DODGE_PHASE
				result = await _bulldozer_parry_async()
				phase = pp
			if result == "miss":
				_apply_damage_to_player(hit_p, 1, "hit")
			var pd : Vector3i = _cube_rotate_60_ccw(charge_dir_cube) if side_counter % 2 == 0 \
								 else _cube_rotate_60_cw(charge_dir_cube)
			side_counter += 1
			var fp : Vector2i = _from_cube_i(_to_cube_i(cur_hex.x, cur_hex.y) - pd)
			_push_player(hit_p, fp.x, fp.y, 1)
			if _get_player_at(cur_hex) >= 0 or _get_enemy_at(cur_hex) != null:
				bz.take_damage(1)
				_spawn_damage_popup(bz.position + Vector3(0, 1.8, 0), "-1", Color(1.0, 0.3, 0.3))
				if bz.hp <= 0: _kill_enemy(bz)
				stopped = true
				break
			bz.grid_col = cur_hex.x
			bz.grid_row = cur_hex.y
			continue

		# Empty passable hex — enter it.
		bz.grid_col = cur_hex.x
		bz.grid_row = cur_hex.y

	# Snap to the center of whichever hex bz ended up in.
	if is_instance_valid(bz) and bz.hp > 0:
		var snap_pos : Vector3 = entity_position(bz.grid_col, bz.grid_row)
		var snap_tw  : Tween   = create_tween()
		snap_tw.set_ease(Tween.EASE_OUT)
		snap_tw.tween_property(bz, "position", snap_pos, 0.12)
		_entity_tweens[bz_eid] = snap_tw
		await snap_tw.finished
		_update_valid_moves()
		_refresh_tile_colors()

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
	_clear_action_modes()
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

# ─── Camera pan (arrow keys) ────────────────────────────────
# Hold UP/DOWN/LEFT/RIGHT để di chuyển camera_anchor quanh bản đồ.
# Pan relative to camera yaw — UP = đi theo hướng camera đang nhìn,
# LEFT/RIGHT = strafe ngang.
const CAM_PAN_SPEED : float = 10.0   # units per second
const CAM_PAN_BOUND : float = 25.0   # giới hạn anchor để không bay xa map

func _process(delta: float) -> void:
	_process_projectiles(delta)
	_update_bz_lock_lines()
	var pan := Vector3.ZERO
	if Input.is_key_pressed(KEY_UP):    pan.z -= 1.0
	if Input.is_key_pressed(KEY_DOWN):  pan.z += 1.0
	if Input.is_key_pressed(KEY_LEFT):  pan.x -= 1.0
	if Input.is_key_pressed(KEY_RIGHT): pan.x += 1.0
	if pan == Vector3.ZERO: return
	var yaw : float = deg_to_rad(camera_yaw_deg)
	var forward : Vector3 = -Vector3(cos(yaw), 0, sin(yaw))   # XZ forward
	var right   : Vector3 =  Vector3(sin(yaw), 0, -cos(yaw))  # XZ right
	var dir : Vector3 = (forward * -pan.z + right * pan.x).normalized()
	camera_anchor += dir * CAM_PAN_SPEED * delta
	camera_anchor.x = clampf(camera_anchor.x, -CAM_PAN_BOUND, CAM_PAN_BOUND)
	camera_anchor.z = clampf(camera_anchor.z, -CAM_PAN_BOUND, CAM_PAN_BOUND)
	_update_camera()

func _input(event: InputEvent) -> void:
	# ESC = cancel bomb/grapple/aim mode trước, sau đó mới quit game
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		if not players.is_empty():
			var _esc_cur = players[current_player_index]
			if _esc_cur.placing_bomb:
				_esc_cur.placing_bomb = false
				_refresh_tile_colors()
				_refresh_debug()
				return
			if _esc_cur.grappling:
				_esc_cur.grappling = false
				_refresh_tile_colors()
				_refresh_debug()
				return
			if _esc_cur.aiming:
				_esc_cur.aiming = false
				_clear_aim_preview()
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
				if phase == Phase.PLAYER_TURN and mike_timing_bar == null \
						and (players.is_empty() or not players[current_player_index].aiming):
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
			KEY_Q:
				if phase == Phase.PLAYER_TURN and not players.is_empty():
					var cur = players[current_player_index]
					if cur.uses_draw_shot:
						_toggle_mike_aim_mode()
					else:
						_toggle_sonny_attack_mode()
			KEY_W:
				if phase == Phase.PLAYER_TURN and not players.is_empty():
					var cur = players[current_player_index]
					if cur.uses_draw_shot:
						_toggle_grapple_mode()
					else:
						_toggle_bomb_placement()
			KEY_SPACE:
				_space_pressed_at = Time.get_ticks_msec() / 1000.0
			KEY_ENTER, KEY_KP_ENTER:
				# Mốc 9.4: ENTER cũng trigger modal callback (floor clear /
				# victory / game over) bên cạnh click chuột.
				if _modal_layer != null and is_instance_valid(_modal_layer):
					_trigger_modal_callback()
				elif phase == Phase.DEAD:
					_restart_from_floor_zero()
			KEY_F4:
				# Toggle lưới tọa độ debug.
				if _coord_grid and is_instance_valid(_coord_grid):
					_coord_grid.visible = not _coord_grid.visible
					print("[coord_grid] visible=%s" % str(_coord_grid.visible))

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

	# ── RMB: cancel aim mode (design §5); otherwise orbit camera ───────
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		var _rmb_cur : Node = players[current_player_index] if not players.is_empty() else null
		if event.pressed and (_rmb_cur != null and (_rmb_cur.aiming or _rmb_cur.attack_mode) or mike_timing_bar != null):
			# Cancel aim / timing bar / Sonny attack mode (no action was consumed yet)
			if _rmb_cur != null:
				_rmb_cur.aiming       = false
				_rmb_cur.attack_mode  = false
			_clear_aim_preview()
			if mike_timing_bar != null and is_instance_valid(mike_timing_bar):
				mike_timing_bar.queue_free()
				mike_timing_bar = null
			_update_valid_moves()
			_refresh_tile_colors()
			_refresh_debug()
		else:
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
		# Track mouse world position cho aim preview free direction
		hover_world_pos = mouse_to_ground(event.position)
		var hex : Vector2i = mouse_to_hex(event.position)
		if hex != hover_hex:
			hover_hex = hex
			_refresh_tile_colors()
			_refresh_debug()
		else:
			# Hex không đổi nhưng world pos đổi → vẫn cần update aim preview
			_update_aim_preview()

	# LMB press / release — split để Sonny giữ-thả LMB cho Boong charge bar.
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_handle_lmb_press(event.position)
		else:
			_handle_lmb_release()

func _refresh_debug() -> void:
	if not debug_label: return
	if phase == Phase.DEAD:
		debug_label.text = "[DEAD] All heroes fallen. ENTER/click to restart."
		return
	if phase == Phase.FLOOR_CLEAR:
		debug_label.text = "[FLOOR CLEAR] ENTER/click to continue."
		return
	if phase == Phase.VICTORY:
		debug_label.text = "[VICTORY] ENTER/click to play again."
		return
	if players.is_empty():
		debug_label.text = "pitch %.0f° yaw %.0f° dist %.0f  hover=%s" \
			% [camera_pitch_deg, camera_yaw_deg, camera_distance, str(hover_hex)]
		return
	var cur = players[current_player_index]
	if cur.placing_bomb:
		debug_label.text = "[PLACING BOMB] click ô kề bên (passable) để đặt — ESC = cancel"
		return
	if cur.grappling:
		debug_label.text = "[GRAPPLE] click hex bất kỳ để kéo entity đầu tiên trên đường — ESC = cancel"
		return
	var phase_str : String
	match phase:
		Phase.PLAYER_TURN: phase_str = "PLAYER"
		Phase.ENEMY_TURN:  phase_str = "ENEMY"
		Phase.DODGE_PHASE: phase_str = "DODGE!"
		_:                 phase_str = "?"
	var floor_name : String = _current_scenario().get("name", "Floor")
	# Hints khác nhau cho Sonny (Boong + bomb) vs Mike (ranged)
	var hints : String
	if cur.uses_draw_shot:
		var aim_state : String = "[AIMING] " if cur.aiming else ""
		hints = "%sQ=Aim  LMB=move/Shoot  W=Grapple(%d)  Tab=swap  D=end" \
			% [aim_state, cur.grapples_left]
	else:
		hints = "LMB=move/Boong(hold)  W=Bomb(%d)  Tab=swap  D=end  SPACE=dodge" \
			% cur.bombs_left
	debug_label.text = "[%s] %s | %s HP %d/%d  Act %d/%d   |   %s   |   pitch %.0f° dist %.0f" \
		% [
			floor_name,
			phase_str,
			player_names[current_player_index],
			cur.hp, cur.max_hp,
			cur.actions_left, cur.actions_per_turn,
			hints,
			camera_pitch_deg, camera_distance
		]
