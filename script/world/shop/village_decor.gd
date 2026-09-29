extends Node2D
## Small rural landmarks around the square. Collision is limited to trunks/rim.
static var TREE: Texture2D = ArtLoader.load_texture("res://art/world/village_decor_v1/apple_tree.png")
static var WELL: Texture2D = ArtLoader.load_texture("res://art/world/village_decor_v1/village_well.png")
const STALL = preload("res://art/world/village_decor_v6/market_stall_quarter_turn.png")
static var LOW_WALL: Texture2D = ArtLoader.load_texture("res://art/world/village_decor_v1/low_wall.png")
const HERB_STALL = preload("res://art/world/plaza_props_v1/herb_stall_roof_diamond_v6.png")
const SUPPLY_CART = preload("res://art/world/plaza_props_v1/supply_cart_tile_aligned_v3.png")
const SUPPLY_CRATES = preload("res://art/world/plaza_props_v1/plaza_crates.png")
const MARKET_STALL_FRONT_ANCHOR := Vector2(900,997)
const MARKET_STALL_FRONT_FOOTPRINT := [
	Vector2(-50,-83),Vector2(58,-29),Vector2(0,0),Vector2(-108,-54)
]
const MARKET_STALL_VARIANTS := {
	"fish_front": preload("res://art/world/market_stalls_v3/fish_front.png"),
	"fish_rear": preload("res://art/world/market_stalls_v3/fish_rear.png"),
	"bakery_front": preload("res://art/world/market_stalls_v3/bakery_front.png"),
	"bakery_rear": preload("res://art/world/market_stalls_v3/bakery_rear.png"),
	"cloth_front": preload("res://art/world/market_stalls_v3/cloth_front.png"),
	"cloth_rear": preload("res://art/world/market_stalls_v3/cloth_rear.png")
}
const MARKET_STALL_REAR_ANCHORS := {
	"fish": Vector2(755,970),
	"bakery": Vector2(620,975),
	"cloth": Vector2(870,975)
}

func rebuild(terrain: Node2D) -> void:
	y_sort_enabled = true
	for child in get_children():
		remove_child(child)
		child.queue_free()
	var tree_cells: Array[Vector2i] = terrain.get_village_tree_cells()
	for index in range(tree_cells.size()):
		var cell: Vector2i = tree_cells[index]
		var tree := StaticBody2D.new()
		tree.name = "OrchardTree"+str(index+1)
		tree.collision_layer = 1
		tree.collision_mask = 0
		tree.position = to_local(terrain.to_global(terrain.grid_to_local(cell)))
		add_child(tree)
		var sprite := Sprite2D.new()
		sprite.name = "TreeSprite"
		sprite.texture = TREE
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		sprite.centered = false
		var scale_value: float = [0.17,0.19,0.16,0.18][index]
		sprite.scale = Vector2.ONE*scale_value
		sprite.position = -Vector2(620,1165)*scale_value
		tree.add_child(sprite)
		var trunk := CollisionShape2D.new()
		trunk.name = "Trunk"
		var shape := CircleShape2D.new()
		shape.radius = 18.0
		trunk.shape = shape
		trunk.position = Vector2(0,-13)
		tree.add_child(trunk)
	var well := StaticBody2D.new()
	well.name = "VillageWell"
	well.collision_layer = 1
	well.collision_mask = 0
	well.position = to_local(terrain.to_global(terrain.grid_to_local(terrain.get_village_well_cell())))
	add_child(well)
	var well_sprite := Sprite2D.new()
	well_sprite.name = "WellSprite"
	well_sprite.texture = WELL
	well_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	well_sprite.centered = false
	well_sprite.scale = Vector2.ONE*0.16
	well_sprite.position = -Vector2(660,1130)*0.16
	well.add_child(well_sprite)
	var rim := CollisionShape2D.new()
	rim.name = "Rim"
	var rim_shape := CircleShape2D.new()
	rim_shape.radius = 38.0
	rim.shape = rim_shape
	rim.position = Vector2(0,-12)
	well.add_child(rim)
	var stall := StaticBody2D.new()
	stall.name = "MarketStall"
	stall.collision_layer = 1
	stall.collision_mask = 0
	stall.position = to_local(terrain.to_global(terrain.grid_to_local(terrain.get_village_stall_cell())))
	add_child(stall)
	var stall_sprite := Sprite2D.new()
	stall_sprite.name = "StallSprite"
	stall_sprite.texture = STALL
	stall_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	stall_sprite.centered = false
	# The quarter-turned canopy faces the other isometric ground axis.
	stall_sprite.scale = Vector2.ONE*0.2
	# The near timber post is the tile anchor.
	stall_sprite.position = -MARKET_STALL_FRONT_ANCHOR*0.2
	stall.add_child(stall_sprite)
	var stall_footprint := CollisionPolygon2D.new()
	stall_footprint.name = "Footprint"
	stall_footprint.polygon = PackedVector2Array(MARKET_STALL_FRONT_FOOTPRINT)
	stall.add_child(stall_footprint)
	var wall_cells: Array[Vector2i] = terrain.get_village_wall_cells()
	for index in range(wall_cells.size()):
		var wall := StaticBody2D.new()
		wall.name = "GardenWall"+str(index+1)
		wall.collision_layer = 1
		wall.collision_mask = 0
		wall.position = to_local(terrain.to_global(terrain.grid_to_local(wall_cells[index])))
		add_child(wall)
		var wall_sprite := Sprite2D.new()
		wall_sprite.name = "WallSprite"
		wall_sprite.texture = LOW_WALL
		wall_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		wall_sprite.centered = false
		# The painted wall is shallower than the 2:1 ground grid. Narrow only
		# its horizontal axis so the masonry follows one isometric tile edge.
		# Mirror the south wall onto the other ground axis to frame the lane.
		var turn_wall := index == 0
		wall_sprite.scale = Vector2(-0.15 if turn_wall else 0.15,0.2)
		wall_sprite.position = Vector2(768*0.15 if turn_wall else -768*0.15,-710*0.2)
		wall.add_child(wall_sprite)
		var wall_footprint := CollisionPolygon2D.new()
		wall_footprint.name = "Footprint"
		wall_footprint.polygon = PackedVector2Array([Vector2(-88,24),Vector2(88,-64),Vector2(88,-40),Vector2(-88,48)])
		if turn_wall:
			var turned_footprint := wall_footprint.polygon
			for i in range(turned_footprint.size()):
				turned_footprint[i].x *= -1.0
			wall_footprint.polygon = turned_footprint
		wall.add_child(wall_footprint)
	# Cluster supplies near the rim of the square while leaving the well,
	# central crossing, and approaches to the buildings walkable.
	_add_plaza_prop(terrain,"PlazaHerbStall",terrain.get_village_herb_stall_cell(),HERB_STALL,0.2,Vector2(679,1107),PackedVector2Array([
		Vector2(-90,-42),Vector2(20,-97),Vector2(110,-52),Vector2(0,3)]),true)
	_add_plaza_prop(terrain,"PlazaSupplyCart",terrain.get_village_supply_cart_cell(),SUPPLY_CART,0.12,Vector2(790,760),PackedVector2Array([
		Vector2(-64,13),Vector2(-20,-38),Vector2(59,-11),Vector2(13,20)]))
	_add_plaza_prop(terrain,"PlazaCrates",terrain.get_village_supply_crates_cell(),SUPPLY_CRATES,0.09,Vector2(790,930),PackedVector2Array([
		Vector2(-47,-18),Vector2(-7,-39),Vector2(47,-17),Vector2(9,5)]))

