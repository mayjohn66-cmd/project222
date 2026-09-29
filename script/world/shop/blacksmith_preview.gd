extends "res://script/world/shop/rural_village_preview.gd"
func _place_samples() -> void:
	await super._place_samples()
	var terrain = $StoreExterior
	var smith = $VillageBlacksmith/Smithy
	if OS.get_cmdline_user_args().has("--smithy"):
		$Actors/Player.global_position = smith.global_position+Vector2(-100,15)
		$Actors/Player/Camera2D.zoom = Vector2(1.15,1.15)
		$Actors/Player/Camera2D.position = Vector2(100,-130)
	if OS.get_cmdline_user_args().has("--smoke"):
		await get_tree().physics_frame
		assert(smith.get_node("BuildingSprite").texture != null)
		var ray := PhysicsRayQueryParameters2D.create(smith.global_position+Vector2(0,20),smith.global_position+Vector2(0,-100),1)
		var hit := get_world_2d().direct_space_state.intersect_ray(ray)
		assert(not hit.is_empty() and hit.collider == smith)
		var actor = $Actors/Player
		var entrance: Vector2i = terrain.get_blacksmith_entrance_cell()
		actor.global_position = terrain.to_global(terrain.grid_to_local(terrain.get_village_square_cell()))
		var square: Vector2i = terrain.get_village_square_cell()
		var lane_y: int = terrain.get_tool_shop_entrance_cell().y+2
		for cell in [Vector2i(square.x,lane_y),Vector2i(entrance.x,lane_y),entrance]:
			var destination: Vector2 = terrain.to_global(terrain.grid_to_local(cell))
			for step in range(200):
				if actor.global_position.distance_to(destination) < 2: break
				assert(actor.move_and_collide((destination-actor.global_position).limit_length(6)) == null)
			assert(actor.global_position.distance_to(destination) < 2)
		print("BLACKSMITH_TEXTURE_COLLISION_AND_APPROACH_PASS")
