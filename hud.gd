extends CanvasLayer
class_name GameHUD

# ═══════════════════════════════════════════════════════════════
#  HUD — Mốc 5
#  ► Hiển thị: avatar 2 nhân vật, HP bar (head/mid/end + gem),
#    HYPE bar dọc smooth fill, 4 item slot mỗi nhân vật, status
#    icon emoji tạm, dialogue scroll, enemy panel động, 4 nút.
#  ► Public API gọi từ main.gd. Combat-driven update chờ Mốc 6+.
# ═══════════════════════════════════════════════════════════════

signal backpack_pressed
signal undo_pressed
signal reset_pressed
signal end_turn_pressed
# Mốc 7+: click avatar HUD → switch sang nhân vật đó
signal player_avatar_clicked(char_name: String)

# ─── Asset preloads ──────────────────────────────────────────
const TEX_HP_HEAD     := preload("res://CharacterAsset/HUD/panel/hp_head.png")
const TEX_HP_MID      := preload("res://CharacterAsset/HUD/panel/hp_mid.png")
const TEX_HP_END      := preload("res://CharacterAsset/HUD/panel/hp_end.png")
const TEX_GEM_RED     := preload("res://CharacterAsset/HUD/panel/gem_red.png")
const TEX_GEM_PURPLE  := preload("res://CharacterAsset/HUD/panel/gem_purple.png")
const TEX_SLOT        := preload("res://CharacterAsset/HUD/panel/slot.png")
const TEX_HYPE_EMPTY  := preload("res://CharacterAsset/HUD/panel/hype_empty.png")
const TEX_FRAME_SONNY := preload("res://CharacterAsset/HUD/panel/avatar_frame_sonny.png")
const TEX_FRAME_MIKE  := preload("res://CharacterAsset/HUD/panel/avatar_frame_mike.png")
const TEX_AVATAR_SONNY := preload("res://CharacterAsset/HUD/avatar/sonny.png")
const TEX_AVATAR_MIKE  := preload("res://CharacterAsset/HUD/avatar/mike.png")
const FONT_NORMAL     := preload("res://CharacterAsset/HUD/font/Good Old DOS.ttf")
const FONT_ENEMY      := preload("res://CharacterAsset/HUD/font/Good Old DOS Distorted.ttf")

# ─── Color scheme (per design 2026-04-28) ────────────────────
const COLOR_SONNY := Color(0.85, 0.20, 0.20)
const COLOR_MIKE  := Color(0.25, 0.55, 0.95)
const COLOR_ENEMY := Color(0.62, 0.30, 0.85)

# ─── Layout constants ────────────────────────────────────────
const AVATAR_SIZE         : Vector2 = Vector2(109, 130)
const SLOT_SIZE           : Vector2 = Vector2(44, 47)
const SLOTS_PER_CHAR      : int     = 2
const HP_HEIGHT           : float   = 26.0
const ENEMY_HP_HEIGHT     : float   = 18.0
const GEM_HEIGHT          : float   = 16.0
# Gem texture aspect ≈ 1.67:1. Tỉ lệ rect (theo bar_h) khớp với aspect tự nhiên
# để STRETCH_SCALE không bóp méo. Đều nhau ở mọi slot.
const GEM_W_FRAC          : float   = 0.78
const GEM_H_FRAC          : float   = 0.47
# Vị trí center của socket trong từng loại slot (theo % chiều rộng tile).
const HEAD_SOCKET_CENTER  : float   = 0.76    # head: socket nằm bên phải sau "HP"
const MID_SOCKET_CENTER   : float   = 0.50    # mid: socket centered
const END_SOCKET_CENTER   : float   = 0.40    # end: socket lệch trái do cap cong bên phải
const NAME_FONT_SIZE      : int     = 21
const STATUS_FONT_SIZE    : int     = 18
const DIALOGUE_FONT_SIZE  : int     = 14
const HP_LABEL_FONT_SIZE  : int     = 16
const ENEMY_AVATAR_SIZE   : Vector2 = Vector2(94, 109)
const ENEMY_TYPE_FONT_SIZE : int    = 39

# Tube area inside hype_empty.png — relative to texture (282×854)
const HYPE_TUBE_REL := Rect2(0.395, 0.045, 0.21, 0.575)

