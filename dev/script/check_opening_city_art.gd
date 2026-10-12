extends "res://dev/script/check_npc_sprite_art.gd"
## 도시 표시·차량 이동/반복·포장/숲 복원·창밖 원경과 옆면 차량을 실제로 확인한다.

func run() -> void:
	GameState.initialize_new_game()
	PlayerProgress.reset()
	world = load("res://scenes/shop/main.tscn").instantiate()
	world.get_node("TutorialDirector").enabled = false
	get_tree().root.add_child(world)
	get_tree().current_scene = world
	await frames(15)
	view = world.get_node("StoreView3D")
	freeze(world)
	world.get_node("UI").hide()
	view.camera2d.global_position = view.cell_to_world(Vector2(4.5,3.5))
	view.camera2d.zoom = Vector2.ONE*view.match_zoom*0.72
	view.camera2d.reset_smoothing()
	view.camera2d.force_update_scroll()
	view._sync_camera()
	var originals: Dictionary = {}
	for kind in view.village._ground:
		var material: ShaderMaterial = view.village._ground[kind].material
		var parameters: Dictionary = {}
		for uniform in material.shader.get_shader_uniform_list():
			var name := str(uniform.name)
			if name not in ["rank","rank_count","center_world"]: parameters[name]=material.get_shader_parameter(name)
		originals[kind] = {"material":material,"parameters":parameters}
	var city := OpeningCityBackdrop.new(view)
	city.build()
	check(city.built() and city.cars.size()==4,"city preserves four traffic cars")
	var count := city.keys.size()
	check(count<=120,"bounded scenery count")
	city.build()
	check(city.keys.size()==count,"build is idempotent")
	var sprite_count := 0
	for key in city.keys:
		if not view._items.has(key): continue
		var item: Dictionary = view._items[key]
		check(str(key).begins_with("cut_"),"all scenery removable by cinematic prefix")
		if item.has("city_ground_kind"):
			check(item.material.get_shader_parameter("tile_1")!=null,"city floor textures survive shader replacement")
			check(item.material.get_shader_parameter("normal_1")!=null,"city floor normals survive shader replacement")
			check(item.mesh.cast_shadow==GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,"flat street does not shadow other floors")
			check(not is_nan(float(item.fixed_rank)),"street stays below actors and buildings")
			check(is_equal_approx(item.mesh.position.x,item.center.x) and is_equal_approx(item.mesh.position.z,item.center.z),"street plane actually placed at bounds center")
		if not item.has("city_sprite_id"): continue
		sprite_count += 1
		var row: Dictionary = OpeningCityArt.rows()[str(item.city_sprite_id)]
		check(FileAccess.get_sha256(str(row.path))==str(row.sha256),"selected art hash")
		var tex: Texture2D = item.material.get_shader_parameter("frame_texture")
		var size: Vector2 = item.mesh.mesh.size
		var box := tex.get_image().get_used_rect()
		check(is_equal_approx(size.x/size.y,float(box.size.x)/float(box.size.y)),"native aspect ratio")
		check(item.material.get_shader_parameter("normal_texture")!=null,"native normal lighting")
		check(item.mesh.position==item.id_mesh.position,"matching ground and mask position")
	check(sprite_count>15,"buildings/props/cars actually use bitmap sprites")
	for kind in view.village._ground:
		var material: ShaderMaterial = view.village._ground[kind].material
		var tex = material.get_shader_parameter("tile_1")
		if tex != null: check(tex.resource_path.ends_with("paving_1.png"),"grass becomes city paving")
	for car in city.cars:
		var before: float = car.pos
		city.tick(0.2)
		check(not is_equal_approx(before,float(car.pos)),"traffic advances")
		var item: Dictionary = view._items[car.body]
		check(str(item.city_sprite_id)==str(car.art_id),"correct front/rear heading")
		check(item.mesh.position.y==0.0 and item.id_mesh.position.y==0.0,"moving sprites do not gain proxy height")
		car.pos=float(car.wrap.y)+50.0
		city.tick(0.0)
		check(car.pos==car.wrap.x,"traffic wraps without respawn duplication")
	view._sort_and_update()
	view.apply_hour(12)
	await capture("city-day")
	view.apply_hour(22)
	await capture("city-night")
	city.show_forest()
	await frames()
	check(not city.built() and city.keys.is_empty() and city.cars.is_empty(),"cinematic cleanup")
	for key in view._items: check(not str(key).begins_with("cut_"),"no leaked city object")
	for kind in originals:
		var original: Dictionary = originals[kind]
		for name in original.parameters:
			check(original.material.get_shader_parameter(name)==original.parameters[name],"forest shader parameter restored: "+str(name))
	view.apply_hour(12)
	view._sort_and_update()
	await capture("forest-restored")
	var layer := CanvasLayer.new()
	add_child(layer)
	var pov := OpeningWindowPov.new()
	add_child(pov)
	pov.attach(layer)
	pov.show_pov()
	pov.set_process(false)
	check(pov.container.stretch_shrink==1,"POV preserves render resolution")
	check(pov._cars.size()==5,"POV five vehicles retained")
	for car in pov._cars:
		await frames(2)
		check(car.node.get_child_count()==1,"POV vehicle is a single sprite")
		check(str(car.node.get_child(0).get_meta("city_sprite_id")).ends_with("side_right" if car.speed>0 else "side_left"),"POV side heading")
		var x_before: float = car.node.position.x
		pov._process(0.25)
		check(not is_equal_approx(x_before,car.node.position.x),"POV traffic moves")
		pov._respawn(car)
		await frames(2)
		check(car.node.get_child_count()==1,"POV respawn cleans old sprite")
	# 두 차선을 실제 창 안에 놓고 원본 비율·옆면 방향을 시각적으로 확인한다.
	pov._cars[0].node.position.x = -2.6
	pov._cars[1].node.position.x = 3.2
	await capture("window")
	pov.set_drowsy(0.8)
	pov._process(0.25)
	check(pov.camera.position.y<OpeningWindowPov.EYE_HEIGHT,"drowsy camera retained")
	pov.hide_pov()
	check(not pov.is_shown() and pov.viewport.render_target_update_mode==SubViewport.UPDATE_DISABLED,"POV hides/stops after transition")
	print("[opening city art] checks=",checks," failures=",failures," active sprite count=",sprite_count," registered keys=",count)
	get_tree().quit(1 if failures else 0)
