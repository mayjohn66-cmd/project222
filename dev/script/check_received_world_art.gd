extends Node
## 실제 가구 씬/렌더러 검사. 재고와 위치는 시험 준비값이며 사용자 저장을 쓰지 않는다.
var checks := 0
var failures := 0
var world: Node2D
var view: StoreView3D
var manager: Node
var capture_prefix := ""

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func frames(n: int = 3) -> void:
	for i in n: await get_tree().process_frame

func freeze(node: Node) -> void:
	node.set_process(false)
	node.set_physics_process(false)
	if node is Timer: node.stop()
	for child in node.get_children(): freeze(child)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	run.call_deferred()

func make(id: String, rotation: int, anchor: Vector2i = Vector2i(3,3)) -> Node2D:
	manager.build_selection_state.restore_selection(manager.furniture_catalog.find(id), rotation)
	var furniture: Node2D = manager.build_placement_service._create_furniture_instance(id)
	manager.build_placement_service._apply_placement_metadata(furniture, id, anchor)
	view.objects_node.add_child(furniture)
	furniture.global_position = view.cell_to_world(Vector2(anchor))
	manager.build_placement_service.apply_current_size_callable.call(furniture)
	manager.build_placement_service._configure_new_shelf(furniture,id)
	freeze(furniture)
	return furniture

func item_for(node: Node) -> Dictionary:
	var prefix := "wmount" if Furniture3DData.get_row(str(node.get_meta("build_id")))["kind"] in ["door", "wall_plate"] else "furn"
	return view._items.get(prefix + str(node.get_instance_id()) + ("a" if prefix == "wmount" else ""), {})

func sync() -> void:
	view._sync_furniture()
	view._sync_camera()
	view._sort_and_update()

func shot(name: String) -> void:
	if capture_prefix.is_empty() or DisplayServer.get_name() == "headless": return
	await frames(4)
	await RenderingServer.frame_post_draw
	check(get_viewport().get_texture().get_image().save_png(capture_prefix + "-" + name + ".png") == OK, "capture " + name)

