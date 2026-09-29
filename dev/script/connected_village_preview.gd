extends "res://dev/script/tool_shop_preview.gd"

func _place_samples() -> void:
	await super._place_samples()
	var terrain = $StoreExterior
	var square: Vector2i = terrain.get_village_square_cell()
	if OS.get_cmdline_user_args().has("--no-grid"):
		terrain.show_tile_grid = false
	if OS.get_cmdline_user_args().has("--grid"):
		terrain.show_tile_grid = true
	if OS.get_cmdline_user_args().has("--village"):
		var actor = $Actors/Player
		actor.global_position = terrain.to_global(terrain.grid_to_local(square))
		actor.get_node("Camera2D").zoom = Vector2(0.34,0.34)
		actor.get_node("Camera2D").position = Vector2(20,-85)
	if OS.get_cmdline_user_args().has("--road"):
		var actor = $Actors/Player
		actor.global_position = terrain.to_global(terrain.grid_to_local(terrain.get_dungeon_entry_cell()+Vector2i(0,11)))
		actor.get_node("Camera2D").zoom = Vector2(0.62,0.62)
		actor.get_node("Camera2D").position = Vector2(0,-55)
	if OS.get_cmdline_user_args().has("--plaza-close"):
		var actor = $Actors/Player
		actor.global_position = terrain.to_global(terrain.grid_to_local(square+Vector2i(3,7)))
		actor.get_node("Camera2D").zoom = Vector2(1.05,1.05)
		actor.get_node("Camera2D").position = Vector2(0,-80)
	if OS.get_cmdline_user_args().has("--townhouse"):
		var actor = $Actors/Player
		actor.global_position = terrain.to_global(terrain.grid_to_local(terrain.get_extra_house_cell(0)))
		actor.get_node("Camera2D").zoom = Vector2(0.85,0.85)
		actor.get_node("Camera2D").position = Vector2(0,-105)
	if OS.get_cmdline_user_args().has("--map-editor"):
		$VillageMapEditor.set_editor_active(true)
	if OS.get_cmdline_user_args().has("--editor-smoke"):
		_smoke_map_editor()
	if OS.get_cmdline_user_args().has("--tile-edit-smoke"):
		_smoke_tile_edit()
	if OS.get_cmdline_user_args().has("--expedition-entry-smoke"):
		_smoke_expedition_entry()
	if OS.get_cmdline_user_args().has("--cottage-color-smoke"):
		_smoke_cottage_colors()
	if OS.get_cmdline_user_args().has("--market-stall-smoke"):
		_smoke_market_stalls()
	if OS.get_cmdline_user_args().has("--round-map-smoke"):
		_smoke_round_map()
	if not OS.get_cmdline_user_args().has("--smoke"): return
	var entry: Vector2i = terrain.get_dungeon_entry_cell()
	var entrances: Array[Vector2i] = [terrain.get_house_entrance_cell(),terrain.get_blacksmith_entrance_cell(),terrain.get_tool_shop_entrance_cell(),terrain.get_extra_house_entrance_cell(0),terrain.get_extra_house_entrance_cell(1)]
	var building_entrances: Array[Vector2i] = [terrain.get_village_building_entrance_cell(0),terrain.get_village_building_entrance_cell(1),terrain.get_village_building_entrance_cell(2)]
	var frontier: Array[Vector2i] = [square]
	var seen := {square:true}
	while not frontier.is_empty():
		var cell: Vector2i = frontier.pop_front()
		for offset in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
			var neighbor: Vector2i = cell+offset
			if seen.has(neighbor) or not terrain.is_exterior_cell(neighbor) or not terrain._is_route_road(neighbor): continue
			seen[neighbor] = true
			frontier.append(neighbor)
	for door in entrances:
		assert(seen.has(door),"Disconnected front door: "+str(door))
	for door in building_entrances:
		assert(seen.has(door),"Disconnected village building: "+str(door))
	assert(seen.has(entry))
	assert($VillageDecor.get_child_count() == 11)
	assert($VillageExtraHouses.get_child_count() == 2)
	assert($VillageBuildings.get_child_count() == 3)
	for building in $VillageBuildings.get_children():
		assert(building.get_node("BuildingSprite").texture != null)
		assert(terrain.is_exterior_cell(building.get_meta("tile_cell")))
		assert(building.get_node("Footprint").polygon.size() == 4)
	# The roof art may overlap, but the ground-level foundations must stay apart.
	# Each group shares the world Y-sort so nearer buildings cover farther ones.
	assert(y_sort_enabled)
	var building_groups := [$NearbyHouses,$VillageExtraHouses,$VillageBuildings]
	for group in building_groups:
		assert(group.y_sort_enabled and group.z_index == 0)
	for building in $VillageBuildings.get_children():
		var footprint := building.get_node("Footprint") as CollisionPolygon2D
		var outline := footprint.global_transform*footprint.polygon
		for group in building_groups:
			for neighbor in group.get_children():
				if neighbor == building: continue
				var neighbor_footprint := neighbor.get_node("Footprint") as CollisionPolygon2D
				var neighbor_outline := neighbor_footprint.global_transform*neighbor_footprint.polygon
				assert(Geometry2D.intersect_polygons(outline,neighbor_outline).is_empty(),"Overlapping building foundations: "+building.name+" / "+neighbor.name)
	for house in $VillageExtraHouses.get_children():
		assert(house.get_node("HouseSprite").texture != null)
		assert(terrain.is_exterior_cell(house.get_meta("tile_cell")))
	assert($VillageGathering.get_child_count() == 6)
	for prop in $VillageGathering.get_children():
		assert(prop.get_node("PropSprite").texture != null)
		assert(terrain.is_exterior_cell(prop.get_meta("tile_cell")))
	for tree_cell in terrain.get_village_tree_cells():
		assert(terrain.is_exterior_cell(tree_cell))
		assert(not terrain._is_route_road(tree_cell),"Tree blocks a village path")
	assert($VillageDecor/VillageWell/WellSprite.texture != null)
	assert($VillageDecor/MarketStall/StallSprite.texture != null)
	for cell in [terrain.get_village_herb_stall_cell(),terrain.get_village_supply_cart_cell(),terrain.get_village_supply_crates_cell()]:
		assert(terrain.is_exterior_cell(cell))
		assert(not terrain._is_route_road(cell),"Plaza prop blocks a village path")
	for prop in [$VillageDecor/PlazaHerbStall,$VillageDecor/PlazaSupplyCart,$VillageDecor/PlazaCrates]:
		var prop_sprite := prop.get_node("PropSprite") as Sprite2D
		assert(prop_sprite != null and prop_sprite.texture != null)
	var market_sprite := $VillageDecor/MarketStall/StallSprite as Sprite2D
	var herb_sprite := $VillageDecor/PlazaHerbStall/PropSprite as Sprite2D
	assert(herb_sprite.scale.is_equal_approx(Vector2(-market_sprite.scale.x,market_sprite.scale.y)))
	assert(herb_sprite.position.is_equal_approx(Vector2(679,-1107)*0.2))
	for wall_cell in terrain.get_village_wall_cells():
		assert(terrain.is_exterior_cell(wall_cell))
		assert(not terrain._is_route_road(wall_cell),"Garden wall blocks a village path")
	await get_tree().physics_frame
	for prop in [$VillageDecor/MarketStall,$VillageDecor/GardenWall1,$VillageDecor/GardenWall2,$VillageDecor/PlazaHerbStall,$VillageDecor/PlazaSupplyCart,$VillageDecor/PlazaCrates]:
		var point := PhysicsPointQueryParameters2D.new()
		point.position = prop.global_position
		point.collision_mask = 1
		var found := false
		for hit in get_world_2d().direct_space_state.intersect_point(point,16):
			if hit.collider == prop: found = true
		assert(found,"Missing village prop collision: "+prop.name)
	var actor = $Actors/Player
	actor.set_physics_process(false)
	var bakery_lane := square+Vector2i(-5,4)
	var routes: Array = [
		[square+Vector2i(-4,-1),square+Vector2i(0,-1),square],
		[square,Vector2i(square.x,entrances[0].y),entrances[0]],
		[square,Vector2i(square.x,entrances[2].y+2),Vector2i(entrances[1].x,entrances[2].y+2),entrances[1]],
		[square,square+Vector2i(0,-7),Vector2i(square.x,entrances[2].y+2),Vector2i(entrances[2].x,entrances[2].y+2),entrances[2]],
		[square,Vector2i(square.x,entrances[3].y),entrances[3]],
		[square,square+Vector2i(0,-9),square+Vector2i(13,-9),entrances[4]],
		[square,square+Vector2i(-4,0),square+Vector2i(-4,4),bakery_lane,Vector2i(bakery_lane.x,building_entrances[0].y),building_entrances[0]],
		[square,square+Vector2i(4,0),square+Vector2i(4,4),square+Vector2i(6,4),Vector2i(square.x+6,building_entrances[1].y),building_entrances[1]],
		[square,building_entrances[2]],
	]
	for route in routes:
		actor.global_position = terrain.to_global(terrain.grid_to_local(route[0]))
		for index in range(1,route.size()):
			var target: Vector2 = terrain.to_global(terrain.grid_to_local(route[index]))
			for step in range(400):
				if actor.global_position.distance_to(target) < 2: break
				var collision = actor.move_and_collide((target-actor.global_position).limit_length(6))
				assert(collision == null,"Blocked route to "+str(route[index])+" at "+str(actor.global_position)+" by "+str(collision.get_collider() if collision else ""))
			assert(actor.global_position.distance_to(target) < 2)
	print("ALL_VILLAGE_DOORS_CONNECTED_AND_WALKABLE_PASS")

