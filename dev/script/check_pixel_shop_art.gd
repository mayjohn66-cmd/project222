extends "res://dev/script/check_received_world_art.gd"
## 새 그림을 실제 main/가구 슬롯/문 상태에 연결해 검사한다. 사용자 저장은 사용하지 않는다.
func image_for(node: Node) -> Image:
	return item_for(node).material.get_shader_parameter("frame_texture").get_image()

func check_wall_tile(kind: String, direction: int) -> void:
	var path := PixelShopArt.SHELL + "%s_%d_tile.png" % [kind,direction]
	var image := ReceivedWorldArt.texture(path).get_image()
	if image.is_compressed(): image.decompress()
	var top := 44 if kind == "wall_full" else 66
	var upper := 15 if kind == "wall_full" else 12
	var lower := 34 if kind == "wall_full" else 27
	var sign := 1 if direction in [0,2] else -1
	var silhouette_ok := image.get_size() == Vector2i(64,128)
	var borders_ok := true
	for x in 64:
		var offset := sign * floori(float(x-32)/2.0)
		for y in 128:
			var inside := x >= 16 and x < 48 and y >= top+offset and y <= 104+offset
			if not is_equal_approx(image.get_pixel(x,y).a,1.0 if inside else 0.0): silhouette_ok = false
		if x < 16 or x >= 48: continue
		for i in range(105-top):
			if i >= upper and i < lower: continue
			if image.get_pixel(x,top+offset+i) != image.get_pixel(32,top+i): borders_ok = false
	check(silhouette_ok,"imported wall keeps exact 2:1 silhouette " + path)
	check(borders_ok,"imported cap/stripe/footer has no seam step " + path)

