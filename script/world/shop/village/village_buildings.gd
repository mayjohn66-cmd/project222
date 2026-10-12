extends Node2D

## Three small rural buildings around the existing village roads.
const DEFINITIONS = [
	["VillageBakery", "res://art/world/village_buildings_v1/bakery.png", Vector2(770,985), 0.30],
	["VillageGranary", "res://art/world/village_buildings_v1/granary.png", Vector2(700,975), 0.31],
	["VillageStable", "res://art/world/village_buildings_v1/stable.png", Vector2(780,1000), 0.30],
]

func rebuild(terrain: Node2D) -> void:
	y_sort_enabled = true
	for child in get_children():
		remove_child(child)
		child.queue_free()
	for index in range(DEFINITIONS.size()):
		var definition: Array = DEFINITIONS[index]
		var cell: Vector2i = terrain.get_village_building_cell(index)
		var building := StaticBody2D.new()
		building.name = definition[0]
		building.collision_layer = 1
		building.collision_mask = 0
		building.position = to_local(terrain.to_global(terrain.grid_to_local(cell)))
		building.set_meta("tile_cell",cell)
		add_child(building)
		var sprite := VillageArt.new()
		sprite.name = "BuildingSprite"
		sprite.art_path = definition[1]
		var scale_value: float = definition[3]
		var anchor: Vector2 = definition[2]
		sprite.scale = Vector2.ONE*scale_value
		sprite.position = -anchor*scale_value
		building.add_child(sprite)
		var footprint := CollisionPolygon2D.new()
		footprint.name = "Footprint"
		var half_width := 151.0 if index == 0 else (157.0 if index == 1 else 166.0)
		footprint.polygon = PackedVector2Array([
			Vector2(-half_width,-75),Vector2(-12,-135),
			Vector2(half_width,-75),Vector2(10,-8)
		])
		building.add_child(footprint)
