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
			# A1 — single shot, medium speed, no bounce
			{ "range": 4, "damage": 1, "aoe": 1, "hits": 1, "speed": "medium",
			  "perfect_window": 0.0, "ok_window": 0.0,
			  "dual_bar": false, "speed_mults": [], "no_bounce": true },
			# A2 — two fast shots; second fires 0.3 s after the first
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

var name_label : Label = null

func _ready() -> void:
	hp         = max_hp
	dodge_line = randf_range(0.60, 1.00)
	_build_label()
	queue_redraw()

func setup(col: int, row: int) -> void:
	grid_col = col
	grid_row = row

func _draw() -> void:
	draw_circle(Vector2.ZERO, 14, body_color)
	draw_circle(Vector2.ZERO, 14, body_color.darkened(0.3), false, 2.0)
	_draw_hp_bar()

func _draw_hp_bar() -> void:
	const CELL_W   := 8.0
	const CELL_H   := 7.0
	const CELL_GAP := 2.0
	const PAD      := 2.0
	const R        := 3.0
	const BY       := -32.0

	var bar_w := max_hp * (CELL_W + CELL_GAP) - CELL_GAP + PAD * 2.0
	var bar_h := CELL_H + PAD * 2.0
	var bx    := -bar_w * 0.5

	# Outer background
	_draw_rrect_filled(Rect2(bx, BY, bar_w, bar_h), R, Color(0.08, 0.08, 0.08))

	# HP cells — filled red, empty dark
	for i in range(max_hp):
		var cx    := bx + PAD + i * (CELL_W + CELL_GAP)
		var color := Color(0.85, 0.10, 0.10) if i < hp else Color(0.18, 0.05, 0.05)
		draw_rect(Rect2(cx, BY + PAD, CELL_W, CELL_H), color)

	# Dividers between cells
	for i in range(1, max_hp):
		var dx := bx + PAD + i * (CELL_W + CELL_GAP) - CELL_GAP * 0.5
		draw_line(Vector2(dx, BY + 1.0), Vector2(dx, BY + bar_h - 1.0),
				  Color(0.05, 0.05, 0.05), 2.0)

	# Border
	_draw_rrect_outline(Rect2(bx, BY, bar_w, bar_h), R, Color(0.50, 0.50, 0.55), 1.5)

func _draw_rrect_filled(rect: Rect2, r: float, color: Color) -> void:
	draw_rect(Rect2(rect.position + Vector2(r, 0.0),
					rect.size    - Vector2(r * 2.0, 0.0)), color)
	draw_rect(Rect2(rect.position + Vector2(0.0, r),
					Vector2(r, rect.size.y - r * 2.0)), color)
	draw_rect(Rect2(rect.position + Vector2(rect.size.x - r, r),
					Vector2(r, rect.size.y - r * 2.0)), color)
	draw_circle(rect.position + Vector2(r,                r),                r, color)
	draw_circle(rect.position + Vector2(rect.size.x - r,  r),                r, color)
	draw_circle(rect.position + Vector2(r,                rect.size.y - r),  r, color)
	draw_circle(rect.position + Vector2(rect.size.x - r,  rect.size.y - r), r, color)

func _draw_rrect_outline(rect: Rect2, r: float, color: Color, width: float) -> void:
	var x1 := rect.position.x;         var y1 := rect.position.y
	var x2 := rect.position.x + rect.size.x; var y2 := rect.position.y + rect.size.y
	draw_line(Vector2(x1 + r, y1), Vector2(x2 - r, y1), color, width)
	draw_line(Vector2(x1 + r, y2), Vector2(x2 - r, y2), color, width)
	draw_line(Vector2(x1, y1 + r), Vector2(x1, y2 - r), color, width)
	draw_line(Vector2(x2, y1 + r), Vector2(x2, y2 - r), color, width)
	draw_arc(Vector2(x1 + r, y1 + r), r, PI,           PI * 1.5, 8, color, width)
	draw_arc(Vector2(x2 - r, y1 + r), r, PI * 1.5,     TAU,      8, color, width)
	draw_arc(Vector2(x2 - r, y2 - r), r, 0.0,          PI * 0.5, 8, color, width)
	draw_arc(Vector2(x1 + r, y2 - r), r, PI * 0.5,     PI,       8, color, width)

func _build_label() -> void:
	name_label          = Label.new()
	name_label.text     = display_label
	name_label.position = Vector2(-5, -14)
	add_child(name_label)

func refresh_hp_bar() -> void:
	queue_redraw()

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