# Tween for HYPE smooth fill animation
const HYPE_TWEEN_TIME : float = 0.35

# ─── Node refs ───────────────────────────────────────────────
@onready var _player_inner : Control       = $Root/PlayerPanel/PlayerInner
@onready var _enemy_inner  : HBoxContainer = $Root/EnemyPanel/EnemyInner
@onready var _btn_backpack : TextureButton = $Root/ButtonRow/BackpackBtn
@onready var _btn_undo     : TextureButton = $Root/ButtonRow/UndoBtn
@onready var _btn_reset    : TextureButton = $Root/ButtonRow/ResetBtn
@onready var _btn_endturn  : TextureButton = $Root/ButtonRow/EndTurnBtn
@onready var _dialogue_text : RichTextLabel = $Root/DialogueRect/DialogueText

# ─── Per-character block refs ────────────────────────────────
# blocks[char_name] -> Dictionary { ... see _make_player_block ... }
var _blocks : Dictionary = {}

# ─── Enemy block refs (id is arbitrary int from main.gd) ─────
var _enemy_blocks : Dictionary = {}

# ─── HYPE bar widget (built in code) ─────────────────────────
var _hype_bg       : TextureRect = null
var _hype_fill_clip : Control    = null
var _hype_fill_tex  : TextureRect = null
var _hype_value     : float      = 0.0
var _hype_tween     : Tween      = null

# ═══════════════════════════════════════════════════════════════
#  LIFECYCLE
# ═══════════════════════════════════════════════════════════════

func _ready() -> void:
	_btn_backpack.pressed.connect(func(): emit_signal("backpack_pressed"))
	_btn_undo.pressed.connect(func():     emit_signal("undo_pressed"))
	_btn_reset.pressed.connect(func():    emit_signal("reset_pressed"))
	_btn_endturn.pressed.connect(func():  emit_signal("end_turn_pressed"))

	# Dialogue defaults
	_dialogue_text.add_theme_font_override("normal_font", FONT_NORMAL)
	_dialogue_text.add_theme_font_size_override("normal_font_size", DIALOGUE_FONT_SIZE)
	clear_dialogue()

	_build_player_blocks()

# ═══════════════════════════════════════════════════════════════
#  PUBLIC API — chamado từ main.gd
# ═══════════════════════════════════════════════════════════════

# Sonny / Mike
func register_player(char_name: String, current_hp: int, max_hp: int, items: Array = []) -> void:
	if not _blocks.has(char_name): return
	set_hp(char_name, current_hp, max_hp)
	for i in range(min(items.size(), SLOTS_PER_CHAR)):
		set_item(char_name, i, items[i])
	# Clear unused slots
	for i in range(items.size(), SLOTS_PER_CHAR):
		set_item(char_name, i, null)

func set_hp(char_name: String, current_hp: int, max_hp: int) -> void:
	if not _blocks.has(char_name): return
	_render_hp_bar(_blocks[char_name], current_hp, max_hp)

func set_actions(char_name: String, actions_left: int, actions_per_turn: int) -> void:
	if not _blocks.has(char_name): return
	var lbl : Label = _blocks[char_name]["status_label"]
	# Tạm dùng emoji: 🪽 = 1 action còn, ⚔️ chỉ thị có thể attack
	# Đơn giản: hiện số action còn dạng "🪽 N/M"
	lbl.text = "🪽 %d/%d" % [actions_left, actions_per_turn]

func set_active(char_name: String, is_active: bool) -> void:
	if not _blocks.has(char_name): return
	var name_lbl : Label = _blocks[char_name]["name_label"]
	# Active: chữ in đậm và có "▶" prefix
	if is_active:
		name_lbl.text = "▶ " + char_name.to_upper()
	else:
		name_lbl.text = char_name.to_upper()

# item: Texture2D hoặc null để clear
func set_item(char_name: String, slot_idx: int, item_tex) -> void:
	if not _blocks.has(char_name): return
	var slots : Array = _blocks[char_name]["item_slots"]
	if slot_idx < 0 or slot_idx >= slots.size(): return
	var icon : TextureRect = slots[slot_idx]["icon"]
	if item_tex == null:
		icon.texture = null
	else:
		icon.texture = item_tex