func _smoke_round_map() -> void:
	var terrain := $StoreExterior
	var square: Vector2i = terrain.get_village_square_cell()
	var radius: float = terrain.get_village_map_radius()
	var cells: Array[Vector2i] = terrain.get_connected_map_cells()
	assert(radius > 900.0 and radius < 1050.0,"The round map was not reduced to roughly one quarter of its previous area")
	assert(cells.has(terrain.get_exterior_rect().position),"The shop lot is outside the round map")
	assert(cells.has(terrain.get_dungeon_entry_cell()),"The dungeon entrance is outside the round map")
	assert(not terrain.is_exterior_cell(terrain.get_route_rect().end-Vector2i(1,terrain.get_route_rect().size.y)),"The old rectangular route still protrudes")
	var center: Vector2 = terrain.get_village_map_center_local()
	var min_pos := Vector2(INF,INF)
	var max_pos := Vector2(-INF,-INF)
	for cell in cells:
		var position: Vector2 = terrain.grid_to_local(cell)
		assert(position.distance_to(center) <= radius+0.01,"A tile protrudes beyond the circle")
		min_pos = min_pos.min(position)
		max_pos = max_pos.max(position)
	var ratio: float = (max_pos.x-min_pos.x)/(max_pos.y-min_pos.y)
	assert(ratio > 0.95 and ratio < 1.05,"The visible map outline is not circular")
	var original: Dictionary = terrain.get_village_layout_snapshot()
	terrain.set_village_map_extent(terrain.get_village_map_extent()+Vector2i(4,4))
	assert(terrain.get_village_map_radius() > radius and terrain.get_connected_map_cells().size() > cells.size(),"The round map did not grow")
	terrain.restore_village_layout_snapshot(original)
	print("ROUND_VILLAGE_MAP_AND_DUNGEON_ENTRY_PASS radius=",snappedf(radius,0.1)," cells=",cells.size())

