extends "res://main.gd"

# ═══════════════════════════════════════════════════════════════════════════════
#  TEST HARNESS
#
#  Setup: duplicate main.tscn → rename main_test.tscn → swap script to main_test.gd.
#  Run main_test.tscn directly (Scene → Run Current Scene, or F6).
#  Press R at any time to restart the current scenario.
#
#  To switch scenarios: change ACTIVE_SCENARIO to any key from SCENARIOS below.
#  To add a scenario:   add a new entry to SCENARIOS and set ACTIVE_SCENARIO.
# ═══════════════════════════════════════════════════════════════════════════════

# ── Active scenario ───────────────────────────────────────────────────────────
const ACTIVE_SCENARIO := "archer_test"

# ── Scenario definitions ──────────────────────────────────────────────────────
#
#  Each entry supports these optional keys:
#
#  "columns" : [[col, row], ...]
#      Impassable column obstacles placed on the grid.
#
#  "players" : {"Sonny": [col, row], "Mike": [col, row]}
#      Override starting positions. Omit to use preset defaults (Sonny 5,1 / Mike 6,1).
#
#  "hp" : {"Sonny": int, "Mike": int}
#      Override max HP for a player (also sets current HP to match).
#
#  "enemies" : [{"type": str, "col": int, "row": int}, ...]
#      Enemy types: "grunt", "archer", "assassin", "bomb", "dummy"

const SCENARIOS := {
	"two_grunts": {
		"enemies": [
			{"type": "grunt", "col": 3, "row": 4},
			{"type": "grunt", "col": 8, "row": 3},
		],
	},

	"archer_test": {
		"columns": [[6, 3], [6, 4], [6, 5]],
		"enemies": [
			{"type": "archer", "col": 3, "row": 3},
			{"type": "grunt", "col": 2, "row": 3},
			{"type": "archer", "col": 3, "row": 7},
		],
	},

	"assassin_flanked": {
		"players": {"Sonny": [5, 4], "Mike": [6, 4]},
		"enemies": [
			{"type": "assassin", "col": 2, "row": 2},
			{"type": "assassin", "col": 9, "row": 6},
			{"type": "grunt",    "col": 5, "row": 7},
		],
	},

	"bomb_room": {
		"enemies": [
			{"type": "bomb",  "col": 5, "row": 5},
			{"type": "grunt", "col": 8, "row": 3},
			{"type": "grunt", "col": 3, "row": 6},
		],
	},

	"dummy_range": {
		"enemies": [
			{"type": "dummy", "col": 5, "row": 6},
			{"type": "dummy", "col": 7, "row": 5},
			{"type": "dummy", "col": 3, "row": 5},
			{"type": "dummy", "col": 6, "row": 7},
		],
	},

	"full_gauntlet": {
		"columns": [[4, 3], [7, 4], [5, 6]],
		"enemies": [
			{"type": "grunt",    "col": 2, "row": 2},
			{"type": "archer",   "col": 9, "row": 2},
			{"type": "assassin", "col": 9, "row": 6},
			{"type": "bomb",     "col": 5, "row": 7},
		],
	},
}

# ─────────────────────────────────────────────────────────────────────────────

var _scenario_label : Label = null

func _ready() -> void:
	# Skip world_map state entirely — testing is always a fresh start
	minutes_left = 999

	_build_grid()
	_compute_grid_bounds()
	_apply_test_columns()
	_spawn_players()
	_spawn_enemies()
	_build_ui()
	_add_scenario_label()
	_update_valid_moves()
	_refresh_tile_colors()
	_refresh_ui()
	_save_turn_snapshot()

	aim_overlay = Node2D.new()
	aim_overlay.set_script(AimOverlayScript)
	aim_overlay.z_as_relative = false
	aim_overlay.z_index = 100
	add_child(aim_overlay)

# Place column tiles listed in the active scenario
func _apply_test_columns() -> void:
	for cr in SCENARIOS[ACTIVE_SCENARIO].get("columns", []):
		var key = Vector2i(cr[0], cr[1])
		if tiles.has(key):
			tiles[key].setup(cr[0], cr[1], HexTileScript.Type.COLUMN)
			column_tiles[key] = tiles[key]

# Spawn players, optionally at scenario-defined positions / HP
func _spawn_players() -> void:
	var pos_overrides : Dictionary = SCENARIOS[ACTIVE_SCENARIO].get("players", {})
	var hp_overrides  : Dictionary = SCENARIOS[ACTIVE_SCENARIO].get("hp",      {})
	var offset = _grid_center_offset()
	for preset_name in PlayerScript.PLAYER_ORDER:
		var p = PlayerScenes[preset_name].instantiate()
		add_child(p)
		p.setup_from_preset(preset_name)
		if pos_overrides.has(preset_name):
			var cr       = pos_overrides[preset_name]
			p.grid_col   = cr[0]
			p.grid_row   = cr[1]
		if hp_overrides.has(preset_name):
			p.hp     = hp_overrides[preset_name]
			p.max_hp = hp_overrides[preset_name]
		player_names.append(preset_name)
		player_positions.append(Vector2i(p.grid_col, p.grid_row))
		p.position = _hex_to_pixel(p.grid_col, p.grid_row) + offset
		players.append(p)

# Spawn exactly the enemies listed in the active scenario
func _spawn_enemies() -> void:
	for entry in SCENARIOS[ACTIVE_SCENARIO].get("enemies", []):
		_spawn_enemy(entry["type"], entry["col"], entry["row"])

# Floor cleared: stay in this scene instead of jumping to the world map
func _on_floor_cleared() -> void:
	if floor_cleared: return
	floor_cleared = true
	sonny_w_used  = false
	mike_w_uses   = 1
	mike_caught_projectiles.clear()
	if sonny_bomb_enemy != null and sonny_bomb_enemy in enemies:
		enemies.erase(sonny_bomb_enemy)
		sonny_bomb_enemy.queue_free()
		sonny_bomb_enemy = null
	for p in players:
		p.floor_cleared = true
	phase = Phase.PLAYER_TURN
	_update_valid_moves()
	_refresh_tile_colors()
	_spawn_float_text(
		get_viewport_rect().size / 2.0 + Vector2(-130, -40),
		"CLEARED!  Press R to restart",
		Color(0.4, 1.0, 0.5)
	)
	_refresh_ui()

# Block the world-map navigation entirely
func _go_to_world_map() -> void:
	pass

# Corner label showing which scenario is loaded
func _add_scenario_label() -> void:
	var vp = get_viewport_rect().size
	_scenario_label          = Label.new()
	_scenario_label.text     = "TEST: " + ACTIVE_SCENARIO
	_scenario_label.position = Vector2(vp.x - 240, 10)
	_scenario_label.modulate = Color(1.0, 0.6, 0.2)
	add_child(_scenario_label)

# R restarts the test scene; everything else falls through to main.gd's handler
func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_R:
		get_tree().reload_current_scene()
		return
	super._input(event)