# ─── HYPE ────────────────────────────────────────────────────

# value 0.0 → 1.0
func set_hype(value: float, animate: bool = true) -> void:
	value = clampf(value, 0.0, 1.0)
	if _hype_tween and _hype_tween.is_valid(): _hype_tween.kill()
	if animate:
		_hype_tween = create_tween()
		_hype_tween.set_ease(Tween.EASE_OUT)
		_hype_tween.set_trans(Tween.TRANS_CUBIC)
		_hype_tween.tween_method(_set_hype_immediate, _hype_value, value, HYPE_TWEEN_TIME)
	else:
		_set_hype_immediate(value)

func _set_hype_immediate(v: float) -> void:
	_hype_value = v
	_layout_hype()

# perfection 0..cap → quy ra 0..1 cho hype bar
func set_hype_from_perfection(perfection: int, cap: int = 10) -> void:
	if cap <= 0:
		set_hype(0.0)
	else:
		set_hype(float(perfection) / float(cap))

# ─── Dialogue ────────────────────────────────────────────────

# speaker: "Sonny" / "Mike" / enemy name. text: dialogue body.
func show_dialogue(speaker: String, text: String) -> void:
	var color : Color = _color_for_speaker(speaker)
	var font_id : String = "enemy" if _is_enemy_speaker(speaker) else "normal"
	var hex := color.to_html(false)
	# Format: [color=...]SPEAKER:[/color] body...
	var bb := "[color=#%s][b]%s:[/b][/color] %s" % [hex, speaker.to_upper(), text]
	_dialogue_text.clear()
	_dialogue_text.append_text(bb)

func clear_dialogue() -> void:
	_dialogue_text.clear()

# ─── Enemies ─────────────────────────────────────────────────

# id: int duy nhất (ví dụ instance_id của enemy node).
# enemy_type_label: "G", "A", "S" — đến từ display_label của preset.
# tint: Color body của enemy để fill avatar.
func register_enemy(id: int, name_str: String, current_hp: int, max_hp: int,
		enemy_type_label: String = "?", tint: Color = Color(0.6, 0.2, 0.2)) -> void:
	if _enemy_blocks.has(id):
		update_enemy_hp(id, current_hp, max_hp)
		return
	var block := _make_enemy_block(name_str, enemy_type_label, tint)
	_enemy_inner.add_child(block["root"])
	_enemy_blocks[id] = block
	_render_hp_bar(block, current_hp, max_hp)

func update_enemy_hp(id: int, current_hp: int, max_hp: int) -> void:
	if not _enemy_blocks.has(id): return
	_render_hp_bar(_enemy_blocks[id], current_hp, max_hp)

func remove_enemy(id: int) -> void:
	if not _enemy_blocks.has(id): return
	var block = _enemy_blocks[id]
	var node : Node = block["root"]
	if node and is_instance_valid(node):
		node.queue_free()
	_enemy_blocks.erase(id)

func clear_enemies() -> void:
	for id in _enemy_blocks.keys():
		remove_enemy(id)

# ═══════════════════════════════════════════════════════════════
#  PLAYER BLOCK BUILDING
# ═══════════════════════════════════════════════════════════════

func _build_player_blocks() -> void:
	# HBox: [Sonny block] [Hype bar] [Mike block]
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 10)
	hbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_player_inner.add_child(hbox)

	_blocks["Sonny"] = _make_player_block("Sonny", TEX_AVATAR_SONNY, TEX_FRAME_SONNY, COLOR_SONNY, true)
	hbox.add_child(_blocks["Sonny"]["root"])

	hbox.add_child(_make_hype_widget())

	_blocks["Mike"] = _make_player_block("Mike", TEX_AVATAR_MIKE, TEX_FRAME_MIKE, COLOR_MIKE, false)
	hbox.add_child(_blocks["Mike"]["root"])

