extends Node2D
## Tool retailer exterior; purchasing will be connected separately.
func rebuild(terrain: Node2D) -> void:
	y_sort_enabled = true
	for child in get_children():
		remove_child(child)
		child.queue_free()
	var body := StaticBody2D.new()
	body.name = "ToolShop"
	body.collision_layer = 1
	body.collision_mask = 0
	body.position = to_local(terrain.to_global(terrain.grid_to_local(terrain.get_tool_shop_cell())))
	add_child(body)
	var sprite := Sprite2D.new()
	sprite.name = "BuildingSprite"
	sprite.texture = load("res://art/world/tool_shop_v1/tool_shop.png")
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.centered = false
	sprite.scale = Vector2.ONE * 0.4
	sprite.position = -Vector2(850,970) * 0.4
	body.add_child(sprite)
	var footprint := CollisionPolygon2D.new()
	footprint.name = "Footprint"
	footprint.polygon = PackedVector2Array([Vector2(-225,-75),Vector2(-30,-171),Vector2(199,-80),Vector2(16,-6)])
	body.add_child(footprint)
