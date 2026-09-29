extends "res://dev/script/slim_furniture_preview.gd"
func _place_samples() -> void:
	super._place_samples()
	$UI/BuildQuickSlotBar.set_inventory_open(true)
	assert($UI/BuildQuickSlotBar.inventory_grid.get_child_count()>=18)
