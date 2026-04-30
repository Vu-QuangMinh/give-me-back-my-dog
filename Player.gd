extends Node3D

# ═══════════════════════════════════════════════════════════════════
#  CHARACTER PRESETS
#  ► All per-character tuning lives here.
#  ► Add / change characters without touching main.gd.
#  ► PLAYER_ORDER controls spawn sequence (index 0 = first to act).
# ═══════════════════════════════════════════════════════════════════

const PLAYER_ORDER : Array = ["Sonny", "Mike"]

const CHARACTER_PRESETS : Dictionary = {
	"Sonny": {
		"max_hp":            4,
		"equipped":          "pan",
		"spawn_col":         0,
		"spawn_row":         4,
		"move_range":        2,
		"actions_per_turn":  2,
		"uses_draw_shot":    false,
		"body_color":        Color(0.93, 0.55, 0.25),   # cam ấm
		# ── Tuning ──────────────────────────────────────────
		"bombs_per_floor":   1,
		"bomb_aoe_damage":   2,
		"grapples_per_floor": 0,
		"proj_launch_speed": 0.0,
		"proj_decay_rate":   0.0,
		"proj_min_speed":    0.0,
		"proj_neg_bounce":   0.0,
		"caught_capacity":   0,
	},
	"Mike": {
		"max_hp":            3,
		"equipped":          "slingshot",
		"spawn_col":         0,
		"spawn_row":         2,
		"move_range":        2,
		"actions_per_turn":  2,
		"uses_draw_shot":    true,
		"body_color":        Color(0.30, 0.65, 0.95),   # xanh lam
		# ── Tuning ──────────────────────────────────────────
		"bombs_per_floor":   0,
		"bomb_aoe_damage":   0,
		"grapples_per_floor": 2,
		"proj_launch_speed": 18.0,
		"proj_decay_rate":   0.85,
		"proj_min_speed":    0.54,
		"proj_neg_bounce":   5.0,
		"caught_capacity":   2,
	},
}

# ═══════════════════════════════════════════════════════════════════
#  WEAPON DEFINITIONS  (giữ nguyên — không dính 3D)
# ═══════════════════════════════════════════════════════════════════

const WEAPONS : Dictionary = {
	"sword": {
		"q_name":   "Swing",               "q_desc":   "3 adj tiles, 1 dmg",
		"w_name":   "Thrust",              "w_desc":   "1 adj tile, 2 dmg",
		"q_dmg":    1,                     "w_dmg":    2,
		"q_mode":   "crescent",            "w_mode":   "single",
		"q_effect": "",                    "w_effect": "",
	},
	"hammer": {
		"q_name":   "Bash",                "q_desc":   "1 adj tile, 1 dmg + push 1",
		"w_name":   "Crush",               "w_desc":   "1 dmg to target + adj tiles",
		"q_dmg":    1,                     "w_dmg":    1,
		"q_mode":   "single",              "w_mode":   "area",
		"q_effect": "push1",               "w_effect": "crush_area",
	},
	"unarmed": {
		"q_name":   "Punch",               "q_desc":   "1 adj tile, 1 dmg",
		"w_name":   "Push",                "w_desc":   "1 adj tile, push 1",
		"q_dmg":    1,                     "w_dmg":    0,
		"q_mode":   "single",              "w_mode":   "single",
		"q_effect": "",                    "w_effect": "push1",
	},
	"pan": {
		"q_name":   "Boong",               "q_desc":   "hold to charge, 1+dmg + push 1",
		"w_name":   "Bomb",                "w_desc":   "adj tile, 2 dmg AOE (1/floor)",
		"q_dmg":    1,                     "w_dmg":    0,
		"q_mode":   "charge_bar",          "w_mode":   "bomb",
		"q_effect": "push1",               "w_effect": "",
	},
	"slingshot": {
		"q_name":       "Draw Shot",
		"q_desc":       "aim+drag timing, 1 dmg, 1 bounce",
		"w_name":       "Grapple",         "w_desc":   "hook phases walls/columns, pull first char (1/floor)",
		"q_dmg":        1,                 "w_dmg":    1,
		"q_mode":       "draw_shot",       "w_mode":   "grapple",
		"q_effect":     "",                "w_effect": "",
		"bounce_count": 1,
	},
}

