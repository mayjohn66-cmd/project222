class_name ExpeditionRoomHud
extends Control
## 체력은 왼쪽 아래, 행동 버튼은 오른쪽 아래. 좁은 창에서는 버튼을 체력 위로 올린다.
const MARGIN := 16.0
const GAP := 6.0
var view: ExpeditionRoomView
var stats: VBoxContainer
var controls: Control
var buttons: Array[Button] = []
var footer_height := 72.0

func build(owner_view: ExpeditionRoomView) -> void:
	view = owner_view
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	view.title_label = _label()
	view.title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(view.title_label)
	view.hint_label = _label()
	view.hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	view.hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(view.hint_label)
	stats = VBoxContainer.new()
	stats.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stats.add_theme_constant_override("separation", 4)
	add_child(stats)
	view.hp_bar = HpBar.new()
	stats.add_child(view.hp_bar)
	view.hp_label = _label()
	view.hp_label.add_theme_font_size_override("font_size", 14)
	view.hp_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	stats.add_child(view.hp_label)
	controls = Control.new()
	controls.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(controls)
	for entry in [["←", Vector2.LEFT], ["↑", Vector2.UP], ["↓", Vector2.DOWN], ["→", Vector2.RIGHT]]:
		var button := _button(str(entry[0]))
		view.move_buttons[button] = entry[1]
	view.attack_button = _button("공격")
	view.swap_button = _button("무기 교체")
	view.swap_button.pressed.connect(func():
		if view._can_play(): view.model.swap_weapon())
	view.interact_button = _button("상호작용")
	view.interact_button.pressed.connect(func():
		if view._can_play(): view.model.interact())
	_button("철수").pressed.connect(func():
		if view._can_play(): view.retreat_requested.emit())
	resized.connect(layout)
	layout()

func _label() -> Label:
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_color_override("font_color", Color("f4eddb"))
	label.add_theme_color_override("font_outline_color", Color("33221c"))
	label.add_theme_constant_override("outline_size", 4)
	return label

func _button(caption: String) -> Button:
	var button := view._button(caption, controls)
	buttons.append(button)
	return button

func layout() -> void:
	if view == null or controls == null: return
	view.title_label.position = Vector2(MARGIN, 10)
	view.title_label.size = Vector2(maxf(1, size.x - MARGIN * 2), 28)
	stats.size = Vector2(260, 48)
	var stats_height := maxf(48, stats.get_combined_minimum_size().y)
	stats.position = Vector2(MARGIN, size.y - MARGIN - stats_height)
	var total_width := -GAP
	for button in buttons: total_width += button.get_combined_minimum_size().x + GAP
	var stacked := total_width + 260 + MARGIN * 3 > size.x
	var available_width := maxf(42, size.x - MARGIN * 2)
	var at := Vector2.ZERO
	var row_height := 0.0
	var used_width := 0.0
	for button in buttons:
		var button_size := button.get_combined_minimum_size()
		if at.x > 0 and at.x + button_size.x > available_width:
			at = Vector2(0, at.y + row_height + GAP)
			row_height = 0
		button.position = at
		button.size = button_size
		at.x += button_size.x + GAP
		row_height = maxf(row_height, button_size.y)
		used_width = maxf(used_width, at.x - GAP)
	var controls_height := at.y + row_height
	controls.size = Vector2(used_width, controls_height)
	controls.position = Vector2(size.x - MARGIN - used_width,
		size.y - MARGIN - controls_height - (stats_height + GAP if stacked else 0.0))
	footer_height = maxf(stats_height, controls_height) + MARGIN + GAP
	if stacked: footer_height = stats_height + controls_height + MARGIN + GAP * 2
	view.hint_label.position = Vector2(MARGIN, size.y - footer_height - 48)
	view.hint_label.size = Vector2(maxf(1, size.x - MARGIN * 2), 42)