# slots_on_left=true → 2 slot dọc nằm bên trái avatar (Sonny);
# slots_on_left=false → 2 slot dọc nằm bên phải avatar (Mike).
# Returns: { root, name_label, status_label, hp_container, item_slots }
func _make_player_block(char_name: String, avatar_tex: Texture2D,
		frame_tex: Texture2D, name_color: Color, slots_on_left: bool) -> Dictionary:
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 4)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Name label trên đầu
	var name_lbl := Label.new()
	name_lbl.text = char_name.to_upper()
	name_lbl.add_theme_font_override("font", FONT_NORMAL)
	name_lbl.add_theme_font_size_override("font_size", NAME_FONT_SIZE)
	name_lbl.add_theme_color_override("font_color", name_color)
	name_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	name_lbl.add_theme_constant_override("outline_size", 4)
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(name_lbl)

	# Avatar + frame — HBox: [slot_col] [avatar] hoặc [avatar] [slot_col]
	var center_row := HBoxContainer.new()
	center_row.add_theme_constant_override("separation", 6)
	center_row.alignment = BoxContainer.ALIGNMENT_CENTER
	root.add_child(center_row)

	# Cột slot duy nhất (2 slot dọc) ở phía ngoài
	var slot_col := VBoxContainer.new()
	slot_col.add_theme_constant_override("separation", 6)
	var slot_1 := _make_item_slot()
	var slot_2 := _make_item_slot()
	slot_col.add_child(slot_1["root"])
	slot_col.add_child(slot_2["root"])

	# Avatar frame (TextureRect bao avatar bên trong) — clickable để switch
	var frame_holder := Control.new()
	frame_holder.custom_minimum_size      = AVATAR_SIZE
	frame_holder.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	frame_holder.pivot_offset             = AVATAR_SIZE * 0.5   # scale từ center
	frame_holder.mouse_entered.connect(_on_avatar_hover_enter.bind(char_name))
	frame_holder.mouse_exited.connect(_on_avatar_hover_exit.bind(char_name))
	frame_holder.gui_input.connect(_on_avatar_gui_input.bind(char_name))

	var frame_tr := TextureRect.new()
	frame_tr.texture = frame_tex
	frame_tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	frame_tr.stretch_mode = TextureRect.STRETCH_SCALE
	frame_tr.set_anchors_preset(Control.PRESET_FULL_RECT)
	frame_tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame_holder.add_child(frame_tr)

	var avatar_tr := TextureRect.new()
	avatar_tr.texture = avatar_tex
	avatar_tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	avatar_tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	avatar_tr.set_anchors_preset(Control.PRESET_FULL_RECT)
	avatar_tr.offset_left = 6.0
	avatar_tr.offset_top = 6.0
	avatar_tr.offset_right = -6.0
	avatar_tr.offset_bottom = -6.0
	avatar_tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame_holder.add_child(avatar_tr)

	# Order: outer slots first, then avatar (Sonny=left | avatar) hoặc (avatar | Mike=right)
	if slots_on_left:
		center_row.add_child(slot_col)
		center_row.add_child(frame_holder)
	else:
		center_row.add_child(frame_holder)
		center_row.add_child(slot_col)

	# Status row (action emoji — placeholder, asset thật sẽ thay sau)
	# Không override font để default theme font (có fallback Unicode) render emoji.
	var status_lbl := Label.new()
	status_lbl.text = "🪽 0/0"
	status_lbl.add_theme_font_size_override("font_size", STATUS_FONT_SIZE)
	status_lbl.add_theme_color_override("font_color", Color(0.95, 0.92, 0.5))
	status_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(status_lbl)

	# HP bar container — width = avatar + 1 slot column + separation
	var hp_container := Control.new()
	hp_container.custom_minimum_size = Vector2(AVATAR_SIZE.x + SLOT_SIZE.x + 8, HP_HEIGHT)
	hp_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(hp_container)

	return {
		"root":         root,
		"name_label":   name_lbl,
		"status_label": status_lbl,
		"hp_container": hp_container,
		"item_slots":   [slot_1, slot_2],
		"frame_holder": frame_holder,
	}

# ─── Avatar hover + click handlers (Mốc 7+) ─────────────────

func _on_avatar_hover_enter(char_name: String) -> void:
	var block = _blocks.get(char_name)
	if block == null: return
	var holder : Control = block["frame_holder"]
	if holder == null: return
	var tw := create_tween()
	tw.tween_property(holder, "scale", Vector2(1.15, 1.15), 0.12) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

