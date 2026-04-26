extends Node2D
class_name Enemy

# ═══════════════════════════════════════════════════════════════════
#  BEHAVIOR ENUM
# ═══════════════════════════════════════════════════════════════════

enum Behavior { AGGRESSIVE, RANGER, DUMMY }

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
#    dual_bar       bool   true → spawn two sequential dodge bars
#    speed_mults    Array  [bar1_mult, bar2_mult] when dual_bar == true
#    hit_details    Array  per-hit override dicts when hits > 1 and not identical
# ═══════════════════════════════════════════════════════════════════

const ENEMY_PRESETS : Dictionary = {
	"grunt": {
		"enemy_type":       "grunt",
		"display_label":    "G",
		"max_hp":           5,
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
		"max_hp":           3,
		"actions_per_turn": 2,
		"move_range":       1,
		"body_color":       Color(0.22, 0.45, 0.85),
		"behavior":         Behavior.RANGER,
		"immovable":        false,
		"range_min":        2,
		"range_max":        4,
		"attacks": [
			{ "range": 4, "damage": 2, "aoe": 1, "hits": 1, "speed": "medium",
			  "perfect_window": 0.0, "ok_window": 0.0,
			  "dual_bar": false, "speed_mults": [] },
			{ "range": 4, "damage": 0, "aoe": 1, "hits": 2, "speed": "medium",
			  "perfect_window": 0.0, "ok_window": 0.0,
			  "dual_bar": false, "speed_mults": [],
			  "hit_details": [
			  	{ "damage": 0.5, "speed": "medium" },
			  	{ "damage": 0.5, "speed": "fast" },
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

# ═══════════════════════════════════════════════════════════════════
#  EXPORTED PARAMETERS
#  ► Set via script before add_child(), or tweak in the Godot Inspector.
# ═══════════════════════════════════════════════════════════════════

@export var enemy_type       : String   = "grunt"
@export var display_label    : String   = "G"
@export var max_hp           : int      = 3
@export var actions_per_turn : int      = 2
@export var move_range       : int      = 2
@export var body_color       : Color    = Color(0.70, 0.20, 0.20)
@export var behavior         : Behavior = Behavior.AGGRESSIVE
@export var immovable        : bool     = false

# Ranger-specific: maintained distance band from nearest player
@export var range_min : int = 2
@export var range_max : int = 5

# Attack list — assigned from ENEMY_PRESETS, not set via Inspector
var attacks : Array = []

# ═══════════════════════════════════════════════════════════════════
#  RUNTIME STATE
# ═══════════════════════════════════════════════════════════════════

var hp                    : int   = 0
var grid_col              : int   = 0
var grid_row              : int   = 0
var dodge_line            : float = 0.0
var bleed_stacks          : int   = 0
var disarmed_turns        : int   = 0
var attack_index          : int   = 0   # cycles through attacks[] each action
var has_attacked_this_turn : bool  = false

# ═══════════════════════════════════════════════════════════════════
#  VISUALS
# ═══════════════════════════════════════════════════════════════════

const BAR_WIDTH  = 36.0
const BAR_HEIGHT = 5.0

var hp_bar_bg   : Line2D = null
var hp_bar_fill : Line2D = null
var name_label  : Label  = null

func _ready() -> void:
	hp         = max_hp
	dodge_line = randf_range(0.60, 1.00)
	_build_hp_bar()
	_build_label()
	queue_redraw()

func setup(col: int, row: int) -> void:
	grid_col = col
	grid_row = row

func _draw() -> void:
	draw_circle(Vector2.ZERO, 14, body_color)
	draw_circle(Vector2.ZERO, 14, body_color.darkened(0.3), false, 2.0)

func _build_label() -> void:
	name_label          = Label.new()
	name_label.text     = display_label
	name_label.position = Vector2(-5, -14)
	add_child(name_label)

func _build_hp_bar() -> void:
	hp_bar_bg               = Line2D.new()
	hp_bar_bg.width         = BAR_HEIGHT
	hp_bar_bg.default_color = body_color.darkened(0.6)
	hp_bar_bg.points        = PackedVector2Array([
		Vector2(-BAR_WIDTH / 2, -28),
		Vector2( BAR_WIDTH / 2, -28)
	])
	add_child(hp_bar_bg)

	hp_bar_fill               = Line2D.new()
	hp_bar_fill.width         = BAR_HEIGHT
	hp_bar_fill.default_color = body_color.lightened(0.2)
	hp_bar_fill.points        = PackedVector2Array([
		Vector2(-BAR_WIDTH / 2, -28),
		Vector2( BAR_WIDTH / 2, -28)
	])
	add_child(hp_bar_fill)

func refresh_hp_bar() -> void:
	if not hp_bar_fill: return
	var frac  = float(hp) / float(max_hp)
	var right = -BAR_WIDTH / 2 + BAR_WIDTH * frac
	hp_bar_fill.points = PackedVector2Array([
		Vector2(-BAR_WIDTH / 2, -28),
		Vector2(right,          -28)
	])

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

# ═══════════════════════════════════════════════════════════════════
#  COMBAT
# ═══════════════════════════════════════════════════════════════════

func take_damage(dmg: int) -> void:
	hp = maxi(0, hp - dmg)
	refresh_hp_bar()

func tick_turn() -> void:
	if disarmed_turns > 0:
		disarmed_turns -= 1

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
