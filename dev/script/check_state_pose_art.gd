extends "res://dev/script/check_village_sprite_art.gd"
## 실제 렌더와 벤치 중단/종료 복원, 남녀·앞뒤·바닥 자세, 계절/상태 빛과 마스크를 확인한다.

func run() -> void:
	GameState.initialize_new_game()
	PlayerProgress.reset()
	world = load("res://scenes/shop/main.tscn").instantiate()
	world.get_node("TutorialDirector").enabled = false
	get_tree().root.add_child(world)
	get_tree().current_scene = world
	await frames(12)
	view = world.get_node("StoreView3D")
	PlayerProgress.record_story_beat(OpeningTerrain.END_STEP,1)
	check(not view.exterior.is_wild(),"post-tutorial ground transition")
	freeze(world)
	for id in NatureStateArt.assets():
		var row: Dictionary = NatureStateArt.assets()[id]
		check(FileAccess.get_sha256(str(row.path)) == row.sha256,"state pixels selected: " + str(id))
	var index := 0
	for tint in ["ffffff","ff9a84","ffe48a","ffc070"]:
		var rule := {"style":"tree","variant":"autumn","season_leaf":Color.html(tint)}
		var key := "state_tree_%d" % index
		var lo := Vector2(index*1.6,0)
		check(ReceivedWorldArt.nature(view,key,lo,lo+Vector2.ONE,rule,key),"autumn variant uses sprite")
		check(view._items[key].has("nature_state"),"autumn model replaced")
		check(view._items[key].material.get_shader_parameter("normal_texture") != null,"autumn shares normal geometry")
		index += 1
	for state in ["ready","empty"]:
		var rule := {"style":"flower_bush","variant":"berry","berry_state":state}
		var key: String = "state_berry_"+str(state)
		check(ReceivedWorldArt.nature(view,key,Vector2(2,2),Vector2(3,3),rule,key),"berry state uses sprite")
		check(view._items[key].nature_state == "berry_"+state,"correct berry state")
	var original := ReceivedWorldArt.texture("res://art/received/nature/iso_tree_round.png").get_image()
	var autumn := ReceivedWorldArt.texture(str(NatureStateArt.assets().autumn_orange.path)).get_image()
	check(original.get_size() == autumn.get_size(),"season preserves canvas")
	for y in original.get_height():
		for x in original.get_width():
			check(original.get_pixel(x,y).a == autumn.get_pixel(x,y).a,"season preserves silhouette alpha")
			# 원본 가져오기는 투명 여백 RGB를 채운다. 보이는 픽셀과 알파만 비교한다.
			if y >= 82 and original.get_pixel(x,y).a > 0: check(original.get_pixel(x,y) == autumn.get_pixel(x,y),"trunk and ground unchanged")
	for id in ActorPoseArt.assets():
		var row: Dictionary = ActorPoseArt.assets()[id]
		check(FileAccess.get_sha256(str(row.path)) == row.sha256,"pose source selected: " + str(id))
		var set_data := ActorSpriteFrames.load_set(ActorPoseArt.PREFIX+str(id))
		check(not set_data.is_empty() and set_data.has("static_direction"),"only prepared static pose")
		check(is_equal_approx(float(set_data.reference_height),84.0),"seated scale uses standing height")
	var modern := StoryNpc.new()
	var ordinary = load("res://script/actor/customer.gd").new()
	ordinary.customer_type_id = "commuter"
	ordinary.add_to_group("customer")
	check(StoreActorVisuals.sprite_key(ordinary,"commuter") == "normal","regular customers keep fantasy group art; modern costume is explicit prologue only")
	ordinary.free()
	modern.setup({"npc_id":"art-check","lines":[]})
	modern.set_meta("look_key","commuter")
	world.get_node("Actors").add_child(modern)
	modern.set_physics_process(false)
	modern.global_position = view.cell_to_world(Vector2(1.5,5.0))
	var smith := VillageResident.new()
	smith.resident_id = "village_blacksmith"
	smith.set_meta("look_key","story_npc")
	world.get_node("Actors").add_child(smith)
	smith.set_physics_process(false)
	smith.global_position = view.cell_to_world(Vector2(3.5,5.0))
	view._sync_actors(0.016)
	for pair in [[modern,"pose:commuter"],[smith,"pose:blacksmith"]]:
		var figure: PixelActorFigure = view._actors[pair[0].get_instance_id()].figure
		check(figure.sprite_key == str(pair[1]),"dedicated costume in actual renderer")
		check(figure._material.get_shader_parameter("normal_texture") != null,"dedicated costume normals")
	# 캔버스가 같아도 머리/몸 비율은 다를 수 있다. 기존 성인과 같은 발 위치에서 실제 그림을 비교한다.
	var references: Array[VillageResident] = []
	var lineup_base := modern.global_position
	for npc_id in ["doyun","naru","sora"]:
		var reference := VillageResident.new()
		reference.resident_id = npc_id
		reference.set_meta("look_key","story_npc")
		world.get_node("Actors").add_child(reference)
		reference.set_physics_process(false)
		reference.global_position = lineup_base + Vector2(references.size()*90.0,0)
		references.append(reference)
	smith.global_position = lineup_base + Vector2(270,0)
	modern.global_position = lineup_base + Vector2(360,0)
	view._sync_actors(0.016)
	var adult_figure: PixelActorFigure = view._actors[references[0].get_instance_id()].figure
	for actor in [references[0],references[1],references[2],smith,modern]:
		var figure: PixelActorFigure = view._actors[actor.get_instance_id()].figure
		check(absf(figure._mesh.mesh.size.y-adult_figure._mesh.mesh.size.y) < 0.01,"standing height matches existing adult NPC")
		var offset: Vector2 = figure._material.get_shader_parameter("frame_offset")
		check(absf(offset.y-figure._mesh.mesh.size.y*0.5) < 0.0001,"standing sprite feet stay on common ground line")
	view.camera2d.global_position = lineup_base+Vector2(180,-30)
	view.camera2d.zoom *= 2.0
	view.camera2d.reset_smoothing()
	view.camera2d.force_update_scroll()
	view.forced_hour = 12
	view.apply_hour(12)
	sync()
	await capture("costumes")
	for reference in references: reference.queue_free()
	var player := view.player
	var actors := world.get_node("Actors")
	var resident := VillageResident.new()
	resident.resident_id = "naru"
	resident.set_meta("look_key","story_npc")
	actors.add_child(resident)
	resident.set_physics_process(false)
	resident.global_position = player.global_position + Vector2(130,0)
	for gender in ["male","female"]:
		PlayerProgress.player_gender = gender
		player.set_meta("sitting",true)
		for kind in ["seat","floor"]:
			player.set_meta("sit_kind",kind)
			for direction in (["south-west","south-east","north-west","north-east"] if kind == "seat" else ["south-west","south-east"]):
				player.set_meta("seat_direction",direction)
				view._sync_actors(0.016)
				view._sort_and_update()
				var figure: PixelActorFigure = view._actors[player.get_instance_id()].figure
				check(figure.sprite_key == "pose:player_"+gender+":"+kind+":"+direction,"gender/kind/direction pose")
				figure.walking = true
				figure.animate(0.2)
				check(figure.frame_index == -1,"static poses never pretend to walk")
				check(figure._mesh.mesh.size == figure._id_mesh.mesh.size,"pose and mask share geometry")
				check(figure._material.get_shader_parameter("normal_texture") != null,"pose participates in light")
				if gender == "female" and kind == "seat" and direction == "south-west": await capture("seated")
	for key in ["sitting","sit_kind","seat_direction"]: player.remove_meta(key)
	view._sync_actors(0.016)
	check(view._actors[player.get_instance_id()].figure.sprite_key == "player_female","standing restores original walking asset")
	var bench := VillageSettlement.find_site(world,VillageRestFlow.SETTINGS.site_path)
	check(bench != null,"existing rest bench")
	bench.show()
	bench.collision_layer = 1
	view.village.sync_objects(world)
	var position: Vector2 = player.global_position
	var pose := VillageRestPose.new()
	check(pose.begin(world,player,bench),"quiet bench seat can render")
	view._sync_actors(0.016)
	view._sort_and_update()
	check(view._actors[player.get_instance_id()].figure is PixelActorFigure,"bench uses seated sprite")
	view.camera2d.global_position = player.global_position+Vector2(0,-35)
	view.camera2d.reset_smoothing()
	view.camera2d.force_update_scroll()
	view.forced_hour = 12
	view.apply_hour(12)
	sync()
	var day := await capture("bench-day")
	view.forced_hour = 22
	view.apply_hour(22)
	sync()
	var night := await capture("bench-night")
	if day != null and night != null: check(day.get_data()!=night.get_data(),"seated day/night lighting")
	pose.restore()
	check(player.global_position == position and not player.has_meta("sitting"),"bench exit restores exact position and pose")
	var bench_art := VillageSpriteArt.sprite_of(bench)
	var old_scale := bench_art.scale
	bench_art.scale.x = -bench_art.scale.x
	view.forced_hour = 12
	view.apply_hour(12)
	view.village.sync_objects(world)
	check(pose.begin(world,player,bench),"mirrored bench can seat")
	check(str(player.get_meta("seat_direction")) == "south-west","mirrored bench uses opposite seated direction")
	view._sync_actors(0.016)
	check(view._actors[player.get_instance_id()].figure.sprite_key.ends_with("south-west"),"mirrored bench selects matching pixels")
	sync()
	await capture("bench-mirrored")
	pose.restore()
	check(player.global_position == position,"mirrored bench exit restores position")
	bench_art.scale = old_scale
	view.village.sync_objects(world)
	player.set_meta("face_dir",Vector2.UP)
	player.set_meta("sit_kind","floor")
	check(pose.begin(world,player,bench),"bench repeat session")
	pose.restore()
	check(player.get_meta("face_dir") == Vector2.UP and player.get_meta("sit_kind") == "floor","interrupted pose restores previous metadata")
	player.remove_meta("face_dir")
	player.remove_meta("sit_kind")
	check(pose.begin(world,resident,bench),"named resident bench seat")
	view._sync_actors(0.016)
	check(view._actors[resident.get_instance_id()].figure.sprite_key.begins_with("pose:naru:seat:"),"named bench resident keeps identity")
	pose.restore()
	# 실제 쉼터 대화 경로에서 중단과 완독, 기존 보상/저장 규칙을 확인한다.
	PlayerProgress.record_story_beat(VillageRestFlow.PREFIX+"done",1)
	var life: VillageLifeDirector = world.get_node("VillageLifeDirector")
	var director: VillageRestDirector = life.get_node("VillageRestDirector")
	player.global_position = bench.global_position + Vector2(100,0)
	var return_position: Vector2 = player.global_position
	check(director.try_interact(),"actual quiet rest dialogue opens")
	check(player.get_meta("sitting",false),"actual quiet dialogue seats player")
	director.dialogue.close()
	check(player.global_position == return_position and not player.has_meta("sitting"),"dialogue cancel restores placement")
	check(director.try_interact(),"rest can restart after cancel")
	for i in 100:
		if not director.dialogue.open: break
		director.dialogue._advance()
	check(not player.has_meta("sitting") and player.global_position == return_position,"completed dialogue restores standing")
	check(PlayerProgress.story_beat_days.has(VillageRestFlow.PREFIX+"rested"),"existing rest completion still records")
	print("[state pose art] checks=",checks," failures=",failures)
	get_tree().quit(1 if failures else 0)
