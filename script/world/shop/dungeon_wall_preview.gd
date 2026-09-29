extends "res://script/world/shop/dungeon_route_preview.gd"
func _place_samples() -> void:
 await super._place_samples()
 if not OS.get_cmdline_user_args().has("--smoke"): return
 for i in range(3): await get_tree().physics_frame
 var terrain = $StoreExterior
 var entry: Vector2i = terrain.get_dungeon_entry_cell()
 assert($DungeonWall.get_child_count() == 4)
 for column in [-7,-3,3,7]:
  var from: Vector2 = terrain.to_global(terrain.grid_to_local(entry+Vector2i(column,2)))
  var to: Vector2 = terrain.to_global(terrain.grid_to_local(entry+Vector2i(column,0)))
  var query := PhysicsRayQueryParameters2D.create(from,to,1)
  var hit := get_world_2d().direct_space_state.intersect_ray(query)
  assert(not hit.is_empty())
  assert(hit.collider.get_parent() == $DungeonWall)
  var sprite := hit.collider.get_node("WallSprite") as Sprite2D
  assert(sprite.texture == load("res://art/world/village_decor_v1/low_wall.png"))
  assert(sprite.scale.x < 0.0)
 assert(terrain._is_route_road(entry+Vector2i(0,-2)))
 assert($DungeonRoadside.get_child_count() == 5)
 for prop in $DungeonRoadside.get_children():
  var cell: Vector2i = prop.get_meta("tile_cell")
  assert(terrain.is_exterior_cell(cell))
  assert(not terrain._is_route_road(cell),"Roadside prop blocks the dungeon lane: "+prop.name)
  assert(prop.get_node("PropSprite").texture != null)
  var point := PhysicsPointQueryParameters2D.new()
  point.position = prop.global_position+Vector2(0,-7)
  point.collision_mask = 1
  var found := false
  for hit in get_world_2d().direct_space_state.intersect_point(point,16):
   if hit.collider == prop: found = true
  assert(found,"Missing roadside collision: "+prop.name)
 var actor = $Actors/Player
 actor.set_physics_process(false)
 actor.global_position = terrain.to_global(terrain.grid_to_local(entry+Vector2i(0,3)))
 var destination: Vector2 = terrain.to_global(terrain.grid_to_local(entry))
 for step in range(80):
  if actor.global_position.distance_to(destination) < 1: break
  var hit = actor.move_and_collide((destination-actor.global_position).limit_length(5))
  assert(hit == null,"Dungeon opening is blocked")
 assert(actor.global_position.distance_to(destination) < 1)
 assert($WorldInteractions.near_dungeon())
 print("DUNGEON_WALL_COLLISION_AND_OPENING_PASS")