# ═══════════════════════════════════════════════════════════════════
#  GRID POSITION
# ═══════════════════════════════════════════════════════════════════

var grid_col : int = 5
var grid_row : int = 4

# ═══════════════════════════════════════════════════════════════════
#  INSTANCE CONFIG
# ═══════════════════════════════════════════════════════════════════

var character_name    : String = ""
var move_range        : int    = 2
var actions_per_turn  : int    = 2
var uses_draw_shot    : bool   = false

# ═══════════════════════════════════════════════════════════════════
#  COMBAT STATS
# ═══════════════════════════════════════════════════════════════════

var hp      : int = 4
var max_hp  : int = 4
var armor   : int = 0

var perfection     : int = 0
var perfection_cap : int = 10
var poison_stacks  : int = 0
var burn_stacks    : int = 0

var actions_left  : int  = 2
var has_attacked  : bool = false
var disarmed      : bool = false
var floor_cleared : bool = false

# ── Per-character tuning (read from preset, never touch directly) ──
var bombs_left         : int   = 0   # Sonny: bombs remaining this floor
var bomb_aoe_damage    : int   = 0   # Sonny: AOE damage per bomb explosion
var grapples_left      : int   = 0   # Mike:  grapple uses remaining this floor
var proj_launch_speed  : float = 0.0 # Mike:  initial projectile speed
var proj_decay_rate    : float = 0.0 # Mike:  exponential speed decay
var proj_min_speed     : float = 0.0 # Mike:  die below this speed
var proj_neg_bounce    : float = 0.0 # Mike:  speed penalty per bounce
var caught_capacity    : int   = 0   # Mike:  max projectiles held at once

# ── Per-turn / action-mode state (main.gd reads these instead of globals) ─
var shot_used          : bool  = false  # Mike: one Draw Shot per round
var aiming             : bool  = false  # Mike: aim-mode active
var grappling          : bool  = false  # Mike: grapple-mode active
var placing_bomb       : bool  = false  # Sonny: bomb-placement mode active
var attack_mode        : bool  = false  # Sonny: Q target-selection mode active
var caught_projectiles : Array = []     # Mike: caught projectile queue (max caught_capacity)

var tiles_traveled_this_turn : int    = 0
var swift_kill_count         : int    = 0
var passives                 : Array  = []
var equipped                 : String = "sword"

# ═══════════════════════════════════════════════════════════════════
#  3D NODES (đến từ scene)
#    - ModelPlaceholder : MeshInstance3D — placeholder body (CapsuleMesh).
#      Để swap sang model thật: xoá node này, thay bằng .glb cùng tên,
#      hoặc đổi `model_node` reference cho phù hợp.
#    - NameLabel : Label3D billboard hiển thị tên trên đầu nhân vật.
# ═══════════════════════════════════════════════════════════════════

var name_label : Label3D = null
var model_node : Node3D  = null   # initial .glb instance từ scene (idle)
var armor_ring : Node    = null   # TODO Mốc 5: 3D armor visual

# Single-model animation system: chỉ giữ idle .glb, run/attack là Tween
# transform-level overlay (xem block comment phía dưới).
const MODEL_PATHS_BY_CHAR : Dictionary = {
	"Sonny": { "idle": "res://CharacterAsset/Sonny/Sonny Idle.glb" },
	"Mike":  { "idle": "res://CharacterAsset/Mike/Mike idle.glb"   },
}

# Run + attack KHÔNG còn dùng .glb riêng (đã xóa để giảm 46 MB).
# Thay bằng Tween-based custom animation lên model_node:
#   ► Hop (Y bobble) khi running — abs(sin) oscillation trong _process
#   ► Lunge (Z forward + back) khi attack — tween 1-shot
const HOP_HEIGHT  : float = 0.18
const HOP_PERIOD  : float = 0.30
const LUNGE_DIST  : float = 0.40
const LUNGE_OUT   : float = 0.10
const LUNGE_BACK  : float = 0.20

