extends "res://dev/script/check_npc_sprite_art.gd"
## 실제 인물의 방향 전환·그림 선택·발 기준·법선·시간대 빛을 검사한다.

func run() -> void:
	GameState.initialize_new_game()
	PlayerProgress.reset()
	world = load("res://scenes/shop/main.tscn").instantiate()
	world.get_node("TutorialDirector").enabled = false
	get_tree().root.add_child(world)
	get_tree().current_scene = world
	await frames(12)
	view = world.get_node("StoreView3D")
	freeze(world)
	world.get_node("UI").hide()
	var actors: Array[Node2D] = []
	var identities: Array[String] = []
	var index := 0
	for identity in NpcDirectionArt.assets():
		var actor: Node2D
		if identity == "blacksmith":
			var resident := VillageResident.new()
			resident.resident_id = "village_blacksmith"
			resident.set_meta("look_key","story_npc")
			actor = resident
		else:
			var npc := StoryNpc.new()
			npc.setup({"npc_id":identity,"beat_id":"direction-check","lines":[]})
			if identity == "commuter": npc.set_meta("look_key","commuter")
			actor = npc
		world.get_node("Actors").add_child(actor)
		actor.set_physics_process(false)
		actor.set_process(false)
		actor.global_position = view.cell_to_world(Vector2(1.0+index%4*1.8,1.8+int(index/4)*1.8))
		actors.append(actor)
		identities.append(identity)
		index += 1
	view.camera2d.global_position = view.cell_to_world(Vector2(3.7,3.5))
	view.camera2d.zoom = Vector2.ONE * view.match_zoom * 1.65
	view.camera2d.reset_smoothing()
	view.camera2d.force_update_scroll()
	view._sync_camera()
	view._sync_actors(0.016)
	view._sort_and_update()
	for i in actors.size():
		var identity := identities[i]
		var row: Dictionary = NpcDirectionArt.assets()[identity]
		check(FileAccess.get_sha256(str(row.base_path)) == row.base_sha256,"existing south-west unchanged: "+identity)
		check(FileAccess.get_sha256("res://"+str(row.reference)) == row.reference_sha256,"original design unchanged: "+identity)
		var sprite: PixelActorFigure = view._actors[actors[i].get_instance_id()].figure
		check(sprite.frame_set.get("directional_idle",false),"actual actor uses direction set: "+identity)
		check(sprite.frame_set.directions.size() == 8,"eight real selected directions: "+identity)
		for direction in ActorSpriteFrames.DIRECTIONS:
			var pose: Dictionary = sprite.frame_set.directions[direction]
			check(pose.walk.is_empty(),"no invented walk animation: "+identity)
			check(FileAccess.get_sha256(pose.idle.path) == row.directions[direction].sha256,"selected PNG hash: "+identity+direction)
			check(pose.idle.texture.get_size() == Vector2(96,96),"96px canvas")
			check(pose.anchor + pose.idle.texture.get_size()*0.5 == Vector2(48,90),"shared grounded anchor")
	# 카메라 두 방향에서 360도 이동 각도를 검증한다.
	for camera_yaw in [45.0,135.0]:
		view._camera.rotation_degrees.y = camera_yaw
		for step in 16:
			for actor in actors:
				var sprite: PixelActorFigure = view._actors[actor.get_instance_id()].figure
				sprite.facing_yaw_deg = float(step)*22.5
				sprite.walking = true
				sprite.sync_sort(0,1,view._camera,0.5)
				sprite.animate(0.2)
				check(sprite.direction == ActorSpriteFrames.direction_for(sprite.facing_yaw_deg,camera_yaw),"movement/camera select screen direction")
				check(sprite.frame_index == -1 and sprite.phase == 0.0,"empty walk set remains idle")
				var frame: Dictionary = sprite.frame_set.directions[sprite.direction].idle
				check(sprite._last_frame_path == frame.path,"actual material uses requested orientation")
				var size: Vector2 = sprite._mesh.mesh.size
				check(is_equal_approx(size.x/size.y,float(frame.bounds.size.x)/float(frame.bounds.size.y)),"whole image aspect preserved")
				check(size == sprite._id_mesh.mesh.size,"color/mask geometry synchronized")
				var offset: Vector2 = sprite._material.get_shader_parameter("frame_offset")
				check(is_equal_approx(offset.y,size.y*0.5),"feet do not float when turning")
				check(sprite._material.get_shader_parameter("normal_texture") != null,"normal map on every direction")
	view._camera.rotation_degrees.y = 45.0
	for direction in ActorSpriteFrames.DIRECTIONS:
		for actor in actors:
			var sprite: PixelActorFigure = view._actors[actor.get_instance_id()].figure
			for yaw in 360:
				if ActorSpriteFrames.direction_for(float(yaw),45.0) == direction:
					sprite.facing_yaw_deg = float(yaw)
					break
			sprite.walking = false
			sprite.animate(0.0)
		view._sort_and_update()
		view.apply_hour(12)
		await capture(direction)
	var daytime := await capture("day")
	view.apply_hour(22)
	var nighttime := await capture("night")
	if daytime != null and nighttime != null: check(daytime.get_data()!=nighttime.get_data(),"time lighting affects all prepared directions")
	print("[npc directions] checks=",checks," failures=",failures)
	get_tree().quit(1 if failures else 0)