func _on_avatar_hover_exit(char_name: String) -> void:
	var block = _blocks.get(char_name)
	if block == null: return
	var holder : Control = block["frame_holder"]
	if holder == null: return
	var tw := create_tween()
	tw.tween_property(holder, "scale", Vector2(1.0, 1.0), 0.12) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

func _on_avatar_gui_input(event: InputEvent, char_name: String) -> void:
	if event is InputEventMouseButton \
			and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		emit_signal("player_avatar_clicked", char_name)

func _make_item_slot() -> Dictionary:
	var holder := Control.new()
	holder.custom_minimum_size = SLOT_SIZE
	var bg := TextureRect.new()
	bg.texture = TEX_SLOT
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(bg)
	var icon := TextureRect.new()
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	icon.offset_left = 4.0
	icon.offset_top = 4.0
	icon.offset_right = -4.0
	icon.offset_bottom = -4.0
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(icon)
	return { "root": holder, "icon": icon }

# ═══════════════════════════════════════════════════════════════
#  HP BAR RENDERING
#  ► slots = min(max_hp, 5).
#  ► purples_full = max(0, max_hp - 5); reds_full = slots - purples_full.
#  ► Layout full: P × purples_full ++ R × reds_full (left → right).
#  ► Lose 1 HP: rightmost purple → red. Hết purple thì xóa red từ phải.
# ═══════════════════════════════════════════════════════════════

func _render_hp_bar(block: Dictionary, current_hp: int, max_hp: int, bar_h_override: float = -1.0) -> void:
	var container : Control = block["hp_container"]
	# Clear
	for c in container.get_children():
		c.queue_free()

	var slots : int = clampi(max_hp, 1, 5) if max_hp <= 5 else 5
	if max_hp <= 0: slots = 1
	var purples_full : int = maxi(0, max_hp - 5)
	var reds_full    : int = slots - purples_full

	# Compute current display state
	var hp_lost : int = max_hp - current_hp
	var purples_remaining : int = maxi(0, purples_full - hp_lost)
	var converted_to_red  : int = purples_full - purples_remaining
	var extra_damage      : int = maxi(0, hp_lost - purples_full)
	var reds_remaining    : int = maxi(0, slots - extra_damage)
	# reds_remaining counts BOTH original reds + converted purples; minus damage to red layer

	# Build HBox for HP bar (head | mid×(slots-2) | end), gem overlays per slot
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 0)
	hbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.add_child(hbox)

	# Compute slot piece widths so total ≈ container width
	var head_aspect : float = TEX_HP_HEAD.get_width()  / float(TEX_HP_HEAD.get_height())
	var mid_aspect  : float = TEX_HP_MID.get_width()   / float(TEX_HP_MID.get_height())
	var end_aspect  : float = TEX_HP_END.get_width()   / float(TEX_HP_END.get_height())
	var bar_h : float
	if bar_h_override > 0.0:
		bar_h = bar_h_override
	elif block.has("bar_h"):
		bar_h = block["bar_h"]
	else:
		bar_h = HP_HEIGHT
	var head_w : float = head_aspect * bar_h
	var mid_w  : float = mid_aspect  * bar_h
	var end_w  : float = end_aspect  * bar_h

	# Slot index → which color gem (or none)
	# slots layout (idx 0 = leftmost):
	#   0..purples_remaining-1: PURPLE
	#   purples_remaining..purples_remaining + reds_remaining - 1: RED
	#   rest: empty
	for i in range(slots):
		var piece : TextureRect = TextureRect.new()
		piece.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		piece.stretch_mode = TextureRect.STRETCH_SCALE
		piece.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if i == 0:
			piece.texture = TEX_HP_HEAD
			piece.custom_minimum_size = Vector2(head_w, bar_h)
		elif i == slots - 1:
			piece.texture = TEX_HP_END
			piece.custom_minimum_size = Vector2(end_w, bar_h)
		else:
			piece.texture = TEX_HP_MID
			piece.custom_minimum_size = Vector2(mid_w, bar_h)
		hbox.add_child(piece)

		# Determine gem color for this slot
		var gem_tex : Texture2D = null
		if i < purples_remaining:
			gem_tex = TEX_GEM_PURPLE
		elif i < purples_remaining + reds_remaining:
			gem_tex = TEX_GEM_RED
		# else empty slot

		if gem_tex != null:
			# Uniform rect: w/h khớp gem aspect tự nhiên (~1.67) để STRETCH_SCALE
			# không méo. Mọi slot dùng cùng kích thước → gem nhìn bằng nhau.
			var gem_w : float = bar_h * GEM_W_FRAC
			var gem_h : float = bar_h * GEM_H_FRAC
			var gem := TextureRect.new()
			gem.texture = gem_tex
			gem.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			gem.stretch_mode = TextureRect.STRETCH_SCALE
			gem.mouse_filter = Control.MOUSE_FILTER_IGNORE
			gem.set_anchors_preset(Control.PRESET_TOP_LEFT)
			gem.custom_minimum_size = Vector2(gem_w, gem_h)
			gem.size = Vector2(gem_w, gem_h)
			var gem_y : float = (piece.custom_minimum_size.y - gem_h) * 0.5
			var socket_center_frac : float
			if i == 0:
				socket_center_frac = HEAD_SOCKET_CENTER
			elif i == slots - 1:
				socket_center_frac = END_SOCKET_CENTER
			else:
				socket_center_frac = MID_SOCKET_CENTER
			var gem_x : float = piece.custom_minimum_size.x * socket_center_frac - gem_w * 0.5
			gem.position = Vector2(gem_x, gem_y)
			piece.add_child(gem)

