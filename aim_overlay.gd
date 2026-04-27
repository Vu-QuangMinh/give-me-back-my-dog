extends Node3D
class_name AimOverlay3D

# ═══════════════════════════════════════════════════════════
#  AimOverlay3D — Mốc 8.3 polish
#
#  Vẽ đường preview cho projectile của Mike. Mỗi seg là 1 BoxMesh
#  thin được stretch theo trục X (length = seg length), xoay quanh
#  Y axis để khớp hướng XZ. Seg đầu (direct shot) màu xanh đậm; các
#  seg sau (sau bounce) màu xanh nhạt + thấp alpha.
#
#  Cách dùng:
#    var ovl = AimOverlay3D.new()
#    add_child(ovl)
#    ovl.show_path(segs)   # rebuild visual
#    ovl.clear()           # clear visual nhưng giữ node
#    ovl.queue_free()      # remove khi xong
# ═══════════════════════════════════════════════════════════

const SEG_THICKNESS : float = 0.06
const C_FIRST_SEG   := Color(0.35, 0.65, 1.00, 0.85)
const C_NEXT_SEG    := Color(0.60, 0.80, 1.00, 0.55)

var seg_nodes : Array = []   # Array[MeshInstance3D] — segments hiện đang vẽ

func show_path(segs: Array) -> void:
	clear()
	if segs.is_empty(): return
	for i in range(segs.size()):
		var seg : Array = segs[i]
		if seg.size() < 2: continue
		var s_pos : Vector3 = seg[0]
		var e_pos : Vector3 = seg[1]
		var dir   : Vector3 = e_pos - s_pos
		var seg_len : float = dir.length()
		if seg_len < 0.01: continue
		dir = dir.normalized()

		# BoxMesh stretched dọc trục X local; rotation_y căn theo dir XZ.
		var box_mesh := BoxMesh.new()
		box_mesh.size = Vector3(seg_len, SEG_THICKNESS, SEG_THICKNESS)
		var mi := MeshInstance3D.new()
		mi.mesh = box_mesh
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color = (C_FIRST_SEG if i == 0 else C_NEXT_SEG)
		mi.material_override = mat
		# Midpoint position
		mi.position = (s_pos + e_pos) * 0.5
		# Rotate quanh +Y: angle = atan2(-z, x) để +X local hướng (dir.x, 0, dir.z)
		mi.rotation = Vector3(0.0, atan2(-dir.z, dir.x), 0.0)
		add_child(mi)
		seg_nodes.append(mi)

func clear() -> void:
	for n in seg_nodes:
		if is_instance_valid(n):
			n.queue_free()
	seg_nodes.clear()