func _smoke_cottage_colors() -> void:
	var terrain := $StoreExterior
	var original: Dictionary = terrain.get_village_layout_snapshot()
	var square: Vector2i = terrain.get_village_square_cell()
	var existing_variants := ["blue","terracotta","ochre"]
	for index in range(existing_variants.size()):
		var saved_key := "VillageExtraHouses/EditorObject"+str(index+1)
		if not original["added"].has(saved_key): continue
		var saved_variant: String = str(original["added"][saved_key].get("variant",""))
		if saved_variant.is_empty(): continue
		assert(saved_variant == existing_variants[index],"Existing cottage color was not loaded")
		var saved_house := $VillageExtraHouses.get_node_or_null(saved_key.get_file()) as StaticBody2D
		assert(saved_house != null and saved_house.get_node("HouseSprite").material is ShaderMaterial)
	var variants := ["blue","terracotta","ochre","front","front_blue","front_terracotta","front_ochre"]
	var keys: Array[String] = []
	for index in range(variants.size()):
		var key: String = terrain.add_layout_object("VillageExtraHouses/EastCottage",square+Vector2i(index,0),variants[index])
		assert(not key.is_empty(),"Cannot add the colored cottage")
		keys.append(key)
	for index in range(keys.size()):
		var house := $VillageExtraHouses.get_node_or_null(keys[index].get_file()) as StaticBody2D
		assert(house != null,"Colored cottage was not rebuilt")
		var sprite := house.get_node("HouseSprite") as Sprite2D
		if variants[index].begins_with("front"):
			assert(sprite.texture == preload("res://art/world/village_houses_v2/moss_cottage_180.png"),"The 180-degree cottage art was not applied")
			assert(sprite.scale.x > 0.0 and (house.get_node("Footprint") as CollisionPolygon2D).polygon.size() == 4)
		assert((sprite.material is ShaderMaterial) == (variants[index] != "front"),"Cottage roof color was not applied correctly")
		assert(terrain.get_village_layout_snapshot()["added"][keys[index]]["variant"] == variants[index])
	terrain.restore_village_layout_snapshot(original)
	print("COTTAGE_180_AND_ROOF_COLORS_PASS")

