class_name DecoSystem
extends Node

# ═══════════════════════════════════════════════════════════
#  DecoSystem — quản lý decorations (house, tree, grass, fire)
#  + outline shells + AABB normalize + car ignition.
#  Cần main reference để truy cập tiles, enemies, players, hex_to_world.
# ═══════════════════════════════════════════════════════════

const HexTileScript = preload("res://hextile.gd")

# .glb / .tscn preload cho mỗi key string trong scenario.decorations.
const DECO_SCENES : Dictionary = {
	"house": preload("res://Map/Level Asset/Level 1/House.glb"),
	"tree":  preload("res://Map/Tree.glb"),
	"fire":  preload("res://campfire.tscn"),
}

# Tunables ────────────────────────────────────────────────────
const GRASS_LOD_BIAS         : float = 0.25
const GRASS_VIS_RANGE_END    : float = 30.0
const GRASS_VIS_RANGE_MARGIN : float = 6.0
const GRASS_HEX_FIT_RATIO    : float = 0.85
const TREE_HEX_FIT_RATIO     : float = 0.825
const FIRE_HEX_SIZE_MULT     : float = 0.65

# Cây cố định ở rìa map: row 7 (B,D,F,H,J,L) + row 0 (E,G,I,K).
# Independent of FLOOR_SCENARIOS — luôn rào dọc edge.
const BORDER_TREE_TILES : Array = [
	# Row 7 — top edge
	Vector2i( 1, 7), Vector2i( 3, 7), Vector2i( 5, 7),
	Vector2i( 7, 7), Vector2i( 9, 7), Vector2i(11, 7),
	# Row 0 — bottom edge
	Vector2i( 4, 0), Vector2i( 6, 0), Vector2i( 8, 0), Vector2i(10, 0),
]

# Outline shell (cel-shaded inverted-hull)
const OUTLINE_SHADER       : Shader = preload("res://outline_shell.gdshader")
const OUTLINE_WIDTH        : float  = 0.030
const OUTLINE_NAME_PREFIX  : String = "OutlineShell_"

# Car ignition keyword search
const CAR_KEYWORDS : Array = ["car", "auto", "sedan", "suv", "truck", "vehicle"]

# State ───────────────────────────────────────────────────────
var main : Node = null
var _outline_material  : ShaderMaterial = null
var _deco_prefabs      : Dictionary     = {}    # key → prefab (cached)
var _deco_holder       : Node3D         = null  # hidden parent for prefabs
var _random_used_tiles : Dictionary     = {}    # tile → true (tránh chồng)

func setup(main_ref: Node) -> void:
	main = main_ref

# ═══════════════════════════════════════════════════════════
#  PUBLIC API
# ═══════════════════════════════════════════════════════════

# Spawn decorations từ scenario.decorations array. Gọi 1 lần ở _ready.
func setup_decorations() -> void:
	_ensure_deco_holder()
	var scenario : Dictionary = main._current_scenario()
	var decos : Array = scenario.get("decorations", [])
	for d in decos:
		var key : String = d.get("scene", "")
		if not DECO_SCENES.has(key): continue
		var inst : Node3D
		var s : float = d.get("scale", 1.0)
		if key == "fire":
			# Campfire build mesh+particles trong _ready → KHÔNG duplicate
			# (sẽ build 2 lần). Particles dùng world coords → Node3D scale
			# không ảnh hưởng size emit/quad/light → dùng fire_size_mult.
			inst = DECO_SCENES[key].instantiate() as Node3D
			if inst:
				inst.set("fire_size_mult", s)
			s = 1.0
		else:
			var prefab : Node3D = _get_deco_prefab(key)
			if prefab == null: continue
			inst = prefab.duplicate() as Node3D
		if inst == null: continue
		inst.visible = true
		# Position: ưu tiên "tile": Vector2i(c,r) → world hex; else "pos": Vector3.
		var target_pos : Vector3 = d.get("pos", Vector3.ZERO)
		if d.has("tile"):
			var tk : Vector2i = d.get("tile")
			target_pos = main.hex_to_world(tk.x, tk.y)
			target_pos.y = main.GROUND_Y
		inst.position = target_pos
		inst.scale = Vector3(s, s, s)
		inst.rotation_degrees = Vector3(0, d.get("rot_y_deg", 0.0), 0)
		main.add_child(inst)
		print("[deco] %s spawned at %s (scale=%.3f)" % [key, str(inst.position), s])
		if key == "house":
			# .glb có pivot offset từ Blender → mesh hiển thị lệch scenario
			# pos. Normalize để bottom-center của mesh AABB khớp target.
			normalize_glb_to_target(inst, target_pos)
			_try_ignite_house_car(inst)
	# Grass scatter
	var pct : int = int(scenario.get("grass_scatter_pct", 0))
	if pct > 0:
		_scatter_grass(pct)

