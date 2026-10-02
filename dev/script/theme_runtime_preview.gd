extends Control


func _ready() -> void:
	var backdrop := ColorRect.new()
	backdrop.color = Color("211d1d")
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)

	var outer := PanelContainer.new()
	outer.position = Vector2(28, 24)
	outer.size = Vector2(1096, 596)
	add_child(outer)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_bottom", 18)
	outer.add_child(margin)

	var main := VBoxContainer.new()
	main.add_theme_constant_override("separation", 12)
	margin.add_child(main)

	var title := Label.new()
	title.text = "편의점 판타지 UI — 실제 Godot 적용 화면"
	title.add_theme_font_size_override("font_size", 26)
	main.add_child(title)

	var columns := HBoxContainer.new()
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_theme_constant_override("separation", 14)
	main.add_child(columns)

	columns.add_child(_button_column())
	columns.add_child(_input_column())
	columns.add_child(_list_column())


func _section(title_text: String, width: float) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(width, 0)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	panel.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	margin.add_child(box)
	var title := Label.new()
	title.text = title_text
	title.add_theme_font_size_override("font_size", 20)
	box.add_child(title)
	box.set_meta("panel", panel)
	return box


func _button_column() -> PanelContainer:
	var box := _section("버튼과 선택", 315)
	var normal := Button.new()
	normal.text = "기본 버튼"
	box.add_child(normal)

	var toggle := Button.new()
	toggle.text = "선택된 토글 버튼"
	toggle.toggle_mode = true
	toggle.button_pressed = true
	box.add_child(toggle)

	var disabled := Button.new()
	disabled.text = "비활성화 버튼"
	disabled.disabled = true
	box.add_child(disabled)

	var check_button := CheckButton.new()
	check_button.text = "CheckButton"
	check_button.button_pressed = true
	box.add_child(check_button)

	var check_box := CheckBox.new()
	check_box.text = "CheckBox"
	check_box.button_pressed = true
	box.add_child(check_box)

	var option := OptionButton.new()
	option.add_item("상품 분류")
	option.add_item("음식")
	option.add_item("재료")
	box.add_child(option)

	var separator := HSeparator.new()
	box.add_child(separator)

	var icon_row := HBoxContainer.new()
	icon_row.add_theme_constant_override("separation", 8)
	for label_text in ["−", "+", "닫기"]:
		var button := Button.new()
		button.text = label_text
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		icon_row.add_child(button)
	box.add_child(icon_row)
	return box.get_meta("panel")


func _input_column() -> PanelContainer:
	var box := _section("입력과 수치", 335)
	var line := LineEdit.new()
	line.text = "상품 이름"
	box.add_child(line)

	var disabled_line := LineEdit.new()
	disabled_line.text = "비활성화 입력창"
	disabled_line.editable = false
	box.add_child(disabled_line)

	var text := TextEdit.new()
	text.text = "판타지 상점의 따뜻한 목재와\n양피지 느낌을 적용했습니다."
	text.custom_minimum_size = Vector2(0, 105)
	box.add_child(text)

	var spin := SpinBox.new()
	spin.value = 12
	spin.max_value = 99
	box.add_child(spin)

	var slider := HSlider.new()
	slider.value = 62
	slider.max_value = 100
	box.add_child(slider)

	var progress := ProgressBar.new()
	progress.value = 62
	progress.show_percentage = true
	box.add_child(progress)

	var separator := HSeparator.new()
	box.add_child(separator)

	var note := Label.new()
	note.text = "패널 중앙은 격자 없이 단색으로 표시됩니다."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(note)
	return box.get_meta("panel")


func _list_column() -> PanelContainer:
	var box := _section("탭·목록·스크롤", 390)
	var tabs := TabContainer.new()
	tabs.custom_minimum_size = Vector2(0, 155)
	for tab_name in ["재고", "가구", "원정"]:
		var content := Label.new()
		content.name = tab_name
		content.text = tab_name + " 목록 영역"
		content.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		content.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		tabs.add_child(content)
	box.add_child(tabs)

	var tree := Tree.new()
	tree.custom_minimum_size = Vector2(0, 210)
	var root := tree.create_item()
	root.set_text(0, "현재 보유 상품")
	for item_text in ["물  ×12", "빵  ×8", "포션  ×5", "철광석  ×21", "숲 약초  ×14", "수정 원석  ×3"]:
		var item := tree.create_item(root)
		item.set_text(0, item_text)
	box.add_child(tree)

	var bottom := HBoxContainer.new()
	var cancel := Button.new()
	cancel.text = "취소"
	cancel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(cancel)
	var confirm := Button.new()
	confirm.text = "확인"
	confirm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(confirm)
	box.add_child(bottom)
	return box.get_meta("panel")
