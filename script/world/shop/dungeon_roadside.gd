extends Node2D
## Sparse landmarks along the lane leading out through the village fence.
const SIGN := "res://art/world/route_props_v1/road_sign.png"
const FENCE := "res://art/world/route_props_v1/wood_fence.png"
const BUSH := "res://art/world/route_props_v1/flower_bush.png"

func rebuild(terrain: Node2D) -> void:
	y_sort_enabled = true
	for child in get_children():
		remove_child(child)
		child.queue_free()
	var entry: Vector2i = terrain.get_dungeon_entry_cell()
	# Offsets are in map cells, with a clear three-cell-wide road between sides.
	var placements: Array = [
		["ExitSign",Vector2i(-3,4),SIGN,0.08,Vector2(534,1281),12.0],
		["NorthBush",Vector2i(3,7),BUSH,0.075,Vector2(887,776),18.0],
		["WestFence",Vector2i(-3,10),FENCE,0.09,Vector2(789,941),0.0],
		["EastFence",Vector2i(3,14),FENCE,0.09,Vector2(789,941),0.0],
		["SouthBush",Vector2i(3,19),BUSH,0.07,Vector2(887,776),17.0],
	]
	for placement in placements:
		var cell: Vector2i = terrain.get_layout_cell("DungeonRoadside/"+placement[0],entry+placement[1])
		var body := StaticBody2D.new()
		body.name = placement[0]
		body.collision_layer = 1
		body.collision_mask = 0
		body.position = to_local(terrain.to_global(terrain.grid_to_local(cell)))
		body.set_meta("tile_cell",cell)
		add_child(body)

		var sprite := VillageArt.new()
		sprite.name = "PropSprite"
		sprite.art_path = placement[2]
		var size: float = placement[3]
		var anchor: Vector2 = placement[4]
		sprite.scale = Vector2.ONE*size
		sprite.position = -anchor*size
		body.add_child(sprite)

		if placement[5] > 0.0:
			var collider := CollisionShape2D.new()
			var shape := CircleShape2D.new()
			shape.radius = placement[5]
			collider.shape = shape
			collider.position = Vector2(0,-9)
			body.add_child(collider)
		else:
			var collider := CollisionPolygon2D.new()
			collider.polygon = PackedVector2Array([
				Vector2(-42,8),Vector2(42,-34),Vector2(42,-20),Vector2(-42,22)
			])
			body.add_child(collider)
