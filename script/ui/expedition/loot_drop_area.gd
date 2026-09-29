class_name LootDropArea
extends PanelContainer


var controller: Node = null


func _can_drop_data(
	_at_position: Vector2,
	data: Variant
) -> bool:
	if controller == null:
		return false

	if not data is Dictionary:
		return false

	return str(
		data.get(
			"source",
			""
		)
	) == "bag"


func _drop_data(
	_at_position: Vector2,
	data: Variant
):
	if controller == null:
		return

	if not data is Dictionary:
		return

	controller.return_bag_item_to_loot(
		data
	)
