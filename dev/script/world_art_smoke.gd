extends SceneTree

func _initialize() -> void:
	var floor_node = load("res://scenes/shop/store_floor.tscn").instantiate()
	floor_node.name = "Floor"
	root.add_child(floor_node)
	var objects := Node2D.new()
	root.add_child(objects)
	for id in ["shelf", "register", "door"]:
		for direction in range(4):
			var scene: PackedScene = load("res://scenes/shop/objects/" + id + ".tscn")
			var object = scene.instantiate()
			objects.add_child(object)
			var visual = object.get_node("Visual")
			if id == "door":
				visual.set_rotation_index(direction)
			else:
				var footprint := Vector2i(2, 1) if direction % 2 == 0 else Vector2i(1, 2)
				visual.set_footprint(footprint.x, footprint.y)
				object.get_node("Collision").set_footprint(footprint.x, footprint.y)
				assert(object.get_node("Collision").polygon.size() == 4)
				if id == "shelf":
					visual.set_rotation_index(direction)
					visual.set_stack_level(3)
					assert(visual.stack_level == 3)
	call_deferred("_finish")

func _finish() -> void:
	await process_frame
	await process_frame
	print("WORLD_ART_SMOKE_OK: 12 variants, footprint collision, shelf tiers")
	quit()


