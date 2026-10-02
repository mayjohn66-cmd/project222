extends Node
func _ready() -> void:
	var scene = load("res://scenes/shop/main.tscn").instantiate()
	add_child(scene)
	for i in range(60):
		await get_tree().process_frame
	var ex = scene.get_node("StoreExterior")
	for i in range(3):
		print("B", i, " cell=", ex.get_village_building_cell(i), " entrance=", ex.get_village_building_entrance_cell(i))
	var vb = scene.get_node("VillageBuildings")
	for b in vb.get_children():
		print("body ", b.name, " pos=", b.position, " cell_meta=", b.get_meta("tile_cell", null))
	get_tree().quit()
