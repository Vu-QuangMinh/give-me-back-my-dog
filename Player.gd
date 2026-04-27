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
		"max_hp":           4,
		"equipped":         "pan",
		"spawn_col":        0,
		"spawn_row":        4,
		"move_range":       2,
		"actions_per_turn": 2,
		"uses_draw_shot":   false,
		"body_color":       Color(0.93, 0.55, 0.25),   # cam ấm
	},
	"Mike": {
		"max_hp":           3,
		"equipped":         "slingshot",
		"spawn_col":        0,
		"spawn_row":        2,
		"move_range":       2,
		"actions_per_turn": 2,
		"uses_draw_shot":   true,
		"body_color":       Color(0.30, 0.65, 0.95),   # xanh lam
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

var actions_left  : int  = 2
var has_attacked  : bool = false
var disarmed      : bool = false
var floor_cleared : bool = false

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

var name_label : Label3D        = null
var model_node : MeshInstance3D = null
var armor_ring : Node           = null   # TODO Mốc 5: 3D armor visual

func _ready() -> void:
	name_label = get_node_or_null("NameLabel")
	model_node = get_node_or_null("ModelPlaceholder")
	if name_label and character_name != "":
		name_label.text = character_name

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
	if name_label:
		name_label.text = preset_name
	# Tô màu placeholder body theo preset (không ảnh hưởng khi đã thay model thật)
	if model_node and model_node.material_override is StandardMaterial3D:
		var mat : StandardMaterial3D = model_node.material_override
		mat.albedo_color = p.get("body_color", Color.WHITE)

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
