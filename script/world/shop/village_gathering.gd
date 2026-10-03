extends Node2D

## A few shared landmarks give the paved square a lived-in center.
const NOTICEBOARD = preload("res://art/world/village_gathering_v1/village_noticeboard.png")
const BENCH = preload("res://art/world/village_gathering_v1/oak_bench.png")
const LANTERN = preload("res://art/world/village_gathering_v1/street_lantern.png")
const FLOWER_BUSH = preload("res://art/world/route_props_v1/flower_bush.png")

func rebuild(terrain: Node2D) -> void:
	y_sort_enabled = true
	for child in get_children():
		remove_child(child)
		child.queue_free()
	var square: Vector2i = terrain.get_village_square_cell()
	# Each anchor is the ground contact point in its transparent source image.
	_add_prop(terrain,"VillageNoticeboard",square+Vector2i(-2,-2),NOTICEBOARD,0.18,Vector2(768,950),Vector2(0,-7),20.0)
	_add_prop(terrain,"WellBench",square+Vector2i(-1,4),BENCH,0.11,Vector2(828,970),Vector2(0,-11),21.0)
	_add_prop(terrain,"TrailRestBench",square+Vector2i(-3,6),BENCH,0.11,Vector2(828,970),Vector2(0,-11),21.0)
	_add_prop(terrain,"SmithLantern",square+Vector2i(8,-8),LANTERN,0.17,Vector2(908,847),Vector2(0,-6),11.0)
	_add_prop(terrain,"MarketLantern",square+Vector2i(-6,3),LANTERN,0.14,Vector2(908,847),Vector2(0,-6),11.0)
	_add_prop(terrain,"EastFlowerBed",square+Vector2i(10,-3),FLOWER_BUSH,0.075,Vector2(887,776),Vector2(0,-6),13.0)
	_add_prop(terrain,"CottageFlowerBed",square+Vector2i(12,0),FLOWER_BUSH,0.07,Vector2(887,776),Vector2(0,-6),13.0)

func _add_prop(terrain: Node2D, prop_name: String, cell: Vector2i, art: Texture2D, display_scale: float, anchor: Vector2, collider_offset: Vector2, radius: float) -> void:
	cell = terrain.get_layout_cell("VillageGathering/"+prop_name,cell)
	var body := StaticBody2D.new()
	body.name = prop_name
	body.collision_layer = 1
	body.collision_mask = 0
	body.position = to_local(terrain.to_global(terrain.grid_to_local(cell)))
	body.set_meta("tile_cell",cell)
	add_child(body)
	var sprite := Sprite2D.new()
	sprite.name = "PropSprite"
	sprite.texture = art
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.centered = false
	sprite.scale = Vector2.ONE*display_scale
	sprite.position = -anchor*display_scale
	body.add_child(sprite)
	var collider := CollisionShape2D.new()
	collider.name = "Footprint"
	var shape := CircleShape2D.new()
	shape.radius = radius
	collider.shape = shape
	collider.position = collider_offset
	body.add_child(collider)
