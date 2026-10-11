extends "res://dev/script/check_village_sprite_art.gd"
## All recovered kinds plus retained map instances; fixtures never save the user's map/progress.
func run() -> void:
	GameState.initialize_new_game()
	PlayerProgress.reset()
	world = load("res://scenes/shop/main.tscn").instantiate()
	world.get_node("TutorialDirector").enabled = false
	get_tree().root.add_child(world)
	get_tree().current_scene = world
	await frames(12)
	view = world.get_node("StoreView3D")
	check(view.exterior.is_wild(),"new game retains wilderness")
	var recovered: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://docs/그림_작업/받은그림/마을_원본_복구/복구_목록.json"))
	for row in recovered.assets:
		var path := "res://" + str(row.original_path)
		check(FileAccess.get_sha256("res://" + str(row.restored_path)) == str(row.sha256),"recovered original unchanged: " + path)
		if int(row.rgba_colours) > 10: check(not VillageSpriteArt.row_for(path).is_empty(),"every recovered kind is connected: " + path)
		elif path.ends_with("apple_tree.png"):
			var rule := VillageMirror.find_rule(view.village.rules,path)
			check(rule.get("variant","") == "apple","placeholder apple uses existing apple tree")
		else: check(VillageSpriteArt.row_for(path).is_empty(),"placeholder well/wall isn't drawn as finished art")
	var assets: Array = JSON.parse_string(FileAccess.get_file_as_string(VillageSpriteArt.DATA_PATH)).assets
	for row in assets:
		check(FileAccess.get_sha256(str(row.source)) == str(row.source_sha256),"source unchanged: " + str(row.id))
		check(FileAccess.get_sha256(str(row.path)) == str(row.sha256),"runtime pixels selected: " + str(row.id))
		var image := ReceivedWorldArt.texture(str(row.path)).get_image()
		var colours := {}
		var binary := true
		for y in image.get_height():
			for x in image.get_width():
				var c := image.get_pixel(x,y)
				if c.a > 0 and c.a < 1: binary = false
				if c.a > 0: colours[c.to_rgba32()] = true
		check(binary and colours.size() <= 96,"binary alpha and limited palette: " + str(row.id))
	check(VillageSettlement.find_site(world,"VillageBlacksmith/Smithy").visible == false,"early smith remains locked")
	PlayerProgress.record_story_beat(OpeningTerrain.END_STEP,1)
	check(not view.exterior.is_wild(),"post-tutorial transition applies before demonstration visibility")
	freeze(world)
	var actual: Array[StaticBody2D] = []
	for container_name in VillageMirror.CONTAINERS:
		var container := world.get_node_or_null(container_name)
		if container == null: continue
		for body in container.get_children():
			if not body is StaticBody2D or bool(body.get_meta("settlement_layout_removed",false)): continue
			var art := VillageSpriteArt.sprite_of(body)
			if art == null: continue
			if VillageSpriteArt.row_for(art.art_path).is_empty(): continue
			body.visible = true
			body.collision_layer = 1
			actual.append(body)
	view.village.reset_signatures()
	view.village.sync_ground()
	sync()
	check(actual.size() > 20,"retained authored map objects are rendered")
	var styles := {}
	for body in actual:
		var art := VillageSpriteArt.sprite_of(body)
		var row := VillageSpriteArt.row_for(art.art_path)
		var entry := item(body)
		check(entry.get("village_sprite_id","") == str(row.id),"actual map kind connected: " + str(body.name))
		if entry.is_empty(): continue
		styles[str(row.id)] = true
		var roof := str(art.get_meta("roof_color",""))
		if not roof.is_empty(): check(entry.village_sprite_path == str(row.roof_variants[roof].path),"front/rear saved roof colour: " + str(body.name))
		check(bool(entry.village_mirrored) == (art.scale.x < 0),"saved mirror direction: " + str(body.name))
	check(styles.has("noticeboard") and styles.has("oak_bench") and styles.has("street_lantern"),"living props present on retained map")
	check(styles.has("blacksmith") and styles.has("tool_shop"),"existing service buildings use artwork")
	await get_tree().physics_frame
	var life := world.get_node("VillageLifeDirector") as VillageLifeDirector
	for source in ["VillageBlacksmith/Smithy","VillageToolShop/ToolShop","VillageGathering/VillageNoticeboard","VillageDecor/MarketStall"]:
		var site := VillageSettlement.find_site(world,source)
		var approach := life._approach_position(site)
		check(approach != Vector2.INF,"service approach available: " + source)
		if approach != Vector2.INF:
			var shape := CircleShape2D.new()
			shape.radius = 12
			check(VillageRoutine.clear(world.get_world_2d().direct_space_state,shape,approach),"NPC can stand outside restored floor: " + source)
	# Exercise every source direction including removed/unused prototypes in isolated clones.
	var fixtures := Node2D.new()
	fixtures.name = "RecoveredArtFixtures"
	world.add_child(fixtures)
	for row in assets:
		var body := StaticBody2D.new()
		body.collision_layer = 1
		body.collision_mask = 0
		fixtures.add_child(body)
		body.global_position = view.cell_to_world(Vector2(0,31))
		var art := VillageArt.new()
		art.art_path = str(row.aliases[-1])
		body.add_child(art)
		var shape := CollisionPolygon2D.new()
		shape.name = "Collision3D"
		body.add_child(shape)
		var rule := VillageMirror.find_rule(view.village.rules,art.art_path)
		var size := Vector2(float(rule.get("canon_w",1.0)),float(rule.get("canon_d",1.0)))
		var base := view.world_to_cell(body.global_position)
		var key := "fixture" + str(body.get_instance_id())
		var result := VillageSpriteArt.render(view,key,body,base-size*.5,base+size*.5,"recovered")
		check(not result.is_empty(),"all source poses render: " + str(row.id))
		var entry: Dictionary = view._items[key]
		check(entry.mesh.mesh is QuadMesh,"2D plane: " + str(row.id))
		check(entry.mesh.position == entry.id_mesh.position,"mask uses same position: " + str(row.id))
		check(entry.material.get_shader_parameter("normal_texture") != null,"normal lighting: " + str(row.id))
		var footprint: PackedVector2Array = result.footprint
		var center := Vector2.ZERO
		for point in footprint: center += point/4.0
		await get_tree().physics_frame
		check(contains_body(view.cell_to_world(center),body),"actual movement blocks floor: " + str(row.id))
		check(not contains_body(view.cell_to_world(center+Vector2(10,10)),body),"outside approach free: " + str(row.id))
		var inset := float(row.get("collision_inset",.97))
		for i in 4:
			check(view.world_to_cell(body.to_global(shape.polygon[i])).distance_to(base+(footprint[i]-base)*inset) < .001,"calibrated floor collision: " + str(row.id))
		if row.id == "street_lantern": check(bool(entry.material.get_shader_parameter("use_emission")),"glass emission survives billboard conversion")
		view._remove_item(key)
		body.queue_free()
	await frames()
	fixtures.queue_free()
	# Verify appearance metadata participates in the redraw signature.
	var rear: StaticBody2D
	for body in actual:
		if item(body).get("village_sprite_id","") == "moss_cottage_rear": rear = body; break
	if rear != null:
		var art := VillageSpriteArt.sprite_of(rear)
		var prior := str(art.get_meta("roof_color",""))
		art.set_meta("roof_color","bc934d")
		sync()
		check(str(item(rear).village_sprite_path).ends_with("_ochre.png"),"changing rear roof redraws without moving house")
		if prior.is_empty(): art.remove_meta("roof_color")
		else: art.set_meta("roof_color",prior)
		sync()
	# Preview retained map only, with daytime and nighttime illumination.
	var target: StaticBody2D = VillageSettlement.find_site(world,"VillageGathering/VillageNoticeboard")
	view.player.global_position = target.global_position + Vector2(0,50)
	view.camera2d.global_position = target.global_position + Vector2(0,-90)
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
	if day != null and night != null: check(day.get_data() != night.get_data(),"restored artwork reacts to actual night lighting")
	view.camera2d.global_position = VillageSettlement.find_site(world,"VillageBlacksmith/Smithy").global_position + Vector2(0,-120)
	view.camera2d.reset_smoothing()
	view.camera2d.force_update_scroll()
	view.forced_hour = 12.0
	view.apply_hour(12.0)
	sync()
	await capture("shops")
	view.camera2d.global_position = VillageSettlement.find_site(world,"VillageToolShop/ToolShop").global_position + Vector2(0,-120)
	view.camera2d.reset_smoothing()
	view.camera2d.force_update_scroll()
	sync()
	await capture("tools")
	var lantern: StaticBody2D
	for body in actual:
		if item(body).get("village_sprite_id","") == "street_lantern": lantern = body; break
	if lantern != null:
		view.camera2d.global_position = lantern.global_position + Vector2(0,-40)
		view.camera2d.reset_smoothing()
		view.camera2d.force_update_scroll()
		view.forced_hour = 22.0
		view.apply_hour(22.0)
		sync()
		await capture("lantern")
	VillageSettlement.apply_world(world)
	sync()
	check(not VillageSettlement.find_site(world,"VillageBlacksmith/Smithy").visible,"restored smith still follows progression")
	print("[recovered village art] checks=",checks," failures=",failures," retained=",actual.size()," styles=",styles.size())
	get_tree().quit(1 if failures else 0)
