extends Polygon2D

# ═══════════════════════════════════════════════
#  TILE TYPE
# ═══════════════════════════════════════════════

enum Type { NORMAL, COLUMN, FIRE_PIT }
var tile_type : Type = Type.NORMAL
var passable  : bool = true

var grid_col : int = 0
var grid_row : int = 0

# ═══════════════════════════════════════════════
#  COLORS
# ═══════════════════════════════════════════════

const COLOR_NORMAL   = Color(0.14, 0.12, 0.20)
const COLOR_HOVER    = Color(0.24, 0.22, 0.36)
const COLOR_SELECTED = Color(0.35, 0.63, 0.55)
const COLOR_VALID    = Color(0.16, 0.35, 0.31)
const COLOR_ENEMY    = Color(0.24, 0.08, 0.08)
const COLOR_ATTACK   = Color(0.47, 0.12, 0.12)
const COLOR_COLUMN   = Color(0.30, 0.27, 0.40)
const COLOR_FIRE_PIT = Color(0.55, 0.22, 0.05)

const HEX_SIZE = 38.0

# ═══════════════════════════════════════════════
#  SETUP
# ═══════════════════════════════════════════════

func setup(col: int, row: int, type: Type = Type.NORMAL) -> void:
	grid_col  = col
	grid_row  = row
	tile_type = type
	# Columns are impassable. Fire pits are passable (deal damage on entry).
	passable  = (type != Type.COLUMN)
	polygon   = _build_hex_polygon()
	_apply_base_color()

func _build_hex_polygon() -> PackedVector2Array:
	var points = PackedVector2Array()
	for i in range(6):
		var angle = deg_to_rad(60.0 * i)
		points.append(Vector2(cos(angle), sin(angle)) * HEX_SIZE)
	return points

func _apply_base_color() -> void:
	match tile_type:
		Type.NORMAL:   color = COLOR_NORMAL
		Type.COLUMN:   color = COLOR_COLUMN
		Type.FIRE_PIT: color = COLOR_FIRE_PIT

# ═══════════════════════════════════════════════
#  STATE (called by Main each frame)
# ═══════════════════════════════════════════════

func set_state(state: String) -> void:
	# Hazard tiles always keep their identity color
	if tile_type == Type.COLUMN or tile_type == Type.FIRE_PIT:
		_apply_base_color()
		return

	match state:
		"normal":   color = COLOR_NORMAL
		"hover":    color = COLOR_HOVER
		"selected": color = COLOR_SELECTED
		"valid":    color = COLOR_VALID
		"enemy":    color = COLOR_ENEMY
		"attack":   color = COLOR_ATTACK
		"ladder":   color = Color(0.25, 0.45, 0.18)   # green-brown
		_:          color = COLOR_NORMAL
