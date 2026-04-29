extends "res://main.gd"

# ═══════════════════════════════════════════════════════════
#  TEST HARNESS — open main_test.tscn and press F6 to run.
#  ► Change ACTIVE_SCENARIO below to pick a scenario.
#  ► Press R in-game to reload the current scenario instantly.
#  ► Floor-clear loops back to the same scenario (no world map).
#
#  GRID: 12 columns (0–11) × 8 rows (0–7), flat-top hex.
#  Players spawn at: Sonny col 2 row 3, Mike col 2 row 4.
#
#  ── SCENARIO FORMAT ────────────────────────────────────────
#  "columns"   : Array[Vector2i]  — impassable pillar tiles
#  "fire_pits" : Array[Vector2i]  — passable fire tiles (deal dmg each turn)
#  "enemies"   : Array[Dict]      — { "type", "col", "row" }
#
#  ── ENEMY TYPES ────────────────────────────────────────────
#  "grunt"     melee, aggressive, 3 HP
#  "archer"    ranged (fires projectile), keeps 2–5 hex range, 2 HP
#  "assassin"  melee, aggressive, dual-bar attack, 2 HP
#  "bomb"      stationary, explodes on death (AOE 2, 2 dmg), 1 HP
#  "dummy"     0 dmg, 999 HP — safe punching bag for mechanic tests
# ═══════════════════════════════════════════════════════════

var ACTIVE_SCENARIO : String = "archer_test"

const SCENARIOS : Dictionary = {
	# ── Minimal starting point ──────────────────────────────
	"basic": {
		"columns":   [Vector2i(5, 4), Vector2i(6, 2)],
		"fire_pits": [],
		"enemies": [
			{ "type": "grunt", "col": 7, "row": 3 },
			{ "type": "grunt", "col": 8, "row": 4 },
		],
	},
	"empty": {
		"columns":   [],
		"fire_pits": [],
		"enemies":   [],
	},

	# ── Enemy type showcases ────────────────────────────────
	"archer_test": {
		"columns":   [Vector2i(5, 4), Vector2i(6, 2)],
		"fire_pits": [],
		"enemies": [
			{ "type": "archer", "col": 9, "row": 2 },
			{ "type": "archer", "col": 10, "row": 5 },
		],
	},
	"assassin_test": {
		"columns":   [],
		"fire_pits": [],
		"enemies": [
			{ "type": "assassin", "col": 7, "row": 3 },
			{ "type": "grunt",    "col": 8, "row": 2 },
		],
	},
	"bomb_test": {
		"columns":   [],
		"fire_pits": [],
		"enemies": [
			{ "type": "bomb",  "col": 6, "row": 3 },
			{ "type": "grunt", "col": 8, "row": 3 },
		],
	},
	"all_types": {
		"columns":   [Vector2i(5, 4), Vector2i(7, 2)],
		"fire_pits": [Vector2i(6, 5)],
		"enemies": [
			{ "type": "grunt",    "col": 7,  "row": 3 },
			{ "type": "archer",   "col": 10, "row": 2 },
			{ "type": "assassin", "col": 9,  "row": 5 },
			{ "type": "bomb",     "col": 6,  "row": 4 },
		],
	},

	# ── Mechanic / ability tests ────────────────────────────
	"dummy_range": {
		"columns":   [Vector2i(5, 3)],
		"fire_pits": [],
		"enemies": [
			{ "type": "dummy", "col": 6,  "row": 2 },
			{ "type": "dummy", "col": 8,  "row": 4 },
			{ "type": "dummy", "col": 10, "row": 3 },
		],
	},
	"grapple_test": {
		"columns":   [Vector2i(7, 3)],
		"fire_pits": [Vector2i(8, 3)],
		"enemies": [
			{ "type": "grunt", "col": 9, "row": 2 },
			{ "type": "grunt", "col": 9, "row": 4 },
		],
	},
	"terrain_test": {
		"columns":   [Vector2i(4, 2), Vector2i(4, 4), Vector2i(6, 3), Vector2i(8, 2), Vector2i(8, 5)],
		"fire_pits": [Vector2i(5, 3), Vector2i(6, 5), Vector2i(7, 4)],
		"enemies": [
			{ "type": "grunt",  "col": 9, "row": 3 },
			{ "type": "archer", "col": 11, "row": 2 },
		],
	},
}

# ═══════════════════════════════════════════════════════════
#  OVERRIDES
# ═══════════════════════════════════════════════════════════

func _setup_demo_columns() -> void:
	var s : Dictionary = _scene()
	for cr in s.get("columns", []):
		if tiles.has(cr):
			tiles[cr].setup(cr.x, cr.y, HexTileScript.Type.COLUMN)
			column_tiles[cr] = true
	for cr in s.get("fire_pits", []):
		if tiles.has(cr):
			tiles[cr].setup(cr.x, cr.y, HexTileScript.Type.FIRE_PIT)
			fire_pit_tiles[cr] = true

func _spawn_enemies() -> void:
	var s : Dictionary = _scene()
	for entry in s.get("enemies", []):
		var key := Vector2i(entry["col"], entry["row"])
		if key in column_tiles: continue
		_spawn_enemy(entry["type"], entry["col"], entry["row"])

func _current_scenario() -> Dictionary:
	return { "name": "TEST: " + ACTIVE_SCENARIO, "is_boss": false }

func _next_floor() -> void:
	_reload()

func _restart_from_floor_zero() -> void:
	_reload()

# ─── R key — reload current scenario ────────────────────────

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo \
			and event.keycode == KEY_R:
		_reload()
		return
	super._input(event)

# ─── Helpers ────────────────────────────────────────────────

func _scene() -> Dictionary:
	return SCENARIOS.get(ACTIVE_SCENARIO, {})

func _reload() -> void:
	if Engine.has_meta("current_floor"):
		Engine.remove_meta("current_floor")
	get_tree().reload_current_scene()
