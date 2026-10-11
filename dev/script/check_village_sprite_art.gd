extends Node
## 마을 그림과 실제 충돌/진행 해금/정렬/시간 빛을 검사한다. 사용자 저장은 사용하지 않는다.
var checks := 0
var failures := 0
var world: Node2D
var view: StoreView3D

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().create_timer(110.0,true).timeout.connect(func() -> void: get_tree().quit(9))
	run.call_deferred()

func frames(n: int = 4) -> void:
	for i in n: await get_tree().process_frame

func freeze(node: Node) -> void:
	node.set_process(false)
	node.set_physics_process(false)
	for child in node.get_children(): freeze(child)

func sync() -> void:
	view.village.sync_objects(world)
	view._sync_actors(0.016)
	view._sync_camera()
	view._sort_and_update()

func item(body: StaticBody2D) -> Dictionary:
	return view._items.get("vil%d" % body.get_instance_id() + "a", {})

func contains_body(point: Vector2, body: StaticBody2D) -> bool:
	var query := PhysicsPointQueryParameters2D.new()
	query.position = point
	query.collision_mask = 1
	for hit in world.get_world_2d().direct_space_state.intersect_point(query,64):
		if hit.collider == body: return true
	return false

func run() -> void:
	GameState.initialize_new_game()
	PlayerProgress.reset()
	world = load("res://scenes/shop/main.tscn").instantiate()
	world.get_node("TutorialDirector").enabled = false
	get_tree().root.add_child(world)
	get_tree().current_scene = world
	await frames(12)
	view = world.get_node("StoreView3D")
	check(view.exterior.is_wild(),"new game remains wilderness")
	var house: StaticBody2D
	for body in world.get_node("VillageExtraHouses").get_children():
		if body is StaticBody2D and not bool(body.get_meta("settlement_layout_removed",false)):
			var art := VillageSpriteArt.sprite_of(body)
			if art != null and art.art_path.ends_with("moss_cottage_180.png") and not art.has_meta("roof_color"):
				house = body
				break
	check(house != null,"actual retained front-cottage placement exists")
	check(not house.visible and house.collision_layer == 0,"unbuilt front cottage isn't unlocked by art")
	check(item(house).is_empty(),"unbuilt house isn't rendered")
	for row in JSON.parse_string(FileAccess.get_file_as_string(VillageSpriteArt.DATA_PATH)).assets:
		var tex := ReceivedWorldArt.texture(str(row.path))
		check(tex != null and tex.get_size() == Vector2(float(row.size[0]),float(row.size[1])),"prepared sprite " + str(row.id))
		check(FileAccess.get_sha256(str(row.source)) == str(row.source_sha256),"original image preserved " + str(row.id))
		check(FileAccess.get_sha256(str(row.path)) == str(row.sha256),"runtime image matches selected pixels " + str(row.id))
		var image := tex.get_image()
		var binary := true
		for y in image.get_height():
			for x in image.get_width():
				var a := image.get_pixel(x,y).a
				if a > 0.0 and a < 1.0: binary = false
		check(binary,"no translucent background halo " + str(row.id))
	# Move into the post-tutorial map, then show only prepared landmarks as an unsaved graphics fixture.
	PlayerProgress.record_story_beat(OpeningTerrain.END_STEP,1)
	check(not view.exterior.is_wild(),"post-tutorial ground is available")
	freeze(world)
	var sources := ["VillageDecor/MarketStall","VillageDecor/PlazaHerbStall","VillageDecor/PlazaSupplyCart"]
	var bodies: Array[StaticBody2D] = []
	for source in sources:
		var body: StaticBody2D = VillageSettlement.find_site(world,source)
		body.visible = true
		body.collision_layer = 1
		bodies.append(body)
	house.visible = true
	house.collision_layer = 1
	bodies.append(house)
	view.village.reset_signatures()
	view.village.sync_ground()
	sync()
	for body in bodies:
		var entry := item(body)
		check(entry.has("village_sprite_path"),"actual landmark uses prepared 2D: " + str(body.name))
		if not entry.has("village_sprite_path"): continue
		check(entry.mesh.mesh is QuadMesh,"landmark uses single 2D plane")
		check(entry.mesh.position == entry.id_mesh.position,"color/mask share ground position")
		check(entry.material.get_shader_parameter("frame_offset") == entry.id_material.get_shader_parameter("frame_offset"),"color/mask share image anchor")
		check(entry.material.get_shader_parameter("normal_texture") != null,"world normal-map lighting active")
		if body == house:
			var land: Array[Vector2i] = view.exterior.get_connected_map_cells()
			for p in entry.village_footprint:
				check(Vector2i(roundi(p.x),roundi(p.y)) in land,"retained cottage base is on actual ground")
		var collider := body.get_node("Collision3D") as CollisionPolygon2D
		check(collider.polygon.size() == 4 and not collider.disabled,"prepared ground contact blocks movement")
		var footprint: PackedVector2Array = entry.village_footprint
		var center := Vector2.ZERO
		for p in footprint: center += p / float(footprint.size())
		for i in footprint.size():
			var actual := view.world_to_cell(body.to_global(collider.polygon[i]))
			var base := Vector2(entry.mesh.position.x,entry.mesh.position.z)
			check(actual.distance_to(base + (footprint[i]-base)*0.97) < 0.001,"collision follows visible base, not roof")
		await get_tree().physics_frame
		check(contains_body(view.cell_to_world(center),body),"player collision inside landmark base")
		var outside := view.cell_to_world(center + Vector2(0.0,-4.0))
		check(not contains_body(outside,body),"approach outside base remains walkable")
	check(bool(item(bodies[1]).get("village_mirrored",false)),"herb stall retains saved mirror direction")
	check(not VillageSpriteArt.row_for("res://art/world/village_gathering_v1/oak_bench.png").is_empty(),"recovered bench uses its own artwork")
	var cottage: StaticBody2D = world.get_node("VillageExtraHouses/EastCottage")
	check(VillageSpriteArt.row_for(VillageSpriteArt.sprite_of(cottage).art_path).get("id","") == "moss_cottage_rear","recovered rear cottage uses rear artwork")
	check(item(house).get("village_sprite_id","") == "moss_cottage_front","retained front cottage connects")
	for body in world.get_node("VillageExtraHouses").get_children():
		if not body is StaticBody2D or bool(body.get_meta("settlement_layout_removed",false)): continue
		var art := VillageSpriteArt.sprite_of(body)
		if art == null or not art.art_path.ends_with("moss_cottage_180.png") or not art.has_meta("roof_color"): continue
		body.visible = true
		body.collision_layer = 1
		sync()
		var colour := str(art.get_meta("roof_color"))
		var row := VillageSpriteArt.row_for(art.art_path)
		check(item(body).get("village_sprite_path", "") == str(row.roof_variants[colour].path),"saved roof colour connects without tinting entire house")
	# Camera keeps the original landmark placement. Preview uses the same game renderer and player scale.
	view.player.global_position = bodies[0].global_position + Vector2(0,60)
	view.camera2d.global_position = bodies[0].global_position + Vector2(-30,-70)
	view.camera2d.reset_smoothing()
	view.camera2d.force_update_scroll()
	view.forced_hour = 12.0
	view.apply_hour(12.0)
	sync()
	var day := await capture("day")
	view.forced_hour = 22.0
	view.apply_hour(22.0)
	sync()
	var night := await capture("night")
	if day != null and night != null: check(day.get_data() != night.get_data(),"actual sprite lighting changes at night")
	view.camera2d.global_position = house.global_position + Vector2(0,-170)
	view.camera2d.reset_smoothing()
	view.camera2d.force_update_scroll()
	view.forced_hour = 12.0
	view.apply_hour(12.0)
	sync()
	await capture("houses")
	var removed_id := bodies[2].get_instance_id()
	bodies[2].queue_free()
	await frames()
	sync()
	check(not view._items.has("vil%d" % removed_id + "a"),"removed landmark sprite is cleaned up")
	# Restore saved progression gating, not the unsaved demonstration visibility.
	VillageSettlement.apply_world(world)
	sync()
	check(not house.visible and item(house).is_empty(),"locked landmark hides again with saved progression")
	print("[village sprite art] checks=",checks," failures=",failures)
	get_tree().quit(1 if failures else 0)

func capture(label: String) -> Image:
	if DisplayServer.get_name() == "headless": return null
	await frames(8)
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var args := OS.get_cmdline_user_args()
	if not args.is_empty(): image.save_png(args[0]+"-"+label+".png")
	return image
