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

# Multi-model animation system (swap visibility, không inject).
# Mỗi state có 1 .glb riêng → preload + instantiate đầy đủ; play() tự chạy
# animation đầu tiên của model đó.
const MODEL_PATHS_BY_CHAR : Dictionary = {
	"Sonny": {
		"idle":   "res://CharacterAsset/Sonny/Sonny Idle.glb",
		"run":    "res://CharacterAsset/Sonny/Sonny Run.glb",
		"attack": "res://CharacterAsset/Sonny/Sonny Combo Attack.glb",
	},
	"Mike": {
		"idle":   "res://CharacterAsset/Mike/Mike idle.glb",
		"run":    "res://CharacterAsset/Mike/Mike Run.glb",
		"attack": "res://CharacterAsset/Mike/Mike Skill.glb",
	},
}

var models_by_state : Dictionary = {}   # "idle"/"run"/"attack" → Node3D instance
var current_state   : String     = "idle"

func _ready() -> void:
	name_label = get_node_or_null("NameLabel")
	model_node = get_node_or_null("ModelPlaceholder")
	if name_label and character_name != "":
		name_label.text = character_name
	# Note: _try_play_default_animation() được dời sang cuối setup_from_preset
	# vì lúc _ready chạy character_name vẫn còn rỗng (main.gd gọi
	# setup_from_preset sau add_child).

# Pre-instantiate 3 models (idle, run, attack), tất cả thành con của Player
# với cùng transform (scale từ tscn). Hide tất cả trừ idle ban đầu.
# Mỗi model có AnimationPlayer riêng tự auto-play khi visible.
func _try_play_default_animation() -> void:
	if model_node == null: return
	var base_xform : Transform3D = model_node.transform
	models_by_state["idle"] = model_node
	_setup_animation(model_node, true)

	# Pre-instantiate run + attack models — visible=false ban đầu, swap khi cần.
	var paths : Dictionary = MODEL_PATHS_BY_CHAR.get(character_name, {})
	for state in ["run", "attack"]:
		if not paths.has(state): continue
		var path : String = paths[state]
		if not ResourceLoader.exists(path): continue
		var packed = load(path)
		if packed == null: continue
		var raw_inst = packed.instantiate()
		var inst : Node3D = raw_inst as Node3D
		if inst == null:
			raw_inst.queue_free()
			continue
		inst.transform = base_xform
		inst.visible   = false
		add_child(inst)
		models_by_state[state] = inst
		_setup_animation(inst, state == "run")

	current_state = "idle"

# Hook AnimationPlayer của 1 model: set loop cho idle/run, 1-shot cho attack.
# Connect animation_finished cho attack → play_idle.
func _setup_animation(model: Node, should_loop: bool) -> void:
	var ap : AnimationPlayer = _find_animation_player(model)
	if ap == null: return
	var anims : PackedStringArray = ap.get_animation_list()
	if anims.is_empty(): return
	var first : String = anims[0]
	var anim : Animation = ap.get_animation(first)
	if anim:
		anim.loop_mode = (Animation.LOOP_LINEAR if should_loop else Animation.LOOP_NONE)
	# Auto play để model không bị T-pose lúc visible
	ap.play(first)
	# Attack model: khi animation_finished → revert idle
	if not should_loop:
		if not ap.animation_finished.is_connected(_on_attack_anim_finished):
			ap.animation_finished.connect(_on_attack_anim_finished)

func _find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for child in node.get_children():
		var found : AnimationPlayer = _find_animation_player(child)
		if found:
			return found
	return null

# ─── Public API: play idle / run / attack ─────────────────

func play_idle() -> void:
	_swap_state("idle")

func play_run() -> void:
	_swap_state("run")

func play_attack() -> void:
	# Restart attack animation từ đầu (vì cùng instance dùng lại)
	_swap_state("attack")
	if models_by_state.has("attack"):
		var ap : AnimationPlayer = _find_animation_player(models_by_state["attack"])
		if ap and not ap.get_animation_list().is_empty():
			ap.play(ap.get_animation_list()[0])

func _swap_state(new_state: String) -> void:
	if new_state == current_state: return
	if not models_by_state.has(new_state): return
	for s in models_by_state.keys():
		var m = models_by_state[s]
		if is_instance_valid(m):
			m.visible = (s == new_state)
	current_state = new_state

func _on_attack_anim_finished(_anim_name: String) -> void:
	# Sau attack → quay về idle
	if current_state == "attack":
		play_idle()

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