func _add_plaza_prop(terrain: Node2D, prop_name: String, cell: Vector2i, art: Texture2D, display_scale: float, anchor: Vector2, footprint_points: PackedVector2Array, mirrored: bool = false) -> void:
	var prop := StaticBody2D.new()
	prop.name = prop_name
	prop.collision_layer = 1
	prop.collision_mask = 0
	prop.position = to_local(terrain.to_global(terrain.grid_to_local(cell)))
	add_child(prop)
	var sprite := Sprite2D.new()
	sprite.name = "PropSprite"
	sprite.texture = art
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.centered = false
	sprite.scale = Vector2(-display_scale if mirrored else display_scale,display_scale)
	sprite.position = Vector2(anchor.x*display_scale if mirrored else -anchor.x*display_scale,-anchor.y*display_scale)
	prop.add_child(sprite)
	var footprint := CollisionPolygon2D.new()
	footprint.name = "Footprint"
	if mirrored:
		for i in range(footprint_points.size()):
			footprint_points[i].x *= -1.0
	footprint.polygon = footprint_points
	prop.add_child(footprint)

func apply_market_stall_variant(prop: StaticBody2D, variant: String) -> void:
	if not MARKET_STALL_VARIANTS.has(variant): return
	var sprite := prop.get_node_or_null("StallSprite") as Sprite2D
	var footprint := prop.get_node_or_null("Footprint") as CollisionPolygon2D
	if sprite == null or footprint == null: return
	sprite.texture = MARKET_STALL_VARIANTS[variant]
	if variant.ends_with("_front"):
		# All three customer-facing counters use the fruit stall's southwest view.
		sprite.scale = Vector2.ONE*0.2
		sprite.position = -MARKET_STALL_FRONT_ANCHOR*0.2
		footprint.polygon = PackedVector2Array(MARKET_STALL_FRONT_FOOTPRINT)
	else:
		# The existing rear choices remain available for the opposite approach.
		var anchor: Vector2 = MARKET_STALL_REAR_ANCHORS[variant.get_slice("_",0)]
		sprite.scale = Vector2(-0.2,0.2)
		sprite.position = Vector2(anchor.x*0.2,-anchor.y*0.2)
		footprint.polygon = PackedVector2Array([
			Vector2(0,-110),Vector2(110,-55),Vector2(0,0),Vector2(-110,-55)
		])
