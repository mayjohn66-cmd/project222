class_name LootItemCard
extends Button


var loot_index: int = -1
var item_id: String = ""
var amount: int = 1
var controller: Node = null


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

	text = (
		ItemData.get_item_name(item_id)
		+ "\n×"
		+ str(amount)
	)


func _get_drag_data(
	_at_position: Vector2
) -> Variant:
	if controller == null:
		return null

	if item_id.is_empty():
		return null

	var preview := Label.new()

	preview.text = (
		ItemData.get_item_name(item_id)
		+ " ×"
		+ str(amount)
	)

	preview.custom_minimum_size = Vector2(
		100,
		50
	)

	preview.horizontal_alignment = (
		HORIZONTAL_ALIGNMENT_CENTER
	)

	preview.vertical_alignment = (
		VERTICAL_ALIGNMENT_CENTER
	)

	set_drag_preview(preview)

	return {
		"source": "loot",
		"loot_index": loot_index,
		"item_id": item_id,
		"amount": amount,
		"rotated": false
	}
