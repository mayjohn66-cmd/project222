extends Node2D
## A straight village boundary with an open road through its center.
const LOW_WALL := "res://art/world/village_decor_v1/low_wall.png"
const SEGMENT_COLUMNS := [-7,-3,3,7]
const SEGMENT_SCALE := Vector2(0.15,0.2)
const SEGMENT_ANCHOR := Vector2(768,710)

func rebuild(terrain: Node2D) -> void:
	y_sort_enabled = true
	for child in get_children():
		remove_child(child)
		child.queue_free()
	var entry: Vector2i = terrain.get_dungeon_entry_cell()
	for column in SEGMENT_COLUMNS:
		var segment := StaticBody2D.new()
		segment.name = "Fence"+str(column).replace("-","Left")
		segment.collision_layer = 1
		segment.collision_mask = 0
		var cell: Vector2i = terrain.get_layout_cell("DungeonWall/"+segment.name,entry+Vector2i(clampi(column,-5,5),1))
		segment.position = to_local(terrain.to_global(terrain.grid_to_local(cell)))
		add_child(segment)

		var sprite := VillageArt.new()
		sprite.name = "WallSprite"
		sprite.art_path = LOW_WALL
		# Mirror onto the other 2:1 ground axis without bending the artwork.
		sprite.scale = Vector2(-SEGMENT_SCALE.x,SEGMENT_SCALE.y)
		sprite.position = Vector2(SEGMENT_ANCHOR.x*SEGMENT_SCALE.x,-SEGMENT_ANCHOR.y*SEGMENT_SCALE.y)
		segment.add_child(sprite)

		var collider := CollisionPolygon2D.new()
		collider.name = "Footprint"
		var points := PackedVector2Array([
			Vector2(-88,24),Vector2(88,-64),Vector2(88,-40),Vector2(-88,48)
		])
		for i in range(points.size()):
			points[i].x *= -1.0
		collider.polygon = points
		segment.add_child(collider)