# Spawn N cây random trên hex tiles trống. Gọi SAU spawn_enemies.
func scatter_random_trees() -> void:
	var scenario : Dictionary = main._current_scenario()
	var count : int = int(scenario.get("random_trees", 0))
	if count <= 0: return
	var prefab : Node3D = _get_deco_prefab("tree")
	if prefab == null: return
	var bbox : AABB = measure_combined_aabb(prefab)
	var max_dim : float = maxf(bbox.size.x, bbox.size.z)
	if max_dim < 0.001:
		print("[tree] AABB invalid — skip random scatter")
		return
	var fit_scale : float = (HexUtils.HEX_SIZE * 2.0 * TREE_HEX_FIT_RATIO) / max_dim
	var picked : Array = _pick_free_tiles(count)
	for key in picked:
		var inst : Node3D = prefab.duplicate() as Node3D
		if inst == null: continue
		inst.visible = true
		var p : Vector3 = main.hex_to_world(int(key.x), int(key.y))
		p.y = main.GROUND_Y
		inst.position = p
		inst.scale = Vector3(fit_scale, fit_scale, fit_scale)
		inst.rotation_degrees = Vector3(0, randf() * 360.0, 0)
		main.add_child(inst)
		# Mark ô cây là obstacle: BFS + is_valid_and_passable sẽ skip.
		main.tree_tiles[key] = true
	print("[tree] random scatter %d cây (fit_scale=%.3f)" % [picked.size(), fit_scale])

# Cây cố định ở rìa top (BORDER_TREE_TILES). Cùng fit_scale với random
# trees để đồng bộ kích thước. Mark `tree_tiles[key] = true` để random
# scatter sau đó skip & BFS treat as obstacle.
func place_border_trees() -> void:
	var prefab : Node3D = _get_deco_prefab("tree")
	if prefab == null: return
	var bbox : AABB = measure_combined_aabb(prefab)
	var max_dim : float = maxf(bbox.size.x, bbox.size.z)
	if max_dim < 0.001:
		print("[tree/border] AABB invalid — skip")
		return
	var fit_scale : float = (HexUtils.HEX_SIZE * 2.0 * TREE_HEX_FIT_RATIO) / max_dim
	var placed : int = 0
	for key in BORDER_TREE_TILES:
		if not main.tiles.has(key): continue
		if main.tree_tiles.has(key): continue       # đã có cây từ trước
		var inst : Node3D = prefab.duplicate() as Node3D
		if inst == null: continue
		inst.visible = true
		var p : Vector3 = main.hex_to_world(int(key.x), int(key.y))
		p.y = main.GROUND_Y
		inst.position = p
		inst.scale = Vector3(fit_scale, fit_scale, fit_scale)
		inst.rotation_degrees = Vector3(0, randf() * 360.0, 0)
		main.add_child(inst)
		main.tree_tiles[key] = true
		_random_used_tiles[key] = true            # sync để random scatter skip
		placed += 1
	print("[tree/border] %d cây ở edge rows (fit_scale=%.3f)" % [placed, fit_scale])

# Spawn N campfire random trên hex tiles trống. Mỗi instance fresh.
func scatter_random_fires() -> void:
	var scenario : Dictionary = main._current_scenario()
	var count : int = int(scenario.get("random_fires", 0))
	if count <= 0: return
	if not DECO_SCENES.has("fire"): return
	var picked : Array = _pick_free_tiles(count)
	for key in picked:
		var inst : Node3D = DECO_SCENES["fire"].instantiate() as Node3D
		if inst == null: continue
		inst.set("fire_size_mult", FIRE_HEX_SIZE_MULT)
		var p : Vector3 = main.hex_to_world(int(key.x), int(key.y))
		p.y = main.GROUND_Y
		inst.position = p
		main.add_child(inst)
		# Mark ô lửa: đi qua được nhưng bị -1 HP (logic ở main._check_fire_step_*).
		main.fire_pit_tiles[key] = true
	print("[fire] random scatter %d ngọn lửa" % picked.size())

