extends Node3D
class_name Enemy

# ═══════════════════════════════════════════════════════════════════
#  BEHAVIOR ENUM
# ═══════════════════════════════════════════════════════════════════

enum Behavior { AGGRESSIVE, RANGER, DUMMY, BULLDOZER, DASHER, GUARDIAN_GORILLA }

# ═══════════════════════════════════════════════════════════════════
#  ENEMY PRESETS
#  ► All per-enemy tuning lives here — mirror of CHARACTER_PRESETS in Player.gd.
#  ► Call _spawn_enemy("grunt", col, row) in main.gd to instantiate.
#
#  Attack dict keys:
#    range          int    1 = melee (dodge bar), 2+ = ranged (projectile)
#    damage         float  base damage per hit
#    aoe            int    1 = target only, 2 = target + adjacent ring
#    hits           int    how many times this attack fires per action
#    speed          String "" for melee; "slow" / "medium" / "fast" for ranged
#    perfect_window float  seconds from timing line (melee only)
#    ok_window      float  seconds from timing line (melee only)
#    dual_bar       bool   true → spawn two sequential dodge bars (melee hits > 1)
#    speed_mults    Array  [bar1_mult, bar2_mult] when dual_bar == true
#    timing_lines   Array  [bar1_line, bar2_line] target positions (0–1) for dual_bar bars
#    hit_details    Array  per-hit override dicts when hits > 1 and not identical
#    poison_stacks  int    stacks of poison to apply on hit (ranged only)
#    single_use     bool   true → attack can only fire once per combat
#    telegraphed    bool   true → aim on turn N (costs action), erupt free at turn N+1 start
#    is_beam        bool   true → eruption area is hex line from Mage to target (Fire Lance)
#                           false/absent → eruption area is target hex + adjacent ring (Inferno Bloom)
#    burn_stacks    int    burn stacks applied on eruption contact, even if damage is dodged (mage only)
# ═══════════════════════════════════════════════════════════════════

