class_name LootItemCard
extends Button


var loot_index: int = -1
var item_id: String = ""
var amount: int = 1
var controller: Node = null


const CARD_SIZE := Vector2(72, 72)

var icon_rect: TextureRect = null
var count_label: Label = null


func setup(
	new_loot_index: int,
	new_item_id: String,
	new_amount: int,
	new_controller: Node
):
	loot_index = new_loot_index
	item_id = new_item_id
	amount = new_amount
	controller = new_controller

	custom_minimum_size = CARD_SIZE
	clip_contents = true
	tooltip_text = "%s ×%d\n끌어서 가방에 넣으세요." % [ItemData.get_item_name(item_id), amount]

	var icon: Texture2D = ItemData.get_item_icon(item_id)

	if icon == null:
		# 아이콘이 없는 물품은 이름으로 대신한다.
		text = ItemData.get_item_name(item_id)
		clip_text = true
		add_theme_font_size_override("font_size", UiTypography.size(12))
	else:
		text = ""
		icon_rect = TextureRect.new()
		icon_rect.texture = icon
		icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 6)
		add_child(icon_rect)

	# 수량 표시(가방 칸과 같은 모서리 배지)
	count_label = Label.new()
	count_label.text = "×%d" % amount
	count_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	count_label.add_theme_font_size_override("font_size", UiTypography.size(14))
	count_label.add_theme_color_override("font_color", Color("fff0d0"))
	count_label.add_theme_color_override("font_outline_color", Color("302415"))
	count_label.add_theme_constant_override("outline_size", 4)
	count_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, 4)
	count_label.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	count_label.grow_vertical = Control.GROW_DIRECTION_BEGIN
	add_child(count_label)


func _get_drag_data(
	_at_position: Vector2
) -> Variant:
	if controller == null:
		return null

	if item_id.is_empty():
		return null

	var preview: Control
	var icon: Texture2D = ItemData.get_item_icon(item_id)
	if icon != null:
		var picture := TextureRect.new()
		picture.texture = icon
		picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		picture.custom_minimum_size = Vector2(56, 56)
		picture.modulate.a = 0.9
		preview = picture
	else:
		var label := Label.new()
		label.text = ItemData.get_item_name(item_id) + " ×" + str(amount)
		label.custom_minimum_size = Vector2(100, 50)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		preview = label

	set_drag_preview(preview)

	return {
		"source": "loot",
		"loot_index": loot_index,
		"item_id": item_id,
		"amount": amount,
		"rotated": false
	}