var _hop_active : bool = false
var _hop_time   : float = 0.0

func _ready() -> void:
	name_label = get_node_or_null("NameLabel")
	model_node = get_node_or_null("ModelPlaceholder")
	if name_label and character_name != "":
		name_label.text = character_name
	# Note: _try_play_default_animation() được dời sang cuối setup_from_preset
	# vì lúc _ready chạy character_name vẫn còn rỗng (main.gd gọi
	# setup_from_preset sau add_child).

# Setup idle animation (model_node được tạo từ tscn với .glb idle).
# AnimationPlayer trong .glb auto-play idle, set loop. Run/attack được handle
# bằng Tween trên model_node.position (xem play_run / play_attack).
func _try_play_default_animation() -> void:
	if model_node == null: return
	_setup_idle_animation(model_node)

func _setup_idle_animation(model: Node) -> void:
	var ap : AnimationPlayer = _find_animation_player(model)
	if ap == null: return
	var anims : PackedStringArray = ap.get_animation_list()
	if anims.is_empty(): return
	var first : String = anims[0]
	var anim : Animation = ap.get_animation(first)
	if anim:
		anim.loop_mode = Animation.LOOP_LINEAR
	ap.play(first)

func _find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for child in node.get_children():
		var found : AnimationPlayer = _find_animation_player(child)
		if found:
			return found
	return null

# ─── Public API: play idle / run / attack ─────────────────
# Skeletal idle vẫn chạy nguyên (loop từ .glb embedded).
# Run + attack là Tween-based transform animation lên model_node — KHÔNG
# touch skeleton, chỉ dịch chuyển nguyên model về vị trí khác relative to
# Player root.

func play_idle() -> void:
	# Tắt hop, snap model về local origin (Z + Y).
	_hop_active = false
	if model_node:
		model_node.position = Vector3.ZERO

func play_run() -> void:
	# Bắt đầu hop loop (abs sin Y oscillation trong _process).
	_hop_active = true
	_hop_time = 0.0
	if model_node:
		model_node.position.z = 0.0   # đảm bảo không có lunge tồn dư

func play_attack() -> void:
	# Lunge tới phía trước (local +Z, Player đã look_at + flip 180 nên +Z
	# = hướng nhìn về địch) rồi recoil về vị trí ban đầu.
	if model_node == null: return
	_hop_active = false
	model_node.position.y = 0.0
	var t := create_tween()
	t.set_trans(Tween.TRANS_QUAD)
	t.tween_property(model_node, "position:z",  LUNGE_DIST, LUNGE_OUT) \
			.set_ease(Tween.EASE_OUT)
	t.tween_property(model_node, "position:z",  0.0,         LUNGE_BACK) \
			.set_ease(Tween.EASE_IN)

# Hop oscillation suốt thời gian _hop_active (giữa play_run và play_idle).
func _process(delta: float) -> void:
	if not _hop_active or model_node == null: return
	_hop_time += delta
	var phase : float = _hop_time / HOP_PERIOD * TAU
	# abs(sin) → bouncing motion luôn ≥ 0 (tránh "chìm" dưới sàn).
	model_node.position.y = absf(sin(phase)) * HOP_HEIGHT

func refresh_visuals() -> void:
	# TODO Mốc 5: hiển thị armor ring 3D khi armor > 0
	pass

# ═══════════════════════════════════════════════════════════════════
#  PRESET SETUP
# ═══════════════════════════════════════════════════════════════════

