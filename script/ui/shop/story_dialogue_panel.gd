class_name StoryDialoguePanel
extends CanvasLayer


# 스토리 NPC와의 대화 창. 왼쪽에 NPC 그림, 오른쪽에 이름과 대사.
# E 키나 마우스 클릭으로 다음 줄로 넘기고, 마지막 줄 뒤에 finished 신호를 보낸다.

signal finished

var lines: Array[String] = []
var line_index: int = 0
var open: bool = false
var typing_tween: Tween = null

var root: Control
var portrait: TextureRect
var name_label: Label
var text_label: Label
var hint_label: Label


func _ready() -> void:
	layer = 30

	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	root.visible = false
	add_child(root)

	var panel := PanelContainer.new()
	panel.anchor_left = 0.0
	panel.anchor_right = 1.0
	panel.anchor_top = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_left = 40.0
	panel.offset_right = -40.0
	panel.offset_top = -250.0
	panel.offset_bottom = -30.0

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.2, 0.12, 0.08, 0.97)
	style.border_color = Color(0.85, 0.65, 0.3)
	style.set_border_width_all(3)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(14)
	panel.add_theme_stylebox_override("panel", style)
	root.add_child(panel)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	panel.add_child(row)

	portrait = TextureRect.new()
	portrait.custom_minimum_size = Vector2(160, 190)
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	row.add_child(portrait)

	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 10)
	row.add_child(column)

	name_label = Label.new()
	name_label.add_theme_font_size_override("font_size", 24)
	name_label.add_theme_color_override("font_color", Color(0.97, 0.85, 0.55))
	column.add_child(name_label)

	text_label = Label.new()
	text_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text_label.add_theme_font_size_override("font_size", 21)
	text_label.add_theme_color_override("font_color", Color(0.96, 0.93, 0.85))
	column.add_child(text_label)

	hint_label = Label.new()
	hint_label.text = "▼"
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hint_label.add_theme_font_size_override("font_size", 18)
	hint_label.add_theme_color_override("font_color", Color(0.85, 0.65, 0.3))
	column.add_child(hint_label)


func start(
	npc_name: String,
	portrait_texture: Texture2D,
	new_lines: Array[String]
) -> void:
	if new_lines.is_empty():
		push_warning("[스토리] 대사가 없는 NPC 장면을 건너뜁니다.")
		finished.emit()
		return

	lines = new_lines
	line_index = 0
	name_label.text = npc_name
	portrait.texture = portrait_texture
	portrait.visible = portrait_texture != null
	root.visible = true
	open = true
	_show_line()


func _show_line() -> void:
	text_label.text = lines[line_index]
	text_label.visible_ratio = 0.0
	hint_label.visible = false

	if typing_tween != null:
		typing_tween.kill()

	typing_tween = create_tween()
	typing_tween.tween_property(
		text_label,
		"visible_ratio",
		1.0,
		maxf(0.2, 0.025 * text_label.text.length())
	)
	typing_tween.tween_callback(
		func() -> void:
			hint_label.visible = true
	)


func _advance() -> void:
	# 글자가 나오는 중이면 먼저 전부 보여 준다.
	if text_label.visible_ratio < 1.0:
		if typing_tween != null:
			typing_tween.kill()

		text_label.visible_ratio = 1.0
		hint_label.visible = true
		return

	line_index += 1

	if line_index >= lines.size():
		close()
		return

	_show_line()


func close() -> void:
	open = false
	root.visible = false

	if typing_tween != null:
		typing_tween.kill()

	finished.emit()


func _input(event: InputEvent) -> void:
	if not open:
		return

	var pressed: bool = (
		event.is_action_pressed("interact")
		or (
			event is InputEventMouseButton
			and event.pressed
			and event.button_index == MOUSE_BUTTON_LEFT
		)
	)

	if event is InputEventKey and event.is_echo():
		return

	if pressed:
		get_viewport().set_input_as_handled()
		_advance()
