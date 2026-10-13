class_name ArrivalBarterPanel
extends CommunityBoardPanel
## 한 번의 교환 제안. 게시판 목록 대신 물품 비교와 두 응답만 표시한다.
var receive_label: Label
var shortage_label: Label

func panel_title() -> String: return "타블렌의 교환 제안"
func introduction() -> String: return ""

func _ready() -> void:
	layer = 25
	backdrop = ColorRect.new()
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.color = InteractionUiStyle.tone(InteractionUiStyle.INK, 0.5, 0.35)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(backdrop)
	root = PanelContainer.new()
	root.theme = preload("res://art/ui/pixel_theme/pixel_ui_theme.tres")
	add_child(root)
	var margin := MarginContainer.new()
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	root.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 16)
	margin.add_child(column)
	var title := _label(panel_title(), UiTypography.DEFAULT_SIZE)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)
	column.add_child(HSeparator.new())
	var goods := HBoxContainer.new()
	goods.add_theme_constant_override("separation", 24)
	column.add_child(goods)
	var give_label := _goods_column(goods, "건네는 물품")
	receive_label = _goods_column(goods, "받는 물품")
	shortage_label = _label("", UiTypography.SMALL_SIZE)
	shortage_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(shortage_label)
	var responses := HBoxContainer.new()
	responses.add_theme_constant_override("separation", 16)
	column.add_child(responses)
	var accept := _response("수락")
	accept.pressed.connect(func(): action_requested.emit("arrival_barter"))
	responses.add_child(accept)
	close_button = _response("거절")
	close_button.pressed.connect(close)
	responses.add_child(close_button)
	cards["arrival_barter"] = {"info": give_label, "action": accept}
	# 상속한 패널의 공개 필드는 유지하되 설명·진행 문구는 화면에 붙이지 않는다.
	count_label = Label.new()
	message = Label.new()
	for hidden_label in [count_label, message]:
		hidden_label.hide()
		column.add_child(hidden_label)
	get_viewport().size_changed.connect(_fit_screen)
	root.minimum_size_changed.connect(func(): call_deferred("_fit_screen"))
	_fit_screen()
	root.hide()
	backdrop.hide()

func _label(text: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", InteractionUiStyle.INK)
	return label

func _goods_column(parent: HBoxContainer, heading: String) -> Label:
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 8)
	parent.add_child(column)
	column.add_child(_label(heading, UiTypography.SMALL_SIZE))
	var goods := _label("", UiTypography.DEFAULT_SIZE)
	goods.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(goods)
	return goods

func _response(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 54
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.add_theme_font_size_override("font_size", UiTypography.DEFAULT_SIZE)
	InteractionUiStyle.apply_button(button)
	return button

func _fit_screen() -> void:
	if not is_instance_valid(root): return
	var screen := get_viewport().get_visible_rect().size
	# 내용 높이로 맞춰 빈 공간을 줄인다. 글씨를 축소하지 않는다.
	root.size = Vector2(minf(640, screen.x - 48), root.get_combined_minimum_size().y)
	root.position = (screen - root.size) * 0.5

func display() -> void:
	refresh()
	root.show()
	backdrop.show()
	_fit_screen()
	call_deferred("_fit_screen")
	# Enter를 연타해 대사를 넘겨도 바로 교환하지 않도록 기본 초점은 거절.
	close_button.grab_focus()

func refresh() -> void:
	var give_lines := PackedStringArray()
	var receive_lines := PackedStringArray()
	var shortages := PackedStringArray()
	for item in OpeningJourneyFlow.SETTINGS.barter_requirements:
		var id := str(item["id"])
		var amount := int(item["amount"])
		give_lines.append("%s ×%d" % [ItemData.get_item_name(id), amount])
		var missing := amount - GameState.get_item_count(id)
		if missing > 0:
			shortages.append("%s %d개 부족" % [ItemData.get_item_name(id), missing])
	for gift in OpeningJourneyFlow.SETTINGS.barter_gifts:
		receive_lines.append("%s ×%d" % [ItemData.get_item_name(str(gift["id"])), gift["amount"]])
	var card: Dictionary = cards["arrival_barter"]
	card["info"].text = "\n".join(give_lines)
	receive_label.text = "\n".join(receive_lines)
	card["action"].disabled = not OpeningJourneyFlow.can_trade()
	shortage_label.text = " · ".join(shortages) if not OpeningJourneyFlow.traded() else ""
	shortage_label.visible = not shortage_label.text.is_empty()
	message.text = ""
	count_label.text = ""
