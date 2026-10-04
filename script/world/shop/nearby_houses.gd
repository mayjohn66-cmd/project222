extends Node2D
## Exterior red-roof house; sprites retain their generated alpha.
const DEFINITIONS = [
 ["RedRoofHouse","res://art/world/houses_v1/red_house.png",Vector2i(-5,7),Vector2(880,974),0.375]
]
const RED_QUARTER_TURN := "res://art/world/houses_v1/red_house_quarter_turn.png"

func rebuild(terrain: Node2D) -> void:
 y_sort_enabled = true
 for child in get_children():
  remove_child(child)
  child.queue_free()
 for index in range(DEFINITIONS.size()):
  var definition = DEFINITIONS[index]
  var house := StaticBody2D.new()
  house.name = definition[0]
  house.collision_layer = 1
  house.collision_mask = 0
  house.position = to_local(terrain.to_global(terrain.grid_to_local(terrain.get_house_cell())))
  add_child(house)
  var sprite := VillageArt.new()
  sprite.name = "HouseSprite"
  sprite.art_path = definition[1]
  # Front doors are about 60px high against the roughly 50px player.
  var display_scale: float = definition[4]
  var faces_right := true
  sprite.scale = Vector2(-display_scale if faces_right else display_scale,display_scale)
  sprite.position = Vector2(definition[3].x*display_scale if faces_right else -definition[3].x*display_scale,-definition[3].y*display_scale)
  house.add_child(sprite)
  var collider := CollisionPolygon2D.new()
  collider.name = "Footprint"
  # Only the ground-level foundation blocks movement; the roof overhang is
  # drawn above pedestrians and must not seal the lane behind the cottage.
  collider.polygon = PackedVector2Array([Vector2(-153,-76),Vector2(-22,-94),Vector2(134,-75),Vector2(30,0),Vector2(-98,-29)])
  var scaled_footprint := collider.polygon
  for i in range(scaled_footprint.size()):
   scaled_footprint[i] *= display_scale/0.25
   if faces_right: scaled_footprint[i].x *= -1.0
  collider.polygon = scaled_footprint
  house.add_child(collider)

func apply_house_variant(house: StaticBody2D, source: String, variant: String) -> void:
 if variant != "quarter_turn" or not source.ends_with("/RedRoofHouse"): return
 var sprite := house.get_node_or_null("HouseSprite") as VillageArt
 var footprint := house.get_node_or_null("Footprint") as CollisionPolygon2D
 if sprite == null or footprint == null: return
 var display_scale := 0.375
 var anchor := Vector2(768,985)
 sprite.art_path = RED_QUARTER_TURN
 sprite.scale = Vector2(display_scale,display_scale)
 sprite.position = Vector2(-anchor.x*display_scale,-anchor.y*display_scale)
 var half_width := 205.0
 var half_height := 95.0
 footprint.polygon = PackedVector2Array([
  Vector2(0,-2.0*half_height),Vector2(half_width,-half_height),
  Vector2(0,0),Vector2(-half_width,-half_height)
 ])