const ENEMY_PRESETS : Dictionary = {
	"grunt": {
		"enemy_type":       "grunt",
		"display_label":    "G",
		"max_hp":           3,
		"actions_per_turn": 2,
		"move_range":       2,
		"body_color":       Color(0.70, 0.20, 0.20),
		"behavior":         Behavior.AGGRESSIVE,
		"immovable":        false,
		"range_min":        0,
		"range_max":        0,
		"attacks": [
			{ "range": 1, "damage": 1, "aoe": 1, "hits": 1, "speed": "",
			  "perfect_window": 0.20, "ok_window": 0.40,
			  "dual_bar": false, "speed_mults": [] },
			{ "range": 1, "damage": 2, "aoe": 1, "hits": 1, "speed": "",
			  "perfect_window": 0.15, "ok_window": 0.35,
			  "dual_bar": false, "speed_mults": [] },
		],
	},
	"archer": {
		"enemy_type":       "archer",
		"display_label":    "A",
		"max_hp":           2,
		"actions_per_turn": 1,
		"move_range":       1,
		"body_color":       Color(0.58, 0.15, 0.82),
		"behavior":         Behavior.RANGER,
		"immovable":        false,
		"range_min":        2,
		"range_max":        5,
		"attacks": [
			{ "range": 4, "damage": 1, "aoe": 1, "hits": 1, "speed": "medium",
			  "perfect_window": 0.0, "ok_window": 0.0,
			  "dual_bar": false, "speed_mults": [], "no_bounce": true },
			{ "range": 4, "damage": 0, "aoe": 1, "hits": 2, "speed": "fast",
			  "perfect_window": 0.0, "ok_window": 0.0,
			  "dual_bar": false, "speed_mults": [], "no_bounce": true,
			  "hit_details": [
			  	{ "damage": 0.5, "speed": "fast", "delay": 0.0 },
			  	{ "damage": 0.5, "speed": "fast", "delay": 0.3 },
			  ] },
		],
	},
	"mage": {
		"enemy_type":       "mage",
		"display_label":    "M",
		"max_hp":           2,
		"actions_per_turn": 1,
		"move_range":       2,
		"body_color":       Color(0.78, 0.22, 0.55),
		"behavior":         Behavior.RANGER,
		"immovable":        false,
		"range_min":        2,
		"range_max":        6,
		"attacks": [
			# A1 — Inferno Bloom: telegraphed AOE (target hex + ring). Aim costs action on turn N,
			# eruption fires free at start of turn N+1. Burn applies even on dodge.
			{ "range": 6, "damage": 1, "aoe": 2, "hits": 1, "speed": "",
			  "perfect_window": 0.20, "ok_window": 0.40,
			  "dual_bar": false, "speed_mults": [],
			  "telegraphed": true, "burn_stacks": 1 },
			# A2 — Fire Lance: telegraphed beam along hex line from Mage to target.
			# Affected hexes locked at aim time. Same resolution rules as A1.
			{ "range": 6, "damage": 1, "aoe": 1, "hits": 1, "speed": "",
			  "perfect_window": 0.20, "ok_window": 0.40,
			  "dual_bar": false, "speed_mults": [],
			  "telegraphed": true, "is_beam": true, "burn_stacks": 1 },
		],
	},
	"assassin": {
		"enemy_type":       "assassin",
		"display_label":    "S",
		"max_hp":           3,
		"actions_per_turn": 2,
		"move_range":       2,
		"body_color":       Color(0.50, 0.15, 0.70),
		"behavior":         Behavior.AGGRESSIVE,
		"immovable":        false,
		"range_min":        0,
		"range_max":        0,
		"attacks": [
			# A1 — Poison Dagger: ranged, single-use, applies 1 poison stack on hit
			{ "range": 6, "damage": 1, "aoe": 1, "hits": 1, "speed": "medium",
			  "perfect_window": 0.0, "ok_window": 0.0,
			  "dual_bar": false, "speed_mults": [], "no_bounce": true,
			  "poison_stacks": 1, "single_use": true },
			# A2 — Melee Combo: two sequential dodge bars, slow then fast
			{ "range": 1, "damage": 1, "aoe": 1, "hits": 2, "speed": "",
			  "perfect_window": 0.16, "ok_window": 0.32,
			  "dual_bar": true, "speed_mults": [0.70, 1.40],
			  "timing_lines": [0.60, 0.75] },
		],
	},
	"bulldozer": {
		"enemy_type":       "bulldozer",
		"display_label":    "Z",
		"max_hp":           5,
		"actions_per_turn": 2,
		"move_range":       1,
		"body_color":       Color(0.55, 0.55, 0.55),
		"behavior":         Behavior.BULLDOZER,
		"immovable":        false,
		"range_min":        0,
		"range_max":        0,
		"attacks":          [],  # charge is handled directly in main.gd
	},
	"gunner": {
		"enemy_type":       "gunner",
		"display_label":    "U",
		"max_hp":           2,
		"actions_per_turn": 1,
		"move_range":       1,                      # chậm, giữ khoảng cách
		"body_color":       Color(0.40, 0.45, 0.65),   # xanh xám — vibe sniper
		"behavior":         Behavior.RANGER,
		"immovable":        false,
		"range_min":        2,
		"range_max":        5,
		"attacks": [
			{ "range": 5, "damage": 1, "aoe": 1, "hits": 1, "speed": "fast",
			  "perfect_window": 0.0, "ok_window": 0.0,
			  "dual_bar": false, "speed_mults": [], "no_bounce": true },
		],
	},
	"bomb": {
		"enemy_type":       "bomb",
		"display_label":    "B",
		"max_hp":           1,
		"actions_per_turn": 0,
		"move_range":       0,
		"body_color":       Color(0.90, 0.75, 0.10),
		"behavior":         Behavior.DUMMY,
		"immovable":        false,
		"range_min":        0,
		"range_max":        0,
		"attacks":          [],
	},
	"dummy": {
		"enemy_type":       "dummy",
		"display_label":    "D",
		"max_hp":           5,
		"actions_per_turn": 0,
		"move_range":       0,
		"body_color":       Color(0.20, 0.65, 0.30),
		"behavior":         Behavior.DUMMY,
		"immovable":        true,
		"range_min":        0,
		"range_max":        0,
		"attacks":          [],
	},
	"dasher": {
		"enemy_type":       "dasher",
		"display_label":    "D",
		"max_hp":           7,
		"actions_per_turn": 2,
		"move_range":       0,
		"body_color":       Color(0.20, 0.70, 1.00),
		"behavior":         Behavior.DASHER,
		"immovable":        false,
		"range_min":        4,
		"range_max":        6,
		"attacks": [
			# A1 — Triple Shot (fast, 0.2s interval)
			{ "range": 6, "damage": 1, "aoe": 1, "hits": 3, "speed": "fast",
			  "perfect_window": 0.0, "ok_window": 0.0,
			  "dual_bar": false, "speed_mults": [], "hit_interval": 0.2 },
			# A2 — Barrage (slow, 0.1s interval)
			{ "range": 6, "damage": 1, "aoe": 1, "hits": 5, "speed": "slow",
			  "perfect_window": 0.0, "ok_window": 0.0,
			  "dual_bar": false, "speed_mults": [], "hit_interval": 0.1 },
			# A3 — Adjacency Slam (handled via "adjacency_slam" action in main.gd)
			{ "range": 1, "damage": 1, "aoe": 2, "hits": 1, "speed": "",
			  "perfect_window": 0.20, "ok_window": 0.40,
			  "dual_bar": false, "speed_mults": [],
			  "adjacency_slam": true, "stun_on_miss": true },
			# A4 — Dash Combo (handled via "dash_combo" action in main.gd)
			{ "range": 1, "damage": 1, "aoe": 1, "hits": 3, "speed": "",
			  "perfect_window": 0.20, "ok_window": 0.40,
			  "dual_bar": false, "speed_mults": [0.70, 1.00, 1.50] },
		],
	},
	"guardian_gorilla": {
		"enemy_type":       "guardian_gorilla",
		"display_label":    "G",
		"max_hp":           5,
		"actions_per_turn": 2,
		"move_range":       2,
		"body_color":       Color(0.60, 0.70, 0.85),
		"behavior":         Behavior.GUARDIAN_GORILLA,
		"immovable":        false,
		"range_min":        0,
		"range_max":        0,
		"attacks": [
			# A1 — Shield Slam: front arc, 0 dmg, stun on miss, shared SPACE
			{ "range": 1, "damage": 0, "aoe": 1, "hits": 1, "speed": "",
			  "perfect_window": 0.20, "ok_window": 0.40,
			  "dual_bar": false, "speed_mults": [],
			  "guard_slam": true },
			# A2 — Triple Strike: 3 escalating bars, 1 dmg each, all always fire
			{ "range": 1, "damage": 1, "aoe": 1, "hits": 3, "speed": "",
			  "perfect_window": 0.20, "ok_window": 0.40,
			  "dual_bar": false, "speed_mults": [0.70, 1.00, 1.50] },
		],
	},
	"boxing_bear": {
		"enemy_type":       "boxing_bear",
		"display_label":    "R",
		"max_hp":           5,
		"actions_per_turn": 1,
		"move_range":       2,
		"body_color":       Color(0.85, 0.40, 0.10),
		"behavior":         Behavior.AGGRESSIVE,
		"immovable":        false,
		"range_min":        0,
		"range_max":        0,
		"attacks": [
			{ "range": 1, "damage": 1, "aoe": 1, "hits": 5, "speed": "",
			  "perfect_window": 0.20, "ok_window": 0.40,
			  "dual_bar": false, "speed_mults": [],
			  "boxing_bear_combo": true, "max_chain": 5, "chain_speed_mult": 1.5 },
		],
	},
}

