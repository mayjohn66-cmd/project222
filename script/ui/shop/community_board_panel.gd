class_name CommunityBoardPanel
extends CanvasLayer

signal action_requested(id: String)
signal closed
var root: PanelContainer
var count_label: Label
var message: Label
var cards: Dictionary = {}
var close_button: Button
var backdrop: ColorRect

func entries() -> Array[Dictionary]: return RequestTextData.enrich_all(CommunityRequestFlow.SETTINGS.requests, "community_request")
func panel_title() -> String: return "마을 부탁 게시판"
func introduction() -> String: return UiText.t("request.followthrough.board_intro")

func _ready() -> void:
	layer = 25
	backdrop = ColorRect.new()
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color(0, 0, 0, 0.35)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(backdrop)
	root = PanelContainer.new()
	add_child(root)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	root.add_child(column)
	var title := Label.new()
	title.text = panel_title()
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", UiTypography.size(24))
	column.add_child(title)
	count_label = Label.new()
	count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(count_label)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 12)
	scroll.add_child(list)
	for entry in entries():
		var id := str(entry["id"])
		var card := VBoxContainer.new()
		list.add_child(card)
		var heading := Label.new()
		heading.text = str(entry["title"])
		heading.add_theme_font_size_override("font_size", UiTypography.size(20))
		card.add_child(heading)
		var info := Label.new()
		info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		info.add_theme_font_size_override("font_size", UiTypography.size(17))
		card.add_child(info)
		var action := Button.new()
		action.custom_minimum_size.y = 42
		_style_button(action)
		action.pressed.connect(func(): action_requested.emit(id))
		card.add_child(action)
		cards[id] = {"info":info, "action":action}
	message = Label.new()
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	message.add_theme_font_size_override("font_size", UiTypography.size(17))
	column.add_child(message)
	close_button = Button.new()
	close_button.text = "닫기 [E / Esc]"
	close_button.custom_minimum_size.y = 44
	_style_button(close_button)
	close_button.pressed.connect(close)
	column.add_child(close_button)
	get_viewport().size_changed.connect(_fit_screen)
	root.minimum_size_changed.connect(func(): call_deferred("_fit_screen"))
	_fit_screen()
	root.hide()
	backdrop.hide()

func _style_button(button: Button) -> void:
	for property in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		button.add_theme_color_override(property, Color("38220f"))

func _fit_screen() -> void:
	var screen := get_viewport().get_visible_rect().size
	root.size = Vector2(minf(720, screen.x - 48), minf(560, screen.y - 48))
	root.position = (screen - root.size) * 0.5

func display() -> void:
	message.text = introduction()
	root.show()
	backdrop.show()
	_fit_screen()
	refresh()
	call_deferred("_fit_screen")
	close_button.grab_focus()

func refresh() -> void:
	count_label.text = "공동 부탁 %d/%d 완료 · 마을 평판 %d" % [CommunityRequestFlow.completed_count(), CommunityRequestFlow.SETTINGS.requests.size(), ResidentRequestFlow.reputation()]
	for entry in RequestTextData.enrich_all(CommunityRequestFlow.SETTINGS.requests, "community_request"):
		var id := str(entry["id"])
		var card: Dictionary = cards[id]
		var text := str(entry["summary"]) + "\n"
		var required_items := CommunityRequestFlow.required_items(entry)
		for item in required_items:
			var required: int = required_items[item]
			if CommunityRequestFlow.done(id): text += "%s %d개 전달 완료  " % [ItemData.get_item_name(item), required]
			else: text += "%s %d/%d  " % [ItemData.get_item_name(item), mini(GameState.get_item_count(item), required), required]
		if RequestPaymentText.is_gift(entry): text += "\n" + RequestPaymentText.notice(entry)
		text += "\n%s: 평판 +%d · %d G · %s" % [RequestPaymentText.label(entry), entry["reputation"], entry["money"], entry["landmark_name"]]
		var reason := CommunityRequestFlow.locked_reason(entry)
		if CommunityRequestFlow.done(id):
			card["action"].text = "함께 완료한 부탁"
			card["action"].disabled = true
		elif not reason.is_empty():
			text += "\n" + reason
			card["action"].text = "아직 준비 중"
			card["action"].disabled = true
		elif CommunityRequestFlow.accepted(id):
			card["action"].text = "물품 전달하기" if CommunityRequestFlow.can_deliver(id) else "물품을 준비하는 중"
			card["action"].disabled = not CommunityRequestFlow.can_deliver(id)
		else:
			card["action"].text = "부탁 맡기"
			card["action"].disabled = false
		card["info"].text = text

func close() -> void:
	if not root.visible: return
	root.hide()
	backdrop.hide()
	closed.emit()

func _input(event: InputEvent) -> void:
	if root.visible and not event.is_echo() and (event.is_action_pressed("interact") or event.is_action_pressed("ui_cancel")):
		get_viewport().set_input_as_handled()
		close()