func run() -> void:
	if not OS.get_user_data_dir().contains("foodbag_checks"):
		push_error("Use isolated foodbag_checks project")
		get_tree().quit(2)
		return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--snap="): capture_prefix = arg.trim_prefix("--snap=")
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/art/received_assets.json"))
	check(manifest.assets.size() == 147, "147 selected unchanged originals")
	for asset in manifest.assets:
		check(FileAccess.get_sha256(asset.path) == asset.sha256, "exact source pixels: " + asset.path)
		check(ReceivedWorldArt.texture(asset.path) != null, "imported texture: " + asset.path)
	for gender in ["male", "female"]:
		for expression in ["neutral", "smile", "flustered", "surprised", "worried", "tired", "determined"]:
			check(PlayerPortraits.find_for(gender, expression).resource_path.contains("/aligned/"), "aligned portrait " + gender + expression)
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
	check(view._ready_done, "actual main renderer ready")
	check(view.floor_node.tile_width == 96 and view.floor_node.tile_height == 48, "logical coordinate grid preserved")
	check(is_equal_approx(view.tile_low, 64.0), "native 64x32 display")
	check(is_equal_approx(view.camera2d.zoom.x, 64.0 / 96.0), "2D and 3D share camera scale")
	check(view._ground_material.shader == ReceivedWorldArt.FLOOR_SHADER, "shop floor uses supplied tiles")
	var px := view._camera.unproject_position(Vector3(0.5,0.0,-0.5)).x - view._camera.unproject_position(Vector3(-0.5,0.0,0.5)).x
	check(absf(px - 64.0) < 0.05, "one diamond is exactly 64 display pixels")
	for kind in ["tile","wood","grass","dirt","road","paving"]:
		check(ReceivedWorldArt.floor_material(kind) != null, "three floor variants " + kind)
	check(ReceivedWorldArt.floor_material("snow") == null, "winter snow retains existing material")
	view.forced_hour = 12.0
	view.apply_hour(12.0)
	for node in view.objects_node.get_children(): node.free()
	sync()
	var ids: Array[String] = []
	var file := FileAccess.open(ReceivedWorldArt.CSV,FileAccess.READ)
	file.get_csv_line()
	while not file.eof_reached():
		var row := file.get_csv_line()
		if row.size() >= 3 and row[0] not in ids: ids.append(row[0])
	check(ids.size() == 21,"21 furniture types with rotation mapping")
	for id in ids:
		for rotation in range(4):
			var node := make(id, rotation)
			# Preview exercises every prepared image, including the static shelf illustrations.
			node.set_meta("is_build_preview", true)
			node.set_meta("preview_valid",true)
			sync()
			var item := item_for(node)
			var expected := ReceivedWorldArt.furniture_path(id,rotation)
			var pixel_frame := PixelShopArt.frame(id, rotation)
			if not pixel_frame.is_empty(): expected = PixelShopArt.storage_path(pixel_frame,rotation,false)
			if id in ["door","production_door","warehouse_door"]: expected = PixelShopArt.door_path(id,rotation,false)
			check(item.get("received_art", "") == expected, "selected rotation " + id + str(rotation))
			check(item["id_material"].shader == PixelActorFigure.SPRITE_ID_SHADER, "alpha silhouette mask " + id)
			check(item["mesh"].position == item["id_mesh"].position, "matching color/mask origin " + id)
			node.set_meta("preview_valid",false)
			sync()
			check(item_for(node).art_tint.r > item_for(node).art_tint.g,"invalid preview turns red " + id)
			node.free()
			sync()
		check(ReceivedWorldArt.furniture_path(id,4) == ReceivedWorldArt.furniture_path(id,0),"rotation wraps " + id)
	var shelf := make("shelf_2x1", 0)
	sync()
	check(item_for(shelf).has("received_art"),"empty shelf shows no painted goods")
	for i in shelf.slots.size():
		var slot: Dictionary = shelf.slots[i]
		slot["item_id"] = "water"
		slot["stock"] = 4
		shelf.slots[i] = slot
	sync()
	check(item_for(shelf).has("received_art"),"fully stocked single shelf uses art")
	shelf.slots[0]["stock"] = 0
	sync()
	check(item_for(shelf).has("received_art"),"partial stock retains common stocked drawing")
	shelf.slots[0]["stock"] = 4
	shelf.stack_level = 2
	sync()
	check(item_for(shelf).has("received_art"),"stacked shelf retains actual layer count")
	shelf.free()
	var rack := make("warehouse_rack",0)
	sync()
	check(item_for(rack).has("received_art"),"empty warehouse uses empty frame")
	rack.storage_slots[0]["item_id"] = "dry_branch"
	rack.storage_slots[0]["amount"] = 12
	sync()
	check(item_for(rack).has("received_art"),"loaded warehouse displays fixed stocked drawing")
	rack.storage_slots[0]["amount"] = 0
	sync()
	check(item_for(rack).has("received_art"),"warehouse becomes empty again")
	rack.free()
	var fallback := make("modern_shelf_2x1",0)
	sync()
	check(item_for(fallback).has("received_art"),"modern tier uses dedicated empty pixel body")
	fallback.free()
	check(ReceivedWorldArt.texture("res://art/received/no_such.png") == null,"missing texture safely falls back")
	for variant in ["round","pine","dead","birch","big_oak","cherry","poplar","willow","apple"]:
		check(ReceivedWorldArt.nature(view,"nature_test",Vector2.ZERO,Vector2.ONE,{"style":"tree","variant":variant},"fixture"),"supplied nature " + variant)
		check(view._items.nature_test["mesh"].position == view._items.nature_test["id_mesh"].position,"nature silhouette position " + variant)
	view._remove_item("nature_test")
	check(not ReceivedWorldArt.nature(view,"nature_test",Vector2.ZERO,Vector2.ONE,{"style":"tree","variant":"autumn"},"fixture"),"autumn leaf colors use seasonal model")
	check(not ReceivedWorldArt.nature(view,"nature_test",Vector2.ZERO,Vector2.ONE,{"style":"flower_bush","variant":"berry"},"fixture"),"harvestable berry display preserved")
	for kind in view.village._ground:
		if kind != "grass" or view.current_season() != "winter":
			check(view.village._ground[kind].material.shader == ReceivedWorldArt.FLOOR_SHADER,"outside ground connected " + str(kind))
	for name in view._room_mirror._floors:
		check(view._room_mirror._floors[name].material.shader == ReceivedWorldArt.FLOOR_SHADER,"room floor connected " + str(name))
	# 받은 계산대와 실제 인물의 앞뒤 깊이 순서를 함께 검증한다.
	var counter := make("register",0,Vector2i(3,3))
	sync()
	view.player.global_position = view.cell_to_world(Vector2(3.5,2.0))
	view._sync_actors(0.016)
	view._sort_and_update()
	var figure: PixelActorFigure = view._actors[view.player.get_instance_id()].figure
	check(float(figure._material.get_shader_parameter("rank")) < float(item_for(counter).material.get_shader_parameter("rank")),"player behind uploaded counter")
	view.player.global_position = view.cell_to_world(Vector2(3.5,4.0))
	view._sync_actors(0.016)
	view._sort_and_update()
	check(float(figure._material.get_shader_parameter("rank")) > float(item_for(counter).material.get_shader_parameter("rank")),"player in front of uploaded counter")
	counter.free()
	# 최종 오두막 면 질감이 기존 임시 틀보다 우선되는지 실제 재질 생성으로 확인한다.
	var rule: Dictionary = {}
	for candidate in VillageMirror.load_rules():
		if str(candidate.get("asset", "")) == "moss_cottage":
			rule = candidate.duplicate()
			break
	check(not rule.is_empty(), "actual cottage rule is present")
	var params := {"ts":view.texture_size,"block_px":view.block_px,"unit_px_z":(view.tile_low/sqrt(2.0))*cos(deg_to_rad(30.0))}
	var cottage := VillageAssets.build_gable(Vector2(10,-6),Vector2(13,-3),rule,params)
	var used := 0
	for spec in cottage.specs:
		if bool(spec.get("real",false)):
			check(spec.tex.resource_path.begins_with("res://art/received/world3d/moss_cottage/"),"final cottage texture " + str(spec.name))
			used += 1
	check(used >= 8,"actual cottage uses final facade/roof/details")
	view._set_mesh_item("received_cottage",cottage.mesh,VillageAssets.make_materials(cottage.specs),Vector2(10,-6),Vector2(13,-3),cottage.total_blocks,"fixture")
	view.player.global_position = view.cell_to_world(Vector2(11.5,-4.5))
	view.camera2d.reset_smoothing()
	sync()
	await shot("cottage")
	view._remove_item("received_cottage")
	for season in ["spring","summer","autumn","winter"]:
		view.season_override = season
		view.village.set_season(season)
		view.village.sync_ground()
		check(view.village._ground.has("grass"),"season ground exists " + season)
		if season == "winter":
			check(view.village._ground.grass.material.shader != ReceivedWorldArt.FLOOR_SHADER,"winter retains actual snow ground")
		else:
			check(view.village._ground.grass.material.shader == ReceivedWorldArt.FLOOR_SHADER,"supplied seasonal grass " + season)
	view.season_override = "spring"
	view.village.set_season("spring")
	view.village.sync_ground()
	view.player.global_position = view.cell_to_world(Vector2(4.5,5.5))
	view.camera2d.reset_smoothing()
	view._sync_actors(0.016)
	var shape_preview := FurniturePreview.new()
	add_child(shape_preview)
	await frames()
	shape_preview.show_furniture("register")
	check(shape_preview.received_preview.visible and not shape_preview.display.visible, "blueprint shows supplied shape")
	shape_preview.show_furniture("modern_shelf_2x1")
	check(shape_preview.received_preview.visible and not shape_preview.display.visible, "blueprint uses modern empty body")
	shape_preview.show_furniture("steel_warehouse_rack")
	check((shape_preview.received_preview.texture as AtlasTexture).atlas == ReceivedWorldArt.texture(ReceivedWorldArt.furniture_path("steel_warehouse_rack",0)),"blueprint and empty placed rack share the same body")
	shape_preview.free()
	var sample := ["register","shelf_2x1","drink_machine","plant_small","magic_oven","fridge_unit","freezer_unit","night_lantern"]
	for i in sample.size():
		var node := make(sample[i],0,Vector2i(1+(i%4)*2,1+(i/4)*3))
		if node.get("slots") != null:
			for slot in node.slots: slot["item_id"]="water";slot["stock"]=4
	sync()
	view._sort_and_update()
	await shot("shop")
	var day_lights: Array = [view._sun.light_color,view._sun.light_energy,view._env.ambient_light_color,view._env.ambient_light_energy]
	view.apply_hour(23.0)
	view._sort_and_update()
	var night_lights: Array = [view._sun.light_color,view._sun.light_energy,view._env.ambient_light_color,view._env.ambient_light_energy]
	check(day_lights != night_lights,"scene lights respond to day/night")
	await shot("night")
	view.apply_hour(12.0)
	# Real camera motion and deterministic artist-independent floor mapping.
	view.player.global_position += Vector2(48,24)
	view.camera2d.reset_smoothing()
	sync()
	await shot("moved")
	print("CHECK_RECEIVED_ART checks=%d failures=%d" % [checks,failures])
	get_tree().paused = false
	get_tree().quit(1 if failures > 0 else 0)
