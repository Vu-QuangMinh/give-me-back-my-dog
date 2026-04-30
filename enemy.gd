extends Node3D
class_name Enemy

# â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
#  BEHAVIOR ENUM
# â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•

enum Behavior { AGGRESSIVE, RANGER, DUMMY }

# â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
#  ENEMY PRESETS
#  â–º All per-enemy tuning lives here â€” mirror of CHARACTER_PRESETS in Player.gd.
#  â–º Call _spawn_enemy("grunt", col, row) in main.gd to instantiate.
#
#  Attack dict keys:
#    range          int    1 = melee (dodge bar), 2+ = ranged (projectile)
#    damage         float  base damage per hit
#    aoe            int    1 = target only, 2 = target + adjacent ring
#    hits           int    how many times this attack fires per action
#    speed          String "" for melee; "slow" / "medium" / "fast" for ranged
#    perfect_window float  seconds from timing line (melee only)
#    ok_window      float  seconds from timing line (melee only)
#    dual_bar       bool   true â†’ spawn two sequential dodge bars
#    speed_mults    Array  [bar1_mult, bar2_mult] when dual_bar == true
#    hit_details    Array  per-hit override dicts when hits > 1 and not identical
# â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•

const ENEMY_PRESETS : Dictionary = {
	"grunt": {
		"enemy_type":       "grunt",
		"display_label":    "Crab",
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
	"squirrel": {
		"enemy_type":       "squirrel",
		"display_label":    "Squirrel",
		"max_hp":           2,
		"actions_per_turn": 2,
		"move_range":       3,                              # nhanh hơn crab
		"body_color":       Color(0.78, 0.55, 0.28),
		"behavior":         Behavior.AGGRESSIVE,
		"immovable":        false,
		"range_min":        0,
		"range_max":        0,
		"attacks": [
			{ "range": 1, "damage": 1, "aoe": 1, "hits": 1, "speed": "",
			  "perfect_window": 0.18, "ok_window": 0.36,
			  "dual_bar": false, "speed_mults": [] },
		],
	},
	"bulldozer": {
		"enemy_type":       "bulldozer",
		"display_label":    "Bulldozer",
		"max_hp":           5,                              # tank, máu cao
		"actions_per_turn": 1,                              # chậm — 1 hành động/turn
		"move_range":       2,
		"body_color":       Color(0.55, 0.55, 0.58),       # xám máy móc
		"behavior":         Behavior.AGGRESSIVE,
		"immovable":        false,
		"range_min":        0,
		"range_max":        0,
		"attacks": [
			{ "range": 1, "damage": 2, "aoe": 1, "hits": 1, "speed": "",
			  "perfect_window": 0.22, "ok_window": 0.44,
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
	"assassin": {
		"enemy_type":       "assassin",
		"display_label":    "S",
		"max_hp":           4,
		"actions_per_turn": 2,
		"move_range":       2,
		"body_color":       Color(0.50, 0.15, 0.70),
		"behavior":         Behavior.AGGRESSIVE,
		"immovable":        false,
		"range_min":        0,
		"range_max":        0,
		"attacks": [
			{ "range": 1, "damage": 1, "aoe": 1, "hits": 1, "speed": "",
			  "perfect_window": 0.16, "ok_window": 0.32,
			  "dual_bar": true, "speed_mults": [0.80, 1.30] },
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
}

# â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
#  EXPORTED PARAMETERS
# â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•

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

# â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
#  RUNTIME STATE
# â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•

var hp                     : int   = 0
var grid_col               : int   = 0
var grid_row               : int   = 0
var dodge_line             : float = 0.0
var bleed_stacks           : int   = 0
var disarmed_turns         : int   = 0
var attack_index           : int   = 0
var has_attacked_this_turn : bool  = false
var fuse_turns             : int   = 0   # Má»‘c 7: chá»‰ dÃ¹ng cho type "bomb"

# â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
#  3D NODES (tá»« scene)
# â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•

var name_label : Label3D        = null
var model_node : MeshInstance3D = null

func _ready() -> void:
	hp         = max_hp
	dodge_line = randf_range(0.60, 1.00)
	name_label = get_node_or_null("NameLabel")
	model_node = get_node_or_null("ModelPlaceholder")
	if name_label:
		name_label.text = display_label
	# TÃ´ placeholder body báº±ng mÃ u cá»§a preset (khÃ´ng áº£nh hÆ°á»Ÿng khi Ä‘Ã£ thay model tháº­t).
	# QUAN TRá»ŒNG: duplicate material Ä‘á»ƒ má»—i enemy cÃ³ instance riÃªng â€” enemy.tscn
	# cÃ³ 1 sub_resource Mat_enemy, náº¿u khÃ´ng duplicate thÃ¬ 3 enemy share chung
	# material â†’ tween alpha cá»§a 1 con sáº½ lÃ m cÃ¡c con khÃ¡c cÅ©ng tÃ ng hÃ¬nh.
	if model_node and model_node.material_override is StandardMaterial3D:
		var mat : StandardMaterial3D = model_node.material_override.duplicate()
		model_node.material_override = mat
		mat.albedo_color = body_color
	# Skinned-mesh enemies dùng dual-model (Base/Walk) swap visibility.
	# Trải table lên thay vì if-else dài: enemy_type → [base_scene, walk_scene].
	if DUAL_MODEL_SCENES.has(enemy_type):
		_setup_dual_model(enemy_type)

# Bảng dual-model cho các enemy có .glb skinned. Key = enemy_type.
const DUAL_MODEL_SCENES : Dictionary = {
	"grunt": [
		preload("res://Enemies/Skull Crab/Skull Crab Base.glb"),
		preload("res://Enemies/Skull Crab/Skull Crab Walk.glb"),
	],
	"squirrel": [
		preload("res://Enemies/squirrel/Squirrel Base.glb"),
		preload("res://Enemies/squirrel/Squirrel Walk.glb"),
	],
	"bulldozer": [
		preload("res://Enemies/Bull/Bull Base.glb"),
		preload("res://Enemies/Bull/Bull Walk.glb"),
	],
}

# Target visible height per enemy_type. Skinned mesh AABB undercount → auto-fit
# cần factor lớn. Base = 0.015; tinh chỉnh per-type qua multiplier.
const DUAL_MODEL_TARGET_HEIGHT : Dictionary = {
	"grunt":     0.015 * 0.9,   # crab × 0.9
	"squirrel":  0.015 * 0.8,   # squirrel × 0.8
	"bulldozer": 0.015,          # bull default
}
const DUAL_MODEL_TARGET_HEIGHT_DEFAULT : float = 0.015

# Active model pair (whichever enemy_type loaded). Swap visibility theo walking.
var _model_base_inst : Node3D = null
var _model_walk_inst : Node3D = null

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
	# Auto-fit: scale model lên target height (model gốc rất nhỏ 0.04mm).
	var bbox : AABB = _measure_node_aabb(inst)
	if bbox.size.y > 0.0:
		var target_h : float = float(DUAL_MODEL_TARGET_HEIGHT.get(
				enemy_type, DUAL_MODEL_TARGET_HEIGHT_DEFAULT))
		var s : float = target_h / bbox.size.y
		inst.scale = Vector3(s, s, s)
		# Re-measure để recenter bottom-center về inst origin.
		var bbox2 : AABB = _measure_node_aabb(inst)
		var bc : Vector3 = bbox2.position + Vector3(
				bbox2.size.x * 0.5, 0.0, bbox2.size.z * 0.5)
		inst.position -= bc
		var ap_info : String = (" anim=" + str(ap.get_animation_list()[0])) \
				if (ap and ap.get_animation_list().size() > 0) else " anim=NONE"
		print("[%s %d] %s scale=%.0fx, raw_size.y=%.6f%s" \
				% [enemy_type, get_instance_id(), node_name, s, bbox.size.y, ap_info])
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

# â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
#  GRUNT â€” placeholder only. Grunt dÃ¹ng capsule mesh tá»« enemy.tscn,
#  khÃ´ng cÃ³ .glb model hay animation. Sáº½ thay model má»›i sau.
# â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•

func refresh_hp_bar() -> void:
	# TODO Má»‘c 5: cáº­p nháº­t HP bar 3D (Label3D hoáº·c mesh segments)
	pass

# â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
#  ATTACK CYCLING
# â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•

func get_current_attack() -> Dictionary:
	if attacks.is_empty(): return {}
	return attacks[attack_index]

func advance_attack() -> void:
	if attacks.is_empty(): return
	attack_index = (attack_index + 1) % attacks.size()

# â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
#  AI
# â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•

func plan_action(player_col: int, player_row: int,
				 _grid_cols: int, _grid_rows: int) -> String:
	if behavior == Behavior.DUMMY:
		return "idle"
	if disarmed_turns > 0:
		return "move"

	var dist      = _hex_dist(grid_col, grid_row, player_col, player_row)
	var atk_range = get_current_attack().get("range", 1)

	match behavior:
		Behavior.AGGRESSIVE:
			if dist <= atk_range:
				return "attack"
		Behavior.RANGER:
			if dist < range_min:
				return "move_away"
			if dist <= atk_range:
				return "attack"
	return "move"

func best_move_toward(player_col: int, player_row: int,
					  occupied: Dictionary, grid) -> Vector2i:
	var neighbors = _get_neighbors(grid_col, grid_row)
	var best      = Vector2i(-1, -1)
	var best_dist = 999
	for nb in neighbors:
		if nb in occupied: continue
		if not grid.is_valid_and_passable(nb.x, nb.y): continue
		var d = _hex_dist(nb.x, nb.y, player_col, player_row)
		if d < best_dist:
			best_dist = d
			best      = nb
	return best

func best_move_away(player_col: int, player_row: int,
					occupied: Dictionary, grid) -> Vector2i:
	var neighbors = _get_neighbors(grid_col, grid_row)
	var best      = Vector2i(-1, -1)
	var best_dist = -1
	for nb in neighbors:
		if nb in occupied: continue
		if not grid.is_valid_and_passable(nb.x, nb.y): continue
		var d = _hex_dist(nb.x, nb.y, player_col, player_row)
		if d > best_dist:
			best_dist = d
			best      = nb
	return best

# â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
#  COMBAT
# â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•

func take_damage(dmg: int) -> void:
	hp = maxi(0, hp - dmg)
	refresh_hp_bar()

func tick_turn() -> void:
	if disarmed_turns > 0:
		disarmed_turns -= 1

# â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
#  HEX HELPERS
# â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•

func _get_neighbors(col: int, row: int) -> Array:
	return HexUtils.get_neighbors(col, row)

func _hex_dist(c1: int, r1: int, c2: int, r2: int) -> int:
	return HexUtils.hex_dist(c1, r1, c2, r2)
