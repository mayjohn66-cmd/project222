extends "res://dev/script/check_village_sprite_art.gd"
## Isolated save/profile fixture: selected normals, source proportions, species and actual lighting.
const VARIANTS := ["round","pine","dead","birch","big_oak","apple","cherry","poplar","willow"]
const PROPS := ["bush","flower_bush","rocks","mushroom","stump","log"]

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
	freeze(world)
	var well := VillageSettlement.find_site(world,"VillageDecor/VillageWell")
	var land: Array[Vector2i] = view.exterior.get_connected_map_cells()
	var center := Vector2.ZERO
	for cell in land: center += Vector2(cell)/float(land.size())
	var origin := center-Vector2(4,4)
	# Hide procedural trees only in this unsaved contact-sheet fixture, preventing overlaps.
	for key in view.village._tree_keys + view.village._bush_keys:
		view._remove_item(key)
	var keys: Array[String] = []
	for i in VARIANTS.size() + PROPS.size():
		var key := "nature_review_%d" % i
		keys.append(key)
		var point := origin + Vector2((i%5)*2.0,(i/5)*2.6)
		var rule := rule_for(i)
		check(ReceivedWorldArt.nature(view,key,point,point+Vector2.ONE,rule,key),"nature source displayed: "+str(i))
		var entry: Dictionary = view._items[key]
		var texture := entry.material.get_shader_parameter("frame_texture") as Texture2D
		var normal := entry.material.get_shader_parameter("normal_texture") as Texture2D
		var normal_source: String = str(NatureStateArt.assets()[entry.nature_state].normal_source) if entry.has("nature_state") else texture.resource_path
		check(normal.resource_path == normal_source.get_basename()+"_n.png","selected shape normal loaded instead of brightness fallback")
		check(normal.get_size() == texture.get_size(),"normal canvas matches diffuse")
		var bounds := texture.get_image().get_used_rect()
		var size: Vector2 = entry.mesh.mesh.size
		check(is_equal_approx(size.x/size.y,float(bounds.size.x)/bounds.size.y),"no axis-specific compression")
		check(entry.mesh.position == entry.id_mesh.position,"colour and selection mask align")
	view.player.global_position = view.cell_to_world(origin+Vector2(4.5,4.5))
	view.camera2d.global_position = view.cell_to_world(origin+Vector2(4,3))+Vector2(0,-40)
	view.camera2d.reset_smoothing()
	view.camera2d.force_update_scroll()
	view._sync_actors(.016)
	for hour in [6.0,12.0,18.0,22.0]:
		view.forced_hour = hour
		view.apply_hour(hour)
		view._sync_camera()
		view._sort_and_update()
		await save_capture("nature_spring_%d" % int(hour))
	# Actual season selector keeps six distinct crowns rather than replacing all with round.
	for variant in ["round","birch","big_oak","cherry","poplar","willow"]:
		var original := {"kind":"prop","style":"tree","variant":variant,"generated":true}
		var rule := SeasonStyle.adjust_rule(original,"autumn",3)
		var id := NatureStateArt.state_id(rule)
		check(not id.is_empty() and NatureStateArt.assets()[id].base_variant == variant,"autumn keeps tree species: "+variant)
		var row: Dictionary = NatureStateArt.assets()[id]
		var native := ReceivedWorldArt.texture(str(row.normal_source)).get_image()
		var changed := ReceivedWorldArt.texture(str(row.path)).get_image()
		check(native.get_size() == changed.get_size(),"season retains native canvas: "+variant)
		for y in native.get_height():
			for x in native.get_width():
				var a := native.get_pixel(x,y)
				var b := changed.get_pixel(x,y)
				check(a.a == b.a,"season retains native alpha")
				if a.a > 0 and a.r > a.g and variant != "cherry": check(a == b,"season retains wooden trunk")
	var dead := ReceivedWorldArt.texture("res://art/received/nature/tree_dead.png").get_image().get_used_rect()
	check(dead.size.y >= 100,"winter bare tree remains mature height")
	for season in ["autumn","winter"]:
		for i in VARIANTS.size():
			var key := keys[i]
			var entry: Dictionary = view._items[key]
			var point := Vector2(entry.mesh.position.x,entry.mesh.position.z)
			var original := rule_for(i)
			original["kind"] = "prop"
			original["generated"] = true
			var rule := SeasonStyle.adjust_rule(original,season,3)
			check(ReceivedWorldArt.nature(view,key,point,point+Vector2.ONE,rule,season+key),"season sprite connected")
		view.forced_hour = 12
		view.apply_hour(12)
		view._sync_camera()
		view._sort_and_update()
		await save_capture("nature_"+season+"_12")
	# Four growth scales must remain uniform and share normal/mask anchors.
	for scale in [.45,.65,.85,1.0]:
		var key := "nature_growth_"+str(scale)
		check(ReceivedWorldArt.nature(view,key,origin,origin+Vector2.ONE,rule_for(0),key,scale),"growth source available")
		var entry: Dictionary = view._items[key]
		var tex := entry.material.get_shader_parameter("frame_texture") as Texture2D
		var bounds := tex.get_image().get_used_rect()
		check((entry.mesh.mesh.size/Vector2(bounds.size)).distance_to(Vector2.ONE*(sqrt(2.0)/64.0*scale)) < .0001,"growth is uniform in both axes")
		view._remove_item(key)
	print("[자연물 통일] 검사 ",checks," / 실패 ",failures)
	get_tree().quit(1 if failures else 0)

func rule_for(index: int) -> Dictionary:
	if index < VARIANTS.size(): return {"style":"tree","variant":VARIANTS[index]}
	var prop: String = PROPS[index-VARIANTS.size()]
	return {"style":"flower_bush","variant":"berry","berry_state":"empty"} if prop == "bush" else {"style":prop}

func save_capture(label: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await frames(6)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("user://"+label+".png")
