extends "res://dev/script/world_art_preview.gd"

func _place_samples() -> void:
	super._place_samples()
	var builder = $BuildManager
	for sample in [["warehouse_rack",Vector2i(0,6),0],["warehouse_door",Vector2i(0,3),1],["production_door",Vector2i(2,0),0],["register",Vector2i(8,1),2]]:
		GameState.add_furniture(sample[0],1)
		builder.build_selection_state.restore_selection(builder.get_catalog_index_from_build_id(sample[0]),sample[2])
		var object = builder.build_placement_service.place_furniture(sample[0],sample[1])
		assert(object != null)
		if "door" in sample[0]:
			var expected: String = "warehouse" if sample[0] == "warehouse_door" else "production"
			assert(object.get_node("Visual").door_kind == expected)
			assert(expected in object.get_node("Visual").get_door_texture().resource_path)
	for id in ["shelf_1x1","shelf_2x1","shelf_3x1","register"]:
		for direction in range(4):
			var object = BuildObjectData.get_build_scene(id).instantiate()
			object.set_meta("build_id",id)
			object.set_meta("rotation_index",direction)
			$Objects.add_child(object)
			object.position = Vector2(10000,10000)
			builder.build_selection_state.restore_selection(builder.get_catalog_index_from_build_id(id),direction)
			builder.apply_current_size(object)
			var p: PackedVector2Array = object.get_node("Collision").polygon
			var area := 0.0
			for j in range(4): area += p[j].cross(p[(j+1)%4])
			var size: Vector2i = builder.get_current_size()
			assert(is_equal_approx(absf(area)*0.5,float(size.x*size.y)*1152.0))
			var guide: PackedVector2Array = builder.get_build_footprint_outline(Vector2i.ZERO)
			var origin: Vector2 = builder.to_local(builder.get_cell_world_position(Vector2i.ZERO))
			for j in range(4): assert((guide[j]-origin).distance_to(p[j])<0.01)
			var free_grid: Vector2 = [Vector2(0,0.25),Vector2(0.25,0),Vector2(0,-0.25),Vector2(-0.25,0)][direction]
			var free_point := Vector2((free_grid.x-free_grid.y)*48,(free_grid.x+free_grid.y)*24)
			assert(not Geometry2D.is_point_in_polygon(free_point,p),"Free half blocked")
			assert(Geometry2D.is_point_in_polygon(-free_point,p),"Occupied half missing")
			assert(object.get_node("Visual").VIEWS.size()==4)
			assert(object.get_node("Visual").VIEWS[0] != object.get_node("Visual").VIEWS[2])
			object.queue_free()
	builder.clear_build_selection()
	var hud = $UI/HUD
	var saved_money: int = GameState.money
	for amount in [0,500000,999999999,1000000000]:
		GameState.money = amount
		hud._update_money_digits()
		var rendered := ""
		for card in hud.money_digits.get_children():
			for child in card.get_children():
				if child is Label: rendered += child.text
		assert(rendered.strip_edges() == str(amount),"Money digits lost/truncated")
		assert(not hud.get_node("MoneyLabel").visible)
	GameState.money = 999999999 if OS.get_cmdline_user_args().has("--money-max") else saved_money
	hud._update_money_digits()
	if OS.get_cmdline_user_args().has("--guides"):
		for object in $Objects.get_children():
			if object.position.x>9000: continue
			var c = object.get_node_or_null("Collision")
			var p := PackedVector2Array()
			if c is CollisionPolygon2D: p = c.polygon
			elif c != null and c.get("collision_shape") != null: p = c.collision_shape.shape.points
			if p.is_empty(): continue
			var line := Line2D.new()
			line.points = p
			line.closed = true
			line.width = 1
			line.default_color = Color.CYAN
			line.z_index = 20
			object.add_child(line)
	print("CARDINAL_OK: 16 edge halves; guide agreement; distinct rear art; installed door patterns; money 0..10 digits")