# ═══════════════════════════════════════════════════════════════════
#  EXPORTED PARAMETERS
# ═══════════════════════════════════════════════════════════════════

@export var enemy_type       : String   = "grunt"
@export var display_label    : String   = "G"
@export var max_hp           : int      = 3
@export var actions_per_turn : int      = 2
@export var move_range       : int      = 2
@export var body_color       : Color    = Color(0.70, 0.20, 0.20)
@export var behavior         : Behavior = Behavior.AGGRESSIVE
@export var immovable        : bool     = false

@export var range_min : int = 2
@export var range_max : int = 5

var attacks : Array = []

# ═══════════════════════════════════════════════════════════════════
#  RUNTIME STATE
# ═══════════════════════════════════════════════════════════════════

var hp                     : int   = 0
var grid_col               : int   = 0
var grid_row               : int   = 0
var dodge_line             : float = 0.0
var bleed_stacks           : int   = 0
var poison_stacks          : int   = 0
var burn_stacks            : int   = 0
var disarmed_turns         : int   = 0
var attack_index           : int   = 0
var has_attacked_this_turn : bool  = false
var fuse_turns             : int   = 0   # Mốc 7: chỉ dùng cho type "bomb"
var ranged_used            : bool  = false  # assassin: A1 single-use fired flag
var lock_target_idx        : int   = -1     # bulldozer: locked player index, -1 = none
var charge_this_turn       : bool  = false  # bulldozer: charged, skip remaining actions
var move_done_this_turn    : bool  = false  # bulldozer: moved without lock; next = lock attempt
var lock_attempted         : bool  = false  # bulldozer: lock attempt made this turn
var pending_eruption       : bool  = false  # mage: eruption queued from last turn's aim
var eruption_attack_idx    : int   = 0      # mage: index into attacks[] that was aimed
var eruption_target_col    : int   = -1     # mage: hex col locked at aim time
var eruption_target_row    : int   = -1     # mage: hex row locked at aim time
var stun_turns             : int   = 0      # turns remaining to skip (1 = skip 1 full turn)
var dash_attack_index      : int   = 0      # dasher: alternates A1 (0) and A2 (1) each ranged volley
var guard_facing           : int   = 0      # guardian_gorilla: index into CUBE_DIR_VECS for shield direction
var guard_attack_index     : int   = 0      # guardian_gorilla: cycles A1/A2 when not forced A1