# Inverted-hull outline cho enemies (capsule). Skip skinned meshes (artifact).
func apply_outline_shells_to_entities() -> void:
	for e in main.enemies:
		if is_instance_valid(e):
			_add_outlines_recursive(e)

# Đo combined world AABB. Prefab phải đã trong scene tree.
func measure_combined_aabb(root: Node) -> AABB:
	var collected : Array = []
	_collect_mesh_aabbs(root, collected)
	if collected.is_empty(): return AABB()
	var combined : AABB = collected[0]
	for i in range(1, collected.size()):
		combined = combined.merge(collected[i])
	return combined

# Compensate cho .glb có pivot offset. Yêu cầu inst đã trong tree.
func normalize_glb_to_target(inst: Node3D, target_pos: Vector3) -> void:
	var bbox : AABB = measure_combined_aabb(inst)
	if bbox.size.length_squared() < 0.0001:
		print("[normalize] AABB empty — skip")
		return
	var bottom_center : Vector3 = bbox.position + Vector3(
			bbox.size.x * 0.5, 0.0, bbox.size.z * 0.5)
	var correction : Vector3 = target_pos - bottom_center
	inst.position += correction
	print("[normalize] %s: bbox.pos=%s size=%s correction=%s final=%s" \
			% [inst.name, str(bbox.position), str(bbox.size),
			   str(correction), str(inst.position)])

# ═══════════════════════════════════════════════════════════
#  INTERNAL HELPERS
# ═══════════════════════════════════════════════════════════

func _ensure_deco_holder() -> void:
	if _deco_holder and is_instance_valid(_deco_holder): return
	_deco_holder = Node3D.new()
	_deco_holder.name = "DecoPrefabHolder"
	_deco_holder.visible = false
	main.add_child(_deco_holder)

func _get_deco_prefab(key: String) -> Node3D:
	if _deco_prefabs.has(key):
		return _deco_prefabs[key]
	if not DECO_SCENES.has(key): return null
	var prefab : Node3D = DECO_SCENES[key].instantiate() as Node3D
	if prefab:
		prefab.visible = false
		_deco_holder.add_child(prefab)
	_deco_prefabs[key] = prefab
	return prefab

func _pick_free_tiles(count: int) -> Array:
	if count <= 0: return []
	var occupied : Dictionary = _random_used_tiles.duplicate()
	for pos in main.player_positions:
		occupied[pos] = true
	for e in main.enemies:
		if is_instance_valid(e):
			occupied[Vector2i(e.grid_col, e.grid_row)] = true
	var candidates : Array = []
	for key in main.tiles.keys():
		if main.tiles[key].tile_type != HexTileScript.Type.NORMAL: continue
		if occupied.has(key): continue
		if main.tree_tiles.has(key): continue          # đã có cây border
		if main.fire_pit_tiles.has(key): continue      # đã có lửa
		candidates.append(key)
	candidates.shuffle()
	var picked : Array = candidates.slice(0, mini(count, candidates.size()))
	for k in picked:
		_random_used_tiles[k] = true
	return picked

func _scatter_grass(pct: int) -> void:
	var prefab : Node3D = _get_deco_prefab("grass")
	if prefab == null: return
	var bbox : AABB = measure_combined_aabb(prefab)
	var max_dim : float = maxf(bbox.size.x, bbox.size.z)
	if max_dim < 0.001:
		print("[grass] AABB invalid — skip scatter")
		return
	var fit_scale : float = (HexUtils.HEX_SIZE * 2.0 * GRASS_HEX_FIT_RATIO) / max_dim
	var spawned : int = 0
	for key in main.tiles.keys():
		var tile = main.tiles[key]
		if tile.tile_type != HexTileScript.Type.NORMAL: continue
		if randf() * 100.0 > pct: continue
		var inst : Node3D = prefab.duplicate() as Node3D
		if inst == null: continue
		inst.visible = true
		var p : Vector3 = main.hex_to_world(int(key.x), int(key.y))
		p.y = main.GROUND_Y
		inst.position = p
		inst.scale = Vector3(fit_scale, fit_scale, fit_scale)
		inst.rotation_degrees = Vector3(0, randf() * 360.0, 0)
		_apply_grass_runtime_opts(inst)
		main.add_child(inst)
		spawned += 1
	print("[grass] scattered %d clumps (pct=%d, fit_scale=%.3f)" % [spawned, pct, fit_scale])

