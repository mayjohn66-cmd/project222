extends "res://script/world/shop/world_art_preview.gd"
func _place_samples() -> void:
 super._place_samples()
 var builder = $BuildManager
 GameState.add_furniture("door",1)
 builder.build_selection_state.restore_selection(builder.get_catalog_index_from_build_id("door"),2)
 var door = builder.build_placement_service.place_furniture("door",Vector2i(4,$Floor.rows-1))
 assert(door != null)
 builder.clear_build_selection()
 for i in range(5): await get_tree().process_frame
 await get_tree().physics_frame
 var terrain = $StoreExterior
 var lot: Rect2i = terrain.get_exterior_rect()
 var route: Rect2i = terrain.get_route_rect()
 var entry: Vector2i = terrain.get_dungeon_entry_cell()
 var actor = $Actors/Player
 if OS.get_cmdline_user_args().has("--overview"):
  actor.global_position = $Floor.to_global($Floor.grid_to_local(Vector2i(4,4)))
  actor.get_node("Camera2D").position = terrain.to_global(terrain.grid_to_local(Vector2i(12,-10)))-actor.global_position
  actor.get_node("Camera2D").zoom = Vector2(0.25,0.25)
  return
 if OS.get_cmdline_user_args().has("--entrance"):
  actor.global_position = terrain.to_global(terrain.grid_to_local(entry+Vector2i(0,2)))
  return
 if not OS.get_cmdline_user_args().has("--smoke"): return
 assert(route.end.y == lot.position.y)
 assert(terrain.is_exterior_cell(entry))
 assert(terrain.get_connected_map_cells().size() >= 1000)
 var unique := {}
 for cell in terrain.get_connected_map_cells():
  assert(not unique.has(cell))
  unique[cell] = true
 assert(not terrain.is_exterior_cell(Vector2i(route.end.x-1,route.position.y)))
 assert($ProductionRoom.position.distance_to(terrain.to_global(terrain.grid_to_local(entry))) > 5000)
 assert($WarehouseRoom.position.distance_to(terrain.to_global(terrain.grid_to_local(entry))) > 5000)
 actor.set_physics_process(false)
 actor.global_position = $Floor.to_global($Floor.grid_to_local(Vector2i(4,$Floor.rows-1)))
 var square: Vector2i = terrain.get_village_square_cell()
 var waypoints: Array[Vector2i] = [Vector2i(4,lot.end.y-2),Vector2i(lot.end.x-2,lot.end.y-2),Vector2i(lot.end.x-2,square.y),square,square+Vector2i(0,-7),Vector2i(entry.x,square.y-7),entry]
 for cell in waypoints:
  var target: Vector2 = terrain.to_global(terrain.grid_to_local(cell))
  for step in range(700):
   if actor.global_position.distance_to(target) < 2: break
   var delta: Vector2 = (target-actor.global_position).limit_length(6)
   var collision = actor.move_and_collide(delta)
   if collision: print("ROUTE_COLLIDER ",collision.get_collider().get_path())
   assert(collision == null,"Route blocked at "+str(actor.global_position))
  assert(actor.global_position.distance_to(target) < 2)
 # Rebuilding boundaries must replace the old one, including during expansion.
 var old_size: int = terrain.get_node("ExteriorBoundary").get_child_count()
 terrain._create_boundary_collision()
 assert(terrain.get_node("ExteriorBoundary").get_child_count() == old_size)
 print("SHOP_DOOR_TO_DUNGEON_ROUTE_PASS")
 for definition in [["production_door",Vector2i(6,0),0,$ProductionRoom],["warehouse_door",Vector2i(0,3),3,$WarehouseRoom]]:
  GameState.add_furniture(definition[0],1)
  builder.build_selection_state.restore_selection(builder.get_catalog_index_from_build_id(definition[0]),definition[2])
  var room_door = builder.build_placement_service.place_furniture(definition[0],definition[1])
  assert(room_door != null)
  var room = definition[3]
  assert(room.enter_actor(actor))
  assert(actor.global_position.distance_to(room.get_entry_world_position()) < 1)
  assert(room.exit_actor(actor,room_door))
  assert(actor.global_position.distance_to($Floor.global_position) < 1500)
 builder.clear_build_selection()
 print("EXPANDED_WORLD_ROOM_ROUNDTRIP_PASS")