# ═══════════════════════════════════════════════════════════════════
#  3D NODES (từ scene)
# ═══════════════════════════════════════════════════════════════════

var name_label : Label3D        = null
var model_node : MeshInstance3D = null

# ═══════════════════════════════════════════════════════════════════
#  DUAL-MODEL (Base ↔ Walk) cho enemy có .glb skinned mesh
#  ► Mapping: grunt → Skull Crab, assassin → Squirrel, bulldozer → Bull.
#  ► Visibility swap qua anim_set_walking() (gọi từ main._move_entity_smooth).
# ═══════════════════════════════════════════════════════════════════

const DUAL_MODEL_SCENES : Dictionary = {
	# 3 enemy LP (low poly) — mỗi model có 1 .glb duy nhất với anim embedded.
	# Đặt cùng scene cho cả base + walk slot: visibility swap thành no-op,
	# anim chạy liên tục từ AnimationPlayer trong .glb (không phân biệt
	# idle/walk pose vì model gộp 1).
	"grunt": [
		preload("res://Enemies/Skull Crab/Skull Crab LP.glb"),
		preload("res://Enemies/Skull Crab/Skull Crab LP.glb"),
	],
	"assassin": [
		preload("res://Enemies/Assasin/Squirrel LP.glb"),
		preload("res://Enemies/Assasin/Squirrel LP.glb"),
	],
	"bulldozer": [
		preload("res://Enemies/Bull/BullLP.glb"),
		preload("res://Enemies/Bull/BullLP.glb"),
	],
	"dasher": [
		preload("res://Enemies/Dasher/Dasher LP.glb"),
		preload("res://Enemies/Dasher/Dasher LP.glb"),
	],
	"gunner": [
		preload("res://Enemies/Gunner/Gunner LP.glb"),
		preload("res://Enemies/Gunner/Gunner LP.glb"),
	],
}