func _apply_grass_runtime_opts(node: Node) -> void:
	if node is MeshInstance3D:
		var mi : MeshInstance3D = node
		mi.lod_bias                    = GRASS_LOD_BIAS
		mi.visibility_range_end        = GRASS_VIS_RANGE_END
		mi.visibility_range_end_margin = GRASS_VIS_RANGE_MARGIN
	for c in node.get_children():
		_apply_grass_runtime_opts(c)

func _collect_mesh_aabbs(node: Node, out: Array) -> void:
	if node is MeshInstance3D:
		var mi : MeshInstance3D = node
		out.append(mi.global_transform * mi.get_aabb())
	for c in node.get_children():
		_collect_mesh_aabbs(c, out)

# Outline shell ──────────────────────────────────────────────

func _get_outline_material() -> ShaderMaterial:
	if _outline_material == null:
		_outline_material = ShaderMaterial.new()
		_outline_material.shader = OUTLINE_SHADER
		_outline_material.set_shader_parameter("outline_width", OUTLINE_WIDTH)
		_outline_material.set_shader_parameter("outline_color", Color(0, 0, 0, 1))
	return _outline_material

func _add_outlines_recursive(node: Node) -> void:
	# Skip Skeleton3D subtree — chứa skinned meshes + bone-attached meshes
	# (vd rìu attached via BoneAttachment3D). Inverted-hull artifact trên
	# cả 2 loại — dùng post-process outline thay thế.
	if node is Skeleton3D: return
	if node is MeshInstance3D and not node.name.begins_with(OUTLINE_NAME_PREFIX):
		_add_outline_shell(node)
	# Snapshot children TRƯỚC khi recurse (sibling shell mới add sẽ bị recurse nhầm).
	var kids : Array = node.get_children()
	for c in kids:
		_add_outlines_recursive(c)

func _add_outline_shell(mesh_node: MeshInstance3D) -> void:
	if mesh_node == null or mesh_node.mesh == null: return
	if not mesh_node.visible: return
	# Skip skinned meshes — push along normal bị deform sai khi bone xoay.
	if mesh_node.skeleton != NodePath(""): return
	var parent : Node = mesh_node.get_parent()
	if parent == null: return
	var shell_name : String = OUTLINE_NAME_PREFIX + mesh_node.name
	if parent.has_node(shell_name): return
	var shell := MeshInstance3D.new()
	shell.name             = shell_name
	shell.mesh             = mesh_node.mesh
	shell.material_override = _get_outline_material()
	shell.cast_shadow      = MeshInstance3D.SHADOW_CASTING_SETTING_OFF
	shell.transform        = mesh_node.transform
	if mesh_node.skeleton != NodePath(""):
		shell.skeleton = mesh_node.skeleton
	parent.add_child(shell)

# Car ignition ───────────────────────────────────────────────

func _try_ignite_house_car(house: Node3D) -> void:
	var car : Node3D = _find_node_by_keywords(house, CAR_KEYWORDS)
	if car == null:
		print("[fire/car] không tìm thấy node ô tô — cây node của house:")
		_print_subtree(house, 0)
		return
	var aabb : AABB = measure_combined_aabb(car)
	var max_dim : float = maxf(aabb.size.x, maxf(aabb.size.y, aabb.size.z))
	if max_dim < 0.001:
		print("[fire/car] tìm thấy '%s' nhưng AABB rỗng" % car.name)
		return
	var center : Vector3 = aabb.position + aabb.size * 0.5
	var fire : Node3D = DECO_SCENES["fire"].instantiate() as Node3D
	if fire == null: return
	fire.position = center
	fire.set("fire_size_mult", max_dim * 1.1)
	fire.set("black_smoke",    true)
	fire.set("no_logs",        true)
	main.add_child(fire)
	print("[fire/car] đốt '%s' tại %s, max_dim=%.2f, mult=%.2f" \
			% [car.name, str(center), max_dim, max_dim * 1.1])

func _find_node_by_keywords(root: Node, keywords: Array) -> Node3D:
	var stack : Array = [root]
	while not stack.is_empty():
		var n : Node = stack.pop_back()
		if n is Node3D:
			var nm : String = String(n.name).to_lower()
			for kw in keywords:
				if kw in nm:
					return n
		for c in n.get_children():
			stack.append(c)
	return null

func _print_subtree(node: Node, depth: int) -> void:
	var indent : String = "  ".repeat(depth)
	print("%s%s [%s]" % [indent, node.name, node.get_class()])
	for c in node.get_children():
		_print_subtree(c, depth + 1)