func run() -> void:
	if not OS.get_user_data_dir().contains("foodbag_checks"):
		push_error("Use isolated foodbag_checks project")
		get_tree().quit(2)
		return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--snap="): capture_prefix = arg.trim_prefix("--snap=")
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/art/pixel_shop_assets.json"))
	check(manifest.assets.size() == 332, "316 existing images plus 16 cold state images")
	for asset in manifest.assets:
		check(FileAccess.get_sha256(asset.path) == asset.sha256, "pixels unchanged " + asset.path)
		check(ReceivedWorldArt.texture(asset.path) != null, "imported " + asset.path)
	for kind in ["wall_full","window"]:
		for direction in 4: check_wall_tile(kind,direction)
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
	check(view._container.get_canvas() != world.get_node("Floor").get_canvas(), "render layer is separate from 2D day tint")
	var source := ReceivedWorldArt.texture(PixelShopArt.STORAGE+"bodies/shelf_1x1_0_stack1.png")
	var before := source.get_image().get_data()
	var normals := SpriteNormalMaps.texture(source)
	check(normals.get_size() == source.get_size(),"normal canvas matches original")
	check(SpriteNormalMaps.texture(source) == normals,"generated normals cached")
	check(source.get_image().get_data() == before,"normal calculation preserves source pixels")
	var normal_image := normals.get_image()
	var detail := false
	for x in normal_image.get_width():
		for y in normal_image.get_height():
			var n := normal_image.get_pixel(x,y)
			if absf(n.r-0.5) > 0.02 or absf(n.g-0.5) > 0.02: detail = true
	check(detail,"normal texture contains surface detail")
	var roof := load("res://art/world3d/moss_cottage/roof_tiles.png") as Texture2D
	check(SpriteNormalMaps.texture(roof).resource_path.ends_with("roof_tiles_n.png"),"authored normals take priority")
	for i in range(1,4):
		check(view._ground_material.get_shader_parameter("normal_%d" % i) is Texture2D,"actual floor normal bound "+str(i))
	view.forced_hour = 12.0
	view.apply_hour(12.0)
	for node in view.objects_node.get_children(): node.free()
	sync()
	PixelShopArt.prepare()
	check(PixelShopArt._frames.size() == 96, "all supported body/rotation/stack combinations")
	for f in PixelShopArt._frames.values():
		var rotation: int = [0,3,2,1].find(int(f.view))
		var node := make(str(f.build_id), rotation)
		var rack := str(f.build_id).ends_with("warehouse_rack")
		if not rack:
			node.stack_level = int(f.get("stack",1))
			node.ensure_slot_count()
		sync()
		var clean := image_for(node)
		var empty := clean.get_data()
		check(item_for(node).received_art == PixelShopArt.storage_path(f,rotation,false), "actual body " + str(f.body))
		check(item_for(node).material.get_shader_parameter("normal_texture").get_size() == Vector2(clean.get_size()),"actual furniture normal bound "+str(f.body))
		var slots: Array = node.storage_slots if rack else node.slots
		var quantity := "amount" if rack else "stock"
		for i in slots.size():
			slots[i].item_id = "water" if i % 2 == 0 else "bread"
			slots[i][quantity] = 1
		sync()
		check(image_for(node).get_data() == ReceivedWorldArt.texture(PixelShopArt.storage_path(f,rotation,true)).get_image().get_data(),"exact fixed stocked artwork " + str(f.body))
		check(item_for(node).material.get_shader_parameter("normal_texture").get_size() == Vector2(image_for(node).get_size()),"stocked picture normal matches canvas "+str(f.body))
		if bool(f.visible_front):
			check(image_for(node).get_data() != empty,"visible front changes from empty to stocked " + str(f.body))
		var sparse := image_for(node).get_data()
		var mesh_id: int = item_for(node).mesh.get_instance_id()
		check(image_for(node).get_size() == clean.get_size(),"stocked picture adds no icon/padding " + str(f.body))
		for slot in slots: slot[quantity] = 5
		sync()
		check(image_for(node).get_data() == sparse and item_for(node).mesh.get_instance_id() == mesh_id,"quantity changes keep same artwork without rebuilding " + str(f.body))
		for slot in slots: slot.item_id = "iron_ore"
		sync()
		check(image_for(node).get_data() == sparse,"item type keeps same common artwork " + str(f.body))

		for slot in slots: slot[quantity] = 0
		sync()
		check(image_for(node).get_data() == empty, "empty returns exact clean body " + str(f.body))
		node.free()
		sync()
	# 전용 상태 그림을 찾지 못해도 물품 종류/수량에 맞춘 모델을 생성하지 않는다.
	var saved_frames := PixelShopArt._frames.duplicate()
	for build_id in ["shelf_1x1","warehouse_rack"]:
		for frame_key in PixelShopArt._frames.keys():
			if str(frame_key).begins_with(build_id+":"): PixelShopArt._frames.erase(frame_key)
		var fallback := make(build_id,0)
		sync()
		var clean_mesh: Mesh = item_for(fallback).mesh.mesh
		var slots: Array = fallback.storage_slots if build_id == "warehouse_rack" else fallback.slots
		var quantity := "amount" if build_id == "warehouse_rack" else "stock"
		slots[0].item_id = "water"
		slots[0][quantity] = 1
		sync()
		var filled_mesh: Mesh = item_for(fallback).mesh.mesh
		var same_body := clean_mesh.get_surface_count() == filled_mesh.get_surface_count()
		if same_body:
			for surface in clean_mesh.get_surface_count():
				same_body = same_body and clean_mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX] == filled_mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
		check(same_body,"missing state artwork cannot synthesize individual goods "+build_id)
		var filled_id: int = item_for(fallback).mesh.get_instance_id()
		slots[0][quantity] = 5
		sync()
		check(item_for(fallback).mesh.get_instance_id() == filled_id,"missing artwork ignores quantity changes "+build_id)
		slots[0].item_id = "iron_ore"
		sync()
		check(item_for(fallback).mesh.get_instance_id() == filled_id,"missing artwork ignores product changes "+build_id)
		fallback.free()
		sync()
	PixelShopArt._frames = saved_frames
	for build_id in ["fridge_unit","freezer_unit"]:
		var unit: String = ContainerStockArt.COLD_UNITS[build_id]
		PreservationService.install(unit,true)
		var preview := ReceivedFurniturePreview.new()
		check(preview.show_shape(build_id),"cold blueprint has empty state picture "+build_id)
		check((preview.texture as AtlasTexture).atlas == ReceivedWorldArt.texture(ContainerStockArt.cold_pair(build_id,0).empty),"blueprint uses same empty artwork as placement "+build_id)
		preview.free()
		for rotation in 4:
			var cold := make(build_id,rotation)
			sync()
			check(not item_for(cold).stocked,"empty cold unit state "+build_id+str(rotation))
			var original_state := GameState.preservation_state.duplicate(true)
			var pair := ContainerStockArt.cold_pair(build_id,rotation)
			check(pair.ready and item_for(cold).stock_art_ready,"both cold state images imported "+build_id+str(rotation))
			check(image_for(cold).get_size() == ReceivedWorldArt.texture(ReceivedWorldArt.furniture_path(build_id,rotation)).get_image().get_size(),"cold state keeps original canvas "+build_id+str(rotation))
			check(item_for(cold).material.get_shader_parameter("normal_texture").get_size() == Vector2(image_for(cold).get_size()),"empty cold normal texture bound "+build_id+str(rotation))
			check(item_for(cold).received_art == pair.empty,"cold empty uses selected empty artwork "+build_id+str(rotation))
			var empty := image_for(cold).get_data()
			check(GameState.preservation_state == original_state,"rendering cannot settle or mutate cold contents")
			GameState.add_item("bread",4)
			check(PreservationService.deposit(unit,"bread",1) == 1,"real cold deposit "+unit)
			sync()
			check(item_for(cold).stocked and item_for(cold).received_art == pair.filled,"real deposit selects common filled artwork "+build_id+str(rotation))
			check((image_for(cold).get_data() == empty) == (build_id == "fridge_unit" and rotation in [2,3]),"cold visible contents change only through glass "+build_id+str(rotation))
			check(item_for(cold).material.get_shader_parameter("normal_texture").get_size() == Vector2(image_for(cold).get_size()),"filled cold normal texture bound "+build_id+str(rotation))
			var mesh_id: int = item_for(cold).mesh.get_instance_id()
			PreservationService.deposit(unit,"bread",1)
			sync()
			check(item_for(cold).mesh.get_instance_id() == mesh_id,"cold quantity changes cannot rebuild artwork")
			GameState.add_item("camp_bread",1)
			PreservationService.deposit(unit,"camp_bread",1)
			sync()
			check(item_for(cold).mesh.get_instance_id() == mesh_id,"cold product changes cannot rebuild artwork")
			PreservationService.withdraw(unit,"bread",2)
			PreservationService.withdraw(unit,"camp_bread",1)
			sync()
			check(not item_for(cold).stocked and image_for(cold).get_data() == empty,"actual withdrawal returns empty state "+build_id+str(rotation))
			cold.set_meta("is_build_preview",true)
			GameState.add_item("bread",1)
			PreservationService.deposit(unit,"bread",1)
			sync()
			check(not item_for(cold).stocked,"cold placement preview always uses empty state")
			PreservationService.withdraw(unit,"bread",1)
			cold.free()
			sync()
	# 실제 카메라·조명에서 네 방향을 나란히 확인. 입출고는 공통 보관 서비스를 쓴다.
	var cold_nodes: Array[Node2D] = []
	for rotation in 4:
		cold_nodes.append(make("fridge_unit",rotation,Vector2i(2+rotation*2,2)))
		cold_nodes.append(make("freezer_unit",rotation,Vector2i(1+rotation*2,5)))
	sync()
	await shot("cold-empty")
	GameState.add_item("bread",2)
	PreservationService.deposit("fridge","bread",1)
	PreservationService.deposit("freezer","bread",1)
	sync()
	for cold in cold_nodes: check(item_for(cold).stocked,"all placed units reflect shared cold bank "+str(cold.get_meta("build_id")))
	await shot("cold-filled")
	PreservationService.withdraw("fridge","bread",1)
	PreservationService.withdraw("freezer","bread",1)
	for cold in cold_nodes: cold.free()
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
	var tops := 0
	var top_corners := 0
	for key in view._items:
		var item: Dictionary = view._items[key]
		if item.get("signature","") == "pixel_wall" and str(item.received_art).contains("wall_full_"):
			check(view._items.has(str(key)+"_top"),"each tall wall segment has a connected top "+key)
		if not bool(item.get("wall_top",false)): continue
		tops += 1
		if str(key).contains("topcorner"): top_corners += 1
		check(item.material.get_shader_parameter("normal_base") == Vector3.UP,"top surface responds to light as a horizontal face "+key)
		check(item.mesh.mesh == item.id_mesh.mesh,"top geometry and picking geometry are identical "+key)
		for parameter in ["frame_offset","wall_top_enabled","wall_top_corner","wall_top_bounds","wall_top_start","wall_top_along","wall_top_outward","wall_top_profile_sign"]:
			check(item.material.get_shader_parameter(parameter) == item.id_material.get_shader_parameter(parameter),"top color/picking sampling matches "+key+" "+parameter)
	check(tops > 18 and top_corners == 9,"shop rear corner and four corners of both rooms are closed")
	var caps: Array = []
	for key in view._items:
		if bool(view._items[key].get("wall_endcap",false)): caps.append(key)
	check(caps.size() == 2,"both tall-to-window corners have an end face")
	for key in caps:
		var cap: Dictionary = view._items[key]
		var region: Vector4 = cap.material.get_shader_parameter("region")
		check(is_equal_approx(region.z,16.0/64.0),"thicker end face keeps native sixteen-pixel width "+key)
		var footprint: Vector3 = cap.max - cap.min
		check(is_equal_approx(maxf(footprint.x,footprint.y),0.5),"wall thickness grows outward by half a cell "+key)
		check(cap.id_material.get_shader_parameter("region") == region,"end face color and picking mask use the same source crop "+key)
		check(cap.material.get_shader_parameter("frame_texture") == ReceivedWorldArt.texture(cap.received_art),"end face reuses unchanged wall source "+key)
	view._wall_signature = ""
	view._sync_walls()
	var rebuilt_caps := 0
	for item in view._items.values():
		if bool(item.get("wall_endcap",false)): rebuilt_caps += 1
	check(rebuilt_caps == caps.size(),"wall rebuilding does not duplicate corner faces")
	var rebuilt_tops := 0
	for item in view._items.values():
		if bool(item.get("wall_top",false)): rebuilt_tops += 1
	check(rebuilt_tops == tops,"wall rebuilding does not duplicate top strips or corner patches")
	for key in view._items:
		if str(key).begins_with("wall") or str(key).begins_with("rwall"):
			check(view._items[key].material.get_shader_parameter("normal_texture") is Texture2D,"wall normal bound "+key)
			check(view._items[key].received_art.contains("_tile.png"), "wall/window uses repeated image " + key)
	# A 2-tile run must remain 2 equally spaced native strips at the floor boundary.
	var cases := [
		[Vector2(0,-0.3),Vector2(2,0),Vector3(0.5,0,0),Vector3(1,0,0)],
		[Vector2(2,0),Vector2(2.3,2),Vector3(2,0,0.5),Vector3(0,0,1)],
		[Vector2(0,2),Vector2(2,2.3),Vector3(0.5,0,2),Vector3(1,0,0)],
		[Vector2(-0.3,0),Vector2(0,2),Vector3(0,0,0.5),Vector3(0,0,1)],
	]
	for direction in 4:
		var c: Array = cases[direction]
		PixelShopArt.wall_run(view,"proportion_probe",c[0],c[1],direction,true,false)
		var first: MeshInstance3D = view._items["proportion_probe_0"].mesh
		var second: MeshInstance3D = view._items["proportion_probe_1"].mesh
		check(first.position.is_equal_approx(c[2]),"wall anchors meet exact floor edge " + str(direction))
		check((second.position-first.position).is_equal_approx(c[3]),"wall repeat advances exactly one tile " + str(direction))
		view._remove_item("proportion_probe_0")
		view._remove_item("proportion_probe_1")
		view._remove_item("proportion_probe_0_top")
		view._remove_item("proportion_probe_1_top")
	check(not PixelActorFigure.SPRITE_SHADER.code.contains("frame_scale"),"color shader cannot vertically compress artwork")
	check(not PixelActorFigure.SPRITE_ID_SHADER.code.contains("frame_scale"),"mask shader cannot vertically compress artwork")
	view.player.global_position = view.cell_to_world(Vector2(4.5,7.0))
	view.camera2d.reset_smoothing()
	view._sync_actors(0.016)
	view._update_wall_cutaway(1.0)
	for key in view._items:
		var item: Dictionary = view._items[key]
		if not item.get("cutaway",{}).is_empty():
			check(item.material.get_shader_parameter("cutaway_visibility") == item.id_material.get_shader_parameter("cutaway_visibility"), "wall color/mask fade together " + key)
			check(item.mesh.scale == Vector3.ONE and item.id_mesh.scale == Vector3.ONE, "native wall proportions fixed " + key)
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
	for hour in [6.0,12.0,18.0,22.0]:
		view.apply_hour(hour)
		await shot("hour-"+str(int(hour)))
	view.apply_hour(12.0)
	var rack := make("wood_warehouse_rack",0,Vector2i(6,5))
	rack.storage_slots[0].item_id = "iron_ore"
	rack.storage_slots[0].amount = 6
	sync()
	var steel := make("steel_warehouse_rack",0,Vector2i(4,5))
	steel.storage_slots[0].item_id = "bread"
	steel.storage_slots[0].amount = 1
	sync()
	check(image_for(steel).get_data() == load("res://art/received/shop_storage/stocked/steel_warehouse_rack_0.png").get_image().get_data(),"steel rack uses selected filled drawing")
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
	check(figure._material.get_shader_parameter("normal_texture") is Texture2D,"player frame normal bound")
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
		await check_lighting(figure)
	print("CHECK_PIXEL_SHOP checks=%d failures=%d" % [checks,failures])
	get_tree().quit(1 if failures else 0)