# Target visible height (mét) per enemy_type. LP models có AABB chuẩn ~1m,
# scale tới target sẽ ra height visible thực tế.
const DUAL_MODEL_TARGET_HEIGHT : Dictionary = {
	"grunt":     0.8 * 0.9 * 0.8,    # Skull Crab — nhỏ × 0.9 × 0.8
	"assassin":  0.9 * 0.9,           # Squirrel — × 0.9
	"bulldozer": 1.5 * 0.8,           # Bull — lớn × 0.8
	"dasher":    0.7 * 1.5,           # Dasher — × 1.5 (to lên 50%)
	"gunner":    0.9,                  # Gunner — sẽ tinh chỉnh sau visual check
}
const DUAL_MODEL_TARGET_HEIGHT_DEFAULT : float = 1.0

# Manual XZ position offset (mét) sau khi auto-recenter — bù pivot lệch hoặc
# anim shifted. Y giữ 0 (bottom on ground). Chỉ thêm khi cần.
const DUAL_MODEL_OFFSET : Dictionary = {
	# vd: "bulldozer": Vector3(-0.1, 0.0, 0.0),
}

# Active model pair (whichever enemy_type loaded). Swap visibility theo walking.
var _model_base_inst : Node3D = null
var _model_walk_inst : Node3D = null

func _ready() -> void:
	hp         = max_hp
	dodge_line = randf_range(0.60, 1.00)
	name_label = get_node_or_null("NameLabel")
	model_node = get_node_or_null("ModelPlaceholder")
	if name_label:
		name_label.text = display_label
	# Tô placeholder body bằng màu của preset (không ảnh hưởng khi đã thay model thật).
	# QUAN TRỌNG: duplicate material để mỗi enemy có instance riêng — enemy.tscn
	# có 1 sub_resource Mat_enemy, nếu không duplicate thì 3 enemy share chung
	# material → tween alpha của 1 con sẽ làm các con khác cũng tàng hình.
	if model_node and model_node.material_override is StandardMaterial3D:
		var mat : StandardMaterial3D = model_node.material_override.duplicate()
		model_node.material_override = mat
		mat.albedo_color = body_color
	# Skinned-mesh enemies dùng dual-model (Base/Walk) swap visibility.
	if DUAL_MODEL_SCENES.has(enemy_type):
		_setup_dual_model(enemy_type)

func _setup_dual_model(etype: String) -> void:
	if model_node:
		model_node.visible = false
	var pair : Array = DUAL_MODEL_SCENES[etype]
	_model_base_inst = _spawn_dual_variant(pair[0], etype + "Base", true)
	_model_walk_inst = _spawn_dual_variant(pair[1], etype + "Walk", false)

func _spawn_dual_variant(scene: PackedScene, node_name: String, visible: bool) -> Node3D:
	var inst : Node3D = scene.instantiate() as Node3D
	if inst == null: return null
	inst.name = node_name
	inst.visible = visible
	add_child(inst)
	# Tìm AnimationPlayer trong .glb và play anim đầu tiên trên loop. Nếu
	# không play, mesh đứng ở bind-pose (T-pose) → Base/Walk trông y hệt nhau.
	var ap : AnimationPlayer = _find_animation_player(inst)
	if ap and ap.get_animation_list().size() > 0:
		var anim_name : StringName = ap.get_animation_list()[0]
		var anim : Animation = ap.get_animation(anim_name)
		if anim:
			anim.loop_mode = Animation.LOOP_LINEAR
		ap.play(anim_name)
	# Auto-fit: scale model lên target height (model gốc rất nhỏ ~0.04mm).
	var bbox : AABB = _measure_node_aabb(inst)
	if bbox.size.y > 0.0:
		var target_h : float = float(DUAL_MODEL_TARGET_HEIGHT.get(
				enemy_type, DUAL_MODEL_TARGET_HEIGHT_DEFAULT))
		var s : float = target_h / bbox.size.y
		inst.scale = Vector3(s, s, s)
		# Re-measure để recenter bottom-center về inst origin (XZ về (0,0),
		# bottom Y về 0). Chỉ chỉnh XZ để giữ chân enemy chạm GROUND_Y.
		var bbox2 : AABB = _measure_node_aabb(inst)
		var bc : Vector3 = bbox2.position + Vector3(
				bbox2.size.x * 0.5, 0.0, bbox2.size.z * 0.5)
		inst.position -= bc
		# Manual offset per-type cho model có pivot/anim lệch (vd Bull).
		var off : Vector3 = DUAL_MODEL_OFFSET.get(enemy_type, Vector3.ZERO)
		if off != Vector3.ZERO:
			inst.position += off
		print("[%s] %s scale=%.3fx, raw_size.y=%.4f, bbox.x=[%.2f,%.2f] z=[%.2f,%.2f]" \
				% [enemy_type, node_name, s, bbox.size.y,
				   bbox2.position.x, bbox2.position.x + bbox2.size.x,
				   bbox2.position.z, bbox2.position.z + bbox2.size.z])
	return inst