func _smoke_market_stalls() -> void:
	var terrain := $StoreExterior
	var original: Dictionary = terrain.get_village_layout_snapshot()
	var square: Vector2i = terrain.get_village_square_cell()
	var default_stall := $VillageDecor/MarketStall as StaticBody2D
	var default_sprite := default_stall.get_node("StallSprite") as Sprite2D
	assert(default_sprite.texture.resource_path.ends_with("market_stall_quarter_turn.png"),"The market stall was not rotated")
	_assert_isometric_footprint((default_stall.get_node("Footprint") as CollisionPolygon2D).polygon)
	var variants := ["fish_front","fish_rear","bakery_front","bakery_rear","cloth_front","cloth_rear"]
	for index in range(variants.size()):
		var key: String = terrain.add_layout_object("VillageDecor/MarketStall",square+Vector2i(index,0),variants[index])
		assert(not key.is_empty(),"Could not add market stall")
		var stall := $VillageDecor.get_node_or_null(key.get_file()) as StaticBody2D
		assert(stall != null,"Market stall was not built")
		var texture := (stall.get_node("StallSprite") as Sprite2D).texture
		assert(texture != null and texture.resource_path.ends_with(variants[index]+".png"),"Wrong market stall art")
		assert(texture.resource_path.contains("market_stalls_v3"),"The matching southwest-facing stall art was not applied")
		var sprite := stall.get_node("StallSprite") as Sprite2D
		assert((sprite.scale.x < 0.0) == variants[index].ends_with("_rear"),"Wrong market stall facing")
		if variants[index].ends_with("_front"):
			assert(sprite.position == default_sprite.position,"Front stall anchor differs from the fruit stall")
			assert((stall.get_node("Footprint") as CollisionPolygon2D).polygon == (default_stall.get_node("Footprint") as CollisionPolygon2D).polygon,"Front stall footprint differs from the fruit stall")
		_assert_isometric_footprint((stall.get_node("Footprint") as CollisionPolygon2D).polygon)
		assert(terrain.get_village_layout_snapshot()["added"][key]["variant"] == variants[index])
	terrain.restore_village_layout_snapshot(original)
	print("SIX_MARKET_STALL_VIEWS_PASS")

func _assert_isometric_footprint(points: PackedVector2Array) -> void:
	assert(points.size() == 4,"Wrong market stall footprint")
	for index in range(points.size()):
		var edge := points[(index+1)%points.size()]-points[index]
		assert(is_equal_approx(absf(edge.y)*2.0,absf(edge.x)),"Market stall footprint misses the tile axis")

