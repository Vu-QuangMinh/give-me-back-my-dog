extends Node
class_name PixelateRoot

# ═══════════════════════════════════════════════════════════
#  PixelateRoot — lớp phủ pixel-art (SubViewport + downscale)
#
#  Cơ chế:
#  ► main.tscn được instance làm con của SubViewport.
#  ► SubViewportContainer (stretch=true) tự rút SubViewport size về
#    container_size / PIXEL_SCALE (vd 1920×1080 / 2 = 960×540).
#  ► texture_filter = NEAREST trên container → khi upscale lại fullscreen
#    sẽ thấy pixel chunky → artstyle.
#  ► HUD CanvasLayers (HUD / GameHUD / CombatLayer) được reparent ra
#    PixelateRoot ngay sau Main._ready → render full-res root viewport,
#    KHÔNG bị pixelate. Chỉ 3D world bị downscale.
#  ► F3 bật/tắt hiệu ứng (stretch_shrink ↔ 1, filter ↔ LINEAR).
#  ► PageUp / PageDown thay đổi PIXEL_SCALE realtime (2..8).
# ═══════════════════════════════════════════════════════════

const PIXEL_SCALE_DEFAULT : int = 2
const PIXEL_SCALE_MIN     : int = 1   # 1 = no pixelate (xem 3D gốc)
const PIXEL_SCALE_MAX     : int = 8

@onready var container : SubViewportContainer = $SubViewportContainer
@onready var sub       : SubViewport          = $SubViewportContainer/SubViewport

var enabled     : bool = true
var pixel_scale : int  = PIXEL_SCALE_DEFAULT

func _ready() -> void:
	_apply_settings()
	get_window().size_changed.connect(_apply_settings)
	# Defer reparent: chờ Main._ready chạy xong (bắt @onready references)
	# rồi promote HUD CanvasLayers ra ngoài SubViewport → render ở
	# root viewport full-res, không bị pixelate.
	call_deferred("_promote_hud_to_root")

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
	container.stretch        = true
	container.stretch_shrink = pixel_scale if enabled else 1
	# NEAREST chỉ khi thực sự downscale (scale > 1). scale=1 hoặc disabled
	# → LINEAR, hiển thị model 3D gốc không bị chunky.
	if enabled and pixel_scale > 1:
		container.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	else:
		container.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	# SubViewportContainer.stretch tự cập nhật SubViewport.size, nhưng
	# call thủ công cho chắc khi đổi stretch_shrink runtime.
	if sub:
		var win_size : Vector2i = get_window().size
		var sh : int = container.stretch_shrink
		sub.size = Vector2i(maxi(1, win_size.x / sh), maxi(1, win_size.y / sh))

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
