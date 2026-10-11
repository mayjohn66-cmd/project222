extends "res://dev/script/check_village_sprite_art.gd"
const SETTINGS := preload("res://scenes/expedition/rooms/default_room_settings.tres")
var room_view: ExpeditionRoomView

func run() -> void:
	GameState.initialize_new_game()
	PlayerProgress.reset()
	world = load("res://scenes/shop/main.tscn").instantiate()
	world.get_node("TutorialDirector").enabled = false
	get_tree().root.add_child(world)
	get_tree().current_scene = world
	await frames(12)
	view = world.get_node("StoreView3D")
	check(view.exterior.is_wild(),"new game keeps construction gating")
	PlayerProgress.record_story_beat(OpeningTerrain.END_STEP,1)
	check(not view.exterior.is_wild(),"post-tutorial terrain available")
	freeze(world)
	var removed_well := world.get_node("VillageDecor/VillageWell") as StaticBody2D
	check(bool(removed_well.get_meta("settlement_layout_removed",false)) and not removed_well.visible,"removed original well remains absent")
	var well := VillageSettlement.find_site(world,"VillageDecor/VillageWell")
	check(well != null and well != removed_well,"retained edited-map well is selected")
	# Only show the surviving placement in this unsaved graphics fixture.
	well.visible = true
	well.collision_layer = 1
	well.get_node("Rim").disabled = false
	view.village.reset_signatures()
	view.village.sync_ground()
	sync()
	check(item(well).get("village_sprite_id","") == "village_well","live well uses transparent 2D image")
	var original_position := well.global_position
	var polygon := (well.get_node("Collision3D") as CollisionPolygon2D).polygon.duplicate()
	var fixtures := Node2D.new()
	world.add_child(fixtures)
	for axis in 2:
		for mirrored in [false,true]:
			var body := StaticBody2D.new()
			body.collision_layer = 1
			fixtures.add_child(body)
			var base := view.world_to_cell(well.global_position)+Vector2(3+axis*3,0 if not mirrored else 3)
			body.global_position = view.cell_to_world(base)
			var art := VillageArt.new()
			art.art_path = "res://art/world/village_decor_v1/low_wall.png"
			art.scale.x = -1.0 if mirrored else 1.0
			body.add_child(art)
			var size := Vector2(4,.5) if axis == 0 else Vector2(.5,4)
			view.village._apply_collision(body,base-size*.5,base+size*.5)
			var shape := body.get_node("Collision3D") as CollisionPolygon2D
			var before := shape.polygon.duplicate()
			var key := "EnvironmentWall%d%d" % [axis,int(mirrored)]
			var result := VillageSpriteArt.render(view,key,body,base-size*.5,base+size*.5,key)
			var entry: Dictionary = view._items[key]
			check(entry.village_sprite_path.ends_with("low_wall_%d.png" % (axis if not mirrored else 1-axis)),"wall axis compensates saved mirroring")
			check(result.rect.size.distance_to(size) < .001,"wall image ground matches original axis")
			check(shape.polygon == before,"wall collision unchanged by sprite")
			check(entry.mesh.mesh is QuadMesh,"wall is a 2D plane")
			check(entry.mesh.position == entry.id_mesh.position,"wall mask anchored with color")
			var tex := entry.material.get_shader_parameter("frame_texture") as Texture2D
			var bounds := tex.get_image().get_used_rect()
			var drawn: Vector2 = entry.mesh.mesh.size
			check(is_equal_approx(drawn.x/drawn.y,float(bounds.size.x)/bounds.size.y),"wall retains pixel proportions")
			check(entry.material.get_shader_parameter("normal_texture") != null,"wall normal-map light connected")
			await get_tree().physics_frame
			check(contains_body(body.global_position,body),"wall blocks actual player query")
			check(not contains_body(view.cell_to_world(base+Vector2(7,7)),body),"outside wall remains traversable")
	view.camera2d.global_position = well.global_position+Vector2(200,-40)
	view.camera2d.reset_smoothing()
	view.camera2d.force_update_scroll()
	var lit_frames: Array[Image] = []
	for hour in [12.0,22.0]:
		view.forced_hour = hour
		view.apply_hour(hour)
		sync()
		var lit := await room_capture("environment_village_%d" % int(hour))
		if lit != null: lit_frames.append(lit)
	if lit_frames.size() == 2: check(lit_frames[0].get_data() != lit_frames[1].get_data(),"well and walls react to actual day/night light")
	check(well.global_position == original_position and (well.get_node("Collision3D") as CollisionPolygon2D).polygon == polygon,"well position and collider remain unchanged")
	fixtures.queue_free()
	world.queue_free()
	await frames()
	room_view = load("res://scenes/expedition/rooms/expedition_room.tscn").instantiate()
	add_child(room_view)
	await frames()
	room_view.set_physics_process(false)
	room_view.stage.set_process(false)
	check(ExpeditionEnvironmentArt.assets().size() == 40,"all environment mappings indexed")
	for row in ExpeditionEnvironmentArt.assets().values():
		check(FileAccess.get_sha256(str(row.path)) == str(row.sha256),"chosen pixels: " + str(row.id))
		var node := ExpeditionSpriteArt.create_row(room_view.stage._content,row,Vector3.ZERO)
		check(node != null and node.mesh is QuadMesh,"environment drawing renders: " + str(row.id))
		if node == null: continue
		var tex := node.material_override.get_shader_parameter("frame_texture") as Texture2D
		var bounds := tex.get_image().get_used_rect()
		check(is_equal_approx(node.mesh.size.x/node.mesh.size.y,float(bounds.size.x)/bounds.size.y),"native aspect: " + str(row.id))
		check(node.material_override.get_shader_parameter("normal_texture") != null,"environment normal map: " + str(row.id))
		node.queue_free()
	for region in ["forest","mine","swamp","hidden_ruins","meadow","river_valley"]:
		var room := ExpeditionRoomModel.new()
		room.setup(SETTINGS,ExpeditionAttackProfile.new(),80,100,12,3,{},1,false,"")
		room_view.model = room
		room_view.region_id = region
		room_view.weather_overlay.environment = {"season":"spring","weather":"clear"}
		room_view.stage.rebuild(room,region)
		room_view.stage._layout()
		room_view.stage._sync(room,.016)
		await frames()
		check(room_view.stage._pixel_floor_material != null,"shared ground tiles: " + region)
		check(room_view.stage._pixel_floor.mesh is PlaneMesh,"flat ground image without thick platform: " + region)
		var scenery_count := 0
		for node in room_view.stage._content.get_children():
			if node.has_meta("environment_sprite_key"):
				scenery_count += 1
				check(node.mesh is QuadMesh and node.scale == Vector3.ONE and node.rotation == Vector3.ZERO,"scenery uses unwarped camera-facing pixels: " + region)
		check(scenery_count > 25,"actual populated surroundings: " + region)
		for value in room_view.stage._scenery._cache.values(): check(value.has("pixel_key"),"every active scenery template is 2D: " + region)
		if region in ["swamp","river_valley"]:
			check(room_view.stage._pixel_floor.get_meta("puddles").size() > 0,"swamp puddles reuse water images")
		await room_capture("environment_"+region)
	var walls := []
	for rotation in 4:
		var node := ExpeditionEnvironmentArt.create(room_view.stage,"r_wall_2",Vector2.ZERO,1.3,float(rotation)*PI*.5)
		check(str(node.get_meta("expedition_sprite_id")).ends_with("rot%d" % rotation),"ruin wall picks corresponding direction")
		check(float(node.get_meta("environment_uniform_scale")) == 1.3,"uniform scenery scale includes anchor")
		walls.append(node)
	var winter := ExpeditionEnvironment.floor_tint(Color.WHITE,{"season":"winter","weather":"snow"},true)
	var summer := ExpeditionEnvironment.floor_tint(Color.WHITE,{"season":"summer","weather":"clear"},true)
	check(not winter.is_equal_approx(summer),"season/weather floor tint remains active")
	print("[환경 도트 연결] 검사 ",checks," / 실패 ",failures)
	get_tree().quit(1 if failures > 0 else 0)

func room_capture(name: String) -> Image:
	if DisplayServer.get_name() == "headless": return null
	await frames(6)
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	image.save_png("user://"+name+".png")
	return image