func _smoke_expedition_entry() -> void:
	var terrain := $StoreExterior
	var interaction := $WorldInteractions
	var actor := $Actors/Player
	var editor := $VillageMapEditor
	var original: Dictionary = terrain.get_village_layout_snapshot()
	assert(editor.mode_buttons.size() == 7,"The expedition location tool is missing")
	editor._set_mode(6)
	assert(editor.mode == 6,"The expedition location tool did not activate")
	editor._set_mode(0)
	var departure: Vector2i = terrain.get_expedition_departure_cell()
	assert(terrain.get_layout_tile(departure) == "road","Expedition departure needs a paving tile")
	for offset in [Vector2i.ZERO,Vector2i(2,0),Vector2i(-2,0),Vector2i(0,2),Vector2i(0,-2),Vector2i(2,2),Vector2i(-2,-2)]:
		actor.global_position = terrain.to_global(terrain.grid_to_local(departure+offset))
		assert(interaction.near_dungeon(),"E interaction is missing inside the 5x5 departure area")
	for offset in [Vector2i(3,0),Vector2i(-3,0),Vector2i(0,3),Vector2i(0,-3)]:
		actor.global_position = terrain.to_global(terrain.grid_to_local(departure+offset))
		assert(not interaction.near_dungeon(),"Expedition departure extends beyond 5x5 tiles")
	if terrain.get_dungeon_entry_cell() != departure:
		actor.global_position = terrain.to_global(terrain.grid_to_local(terrain.get_dungeon_entry_cell()))
		assert(not interaction.near_dungeon(),"The old dungeon gate still triggers the expedition")
	var alternate := departure
	for cell in terrain.get_connected_map_cells():
		if cell != departure and terrain.get_layout_tile(cell) == "road":
			alternate = cell
			break
	assert(alternate != departure,"No alternate paved tile exists for the relocation check")
	terrain.set_layout_cell("ExpeditionDeparture",alternate)
	assert(terrain.get_expedition_departure_cell() == alternate,"The editor cannot relocate the expedition departure")
	for offset in [Vector2i.ZERO,Vector2i(2,2),Vector2i(-2,-2)]:
		assert(terrain.is_at_expedition_departure(terrain.to_global(terrain.grid_to_local(alternate+offset))),"The 5x5 area did not move with its center")
	terrain.restore_village_layout_snapshot(original)
	print("EXPEDITION_DEPARTURE_5X5_PASS")

func _smoke_tile_edit() -> void:
	var terrain := $StoreExterior
	var editor := $VillageMapEditor
	var original: Dictionary = terrain.get_village_layout_snapshot()
	var departure: Vector2i = terrain.get_expedition_departure_cell()
	assert(terrain.get_layout_tile(departure) == "road","Expedition departure is not on the chosen paving tile")
	assert(terrain.is_at_expedition_departure(terrain.to_global(terrain.grid_to_local(departure))),"Cannot depart from the paving tile")
	assert(not terrain.is_at_expedition_departure(terrain.to_global(terrain.grid_to_local(departure+Vector2i(3,0)))),"Expedition trigger reaches beyond 5x5 tiles")
	var edge_cell := Vector2i.ZERO
	var frontier_cell := Vector2i.ZERO
	var found_frontier := false
	for cell in terrain.get_connected_map_cells():
		for offset in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
			if not terrain.can_add_layout_cell(cell+offset): continue
			edge_cell = cell
			frontier_cell = cell+offset
			found_frontier = true
			break
		if found_frontier: break
	assert(found_frontier and editor.mode_buttons.size() == 7)
	editor._set_mode(4)
	editor.hover_cell = frontier_cell
	editor.stroke_snapshot = original
	editor.stroke_changed = false
	editor.painting = true
	editor._paint_cell()
	editor._finish_paint()
	assert(terrain.is_exterior_cell(frontier_cell),"Tile add did not create ground")
	editor._undo()
	assert(not terrain.is_exterior_cell(frontier_cell),"Undo did not restore the empty tile")
	assert(terrain.set_layout_cell_present(frontier_cell,true))
	editor._set_mode(5)
	editor.hover_cell = edge_cell
	editor.stroke_snapshot = terrain.get_village_layout_snapshot()
	editor.stroke_changed = false
	editor.painting = true
	editor._paint_cell()
	editor._finish_paint()
	assert(not terrain.is_exterior_cell(edge_cell),"Tile delete did not remove ground")
	var edited: Dictionary = terrain.get_village_layout_snapshot()
	terrain.restore_village_layout_snapshot(original)
	terrain.load_village_map_layout()
	terrain.refresh_map_footprint()
	assert(terrain.get_village_layout_snapshot() == edited,"Tile additions and removals did not survive reload")
	terrain.restore_village_layout_snapshot(original)
	assert(not terrain.save_village_map_layout().is_empty())
	print("F12_TILE_ADD_DELETE_UNDO_SAVE_PASS")

