extends "res://dev/script/check_received_world_art.gd"
## 새 그림을 실제 main/가구 슬롯/문 상태에 연결해 검사한다. 사용자 저장은 사용하지 않는다.
func image_for(node: Node) -> Image:
	return item_for(node).material.get_shader_parameter("frame_texture").get_image()

func run() -> void:
	if not OS.get_user_data_dir().contains("foodbag_checks"):
		push_error("Use isolated foodbag_checks project")
		get_tree().quit(2)
		return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--snap="): capture_prefix = arg.trim_prefix("--snap=")
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/art/pixel_shop_assets.json"))
	check(manifest.assets.size() == 220, "220 runtime pixel assets")
	for asset in manifest.assets:
		check(FileAccess.get_sha256(asset.path) == asset.sha256, "pixels unchanged " + asset.path)
		check(ReceivedWorldArt.texture(asset.path) != null, "imported " + asset.path)
	GameState.initialize_new_game()
	PlayerProgress.reset()
	world = load("res://scenes/shop/main.tscn").instantiate()
	world.get_node("TutorialDirector").enabled = false
	get_tree().root.add_child(world)
	get_tree().current_scene = world
	await frames(12)
	view = world.get_node("StoreView3D")
	manager = world.get_node("BuildManager")
	freeze(world)
	view.forced_hour = 12.0
	view.apply_hour(12.0)
	for node in view.objects_node.get_children(): node.free()
	sync()
	PixelShopArt.prepare()
	check(PixelShopArt._frames.size() == 96, "all supported body/rotation/stack combinations")
	check(PixelShopArt._goods.size() == 81, "all merchandise has glyph mapping")
	for f in PixelShopArt._frames.values():
		var rotation: int = [0,3,2,1].find(int(f.view))
		var node := make(str(f.build_id), rotation)
		var rack := str(f.build_id).ends_with("warehouse_rack")
		if not rack:
			node.stack_level = int(f.get("stack",1))
			node.ensure_slot_count()
		sync()
		var empty := image_for(node).get_data()
		check(item_for(node).received_art == PixelShopArt.STORAGE + str(f.body), "actual body " + str(f.body))
		var slots: Array = node.storage_slots if rack else node.slots
		var quantity := "amount" if rack else "stock"
		for i in slots.size():
			slots[i].item_id = "water" if i % 2 == 0 else "bread"
			slots[i][quantity] = 1
		sync()
		check((image_for(node).get_data() != empty) == bool(f.visible_front), "real stock visible only on front " + str(f.body))
		if bool(f.visible_front):
			var sparse := image_for(node).get_data()
			for slot in slots: slot[quantity] = 5
			sync()
			check(image_for(node).get_data() != sparse, "stock count changes display " + str(f.body))
			var water := image_for(node).get_data()
			for slot in slots: slot.item_id = "iron_ore"
			sync()
			check(image_for(node).get_data() != water, "item type changes display " + str(f.body))
		for slot in slots: slot[quantity] = 0
		sync()
		check(image_for(node).get_data() == empty, "empty returns exact clean body " + str(f.body))
		node.free()
		sync()
	for id in ["door", "production_door", "warehouse_door"]:
		for rot in range(4):
			var node := make(id,rot,Vector2i(4,7))
			world.get_node("DayManager").shop_open = false
			view.player.in_production_room = false
			view.player.in_warehouse_room = false
			sync()
			check(item_for(node).received_art == PixelShopArt.door_path(id,rot,false), "closed " + id + str(rot))
			world.get_node("DayManager").shop_open = true
			view.player.in_production_room = true
			view.player.in_warehouse_room = true
			sync()
			check(item_for(node).received_art == PixelShopArt.door_path(id,rot,true), "open updates without moving " + id + str(rot))
			node.free()
			sync()
	view.player.in_production_room = false
	view.player.in_warehouse_room = false
	view._room_mirror.sync()
	for key in view._items:
		if str(key).begins_with("wall") or str(key).begins_with("rwall"):
			check(view._items[key].received_art.contains("_tile.png") or view._items[key].received_art.contains("corner_"), "wall/window uses repeated image " + key)
	view.player.global_position = view.cell_to_world(Vector2(4.5,7.0))
	view.camera2d.reset_smoothing()
	view._sync_actors(0.016)
	view._update_wall_cutaway(1.0)
	for key in view._items:
		var item: Dictionary = view._items[key]
		if not item.get("cutaway",{}).is_empty():
			check(item.material.get_shader_parameter("frame_scale") == item.id_material.get_shader_parameter("frame_scale"), "wall color/mask shrink together " + key)
	var samples := ["shelf_1x1","wood_shelf_1x1","reinforced_shelf_2x1","modern_shelf_2x1"]
	for i in samples.size():
		var node := make(samples[i],0,Vector2i(1+i*2,2))
		for j in node.slots.size():
			node.slots[j].item_id = "water" if j%2==0 else "bread"
			node.slots[j].stock = 3 if i%2 else 0
	var stack := make("modern_shelf_2x1",0,Vector2i(2,5))
	stack.stack_level = 3
	stack.ensure_slot_count()
	for slot in stack.slots: slot.item_id = "forest_herb";slot.stock = 2
	var door := make("door",2,Vector2i(5,7))
	sync()
	await shot("stock-open")
	world.get_node("DayManager").shop_open = false
	sync()
	await shot("stock-closed")
	var rack := make("wood_warehouse_rack",0,Vector2i(6,5))
	rack.storage_slots[0].item_id = "iron_ore"
	rack.storage_slots[0].amount = 6
	sync()
	await shot("rack")
	for pair in [["drink_machine","bottled_water","water"],["magic_oven","bake_bread","bread"]]:
		var machine := make(pair[0],0,Vector2i(4,4)) as ProductionFacility
		var idle := image_for_after_sync(machine)
		machine.active_recipe_id = pair[1]
		machine.pending_item_id = pair[2]
		machine.pending_amount = 1
		machine.remaining_seconds = 15.0
		machine.production_state = ProductionFacility.ProductionState.PROCESSING
		sync()
		check(item_for(machine).production_state == 1, "actual processing state " + pair[0])
		check(image_for(machine).get_height() == idle.get_height()+24, "badge adds space without resizing original")
		var crop := image_for(machine).get_region(Rect2i(0,24,idle.get_width(),idle.get_height()))
		var preserved := true
		for x in idle.get_width():
			for y in idle.get_height():
				if idle.get_pixel(x,y).a > 0 and crop.get_pixel(x,y) != idle.get_pixel(x,y): preserved = false
		check(preserved, "opaque facility body pixels preserved")
		var earlier := image_for(machine).get_data()
		machine.remaining_seconds = 5.0
		sync()
		check(image_for(machine).get_data() != earlier, "progress updates from remaining time")
		machine._process(6.0)
		sync()
		check(machine.production_state == ProductionFacility.ProductionState.READY, "real completion " + pair[0])
		check(item_for(machine).production_state == 2, "ready badge " + pair[0])
		await shot("production-ready-" + pair[0])
		check(machine.collect_production(), "real output collected " + pair[0])
		sync()
		check(image_for(machine).get_data() == idle.get_data(), "collected returns clean idle body")
		machine.free()
		sync()
	check(not item_for(door).is_empty(), "shop entrance persists")
	# 셰이더 수정이 인물을 숨기지 않는지 실제 GPU 색 패스로 확인한다.
	for object in view.objects_node.get_children(): object.free()
	sync()
	view.player.global_position = view.cell_to_world(Vector2(5,5))
	view.camera2d.reset_smoothing()
	view._sync_actors(0.016)
	sync()
	var figure: PixelActorFigure = view._actors[view.player.get_instance_id()].figure
	check(figure.visible and figure._mesh.mesh.size.length() > 0, "actual player sprite is shown")
	if DisplayServer.get_name() != "headless":
		await frames(4)
		await RenderingServer.frame_post_draw
		var shown := get_viewport().get_texture().get_image().get_data()
		figure.set_shown(false)
		await frames(4)
		await RenderingServer.frame_post_draw
		check(get_viewport().get_texture().get_image().get_data() != shown, "player makes visible GPU pixels")
		figure.set_shown(true)
		await shot("player-clear")
	print("CHECK_PIXEL_SHOP checks=%d failures=%d" % [checks,failures])
	get_tree().quit(1 if failures else 0)

func image_for_after_sync(node: Node) -> Image:
	sync()
	return image_for(node)
