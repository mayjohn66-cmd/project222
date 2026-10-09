class_name ExpeditionBag
extends "res://script/inventory/grid_placement_model.gd"


func _init(
	new_width: int = 6,
	new_height: int = 5
) -> void:
	super(
		new_width,
		new_height
	)

func add_item(item_id: String, cell: Vector2i, amount: int = 1, rotated: bool = false, extra_data: Dictionary = {}) -> int:
	var food := ExpeditionFoodBatches.extra(item_id,amount,extra_data)
	if not food["success"]: return -1
	return super.add_item(item_id,cell,amount,rotated,food["data"])

func load_placements(saved_placements: Array[Dictionary]) -> bool:
	if not ExpeditionFoodBatches.valid_entries(saved_placements,GameState.total_day): return false
	if not super.load_placements(saved_placements): return false
	for entry in placements: ExpeditionFoodBatches.adopt(entry)
	return true
