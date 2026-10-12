extends Node2D
## Exterior building; front apron stays walkable for future smith interactions.
func rebuild(terrain: Node2D) -> void:
	y_sort_enabled = true
	for child in get_children():
		remove_child(child)
		child.queue_free()
	var body := StaticBody2D.new()
	body.name = "Smithy"
	body.collision_layer = 1
	body.collision_mask = 0
	body.position = to_local(terrain.to_global(terrain.grid_to_local(terrain.get_blacksmith_cell())))
	add_child(body)
	var sprite := VillageArt.new()
	sprite.name = "BuildingSprite"
	sprite.art_path = "res://art/world/blacksmith_v2/blacksmith_iso.png"
	# The new stone apron is calibrated to the map's 2:1 ground axes.
	sprite.scale = Vector2(0.292,0.36)
	sprite.position = -Vector2(771*0.292,1019*0.36)
	body.add_child(sprite)
	var footprint := CollisionPolygon2D.new()
	footprint.name = "Footprint"
	footprint.polygon = PackedVector2Array([Vector2(-151,-71),Vector2(-35,-137),Vector2(175,-71),Vector2(30,-4)])
	body.add_child(footprint)
