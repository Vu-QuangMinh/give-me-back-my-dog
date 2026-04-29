extends "res://main.gd"

# ═══════════════════════════════════════════════════════════
#  TEST HARNESS — run main_test.tscn with F6
#  ► Edit ACTIVE_SCENARIO to pick a scenario.
#  ► Press R in-game to reload the current scenario instantly.
#  ► Floor-clear stays in scene (no world-map transition).
# ═══════════════════════════════════════════════════════════

# ─── Set this to switch scenarios ───────────────────────────
var ACTIVE_SCENARIO : String = "basic"

# ─── Scenario definitions ───────────────────────────────────
# Each entry can have:
#   "columns" : Array[Vector2i]  — column tile positions
#   "enemies" : Array[Dict]      — { "type": String, "col": int, "row": int }
#   Enemy types: "grunt", "archer", "assassin", "bomb", "dummy"
const SCENARIOS : Dictionary = {
	"basic": {
		"columns": [],
		"enemies": [
			{ "type": "grunt", "col": 7, "row": 3 },
			{ "type": "grunt", "col": 8, "row": 4 },
		],
	},
	"bomb_test": {
		"columns": [],
		"enemies": [
			{ "type": "dummy", "col": 6, "row": 3 },
			{ "type": "dummy", "col": 7, "row": 2 },
		],
	},
	"archer_test": {
		"columns": [Vector2i(5, 4)],
		"enemies": [
			{ "type": "archer", "col": 9, "row": 2 },
			{ "type": "archer", "col": 10, "row": 5 },
		],
	},
	"assassin_test": {
		"columns": [],
		"enemies": [
			{ "type": "assassin", "col": 7, "row": 3 },
			{ "type": "grunt",    "col": 8, "row": 2 },
		],
	},
	"all_types": {
		"columns": [Vector2i(5, 4), Vector2i(7, 2)],
		"enemies": [
			{ "type": "grunt",    "col": 7, "row": 3 },
			{ "type": "archer",   "col": 10, "row": 2 },
			{ "type": "assassin", "col": 9, "row": 5 },
			{ "type": "dummy",    "col": 6, "row": 4 },
		],
	},
	"empty": {
		"columns": [],
		"enemies": [],
	},
}

# ═══════════════════════════════════════════════════════════
#  OVERRIDES
# ═══════════════════════════════════════════════════════════

func _setup_demo_columns() -> void:
	var s : Dictionary = _scene()
	if not s.has("columns"): return
	for cr in s["columns"]:
		if tiles.has(cr):
			tiles[cr].setup(cr.x, cr.y, HexTileScript.Type.COLUMN)
			column_tiles[cr] = true

func _spawn_enemies() -> void:
	var s : Dictionary = _scene()
	if not s.has("enemies"): return
	for entry in s["enemies"]:
		var key := Vector2i(entry["col"], entry["row"])
		if key in column_tiles: continue
		_spawn_enemy(entry["type"], entry["col"], entry["row"])

func _current_scenario() -> Dictionary:
	return { "name": "TEST: " + ACTIVE_SCENARIO, "is_boss": false }

# Floor clear / game over → reload scenario instead of transitioning.
func _next_floor() -> void:
	_reload()

func _restart_from_floor_zero() -> void:
	_reload()

# ─── R key ──────────────────────────────────────────────────

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
