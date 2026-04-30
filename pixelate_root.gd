extends Node
class_name PixelateRoot

# ═══════════════════════════════════════════════════════════
#  PixelateRoot — lớp phủ pixel-art (SubViewport + downscale + shader)
#
#  Cơ chế:
#  ► main.tscn được instance làm con của SubViewport.
#  ► SubViewportContainer (stretch=true) tự rút SubViewport size về
#    container_size / PIXEL_SCALE (vd 1920×1080 / 2 = 960×540).
#  ► texture_filter = NEAREST trên container → upscale chunky.
#  ► pixel_post.gdshader applied lên SubViewportContainer:
#    - Palette limitation (6 levels/channel = 216 màu)
#    - Outline (Sobel-lite, 1 SubViewport-pixel thick)
#  ► AA HOÀN TOÀN OFF trên SubViewport (msaa_3d / screen_space_aa /
#    use_taa) → cạnh sắc, không blur khi xen kẽ với pixelate.
#  ► HUD CanvasLayers (HUD / GameHUD / CombatLayer) reparent ra
#    PixelateRoot → render root viewport full-res, KHÔNG bị shader/
#    pixelate ảnh hưởng.
#  ► F3 bật/tắt fx_active (NEAREST + shader). Khi OFF hoặc scale=1
#    → 3D gốc (LINEAR + material null).
#  ► PageUp / PageDown thay đổi PIXEL_SCALE realtime (1..8).
# ═══════════════════════════════════════════════════════════

const PIXEL_SCALE_DEFAULT : int = 1   # 1 = nấc 0 = no pixelate (3D gốc)
const PIXEL_SCALE_MIN     : int = 1
const PIXEL_SCALE_MAX     : int = 8

# Post-process shader (palette + outline) — chỉ apply lên SubViewportContainer
# nên HUD (đã promote ra ngoài) không bị ảnh hưởng. Bypass khi enabled=false.
const POST_SHADER_PATH : String = "res://pixel_post.gdshader"

@onready var container : SubViewportContainer = $SubViewportContainer
@onready var sub       : SubViewport          = $SubViewportContainer/SubViewport

var enabled         : bool           = true
var pixel_scale     : int            = PIXEL_SCALE_DEFAULT
var post_shader_mat : ShaderMaterial = null

func _ready() -> void:
	print("[PixelateRoot] _ready — scene đang chạy là pixelate_root.tscn ✓")
	_setup_post_shader()
	_disable_aa()
	_apply_settings()
	get_window().size_changed.connect(_apply_settings)
	_spawn_hotkey_panel()
	print("[PixelateRoot] init xong: scale=%d enabled=%s shader=%s" \
			% [pixel_scale, str(enabled), str(post_shader_mat != null)])
	# Defer reparent: chờ Main._ready chạy xong (bắt @onready references)
	# rồi promote HUD CanvasLayers ra ngoài SubViewport → render ở
	# root viewport full-res, không bị pixelate.
	call_deferred("_promote_hud_to_root")

func _spawn_hotkey_panel() -> void:
	var script : Script = load("res://hotkey_panel.gd")
	if script == null: return
	var panel := CanvasLayer.new()
	panel.set_script(script)
	panel.name = "HotkeyPanel"
	add_child(panel)

func _setup_post_shader() -> void:
	var sh : Shader = load(POST_SHADER_PATH)
	if sh == null:
		push_warning("[PixelateRoot] missing post shader at %s" % POST_SHADER_PATH)
		return
	post_shader_mat = ShaderMaterial.new()
	post_shader_mat.shader = sh
	# Default tuning — adjust as needed.
	post_shader_mat.set_shader_parameter("palette_levels",    6.0)
	# Outline mỏng + chỉ ở edge mạnh + xám đậm thay đen tuyền:
	post_shader_mat.set_shader_parameter("outline_thickness", 0.7)            # ↓ từ 1.0
	post_shader_mat.set_shader_parameter("outline_threshold", 0.40)            # ↑ từ 0.25 → ít pixel qualify
	post_shader_mat.set_shader_parameter("outline_color",     Vector3(0.15, 0.15, 0.15))  # xám đậm thay (0,0,0)
	post_shader_mat.set_shader_parameter("enable_outline",    true)
	post_shader_mat.set_shader_parameter("enable_palette",    true)

# Tắt AA hoàn toàn cho 3D scene trong SubViewport. HUD ngoài SubViewport
# vẫn theo project default — không ảnh hưởng.
func _disable_aa() -> void:
	if sub == null: return
	sub.msaa_3d         = Viewport.MSAA_DISABLED
	sub.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	sub.use_taa         = false

func _promote_hud_to_root() -> void:
	var main_node : Node = sub.get_node_or_null("Main")
	if main_node == null: return
	# Snapshot trước khi reparent vì reparent thay đổi get_children().
	var to_move : Array = []
	for child in main_node.get_children():
		if child is CanvasLayer:
			to_move.append(child)
	for cl in to_move:
		cl.reparent(self)

func _apply_settings() -> void:
	if container == null: return
	# fx_active: pixelate scale > 1 và toggle ON → bật toàn bộ retro look
	# (NEAREST + palette + outline). Khi off hoặc scale=1 → 3D gốc.
	var fx_active : bool = enabled and pixel_scale > 1
	container.stretch        = true
	container.stretch_shrink = pixel_scale if enabled else 1
	container.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST if fx_active \
			else CanvasItem.TEXTURE_FILTER_LINEAR
	# Apply / bypass post-shader theo fx_active. Bypass = material null
	# (zero overhead, không qua shader).
	container.material = post_shader_mat if fx_active else null
	# SubViewportContainer.stretch tự cập nhật SubViewport.size, nhưng
	# call thủ công cho chắc khi đổi stretch_shrink runtime.
	if sub:
		var win_size : Vector2i = get_window().size
		var sh : int = container.stretch_shrink
		sub.size = Vector2i(maxi(1, win_size.x / sh), maxi(1, win_size.y / sh))
		print("[PixelateRoot] window=%s sub=%s shrink=%d filter=%d material=%s" \
				% [str(win_size), str(sub.size), sh,
				   container.texture_filter, str(container.material != null)])

func _input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_F3:
			enabled = not enabled
			_apply_settings()
			print("[Pixelate] enabled=", enabled, " scale=", pixel_scale)
			get_viewport().set_input_as_handled()
		KEY_PAGEUP:
			pixel_scale = mini(PIXEL_SCALE_MAX, pixel_scale + 1)
			_apply_settings()
			print("[Pixelate] scale=", pixel_scale)
			get_viewport().set_input_as_handled()
		KEY_PAGEDOWN:
			pixel_scale = maxi(PIXEL_SCALE_MIN, pixel_scale - 1)
			_apply_settings()
			print("[Pixelate] scale=", pixel_scale)
			get_viewport().set_input_as_handled()
