extends Node
var failures := 0
var checks := 0
func check(ok: bool,label: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(label)
func frames(n: int) -> void:
	for i in n: await get_tree().process_frame
func _ready() -> void: call_deferred("run")
func run() -> void:
	GameState.initialize_new_game()
	for step in OpeningJourneyFlow.SETTINGS.steps:
		if not step.get("optional",false): PlayerProgress.record_story_beat("tutorial_step:"+str(step["id"])+":done",1)
	PlayerProgress.record_story_beat(OpeningJourneyFlow.RAW_SALE,1)
	PlayerProgress.record_story_beat("resident_request:gatherer_herbs:accepted",1)
	FishingRecords.mark("fishing_rod:done")
	FishingRecords.mark("fish_request_neighbor:done")
	FishingRecords.mark("fishing_first_sale:done")
	GameState.add_item("fishing_rod_wood",1)
	for fish in FishingData.entries("fish").slice(0,4): FishingRecords.caught(str(fish["id"]))
	var world: Node = load("res://scenes/shop/main.tscn").instantiate()
	world.get_node("TutorialDirector").enabled = false
	get_tree().root.add_child(world)
	get_tree().current_scene = world
	await frames(30)
	var spots: FishingSpots = world.get_node("FishingSpots")
	var player: CharacterBody2D = world.get_node("Actors/Player")
	var view = world.get_node("StoreView3D")
	check(spots.points.size()==3,"all tile footprints placed")
	for id in spots.points:
		var entry: Dictionary = spots.points[id]
		player.global_position = spots.position_for(id)
		check(spots.can_cast_from(player.global_position,id),"stand casts "+id)
		check(not spots.can_cast_from(player.global_position+Vector2(40,0),id),"outside stand rejected "+id)
		var query := PhysicsPointQueryParameters2D.new()
		query.collision_mask = 1
		query.position = player.global_position
		check(get_viewport().world_2d.direct_space_state.intersect_point(query).is_empty(),"dock walkable "+id)
		query.position = spots._world(Vector2(entry["float_cell"]))
		check(not get_viewport().world_2d.direct_space_state.intersect_point(query).is_empty(),"water blocked "+id)
		var body_query := PhysicsShapeQueryParameters2D.new()
		body_query.shape = player.get_node("CollisionShape2D").shape
		body_query.collision_mask = 1
		body_query.transform = player.global_transform
		body_query.motion = query.position-player.global_position
		check(get_viewport().world_2d.direct_space_state.cast_motion(body_query)[0]<1.0,"walking into water stops "+id)
		query.position = spots.visitor_position_for(id)
		check(get_viewport().world_2d.direct_space_state.intersect_point(query).is_empty(),"visitor on land "+id)
		var route := VillageRoutine.route(world,spots.visitor_spawn_for(id),spots.visitor_position_for(id))
		check(not route.is_empty(),"visitor route "+id)
		check(not VillageRoutine.route(world,spots.visitor_position_for(id),spots.position_for(id)).is_empty(),"land to dock route "+id)
		if is_instance_valid(view.get("_viewport")):
			check(not spots.tile_keys.get(id,[]).is_empty(),"rendered tiles "+id)
			for key in spots.tile_keys.get(id,[]):
				var mat: ShaderMaterial = view._items[key]["material"]
				check(mat.shader==ReceivedWorldArt.FLOOR_SHADER and mat.get_shader_parameter("normal_1")!=null,"lit normals "+key)
		var camera = player.get_node_or_null("Camera2D")
		if camera != null: camera.global_position = player.global_position
		await frames(15)
		for arg in OS.get_cmdline_user_args():
			if arg.begins_with("--snap=") and DisplayServer.get_name()!="headless":
				await RenderingServer.frame_post_draw
				get_viewport().get_texture().get_image().save_png(arg.trim_prefix("--snap=")+"_"+id+".png")
	world.get_node("DayManager").current_hour = 20
	player.global_position = spots.position_for("fish_bank")
	await frames(20)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--snap=") and DisplayServer.get_name()!="headless":
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(arg.trim_prefix("--snap=")+"_night.png")
	world.queue_free()
	await frames(3)
	print("[Fishing tiles] checks=",checks," failures=",failures)
	get_tree().quit(1 if failures else 0)
