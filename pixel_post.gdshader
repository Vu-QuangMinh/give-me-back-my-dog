shader_type canvas_item;

// ═══════════════════════════════════════════════════════════
//  Post-process shader cho SubViewportContainer (chỉ ảnh hưởng
//  3D scene, KHÔNG ảnh hưởng HUD vì HUD nằm ngoài SubViewport).
//
//  Combo 2 hiệu ứng:
//  ► Outline (Sobel-lite): so 4 neighbor (N/S/E/W) trong TEXTURE
//    space (= SubViewport pixel), max-diff vượt threshold → vẽ
//    pixel outline_color. Outline dày 1 SubViewport-pixel → khi
//    upscale NEAREST sẽ thành N screen-pixel theo pixel_scale.
//  ► Palette limitation: quantize từng channel RGB về N levels
//    (palette_levels = 6 → 6³ = 216 màu, retro feel).
//
//  Bypass: khi enable_outline / enable_palette = false thì pass
//  through nguyên màu gốc.
// ═══════════════════════════════════════════════════════════

uniform float palette_levels    : hint_range(2.0, 32.0) = 6.0;
uniform float outline_thickness : hint_range(0.0, 4.0)  = 1.0;
uniform vec3  outline_color     : source_color          = vec3(0.0);
uniform float outline_threshold : hint_range(0.0, 1.0)  = 0.20;
uniform bool  enable_outline                            = true;
uniform bool  enable_palette                            = true;

void fragment() {
	vec4 base = texture(TEXTURE, UV);
	vec3 result = base.rgb;
	bool is_outline = false;

	// Outline detection (Sobel-lite 4 neighbors)
	if (enable_outline) {
		vec2 px = TEXTURE_PIXEL_SIZE * outline_thickness;
		vec3 cN = texture(TEXTURE, UV + vec2(0.0, -px.y)).rgb;
		vec3 cS = texture(TEXTURE, UV + vec2(0.0,  px.y)).rgb;
		vec3 cE = texture(TEXTURE, UV + vec2( px.x, 0.0)).rgb;
		vec3 cW = texture(TEXTURE, UV + vec2(-px.x, 0.0)).rgb;
		float dN = length(cN - base.rgb);
		float dS = length(cS - base.rgb);
		float dE = length(cE - base.rgb);
		float dW = length(cW - base.rgb);
		float diff = max(max(dN, dS), max(dE, dW));
		if (diff > outline_threshold) {
			result     = outline_color;
			is_outline = true;
		}
	}

	// Palette quantization (skip nếu pixel là outline)
	if (enable_palette && !is_outline) {
		result = floor(result * palette_levels + 0.5) / palette_levels;
	}

	COLOR = vec4(result, base.a);
}