func _find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for c in node.get_children():
		var found : AnimationPlayer = _find_animation_player(c)
		if found != null:
			return found
	return null

func _measure_node_aabb(root: Node) -> AABB:
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
		if mi.mesh:
			out.append(mi.global_transform * mi.get_aabb())
	for c in node.get_children():
		_collect_mesh_aabbs(c, out)

# Swap visibility Base ↔ Walk theo state. Gọi từ main.gd qua _move_entity_smooth.
func anim_set_walking(walking: bool) -> void:
	if _model_base_inst: _model_base_inst.visible = not walking
	if _model_walk_inst: _model_walk_inst.visible = walking

func setup(col: int, row: int) -> void:
	grid_col = col
	grid_row = row

func refresh_hp_bar() -> void:
	# TODO Mốc 5: cập nhật HP bar 3D (Label3D hoặc mesh segments)
	pass

# ═══════════════════════════════════════════════════════════════════
#  ATTACK CYCLING
# ═══════════════════════════════════════════════════════════════════

func get_current_attack() -> Dictionary:
	if attacks.is_empty(): return {}
	return attacks[attack_index]

func advance_attack() -> void:
	if attacks.is_empty(): return
	attack_index = (attack_index + 1) % attacks.size()

# ═══════════════════════════════════════════════════════════════════
#  AI
# ═══════════════════════════════════════════════════════════════════

func plan_action(player_col: int, player_row: int,
				 _grid_cols: int, _grid_rows: int) -> String:
	if behavior == Behavior.DUMMY:
		return "idle"
	if disarmed_turns > 0:
		return "move"

	var dist      = _hex_dist(grid_col, grid_row, player_col, player_row)
	var atk_range = get_current_attack().get("range", 1)

	match behavior:
		Behavior.BULLDOZER:
			if charge_this_turn:
				return "idle"
			if lock_target_idx >= 0:
				charge_this_turn = true
				return "charge"
			# No lock: first action = move, second = lock attempt (main.gd does LOS+dist check)
			if move_done_this_turn:
				lock_attempted = true
				return "lock_on"
			move_done_this_turn = true
			return "move"
		Behavior.AGGRESSIVE:
			if enemy_type == "assassin":
				# A1 (ranged) first if not yet used and player is within range 6.
				# A2 (melee dual-bar) when adjacent.
				if not ranged_used and dist <= 6:
					attack_index = 0
					return "attack"
				if dist <= 1:
					attack_index = 1
					return "attack"
			elif enemy_type == "boxing_bear":
				if dist <= 1:
					return "boxing_bear_combo"
			else:
				if dist <= atk_range:
					return "attack"
		Behavior.RANGER:
			if enemy_type == "mage":
				# Pending eruption fires free before the normal action; main.gd calls
				# plan_action a second time for the remaining action after resolving it.
				if pending_eruption:
					return "erupt"
				if dist <= 1:
					return "move_away"
				if dist <= range_max:  # LOS check is main.gd's responsibility
					return "aim"
			else:
				if dist < range_min:
					return "move_away"
				if dist <= atk_range:
					return "attack"
		Behavior.DASHER:
			return "dasher_turn"
		Behavior.GUARDIAN_GORILLA:
			return "guardian_gorilla_turn"
	return "move"

