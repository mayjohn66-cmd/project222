class_name InventoryDetailPane
extends VBoxContainer
## 인벤토리 탭의 오른쪽 쪽: 왼쪽 쪽의 목록에서 고른 칸의 이름·그림·가격·획득 방법·설명을 보여 준다.
## 목록(ItemCard)이 눌릴 때 내는 inventory_entry_selected 신호를 듣는다. 목록 쪽 코드는 건드리지 않는다.

const INK := Color("44392e")
const INK_DIM := Color("7a6a55")
const PAPER_LINE := Color("b9a582")
const GUTTER := 32.0  # 두 쪽 사이 간격(가운데 제본 홈 폭)
# 아이템 종류(item_type) → 얻는 방법 문구. 문구는 임시이며 바꾸려면 여기만 고친다.
const ACQUIRE_TEXT := {"material": "채집·원정", "store_product": "제작", "equipment": "원정 장비", "special": "특별한 곳에서"}

var _name: Label
var _frame: PanelContainer
var _icon: TextureRect
var _price: Label
var _acquire: Label
var _desc: Label
var _hint: Label
var _selected_card: Control = null


# inv: ManagementInventory. 왼쪽 반을 목록에 주고 오른쪽 반에 상세 쪽을 붙인다.
static func install(inv: Control) -> void:
	if inv == null or inv.has_node("DetailPage"): return
	var left: Control = inv.get_node("MainVBox")
	var grid: GridContainer = left.get_node("ItemScroll/ItemGrid")
	var pane := InventoryDetailPane.new()
	pane.name = "DetailPage"
	inv.add_child(pane)
	pane.anchor_left = 0.5
	pane.anchor_right = 1.0
	pane.anchor_top = 0.0
	pane.anchor_bottom = 1.0
	pane.offset_left = GUTTER * 0.5
	pane.offset_right = -16.0
	pane.offset_top = 14.0
	pane.offset_bottom = -14.0
	left.anchor_right = 0.5
	left.offset_right = -GUTTER * 0.5
	grid.child_entered_tree.connect(pane._on_card_added)
	pane._build()


func _label(size_px: int,color: Color = INK) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size",size_px)
	l.add_theme_color_override("font_color",color)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


func _build() -> void:
	add_theme_constant_override("separation",12)
	_name = _label(28)
	add_child(_name)
	_frame = PanelContainer.new()
	_frame.custom_minimum_size = Vector2(0,190)
	_frame.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var frame_style := StyleBoxFlat.new()
	frame_style.bg_color = Color("fbf4e2")
	frame_style.border_color = Color("5c4130")
	frame_style.set_border_width_all(3)
	frame_style.set_content_margin_all(10)
	_frame.add_theme_stylebox_override("panel",frame_style)
	_frame.custom_minimum_size = Vector2(240,190)
	add_child(_frame)
	_icon = TextureRect.new()
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_icon.custom_minimum_size = Vector2(0,160)
	_frame.add_child(_icon)
	_price = _label(20)
	add_child(_price)
	_acquire = _label(18)
	add_child(_acquire)
	var line := HSeparator.new()
	line.modulate = PAPER_LINE
	add_child(line)
	_desc = _label(17,INK_DIM)
	_desc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_desc.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	add_child(_desc)
	_hint = _label(18,INK_DIM)
	_hint.text = "왼쪽 쪽에서 물건을 고르면\n여기에 자세한 설명이 적힙니다."
	_hint.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(_hint)
	_show_empty()


func _show_empty() -> void:
	for n in [_name,_frame,_price,_acquire,_desc]:
		n.visible = false
	_hint.visible = true


func _on_card_added(node: Node) -> void:
	if node is ItemCard:
		(node as ItemCard).inventory_entry_selected.connect(_on_entry.bind(node))


func _on_entry(entry_type: String,entry_id: Variant,card: ItemCard) -> void:
	if is_instance_valid(_selected_card): _selected_card.modulate = Color.WHITE
	_selected_card = card
	card.modulate = Color(1.0,0.93,0.72)
	var item_id := card.item_id
	var title := ""
	var icon: Texture2D = null
	var price_text := ""
	var acquire := ""
	var desc := ""
	match entry_type:
		ItemCard.ENTRY_TYPE_FURNITURE:
			var data := FurnitureData.get_furniture(str(entry_id))
			title = FurnitureData.get_furniture_name(str(entry_id))
			icon = FurnitureData.get_furniture_icon(str(entry_id))
			acquire = "획득 방법 : 설계도에서 제작"
			desc = str(data.get("description",""))
		_:
			var data := ItemData.get_item(item_id)
			title = ItemData.get_item_name(item_id)
			icon = ItemData.get_item_icon(item_id)
			var price := ItemData.get_item_price(item_id)
			if price > 0: price_text = "가격 : %d G" % price
			acquire = "획득 방법 : %s" % ACQUIRE_TEXT.get(str(ItemData.get_item_type(item_id)),"알 수 없음")
			desc = str(data.get("description",""))
	_name.text = title
	_icon.texture = icon
	_price.text = price_text
	_price.visible = not price_text.is_empty()
	_acquire.text = acquire
	_desc.text = desc
	_hint.visible = false
	for n in [_name,_frame,_acquire,_desc]:
		n.visible = true
