extends CanvasLayer
class_name HotkeyPanel

# ═══════════════════════════════════════════════════════════
#  HotkeyPanel — bảng cheat-sheet hotkey ở góc trên-phải.
#  ► CanvasLayer layer = 100 (trên HUD game).
#  ► F1 toggle visible.
#  ► Đặt làm con của PixelateRoot (ngoài SubViewport) → KHÔNG bị
#    pixelate hoặc shader, luôn nét.
# ═══════════════════════════════════════════════════════════

const HOTKEY_LINES : Array[String] = [
	"[b]HOTKEYS[/b]   [color=#aaaaaa](F1 ẩn)[/color]",
	"",
	"[color=#88ccff][b]COMBAT[/b][/color]",
	"[color=#ffd55a]Q[/color]      Primary attack",
	"[color=#ffd55a]W[/color]      Secondary action",
	"[color=#ffd55a]SPACE[/color]  End turn / Dodge / React",
	"[color=#ffd55a]TAB[/color]    Switch character",
	"[color=#ffd55a]U[/color]      Undo move",
	"[color=#ffd55a]K[/color]      Reset turn",
	"[color=#ffd55a]ESC[/color]    Cancel mode / Quit",
	"[color=#ffd55a]LMB[/color]    Move / Attack / Drag bar",
	"[color=#ffd55a]Enter[/color]  Modal callback",
	"",
	"[color=#88ccff][b]CAMERA[/b][/color]",
	"[color=#ffd55a]↑↓←→[/color]   Pan map (yaw-relative)",
	"[color=#ffd55a]RMB[/color]    Drag to orbit",
	"[color=#ffd55a]Wheel[/color]  Zoom in / out",
	"[color=#ffd55a]- / =[/color]  Zoom step",
	"[color=#ffd55a][ / ][/color]  Pitch up / down",
	"",
	"[color=#88ccff][b]DEBUG / FX[/b][/color]",
	"[color=#ffd55a]F1[/color]     Toggle bảng này",
	"[color=#ffd55a]F3[/color]     Toggle pixelate + shader",
	"[color=#ffd55a]F4[/color]     Toggle coord grid",
	"[color=#ffd55a]PgUp[/color]   Pixelate scale +",
	"[color=#ffd55a]PgDn[/color]   Pixelate scale −",
]

func _ready() -> void:
	layer = 100
	_build_panel()

func _build_panel() -> void:
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	panel.offset_left   = -380.0
	panel.offset_top    =  10.0
	panel.offset_right  = -10.0
	panel.offset_bottom =  610.0
	panel.mouse_filter  = Control.MOUSE_FILTER_IGNORE

	var sb := StyleBoxFlat.new()
	sb.bg_color           = Color(0.08, 0.10, 0.15, 0.88)
	sb.border_color       = Color(0.45, 0.65, 0.85, 0.85)
	sb.border_width_left   = 2
	sb.border_width_right  = 2
	sb.border_width_top    = 2
	sb.border_width_bottom = 2
	sb.corner_radius_top_left     = 8
	sb.corner_radius_top_right    = 8
	sb.corner_radius_bottom_left  = 8
	sb.corner_radius_bottom_right = 8
	sb.content_margin_left   = 14
	sb.content_margin_right  = 14
	sb.content_margin_top    = 10
	sb.content_margin_bottom = 10
	panel.add_theme_stylebox_override("panel", sb)

	var label := RichTextLabel.new()
	label.bbcode_enabled = true
	label.fit_content    = true
	label.scroll_active  = false
	label.mouse_filter   = Control.MOUSE_FILTER_IGNORE
	label.text           = "\n".join(HOTKEY_LINES)
	label.custom_minimum_size = Vector2(360, 0)
	label.add_theme_font_size_override("normal_font_size", 18)
	label.add_theme_font_size_override("bold_font_size",   20)
	panel.add_child(label)
	add_child(panel)

func _input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo: return
	if event.keycode == KEY_F1:
		visible = not visible
		get_viewport().set_input_as_handled()
