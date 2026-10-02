extends Node
func _ready() -> void:
	var scene = load("res://scenes/shop/main.tscn").instantiate()
	add_child(scene)
	for i in range(90):
		await get_tree().process_frame
	for c in scene.get_children():
		print("W: ", c.name, " [", c.get_class(), "] children=", c.get_child_count(), " pos=", (c as Node2D).position if c is Node2D else "")
	for n in ["StoreExterior","VillageBuildings","VillageDecor","NearbyHouses"]:
		var p = scene.get_node_or_null(n)
		if p:
			var names = []
			for k in p.get_children():
				names.append(k.name + "[" + k.get_class() + "]")
			print(n, " -> ", names.slice(0, 40))
	var ex = scene.get_node("StoreExterior")
	print("exterior_rect=", ex.get_exterior_rect(), " map_extent=", ex.get_village_map_extent(), " route=", ex.get_route_rect())
	get_tree().quit()
