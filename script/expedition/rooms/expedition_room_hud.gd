class_name ExpeditionRoomHud
extends Control
## 화면 하단은 HP만 표시한다. 필요한 진행 상태는 제목 아래에 표시한다.
const MARGIN := 16.0
var view: ExpeditionRoomView
var stats: VBoxContainer
var controls: Control
var buttons: Array[Button] = []

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
	view.hp_label.hide()
	controls = Control.new()
	controls.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(controls)
	# 이전 연결의 버튼 신호는 호환용으로 유지하고 화면에는 표시하지 않는다.
	controls.hide()
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
	stats.size = Vector2(260, 22)
	var stats_height := maxf(22, stats.get_combined_minimum_size().y)
	stats.position = Vector2(MARGIN, size.y - MARGIN - stats_height)
	view.hint_label.position = Vector2(MARGIN, 42)
	view.hint_label.size = Vector2(maxf(1, size.x - MARGIN * 2), 42)
