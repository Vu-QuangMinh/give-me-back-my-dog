class_name HexUtils
extends RefCounted

# ═══════════════════════════════════════════════════════════
#  Hex math utilities — flat-top hex on XZ plane.
#  ► Tất cả functions là static, không state. State (column_tiles,
#    grid bounds, etc.) truyền qua param.
#  ► Cho phép main.gd, enemy.gd, bounce.gd dùng cùng 1 implementation
#    (tránh duplicate hex_dist + get_neighbors trong enemy.gd).
# ═══════════════════════════════════════════════════════════

const HEX_SIZE : float = 1.0

# ─── Conversion ─────────────────────────────────────────────

static func hex_to_world(col: int, row: int, origin: Vector3 = Vector3.ZERO) -> Vector3:
	var x : float = HEX_SIZE * 1.5 * col
	var z : float = HEX_SIZE * sqrt(3.0) * (row + (0.5 if col % 2 == 1 else 0.0))
	return Vector3(x, 0.0, z) + origin

# Tìm hex gần nhất tới world point. Trả Vector2i(-1,-1) nếu quá xa grid.
static func world_to_hex(p: Vector3, grid_cols: int, grid_rows: int,
		origin: Vector3 = Vector3.ZERO) -> Vector2i:
	var best     : Vector2i = Vector2i(-1, -1)
	var best_d2  : float    = INF
	for c in range(grid_cols):
		for r in range(grid_rows):
			var hp : Vector3 = hex_to_world(c, r, origin)
			var dx : float   = p.x - hp.x
			var dz : float   = p.z - hp.z
			var d2 : float   = dx * dx + dz * dz
			if d2 < best_d2:
				best_d2 = d2
				best    = Vector2i(c, r)
	if best_d2 > HEX_SIZE * HEX_SIZE * 1.2:
		return Vector2i(-1, -1)
	return best

# Offset để center grid quanh world origin.
static func grid_center_offset(grid_cols: int, grid_rows: int) -> Vector3:
	var min_p := Vector3(INF, 0.0, INF)
	var max_p := Vector3(-INF, 0.0, -INF)
	for c in range(grid_cols):
		for r in range(grid_rows):
			var p : Vector3 = Vector3(
				HEX_SIZE * 1.5 * c,
				0.0,
				HEX_SIZE * sqrt(3.0) * (r + (0.5 if c % 2 == 1 else 0.0))
			)
			if p.x < min_p.x: min_p.x = p.x
			if p.z < min_p.z: min_p.z = p.z
			if p.x > max_p.x: max_p.x = p.x
			if p.z > max_p.z: max_p.z = p.z
	return -(min_p + max_p) * 0.5

# ─── Distance + line ────────────────────────────────────────

static func hex_dist(c1: int, r1: int, c2: int, r2: int) -> int:
	var a : Vector3i = to_cube(c1, r1)
	var b : Vector3i = to_cube(c2, r2)
	return maxi(maxi(abs(a.x - b.x), abs(a.y - b.y)), abs(a.z - b.z))

# List hex từ (c1,r1) đến (c2,r2) (cả 2 đầu) qua cube interp + round
# với epsilon nudge tránh tie.
static func hex_line(c1: int, r1: int, c2: int, r2: int) -> Array:
	var n : int = hex_dist(c1, r1, c2, r2)
	var path : Array = []
	if n <= 0:
		path.append(Vector2i(c1, r1))
		return path
	var a : Vector3 = to_cube_f(c1, r1)
	var b : Vector3 = to_cube_f(c2, r2)
	a += Vector3(1e-6, 2e-6, -3e-6)
	b += Vector3(1e-6, 2e-6, -3e-6)
	for i in range(n + 1):
		var t : float = float(i) / float(n)
		var rounded : Vector3 = cube_round(a.lerp(b, t))
		path.append(from_cube_f(rounded))
	return path

# ─── Cube coord helpers ─────────────────────────────────────

static func to_cube(col: int, row: int) -> Vector3i:
	var x : int = col
	var z : int = row - (col - (col & 1)) / 2
	return Vector3i(x, -x - z, z)

static func to_cube_f(col: int, row: int) -> Vector3:
	var x : float = float(col)
	var z : float = float(row - (col - (col & 1)) / 2)
	var y : float = -x - z
	return Vector3(x, y, z)

static func from_cube_f(c: Vector3) -> Vector2i:
	var col : int = int(c.x)
	var row : int = int(c.z) + (col - (col & 1)) / 2
	return Vector2i(col, row)

static func cube_round(c: Vector3) -> Vector3:
	var rx : float = round(c.x)
	var ry : float = round(c.y)
	var rz : float = round(c.z)
	var dx : float = abs(rx - c.x)
	var dy : float = abs(ry - c.y)
	var dz : float = abs(rz - c.z)
	if dx > dy and dx > dz:
		rx = -ry - rz
	elif dy > dz:
		ry = -rx - rz
	else:
		rz = -rx - ry
	return Vector3(rx, ry, rz)

# ─── State-dependent (params) ───────────────────────────────

# LOS: chỉ column chặn. Bỏ qua start/end (entity ở 2 đầu hấp thụ projectile).
static func has_line_of_sight(c1: int, r1: int, c2: int, r2: int,
		columns: Dictionary) -> bool:
	var path : Array = hex_line(c1, r1, c2, r2)
	for i in range(1, path.size() - 1):
		if path[i] in columns:
			return false
	return true

static func get_neighbors(col: int, row: int,
		grid_cols: int = -1, grid_rows: int = -1) -> Array:
	var dirs = [[1,0],[-1,0],[0,-1],[0,1],[1,-1],[-1,-1]] if col % 2 == 0 \
			 else [[1,0],[-1,0],[0,-1],[0,1],[1,1],[-1,1]]
	var result : Array = []
	for d in dirs:
		var nc : int = col + d[0]
		var nr : int = row + d[1]
		if grid_cols > 0 and grid_rows > 0:
			if nc < 0 or nc >= grid_cols or nr < 0 or nr >= grid_rows: continue
		result.append(Vector2i(nc, nr))
	return result

static func is_valid_and_passable(col: int, row: int,
		tiles: Dictionary, columns: Dictionary) -> bool:
	var key : Vector2i = Vector2i(col, row)
	if not tiles.has(key):  return false
	if key in columns:      return false
	return true