func setup_from_preset(preset_name: String) -> void:
	var p             = CHARACTER_PRESETS[preset_name]
	character_name    = preset_name
	max_hp            = p["max_hp"]
	hp                = p["max_hp"]
	equipped          = p["equipped"]
	grid_col          = p["spawn_col"]
	grid_row          = p["spawn_row"]
	move_range        = p["move_range"]
	actions_per_turn  = p["actions_per_turn"]
	actions_left      = p["actions_per_turn"]
	uses_draw_shot    = p["uses_draw_shot"]
	# Tuning values
	bombs_left         = p.get("bombs_per_floor",    0)
	bomb_aoe_damage    = p.get("bomb_aoe_damage",    0)
	grapples_left      = p.get("grapples_per_floor", 0)
	proj_launch_speed  = p.get("proj_launch_speed",  0.0)
	proj_decay_rate    = p.get("proj_decay_rate",    0.0)
	proj_min_speed     = p.get("proj_min_speed",     0.0)
	proj_neg_bounce    = p.get("proj_neg_bounce",    0.0)
	caught_capacity    = p.get("caught_capacity",    0)
	if name_label:
		name_label.text = preset_name
	# Tô màu placeholder body theo preset (chỉ áp dụng khi vẫn dùng capsule
	# placeholder; với .glb instance bỏ qua vì có texture riêng).
	if model_node is MeshInstance3D and model_node.material_override is StandardMaterial3D:
		var mat : StandardMaterial3D = model_node.material_override
		mat.albedo_color = p.get("body_color", Color.WHITE)
	# Animation system cần character_name để tra MODEL_PATHS_BY_CHAR → gọi
	# tại đây sau khi name đã set, không phải trong _ready.
	_try_play_default_animation()

# ═══════════════════════════════════════════════════════════════════
#  TURN MANAGEMENT
# ═══════════════════════════════════════════════════════════════════

func reset_turn() -> void:
	actions_left             = actions_per_turn
	has_attacked             = false
	armor                    = 0
	disarmed                 = false
	tiles_traveled_this_turn = 0
	refresh_visuals()

# Called once per floor clear — refills resource counters from preset.
func reset_floor_state() -> void:
	var p : Dictionary = CHARACTER_PRESETS.get(character_name, {})
	bombs_left    = p.get("bombs_per_floor",    0)
	grapples_left = p.get("grapples_per_floor", 0)

func use_action() -> void:
	if not floor_cleared:
		actions_left -= 1

func can_act() -> bool:
	return actions_left > 0 or floor_cleared

# ═══════════════════════════════════════════════════════════════════
#  DAMAGE / HEALING
# ═══════════════════════════════════════════════════════════════════

func take_damage(dmg: int) -> int:
	var absorbed = mini(armor, dmg)
	armor        = maxi(0, armor - dmg)
	var real_dmg = dmg - absorbed
	hp           = maxi(0, hp - real_dmg)
	if real_dmg > 0:
		perfection = 0
	refresh_visuals()
	return real_dmg

func heal(amount: int) -> void:
	hp = mini(hp + amount, max_hp)

func is_dead() -> bool:
	return hp <= 0

# ═══════════════════════════════════════════════════════════════════
#  WEAPON HELPERS
# ═══════════════════════════════════════════════════════════════════

func get_weapon_data() -> Dictionary:
	return WEAPONS.get(equipped, WEAPONS["unarmed"])

func get_q_dmg()        -> int:    return get_weapon_data().get("q_dmg", 1)
func get_w_dmg()        -> int:    return get_weapon_data().get("w_dmg", 1)
func get_q_mode()       -> String: return get_weapon_data().get("q_mode", "single")
func get_w_mode()       -> String: return get_weapon_data().get("w_mode", "single")
func get_q_effect()     -> String: return get_weapon_data().get("q_effect", "")
func get_w_effect()     -> String: return get_weapon_data().get("w_effect", "")
func get_bounce_count() -> int:    return get_weapon_data().get("bounce_count", 0)

# ═══════════════════════════════════════════════════════════════════
#  PASSIVE HELPERS
# ═══════════════════════════════════════════════════════════════════

func has_passive(p_name: String) -> bool:
	return p_name in passives

func add_passive(p_name: String) -> void:
	if not has_passive(p_name):
		passives.append(p_name)
		match p_name:
			"too_easy": perfection_cap = 20
