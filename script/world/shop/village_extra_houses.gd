extends Node2D

## Rear-facing dwellings grouped beyond the east edge of the shared square.
const COTTAGE = preload("res://art/world/village_houses_v2/moss_cottage_rear.png")
const COTTAGE_180 = preload("res://art/world/village_houses_v2/moss_cottage_180.png")
const TOWNHOUSE = preload("res://art/world/village_houses_v2/ochre_townhouse_rear_aligned.png")
const COTTAGE_ROOF_SHADER = preload("res://art/world/village_houses_v2/cottage_roof_recolor.gdshader")
const COTTAGE_ROOF_COLORS := {
	"blue":"597d9c",
	"terracotta":"ad6547",
	"ochre":"bc934d"
}

func rebuild(terrain: Node2D) -> void:
	y_sort_enabled = true
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_add_house(terrain,"SouthTownhouse",terrain.get_extra_house_cell(0),TOWNHOUSE,0.36,Vector2(768,1017),false,0.93)
	_add_house(terrain,"EastCottage",terrain.get_extra_house_cell(1),COTTAGE,0.38,Vector2(770,1016),true)

func _add_house(terrain: Node2D, house_name: String, cell: Vector2i, art: Texture2D, display_scale: float, anchor: Vector2, mirrored: bool, width_factor: float = 1.0) -> void:
	var house := StaticBody2D.new()
	house.name = house_name
	house.collision_layer = 1
	house.collision_mask = 0
	house.position = to_local(terrain.to_global(terrain.grid_to_local(cell)))
	house.set_meta("tile_cell",cell)
	add_child(house)
	var sprite := Sprite2D.new()
	sprite.name = "HouseSprite"
	sprite.texture = art
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.centered = false
	var horizontal_scale := display_scale*width_factor
	sprite.scale = Vector2(-horizontal_scale if mirrored else horizontal_scale,display_scale)
	sprite.position = Vector2(anchor.x*horizontal_scale if mirrored else -anchor.x*horizontal_scale,-anchor.y*display_scale)
	house.add_child(sprite)
	var footprint := CollisionPolygon2D.new()
	footprint.name = "Footprint"
	var points: PackedVector2Array
	if house_name == "SouthTownhouse":
		# Trace the redrawn 2:1 deck, leaving the unseen western approach outside it.
		points = PackedVector2Array([Vector2(-184,-123),Vector2(-8,-183),Vector2(189,-125),Vector2(0,-8)])
	else:
		points = PackedVector2Array([Vector2(-135,-55),Vector2(-30,-111),Vector2(147,-60),Vector2(21,1)])
		for index in range(points.size()):
			points[index] *= display_scale/0.30
			points[index].x *= width_factor
			if mirrored: points[index].x *= -1.0
	footprint.polygon = points
	house.add_child(footprint)

func apply_cottage_roof_variant(house: StaticBody2D, variant: String) -> void:
	var sprite := house.get_node_or_null("HouseSprite") as Sprite2D
	if sprite == null or sprite.texture != COTTAGE: return
	var roof_color := variant
	if variant == "front" or variant.begins_with("front_"):
		sprite.texture = COTTAGE_180
		sprite.scale = Vector2(0.38,0.38)
		sprite.position = Vector2(-768.0, -985.0)*0.38
		var footprint := house.get_node_or_null("Footprint") as CollisionPolygon2D
		if footprint != null:
			footprint.polygon = PackedVector2Array([
				Vector2(0,-180),Vector2(195,-90),Vector2(0,0),Vector2(-195,-90)
			])
		roof_color = variant.trim_prefix("front_")
	if not COTTAGE_ROOF_COLORS.has(roof_color): return
	var roof_material := ShaderMaterial.new()
	roof_material.shader = COTTAGE_ROOF_SHADER
	roof_material.set_shader_parameter("roof_color",Color(COTTAGE_ROOF_COLORS[roof_color]))
	roof_material.set_shader_parameter("front_facing",variant == "front" or variant.begins_with("front_"))
	sprite.material = roof_material