func image_for_after_sync(node: Node) -> Image:
	sync()
	return image_for(node)

func rendered() -> Image:
	await frames(4)
	await RenderingServer.frame_post_draw
	return view._viewport.get_texture().get_image()

func surface_materials(figure: PixelActorFigure) -> Array[ShaderMaterial]:
	var materials: Array[ShaderMaterial] = [view._ground_material,figure._material]
	for item in view._items.values():
		if item.has("received_art"): materials.append(item.material)
		elif item.material.shader == ReceivedWorldArt.FLOOR_SHADER: materials.append(item.material)
	return materials

func check_lighting(figure: PixelActorFigure) -> void:
	var materials := surface_materials(figure)
	view.apply_hour(12.0)
	var noon := await rendered()
	for material in materials: material.set_shader_parameter("use_normal",false)
	var flat := await rendered()
	check(flat.get_data() != noon.get_data(),"normal maps change actual GPU shading")
	for material in materials: material.set_shader_parameter("use_normal",true)
	var direction := view._sun.rotation_degrees
	view._sun.rotation_degrees.y += 90.0
	var turned := await rendered()
	check(turned.get_data() != noon.get_data(),"light direction changes shading with fixed color/energy")
	view._sun.rotation_degrees = direction
	var images: Array[Image] = []
	for hour in [6.0,12.0,18.0,22.0]:
		view.apply_hour(hour)
		images.append(await rendered())
	for i in range(1,images.size()):
		check(images[i].get_data() != images[i-1].get_data(),"morning/noon/evening/night render differently "+str(i))
	var night: Image = images.back()
	for lamp in view._lamps: lamp.visible = false
	var dark := await rendered()
	check(dark.get_data() != night.get_data(),"real ceiling lamps illuminate the shop at night")
	view.weather = {"kind":"rain","intensity":0.85}
	view.apply_hour(12.0)
	var rain := await rendered()
	check(rain.get_data() != noon.get_data(),"weather still affects real scene lights")
	view.weather = {"kind":"clear","intensity":0.0}
	view.season_override = "winter"
	view.apply_hour(12.0)
	var winter := await rendered()
	check(winter.get_data() != noon.get_data(),"season still affects real scene lights")
	view.season_override = ""
	view.apply_hour(12.0)