func best_move_toward(player_col: int, player_row: int,
					  occupied: Dictionary, grid) -> Vector2i:
	var reachable : Array = _bfs_reachable(occupied, grid)
	var best      : Vector2i = Vector2i(-1, -1)
	var best_dist : int      = 999
	for pos in reachable:
		var d : int = _hex_dist(pos.x, pos.y, player_col, player_row)
		if d < best_dist:
			best_dist = d
			best      = pos
	return best

func best_move_away(player_col: int, player_row: int,
					occupied: Dictionary, grid) -> Vector2i:
	var reachable : Array = _bfs_reachable(occupied, grid)
	var best      : Vector2i = Vector2i(-1, -1)
	var best_dist : int      = -1
	for pos in reachable:
		var d : int = _hex_dist(pos.x, pos.y, player_col, player_row)
		if d > best_dist:
			best_dist = d
			best      = pos
	return best

# BFS up to move_range steps; returns all passable non-occupied reachable tiles.
func _bfs_reachable(occupied: Dictionary, grid) -> Array:
	var visited  : Dictionary = { Vector2i(grid_col, grid_row): true }
	var frontier : Array      = [Vector2i(grid_col, grid_row)]
	var reachable : Array     = []
	for _step in range(move_range):
		var next : Array = []
		for pos in frontier:
			for nb in _get_neighbors(pos.x, pos.y):
				if nb in visited: continue
				if not grid.is_valid_and_passable(nb.x, nb.y): continue
				if nb in occupied: continue
				visited[nb] = true
				next.append(nb)
				reachable.append(nb)
		frontier = next
		if frontier.is_empty(): break
	return reachable

# ═══════════════════════════════════════════════════════════════════
#  COMBAT
# ═══════════════════════════════════════════════════════════════════

func take_damage(dmg: int) -> void:
	hp = maxi(0, hp - dmg)
	refresh_hp_bar()

func tick_turn() -> void:
	if disarmed_turns > 0:
		disarmed_turns -= 1
	charge_this_turn    = false
	move_done_this_turn = false
	lock_attempted      = false

# Returns poison damage to deal this turn and decrements one stack.
func tick_poison() -> int:
	if poison_stacks <= 0: return 0
	var dmg := poison_stacks
	poison_stacks -= 1
	return dmg

# Returns burn damage to deal this turn and decrements one stack.
func tick_burn() -> int:
	if burn_stacks <= 0: return 0
	var dmg := burn_stacks
	burn_stacks -= 1
	return dmg

# Called by main.gd when mage takes damage or is pushed during the aim→erupt window.
# Returns true if a cast was actually interrupted.
func interrupt_cast() -> bool:
	if not pending_eruption: return false
	pending_eruption    = false
	eruption_target_col = -1
	eruption_target_row = -1
	return true

# ═══════════════════════════════════════════════════════════════════
#  HEX HELPERS
# ═══════════════════════════════════════════════════════════════════

func _get_neighbors(col: int, row: int) -> Array:
	var dirs = [[1,0],[-1,0],[0,-1],[0,1],[1,-1],[-1,-1]] if col % 2 == 0 \
			 else [[1,0],[-1,0],[0,-1],[0,1],[1,1],[-1,1]]
	var result : Array = []
	for d in dirs:
		result.append(Vector2i(col + d[0], row + d[1]))
	return result

func _hex_dist(c1: int, r1: int, c2: int, r2: int) -> int:
	var to_cube = func(c, r):
		var x = c
		var z = r - (c - (c & 1)) / 2
		return Vector3i(x, -x - z, z)
	var a = to_cube.call(c1, r1)
	var b = to_cube.call(c2, r2)
	return maxi(maxi(abs(a.x - b.x), abs(a.y - b.y)), abs(a.z - b.z))