func _smoke_map_editor() -> void:
	var terrain := $StoreExterior
	var editor := $VillageMapEditor
	var key := InputEventKey.new()
	key.keycode = KEY_F12
	key.pressed = true
	Input.parse_input_event(key)
	Input.flush_buffered_events()
	assert(editor.active and get_tree().paused and terrain.show_tile_grid)
	var camera_before: Vector2 = editor.camera.global_position
	var move_key := InputEventKey.new()
	move_key.keycode = KEY_D
	move_key.pressed = true
	Input.parse_input_event(move_key)
	Input.flush_buffered_events()
	editor._process(0.25)
	assert(editor.camera.global_position.x > camera_before.x+100.0,"Editor camera did not move with D")
	var move_release := InputEventKey.new()
	move_release.keycode = KEY_D
	move_release.pressed = false
	Input.parse_input_event(move_release)
	Input.flush_buffered_events()
	var pan_press := InputEventMouseButton.new()
	pan_press.button_index = MOUSE_BUTTON_MIDDLE
	pan_press.pressed = true
	pan_press.position = Vector2(600,300)
	Input.parse_input_event(pan_press)
	Input.flush_buffered_events()
	assert(editor.panning,"Editor did not start camera dragging")
	camera_before = editor.camera.global_position
	var pan_motion := InputEventMouseMotion.new()
	pan_motion.position = Vector2(640,280)
	pan_motion.relative = Vector2(40,-20)
	Input.parse_input_event(pan_motion)
	Input.flush_buffered_events()
	assert(editor.camera.global_position.x < camera_before.x-50.0 and editor.camera.global_position.y > camera_before.y+25.0,"Editor camera did not follow middle drag")
	var pan_release := InputEventMouseButton.new()
	pan_release.button_index = MOUSE_BUTTON_MIDDLE
	pan_release.pressed = false
	pan_release.position = Vector2(640,280)
	Input.parse_input_event(pan_release)
	Input.flush_buffered_events()
	assert(not editor.panning)
	var release := InputEventKey.new()
	release.keycode = KEY_F12
	release.pressed = false
	Input.parse_input_event(release)
	Input.flush_buffered_events()
	var close_key := InputEventKey.new()
	close_key.keycode = KEY_F12
	close_key.pressed = true
	Input.parse_input_event(close_key)
	Input.flush_buffered_events()
	assert(not editor.active and not get_tree().paused and not terrain.show_tile_grid)
	var picked := false
	for group_name in ["VillageDecor","VillageBuildings","VillageExtraHouses","NearbyHouses"]:
		if picked: break
		var group := get_node(group_name)
		for child in group.get_children():
			if picked: break
			var body := child as StaticBody2D
			if body == null or not body.visible: continue
			for piece in body.get_children():
				if picked: break
				var sprite := piece as Sprite2D
				if sprite == null or sprite.texture == null: continue
				var art := sprite.texture.get_image()
				for y in range(0,art.get_height(),48):
					if picked: break
					for x in range(0,art.get_width(),48):
						if art.get_pixel(x,y).a < 0.9: continue
						if editor._pick_object(sprite.to_global(Vector2(x,y))) == body:
							picked = true
							break
	assert(picked,"Cannot select any visible village sprite")
	var original: Dictionary = terrain.get_village_layout_snapshot()
	assert(editor.mode_buttons.size() == 7,"Tile editing tools are missing")
	var edge_cell := Vector2i.ZERO
	var frontier_cell := Vector2i.ZERO
	var found_frontier := false
	for cell in terrain.get_connected_map_cells():
		for offset in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
			if not terrain.can_add_layout_cell(cell+offset): continue
			edge_cell = cell
			frontier_cell = cell+offset
			found_frontier = true
			break
		if found_frontier: break
	assert(found_frontier,"No editable map edge was found")
	editor._set_mode(4)
	editor.hover_cell = frontier_cell
	editor.stroke_snapshot = terrain.get_village_layout_snapshot()
	editor.stroke_changed = false
	editor.painting = true
	editor._paint_cell()
	editor._finish_paint()
	assert(terrain.is_exterior_cell(frontier_cell),"Clicking an empty edge tile did not add ground")
	editor._undo()
	assert(not terrain.is_exterior_cell(frontier_cell),"Undo did not remove the added tile")
	assert(terrain.set_layout_cell_present(frontier_cell,true))
	assert(terrain.set_layout_cell_present(edge_cell,false))
	terrain.refresh_map_footprint()
	assert(not terrain.is_exterior_cell(edge_cell),"Deleting a tile did not remove ground")
	var added_cell: Vector2i = terrain.get_village_well_cell()+Vector2i(2,2)
	var added_key: String = terrain.add_layout_object("VillageDecor/OrchardTree1",added_cell)
	assert(not added_key.is_empty() and $VillageDecor.get_node_or_null(added_key.get_file()) != null,"Added object was not drawn")
	assert($VillageDecor.get_node(added_key.get_file()).get_node_or_null("Trunk") != null,"Added object lost its collision")
	var moved_cell: Vector2i = added_cell+Vector2i(1,0)
	terrain.set_layout_cell(added_key,moved_cell)
	terrain.refresh_village_layout()
	assert($VillageDecor.get_node(added_key.get_file()).global_position.is_equal_approx(terrain.to_global(terrain.grid_to_local(moved_cell))),"Added object did not move")
	terrain.remove_layout_object("VillageDecor/OrchardTree1")
	assert(not $VillageDecor/OrchardTree1.visible and $VillageDecor/OrchardTree1.collision_layer == 0,"Removed object is still visible or solid")
	assert(not terrain.save_village_map_layout().is_empty())
	var edited_snapshot: Dictionary = terrain.get_village_layout_snapshot()
	terrain.restore_village_layout_snapshot(original)
	terrain.load_village_map_layout()
	terrain.refresh_village_layout()
	assert(terrain.get_village_layout_snapshot() == edited_snapshot,"Tile and object edits did not survive reload")
	assert(terrain.is_exterior_cell(frontier_cell) and not terrain.is_exterior_cell(edge_cell),"Saved tile footprint was not rebuilt")
	assert($VillageDecor.get_node_or_null(added_key.get_file()) != null and not $VillageDecor/OrchardTree1.visible,"Saved object edits were not rebuilt")
	terrain.remove_layout_object(added_key)
	assert($VillageDecor.get_node_or_null(added_key.get_file()) == null,"Added object was not deleted")
	terrain.restore_village_layout_snapshot(original)
	var base_cell: Vector2i = terrain.get_village_building_cell(0)
	terrain.set_layout_cell("VillageBuildings/VillageBakery",base_cell+Vector2i(1,0))
	terrain.refresh_village_layout()
	assert(terrain.get_village_building_cell(0) == base_cell+Vector2i(1,0))
	assert($VillageBuildings/VillageBakery.global_position.is_equal_approx(terrain.to_global(terrain.grid_to_local(base_cell+Vector2i(1,0)))))
	var paint_cell: Vector2i = terrain.get_village_square_cell()+Vector2i(3,2)
	terrain.set_layout_tile(paint_cell,"grass")
	assert(terrain.get_layout_tile(paint_cell) == "grass")
	assert(not terrain.save_village_map_layout().is_empty())
	terrain.restore_village_layout_snapshot(original)
	terrain.load_village_map_layout()
	assert(terrain.get_village_building_cell(0) == base_cell+Vector2i(1,0))
	assert(terrain.get_layout_tile(paint_cell) == "grass")
	terrain.restore_village_layout_snapshot(original)
	assert(terrain.get_village_building_cell(0) == base_cell)
	assert(terrain.get_layout_tile(paint_cell) == str(original["tiles"].get(str(paint_cell.x)+","+str(paint_cell.y),"")))
	assert(not terrain.save_village_map_layout().is_empty())
	terrain.load_village_map_layout()
	assert(terrain.get_village_layout_snapshot() == original)
	print("F12_VILLAGE_MAP_EDITOR_SAVE_AND_RESTORE_PASS")
