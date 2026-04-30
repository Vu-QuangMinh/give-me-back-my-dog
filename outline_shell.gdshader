shader_type spatial;

// ═══════════════════════════════════════════════════════════
//  Outline shell — inverted-hull technique cel-shaded.
//  ► render_mode cull_front: chỉ render BACK faces của shell
//    (front bị cull) → từ camera, shell hiện ra ở viền vì
//    front-faces của original mesh ở gần hơn, che hết phần shell
//    bên trong.
//  ► VERTEX += NORMAL * width: push từng vertex ra ngoài theo
//    pháp tuyến → shell to hơn original 1 chút → "thừa" ở viền.
//  ► unshaded: shell luôn đen, không bị light ảnh hưởng.
//  ► Dùng làm material_override cho MeshInstance3D shell — sibling
//    của mesh gốc, copy mesh resource + skeleton path để follow
//    animation (skinning).
// ═══════════════════════════════════════════════════════════

render_mode unshaded, cull_front, depth_draw_opaque;

uniform float outline_width : hint_range(0.0, 0.2) = 0.025;
uniform vec4  outline_color : source_color         = vec4(0.0, 0.0, 0.0, 1.0);

void vertex() {
	VERTEX += NORMAL * outline_width;
}

void fragment() {
	ALBEDO = outline_color.rgb;
	ALPHA  = outline_color.a;
}
