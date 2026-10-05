class_name SecretMerchantPanel
extends CanvasLayer


# 비밀 상인의 판매 창. 물건 한 줄마다 [구매]로 1개씩 산다(돈이 모자라거나 재고가 없으면 눌리지 않음).
# 산 물건은 가방(일반 인벤토리)에 들어간다. Esc나 [닫기]로 닫는다.

signal closed
signal purchased(item: String)

var offers: Array[Dictionary] = []
var open: bool = false

var root: Control
var money_label: Label
var message_label: Label
var list_box: VBoxContainer


func _ready() -> void:
	layer = 30

	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	root.visible = false
	add_child(root)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.45)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(640, 420)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.16, 0.1, 0.24, 0.98)
	style.border_color = Color(0.7, 0.5, 0.95)
	style.set_border_width_all(3)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(16)
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	panel.add_child(column)

	var title := Label.new()
	title.text = "심야의 비밀 상인"
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", Color(0.9, 0.78, 1.0))
	column.add_child(title)

	money_label = Label.new()
	money_label.add_theme_font_size_override("font_size", 20)
	money_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.5))
	column.add_child(money_label)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 260)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(scroll)

	list_box = VBoxContainer.new()
	list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_box.add_theme_constant_override("separation", 6)
	scroll.add_child(list_box)

	message_label = Label.new()
	message_label.add_theme_font_size_override("font_size", 18)
	message_label.add_theme_color_override("font_color", Color(0.85, 0.85, 0.9))
	column.add_child(message_label)

	var close_button := Button.new()
	close_button.text = "닫기"
	close_button.pressed.connect(close)
	column.add_child(close_button)


func start(new_offers: Array[Dictionary]) -> void:
	offers = new_offers
	message_label.text = "필요한 게 있으면 골라 보게. 오늘 밤뿐이야."
	root.visible = true
	open = true
	_refresh()


func close() -> void:
	if not open:
		return

	open = false
	root.visible = false
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if not open:
		return

	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()


func _refresh() -> void:
	money_label.text = "보유 금액: %d G" % GameState.money

	for child in list_box.get_children():
		child.queue_free()

	for offer in offers:
		list_box.add_child(_make_row(offer))


func _make_row(
	offer: Dictionary
) -> Control:
	var item_id: String = str(offer["item_id"])
	var price: int = int(offer["price"])
	var stock: int = int(offer["stock"])
	var is_furniture: bool = str(offer.get("kind", "item")) == "furniture"

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)

	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(48, 48)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.texture = (
		FurnitureData.get_furniture_icon(item_id)
		if is_furniture
		else ItemData.get_item_icon(item_id)
	)
	row.add_child(icon)

	var name_label := Label.new()
	name_label.text = _get_offer_name(offer)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.add_theme_font_size_override("font_size", 20)
	name_label.add_theme_color_override("font_color", Color(0.96, 0.93, 0.85))
	row.add_child(name_label)

	var stock_label := Label.new()
	stock_label.text = "재고 %d" % stock
	stock_label.add_theme_font_size_override("font_size", 18)
	stock_label.add_theme_color_override("font_color", Color(0.8, 0.75, 0.9))
	row.add_child(stock_label)

	var price_label := Label.new()
	price_label.text = "%d G" % price
	price_label.custom_minimum_size = Vector2(90, 0)
	price_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	price_label.add_theme_font_size_override("font_size", 20)
	price_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.5))
	row.add_child(price_label)

	var buy_button := Button.new()
	buy_button.text = "구매"
	buy_button.disabled = stock <= 0 or not GameState.can_afford(price)
	buy_button.pressed.connect(_on_buy_pressed.bind(offer))
	row.add_child(buy_button)

	return row


func _on_buy_pressed(
	offer: Dictionary
) -> void:
	var item_id: String = str(offer["item_id"])
	var price: int = int(offer["price"])

	if int(offer["stock"]) <= 0:
		return

	if not GameState.spend_money(price):
		message_label.text = "돈이 모자라는군."
		return

	if str(offer.get("kind", "item")) == "furniture":
		GameState.add_furniture(item_id, 1)
	else:
		GameState.add_item(item_id, 1)

	offer["stock"] = int(offer["stock"]) - 1
	purchased.emit(item_id)

	message_label.text = "%s, 잘 골랐네." % _get_offer_name(offer)
	_refresh()


func _get_offer_name(
	offer: Dictionary
) -> String:
	var item_id: String = str(offer["item_id"])

	if str(offer.get("kind", "item")) == "furniture":
		return FurnitureData.get_furniture_name(item_id)

	return ItemData.get_item_name(item_id)
