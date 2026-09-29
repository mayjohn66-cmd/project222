extends "res://script/world/shop/nearby_houses_preview.gd"
func _place_samples() -> void:
 await super._place_samples()
 var terrain = $StoreExterior
 if OS.get_cmdline_user_args().has("--square"):
  $Actors/Player.global_position = terrain.to_global(terrain.grid_to_local(terrain.get_village_square_cell()+Vector2i(1,1)))
  $Actors/Player/Camera2D.zoom = Vector2(0.62,0.62)
  $Actors/Player/Camera2D.position = Vector2(0,-100)
 if OS.get_cmdline_user_args().has("--smoke"):
  var square: Vector2i = terrain.get_village_square_cell()
  var start: Vector2i = terrain.get_dungeon_entry_cell()
  var frontier: Array[Vector2i] = [start]
  var seen := {start:true}
  while not frontier.is_empty():
   var cell: Vector2i = frontier.pop_front()
   for offset in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
    var next: Vector2i = cell+offset
    if seen.has(next) or not terrain.is_exterior_cell(next) or not terrain._is_route_road(next): continue
    seen[next] = true
    frontier.append(next)
  assert(seen.has(square))
  assert(seen.has(Vector2i(terrain.get_exterior_rect().end.x-2,terrain.get_exterior_rect().end.y-2)))
  assert($NearbyHouses.get_child_count()>=1)
  print("RURAL_SQUARE_AND_DUNGEON_CONNECTION_PASS")
