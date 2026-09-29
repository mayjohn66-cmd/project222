extends "res://dev/script/world_art_preview.gd"

func _place_samples() -> void:
	super._place_samples()
	var builder = $BuildManager
	var ids = ["shelf_1x1","shelf_2x1","shelf_3x1","register","warehouse_rack","drink_machine","door","production_door","warehouse_door"]
	for i in range(ids.size()):
		GameState.add_furniture(ids[i],3)
		GameState.set_build_quick_slot(i,ids[i])
	$UI/BuildQuickSlotBar.set_build_mode_active(true)
	for sample in [["register",Vector2i(8,1),1],["warehouse_rack",Vector2i(0,6),0]]:
		builder.build_selection_state.restore_selection(builder.get_catalog_index_from_build_id(sample[0]),sample[2])
		builder.build_placement_service.place_furniture(sample[0],sample[1])
	for id in ["shelf_1x1","shelf_2x1","shelf_3x1","register"]:
		for direction in range(4):
			var object = BuildObjectData.get_build_scene(id).instantiate()
			object.set_meta("build_id",id)
			object.set_meta("rotation_index",direction)
			$Objects.add_child(object)
			object.position = Vector2(10000,10000)
			builder.build_selection_state.restore_selection(builder.get_catalog_index_from_build_id(id),direction)
			builder.apply_current_size(object)
			var collision: CollisionPolygon2D = object.get_node("Collision")
			var p := collision.polygon
			var area := 0.0
			for j in range(4): area += p[j].cross(p[(j+1)%4])
			var size: Vector2i = builder.get_current_size()
			assert(is_equal_approx(absf(area)*0.5,float(size.x*size.y)*1152.0),"Half-area mismatch "+id)
			var guide: PackedVector2Array = builder.get_build_footprint_outline(Vector2i(0,0))
			var origin: Vector2 = builder.to_local(builder.get_cell_world_position(Vector2i(0,0)))
			for j in range(4): assert((guide[j]-origin).distance_to(p[j])<0.01,"Guide/collision mismatch")
			# Point in formerly blocked outer quarter must now be outside the solid.
			var free_point: Vector2 = [Vector2(-12,6),Vector2(12,6),Vector2(12,-6),Vector2(-12,-6)][direction]
			assert(not Geometry2D.is_point_in_polygon(free_point,p),"Half depth did not release space")
			assert(Geometry2D.is_point_in_polygon(-free_point,p))
			object.queue_free()
	if OS.get_cmdline_user_args().has("--backs"):
		for object in $Objects.get_children():
			if object.get_meta("build_id","") != "register" or object.position.x>9000: continue
			var direction: int = int(object.get_meta("rotation_index",0))+2
			object.set_meta("rotation_index",direction)
			builder.build_selection_state.restore_selection(builder.get_catalog_index_from_build_id("register"),direction)
			builder.apply_current_size(object)
	builder.clear_build_selection()
	for object in $Objects.get_children():
		if object.position.x>9000: continue
		var c = object.get_node_or_null("Collision")
		if c is CollisionPolygon2D and OS.get_cmdline_user_args().has("--guides"):
			var line := Line2D.new()
			line.points = c.polygon
			line.closed = true
			line.width = 1
			line.default_color = Color.CYAN
			line.z_index = 20
			object.add_child(line)
	for button in $UI/BuildQuickSlotBar.slot_buttons:
		assert(button.get_node("FurnitureIcon").texture != null)
	if OS.get_cmdline_user_args().has("--bag"):
		GameState.add_furniture("plant_small",1)
		GameState.add_furniture("magic_oven",1)
		$UI/BuildQuickSlotBar.set_inventory_open(true)
	print("SLIM_FURNITURE_OK: 16 rotated footprints have half area; guides match; outer quarters free; 9 slot icons")


