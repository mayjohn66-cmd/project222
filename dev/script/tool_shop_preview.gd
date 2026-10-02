extends "res://dev/script/blacksmith_preview.gd"
func _place_samples() -> void:
	await super._place_samples()
	var terrain = $StoreExterior
	var shop = $VillageToolShop/ToolShop
	if OS.get_cmdline_user_args().has("--tools"):
		$Actors/Player.global_position = shop.global_position+Vector2(-120,15)
		$Actors/Player/Camera2D.zoom = Vector2(1.0,1.0)
		$Actors/Player/Camera2D.position = Vector2(120,-150)
	if OS.get_cmdline_user_args().has("--smoke"):
		await get_tree().physics_frame
		assert(shop.get_node("BuildingSprite").texture != null)
		var ray := PhysicsRayQueryParameters2D.create(shop.global_position+Vector2(0,20),shop.global_position+Vector2(0,-100),1)
		var hit := get_world_2d().direct_space_state.intersect_ray(ray)
		assert(not hit.is_empty() and hit.collider == shop)
		var actor = $Actors/Player
		var cell: Vector2i = terrain.get_tool_shop_cell()
		actor.global_position = terrain.to_global(terrain.grid_to_local(Vector2i(terrain.get_dungeon_entry_cell().x,cell.y+1)))
		var destination: Vector2 = terrain.to_global(terrain.grid_to_local(cell+Vector2i(0,1)))
		for step in range(200):
			if actor.global_position.distance_to(destination) < 2: break
			assert(actor.move_and_collide((destination-actor.global_position).limit_length(6)) == null)
		assert(actor.global_position.distance_to(destination) < 2)
		print("TOOL_SHOP_TEXTURE_COLLISION_AND_APPROACH_PASS")
