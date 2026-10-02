extends "res://dev/script/world_art_preview.gd"
func _place_samples() -> void:
 super._place_samples()
 var builder = $BuildManager
 GameState.add_furniture("door",1)
 builder.build_selection_state.restore_selection(builder.get_catalog_index_from_build_id("door"),2)
 builder.build_placement_service.place_furniture("door",Vector2i(4,$Floor.rows-1))
 builder.clear_build_selection()
 await get_tree().process_frame
 await get_tree().process_frame
 await get_tree().process_frame
 for definition in [["production_door",Vector2i(6,0),0],["warehouse_door",Vector2i(0,3),3]]:
  GameState.add_furniture(definition[0],1)
  builder.build_selection_state.restore_selection(builder.get_catalog_index_from_build_id(definition[0]),definition[2])
  var room_door = builder.build_placement_service.place_furniture(definition[0],definition[1])
  assert(room_door != null and room_door.z_index == 0)
 builder.clear_build_selection()
 print("ROOM_DOOR_DEPTH_PASS")
 var expected: int = 2*($Floor.columns+$Floor.rows)-2
 assert($WoodWalls.get_child_count()==expected)
 for panel in $WoodWalls.get_children():
  assert(panel.wall_height==75.0 if panel.direction in [1,2] else panel.wall_height==120.0)
 print("WOOD_WALLS_BOUNDARIES_PASS ",expected)

 if OS.get_cmdline_user_args().has("--smoke"):
  $Floor.columns = 12
  $Floor.rows = 10
  $Floor.request_boundary_rebuild()
  for i in range(4): await get_tree().process_frame
  assert($WoodWalls.get_child_count()==43)
  for door in get_tree().get_nodes_in_group("door"): door.queue_free()
  for i in range(5): await get_tree().process_frame
  assert($WoodWalls.get_child_count()==44)
  assert($WoodWalls.get_child_count()==$Floor/FloorBoundary.get_child_count())
  print("WOOD_WALLS_EXPANSION_REMOVAL_PASS")