# ═══════════════════════════════════════════════════════════════
#  HYPE BAR (smooth fill via gradient + clip rect)
# ═══════════════════════════════════════════════════════════════

func _make_hype_widget() -> Control:
	var holder := Control.new()
	# Sized so HYPE looks tall and slim between Sonny/Mike
	holder.custom_minimum_size = Vector2(73, AVATAR_SIZE.y + HP_HEIGHT + 42)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.size_flags_vertical = Control.SIZE_FILL

	_hype_bg = TextureRect.new()
	_hype_bg.texture = TEX_HYPE_EMPTY
	_hype_bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_hype_bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_hype_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hype_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(_hype_bg)

	_hype_fill_clip = Control.new()
	_hype_fill_clip.clip_contents = true
	_hype_fill_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(_hype_fill_clip)

	_hype_fill_tex = TextureRect.new()
	_hype_fill_tex.texture = _make_hype_gradient()
	_hype_fill_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_hype_fill_tex.stretch_mode = TextureRect.STRETCH_SCALE
	_hype_fill_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hype_fill_clip.add_child(_hype_fill_tex)

	# HYPE label below
	var hype_lbl := Label.new()
	hype_lbl.text = "HYPE"
	hype_lbl.add_theme_font_override("font", FONT_NORMAL)
	hype_lbl.add_theme_font_size_override("font_size", STATUS_FONT_SIZE)
	hype_lbl.add_theme_color_override("font_color", Color(1.0, 0.95, 0.55))
	hype_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	hype_lbl.add_theme_constant_override("outline_size", 3)
	hype_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hype_lbl.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	hype_lbl.offset_top = -22.0
	holder.add_child(hype_lbl)

	holder.resized.connect(_layout_hype)
	return holder

func _layout_hype() -> void:
	if _hype_bg == null: return
	var sz : Vector2 = _hype_bg.size
	if sz.x <= 0.0 or sz.y <= 0.0: return

	# bg uses STRETCH_KEEP_ASPECT_CENTERED → compute actual displayed area
	var tex_size : Vector2 = _hype_bg.texture.get_size()
	var s : float = minf(sz.x / tex_size.x, sz.y / tex_size.y)
	var disp_w : float = tex_size.x * s
	var disp_h : float = tex_size.y * s
	var disp_x : float = (sz.x - disp_w) * 0.5
	var disp_y : float = (sz.y - disp_h) * 0.5

	var tube_x : float = disp_x + HYPE_TUBE_REL.position.x * disp_w
	var tube_y : float = disp_y + HYPE_TUBE_REL.position.y * disp_h
	var tube_w : float = HYPE_TUBE_REL.size.x * disp_w
	var tube_h : float = HYPE_TUBE_REL.size.y * disp_h
	var fill_h : float = _hype_value * tube_h

	_hype_fill_clip.position = Vector2(tube_x, tube_y + tube_h - fill_h)
	_hype_fill_clip.size     = Vector2(tube_w, fill_h)
	_hype_fill_tex.position  = Vector2(0.0, fill_h - tube_h)
	_hype_fill_tex.size      = Vector2(tube_w, tube_h)

