extends "res://dev/script/dungeon_wall_preview.gd"
func _place_samples() -> void:
 await super._place_samples()
 for i in range(4): await get_tree().process_frame
 assert($NearbyHouses.get_child_count() >= 1)
 if OS.get_cmdline_user_args().has("--houses"):
  var entry: Vector2i = $StoreExterior.get_dungeon_entry_cell()
  $Actors/Player.global_position = $StoreExterior.to_global($StoreExterior.grid_to_local(entry+Vector2i(-2,9)))
  $Actors/Player/Camera2D.zoom = Vector2(0.85,0.85)
  $Actors/Player/Camera2D.position = Vector2(0,-90)
 if OS.get_cmdline_user_args().has("--smoke"):
  await get_tree().physics_frame
  for house in $NearbyHouses.get_children():
   assert(house.get_node("HouseSprite").texture != null)
   var ray := PhysicsRayQueryParameters2D.create(house.global_position+Vector2(0,20),house.global_position+Vector2(0,-100),1)
   var hit := get_world_2d().direct_space_state.intersect_ray(ray)
   assert(not hit.is_empty() and hit.collider == house)
  print("RED_HOUSE_TEXTURE_AND_COLLISION_PASS")