func _make_hype_gradient() -> Texture2D:
	var g := Gradient.new()
	g.set_color(0, Color(0.95, 0.20, 0.20))   # đỏ
	g.set_offset(0, 0.0)
	g.set_color(1, Color(0.40, 0.85, 0.30))   # xanh lá
	g.set_offset(1, 1.0)
	g.add_point(0.30, Color(0.95, 0.55, 0.10))  # cam
	g.add_point(0.55, Color(0.95, 0.95, 0.20))  # vàng
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill_from = Vector2(0.0, 0.0)   # top = red
	tex.fill_to   = Vector2(0.0, 1.0)   # bottom = green
	tex.width = 32
	tex.height = 256
	return tex

# ═══════════════════════════════════════════════════════════════
#  ENEMY BLOCKS
# ═══════════════════════════════════════════════════════════════

func _make_enemy_block(name_str: String, type_label: String, tint: Color) -> Dictionary:
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 4)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var name_lbl := Label.new()
	name_lbl.text = name_str.to_upper()
	name_lbl.add_theme_font_override("font", FONT_ENEMY)
	name_lbl.add_theme_font_size_override("font_size", NAME_FONT_SIZE)
	name_lbl.add_theme_color_override("font_color", COLOR_ENEMY)
	name_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	name_lbl.add_theme_constant_override("outline_size", 4)
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(name_lbl)

	# Avatar frame (dùng slot.png phóng to làm placeholder cho enemy avatar)
	var avatar_holder := Control.new()
	avatar_holder.custom_minimum_size = ENEMY_AVATAR_SIZE
	root.add_child(avatar_holder)

	var avatar_bg := TextureRect.new()
	avatar_bg.texture = TEX_SLOT
	avatar_bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	avatar_bg.stretch_mode = TextureRect.STRETCH_SCALE
	avatar_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	avatar_bg.modulate = tint.lerp(Color.WHITE, 0.55)
	avatar_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	avatar_holder.add_child(avatar_bg)

	# Type label centered (G/A/S/etc.)
	var type_lbl := Label.new()
	type_lbl.text = type_label
	type_lbl.add_theme_font_override("font", FONT_ENEMY)
	type_lbl.add_theme_font_size_override("font_size", ENEMY_TYPE_FONT_SIZE)
	type_lbl.add_theme_color_override("font_color", Color(0.96, 0.95, 0.85))
	type_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	type_lbl.add_theme_constant_override("outline_size", 6)
	type_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	type_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	type_lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	type_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	avatar_holder.add_child(type_lbl)

	# HP container — đủ cho HP bar tối đa (5 slot) ở ENEMY_HP_HEIGHT.
	# head_aspect ≈ 2.84, mid/end ≈ 0.96 → 5slot ≈ bar_h * 6.68.
	var enemy_bar_max_w : float = ENEMY_HP_HEIGHT * 6.8
	var hp_container := Control.new()
	hp_container.custom_minimum_size = Vector2(enemy_bar_max_w, ENEMY_HP_HEIGHT)
	root.add_child(hp_container)

	return {
		"root":         root,
		"name_label":   name_lbl,
		"hp_container": hp_container,
		"bar_h":        ENEMY_HP_HEIGHT,
	}

# ═══════════════════════════════════════════════════════════════
#  HELPERS
# ═══════════════════════════════════════════════════════════════

func _color_for_speaker(speaker: String) -> Color:
	match speaker:
		"Sonny": return COLOR_SONNY
		"Mike":  return COLOR_MIKE
	return COLOR_ENEMY

func _is_enemy_speaker(speaker: String) -> bool:
	return speaker != "Sonny" and speaker != "Mike"
