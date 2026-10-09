extends Node
var checks := 0
var failures := 0
var world
var director: BlacksmithDirector
class LootHost extends RefCounted:
	var expedition_bag := ExpeditionBag.new()
	var temporary_loot: Array[Dictionary] = []
	var selected_bag_uid := -1
	var bag_grid_view = null
	var loot_grid := GridContainer.new()
	func refresh_loot_ui() -> void: pass
	func refresh_bag_ui() -> void: pass
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)
func frames() -> void:
	for i in range(12): await get_tree().process_frame
func click(button: Button) -> void:
	var parent := button.get_parent()
	while parent != null and not parent is ScrollContainer: parent = parent.get_parent()
	if parent is ScrollContainer: parent.ensure_control_visible(button)
	await frames()
	for pressed in [true,false]:
		var event := InputEventMouseButton.new()
		event.position = button.get_global_rect().get_center()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		get_viewport().push_input(event,true)
	await frames()
func drain() -> void:
	for i in range(60):
		if not director.dialogue.open: break
		director.dialogue._advance()
func escape() -> void:
	var event := InputEventKey.new()
	event.keycode = KEY_ESCAPE
	event.pressed = true
	get_viewport().push_input(event,true)
	await frames()
func snap(label: String) -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty() or DisplayServer.get_name() == "headless": return
	await get_tree().create_timer(0.4).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(args[0]+"-"+label+".png")
func tutorial_done() -> void:
	for step in TutorialDirector.SETTINGS.steps: PlayerProgress.record_story_beat("tutorial_step:"+str(step["id"])+":done",GameState.total_day)
	PlayerProgress.record_story_beat(CheckoutTutorial.BEAT_ID,GameState.total_day)
	for id in ["settle_naru","traveler_water"]: PlayerProgress.record_story_beat(ResidentRequestFlow.PREFIX+id+":done",GameState.total_day)
func _ready() -> void: call_deferred("run")
func run() -> void:
	GameState.initialize_new_game()
	world = load("res://scenes/shop/main.tscn").instantiate()
	world.get_node("TutorialDirector").enabled = false
	add_child(world)
	await frames()
	director = world.get_node("BlacksmithDirector")
	var player = world.get_node("Actors/Player")
	var manager = world.get_node("DayManager")
	player.set_physics_process(false)
	check(BlacksmithProgressionRecords.has("version") and not BlacksmithProgressionFlow.npc_available() and not BlacksmithProgressionFlow.service_available(),"new tutorial hides blacksmith and service")
	var prep = load("res://scenes/expedition/prep/prep_maintenance.tscn").instantiate()
	add_child(prep)
	await frames()
	prep.hide()
	check(not prep.enhancement_mode_button.visible,"tutorial hides prep enhancement tab")
	prep._set_mode(prep.MaintenanceMode.ENHANCEMENT)
	check(prep.current_mode == prep.MaintenanceMode.CRAFT,"direct prep mode cannot bypass introduction")
	GameState.add_item("iron_ore",8)
	var sword1: int = GameState.create_owned_equipment_instance("rusty_sword")
	var sword2: int = GameState.create_owned_equipment_instance("rusty_sword")
	check(not BlacksmithEquipmentAdapter.enhance(BlacksmithEquipmentAdapter.find(sword1)).get("success",false),"service adapter rejects locked introduction")
	tutorial_done()
	check(not BlacksmithProgressionFlow.introduction_ready(),"gift/owned ore does not replace new expedition evidence")
	var result_service = load("res://script/expedition/services/expedition_result_service.gd").new()
	var bag := ExpeditionBag.new()
	bag.add_item("iron_ore",Vector2i.ZERO,2)
	check(result_service.deposit_items(bag,{"region":"mine","explored":true}).get("success",false) and not BlacksmithProgressionRecords.has("ore_returned"),"packed ore deposit not recorded as freshly gathered")
	bag.add_item("iron_ore",Vector2i.ZERO,1,false,{"blacksmith_ore_origin":true})
	var loot_host := LootHost.new()
	loot_host.temporary_loot = [{"item_id":"iron_ore","amount":1,"blacksmith_ore_origin":true}]
	var controller := ExpeditionBagController.new()
	controller.setup(loot_host)
	# The UI card refresh accesses loot_grid; an unattached empty container is enough for no remaining loot.
	controller.drop_grid_data("bag",{"source":"loot","loot_index":0},Vector2i.ZERO)
	check(loot_host.expedition_bag.placements[0].get("blacksmith_ore_origin",false),"actual loot-to-bag operation preserves acquisition origin")
	loot_host.loot_grid.free()
	var restored := ExpeditionBag.new()
	check(restored.load_placements(bag.placements.duplicate(true)) and restored.placements[0].get("blacksmith_ore_origin",false),"checkpoint load preserves actual loot evidence")
	check(result_service.deposit_items(restored,{"region":"mine","explored":true}).get("success",false) and BlacksmithProgressionRecords.has("ore_returned"),"actual new ore deposit records evidence")
	GameState.remove_item("iron_ore",GameState.get_item_count("iron_ore"))
	check(BlacksmithProgressionFlow.introduction_ready(),"sold ore still permits introduction")
	var before_returns := BlacksmithProgressionRecords.returns()
	result_service.deposit_items(ExpeditionBag.new(),{"region":"mine","explored":false})
	check(BlacksmithProgressionRecords.returns() == before_returns,"empty unexplored return not counted")
	GameState.add_item("iron_ore",8)
	VillageSettlement.apply_world(world)
	world.get_node("VillageLifeDirector").refresh()
	await frames()
	var life = world.get_node("VillageLifeDirector")
	check(life.residents.has("naru"),"settled peddler exists")
	player.global_position = life.residents["naru"].global_position
	VillageLifeFlow.greet("naru")
	# Keep unrelated optional stories pending: they have priority; clear only their test fixture prerequisites.
	check(director._naru_ready() == life._next_story_action("naru").is_empty(),"existing resident story priority is respected")
	# Exercise introduction through the director at actual peddler once other stories are absent.
	var pending: Dictionary = life._next_story_action("naru")
	for i in range(20):
		if pending.is_empty(): break
		life.try_interact()
		for j in range(100):
			if not life.dialogue.open: break
			life.dialogue._advance()
		pending = life._next_story_action("naru")
	check(director.try_interact() and director.dialogue.open and director.active_stage == "smith_heard_naru","E at peddler begins blacksmith introduction")
	await escape()
	check(not BlacksmithProgressionRecords.has("heard") and not director.open,"cancelled peddler introduction leaves progress unchanged")
	check(director.try_interact(),"cancelled introduction can resume")
	drain()
	check(BlacksmithProgressionRecords.has("heard") and not director.open,"full peddler dialogue commits heard")
	director.refresh()
	await frames()
	check(is_instance_valid(director.npc) and director.npc.visible,"separate blacksmith appears")
	player.global_position = director.npc.global_position + Vector2(28,0)
	await frames()
	await snap("npc")
	var shape := CircleShape2D.new()
	shape.radius = 10
	check(VillageRoutine.clear(world.get_world_2d().direct_space_state,shape,director.npc.global_position),"blacksmith standing point is on clear exterior ground")
	check(VillageJournalFlow.destination(world,BlacksmithProgressionFlow.JOURNAL_ID) == director.npc,"journal tracks new NPC")
	player.global_position = director.npc.global_position
	check(director.try_interact(),"blacksmith E starts first meeting")
	drain()
	check(BlacksmithProgressionRecords.has("met") and not BlacksmithProgressionFlow.service_available(),"meeting is non-consuming and does not skip workshop")
	check(GameState.get_item_count("iron_ore") == 8 and int(BlacksmithEquipmentAdapter.find(sword1)["enhancement_level"]) == 0,"showing equipment changes no resources")
	check(not CommunityRequestFlow.accept("open_smithy"),"ore evidence does not skip existing workshop requirements")
	var mid := GameState.create_save_data()
	check(GameState.apply_save_data(mid) and BlacksmithProgressionRecords.has("met"),"save reload preserves introduction stage")
	# Workshop cost/reward pathway is verified in check_village_smithy.
	PlayerProgress.record_story_beat(CommunityRequestFlow.PREFIX+"open_smithy:done",GameState.total_day)
	VillageSettlement.apply_world(world)
	director.refresh()
	player.global_position = director.npc.global_position
	check(director.try_interact() and director.active_stage == "smith_workshop_ready","workshop completion introduces service")
	drain()
	check(director.panel.root.visible and BlacksmithProgressionFlow.service_available(),"service intro full read opens explicit choices")
	check(not BlacksmithProgressionRecords.has("first_enhanced"),"first enhancement not required for service")
	check(manager.hour_timer.paused and world.get_node("WorldInteractions").blocked(),"service modal pauses clock and blocks concurrent interactions")
	prep.refresh_all()
	check(prep.enhancement_mode_button.visible,"prep equipment view appears after intro")
	prep._set_mode(prep.MaintenanceMode.ENHANCEMENT)
	prep.selected_equipment_instance_id = sword1
	prep._enhance_selected_equipment()
	check(int(BlacksmithEquipmentAdapter.find(sword1)["enhancement_level"]) == 0 and GameState.get_item_count("iron_ore") == 8,"direct prep action cannot enhance remotely")
	director.panel.select_mode("craft")
	check(not director.panel.cards.has("rusty_sword_recipe"),"unlearned equipment recipes are not listed")
	PlayerProgress.learn_recipe("rusty_sword_recipe")
	director.panel.refresh()
	check(director.panel.cards.has("rusty_sword_recipe"),"learned recipe appears")
	director.panel.select_mode("enhance")
	await click(director.panel.cards[str(sword1)]["action"])
	check(int(director.panel.selected.get("instance_id",-1)) == sword1 and not director.panel.confirm_button.disabled,"actual mouse selects only chosen instance")
	var money: int = GameState.get_money()
	await frames()
	check(get_viewport().get_visible_rect().encloses(director.panel.root.get_global_rect()),"selected details keep initial viewport controls visible")
	var build_key := InputEventKey.new()
	build_key.keycode = KEY_B
	build_key.pressed = true
	get_viewport().push_input(build_key,true)
	await frames()
	check(not world.get_node("BuildManager").build_mode,"service prevents construction hotkey leaking")
	var journal_key := InputEventKey.new()
	journal_key.keycode = KEY_N
	journal_key.pressed = true
	get_viewport().push_input(journal_key,true)
	await frames()
	check(not manager.management_menu.visible and not get_tree().paused,"service prevents management book overlapping")
	await snap("selected")
	await click(director.panel.confirm_button)
	check(int(BlacksmithEquipmentAdapter.find(sword1)["enhancement_level"]) == 1 and int(BlacksmithEquipmentAdapter.find(sword2)["enhancement_level"]) == 0,"actual confirm enhances one of two same-item instances")
	check(GameState.get_item_count("iron_ore") == 6 and GameState.get_money() == money,"existing material cost and zero gold fee preserved")
	check(BlacksmithProgressionRecords.has("first_enhanced") and not BlacksmithProgressionFlow.afterglow_ready(),"success commits optional first enhancement, no premature return story")
	director._action("enhance")
	check(GameState.get_item_count("iron_ore") == 6,"rapid duplicate confirm consumes nothing")
	var stale := BlacksmithEquipmentAdapter.find(sword2)
	GameState.set_equipment_instance_level(sword2,1)
	check(not BlacksmithEquipmentAdapter.enhance(stale).get("success",false) and GameState.get_item_count("iron_ore") == 6,"stale level rejects without charging")
	var bag_item := GameState.take_owned_equipment_instance(sword2)
	bag_item.merge({"uid":5,"cell":Vector2i(2,1),"rotated":true,"amount":1,"links":[sword1]})
	var saved_bag: Array[Dictionary] = [bag_item]
	GameState.save_expedition_bag(saved_bag)
	var bag_snapshot := BlacksmithEquipmentAdapter.find(sword2)
	check(BlacksmithEquipmentAdapter.enhance(bag_snapshot).get("success",false),"saved bag equipment can enhance")
	var packed := GameState.get_saved_expedition_bag()[0]
	check(packed["enhancement_level"] == 2 and packed["cell"] == Vector2i(2,1) and packed["rotated"] and packed["links"] == [sword1],"bag level persists without changing placement or linked equipment")
	GameState.remove_item("iron_ore",GameState.get_item_count("iron_ore"))
	check(not BlacksmithEquipmentAdapter.enhance(BlacksmithEquipmentAdapter.find(sword1)).get("success",false) and int(BlacksmithEquipmentAdapter.find(sword1)["enhancement_level"]) == 1,"missing material consumes no equipment")
	GameState.set_equipment_instance_level(sword1,8)
	GameState.add_item("iron_ore",9)
	check(not BlacksmithEquipmentAdapter.enhance(BlacksmithEquipmentAdapter.find(sword1)).get("success",false) and GameState.get_item_count("iron_ore") == 9,"cap blocks enhancement without cost")
	check(not BlacksmithEquipmentAdapter.enhance({"instance_id":999,"source":"owned","item_id":"rusty_sword","enhancement_level":0}).get("success",false),"forged/unowned equipment rejected")
	var tool_id: int = GameState.create_owned_equipment_instance("gathering_bottle")
	var armor_id: int = GameState.create_owned_equipment_instance("leather_armor")
	GameState.add_item("forest_herb",2)
	check(BlacksmithEquipmentAdapter.enhance(BlacksmithEquipmentAdapter.find(tool_id)).get("success",false) and GameState.get_item_count("iron_ore") == 7 and GameState.get_item_count("forest_herb") == 2,"tool uses actual basic gathering cost iron ore, not armor herbs")
	check(BlacksmithEquipmentAdapter.enhance(BlacksmithEquipmentAdapter.find(armor_id)).get("success",false) and GameState.get_item_count("forest_herb") == 0 and GameState.get_item_count("iron_ore") == 7,"armor consumes its existing herb cost")
	var saved := GameState.create_save_data()
	check(GameState.apply_save_data(saved) and BlacksmithEquipmentAdapter.find(sword2)["enhancement_level"] == 2 and BlacksmithProgressionFlow.service_available(),"save reload preserves specific bag enhancement and service")
	GameState.total_day += 1
	result_service.deposit_items(ExpeditionBag.new(),{"region":"forest","explored":true})
	check(BlacksmithProgressionFlow.afterglow_ready(),"later real explored return offers afterglow")
	await click(director.panel.tabs["hello"])
	var hello_button: Button = director.panel.list.get_child(1)
	await click(hello_button)
	await escape()
	check(not BlacksmithProgressionRecords.has("afterglow"),"cancelled afterglow can resume")
	director.refresh()
	player.global_position = director.npc.global_position
	check(director.try_interact(),"service reopens without mandatory repeat dialogue")
	director._action("hello")
	drain()
	check(BlacksmithProgressionRecords.has("afterglow") and director.panel.root.visible,"full afterglow records memory and returns to service")
	for dimensions in [Vector2i(1152,648),Vector2i(593,523),Vector2i(800,450)]:
		get_window().size = dimensions
		director.panel.select_mode("enhance")
		await frames()
		await click(director.panel.cards[str(sword2)]["action"])
		await frames()
		check(get_viewport().get_visible_rect().encloses(director.panel.root.get_global_rect()) and director.panel.root.get_global_rect().encloses(director.panel.close_button.get_global_rect()) and director.panel.root.get_global_rect().encloses(director.panel.confirm_button.get_global_rect()),"service controls fit small viewport")
		if dimensions == Vector2i(593,523): await snap("small")
	get_window().size = Vector2i(1152,648)
	await frames()
	await escape()
	check(not director.open and not world.has_meta("blacksmith_open") and not player.is_physics_processing(),"Esc restores previous player state and clears modal")
	# Old saves: remove only optional version/progression keys, keep original equipment/facility.
	for key in PlayerProgress.story_beat_days.keys():
		if str(key).begins_with(BlacksmithProgressionRecords.PREFIX): PlayerProgress.story_beat_days.erase(key)
	PlayerProgress.story_beat_days.erase(CommunityRequestFlow.PREFIX+"open_smithy:done")
	check(BlacksmithProgressionFlow.service_available() and not CommunityRequestFlow.done("open_smithy"),"legacy enhanced save retains temporary service without repeat workshop charge")
	director.refresh()
	check(is_instance_valid(director.npc) and director.npc.visible,"legacy temporary work NPC is present")
	player.global_position = director.npc.global_position
	manager.hour_timer.paused = true
	check(director.try_interact(),"legacy service opens immediately")
	await escape()
	check(manager.hour_timer.paused,"closing preserves already-paused time")
	GameState.initialize_new_game()
	tutorial_done()
	PlayerProgress.story_beat_days.erase(BlacksmithProgressionRecords.PREFIX+"version")
	GameState.add_item("iron_ore",1)
	check(BlacksmithProgressionFlow.introduction_ready() and not BlacksmithProgressionRecords.has("ore_returned"),"untracked old ore supports non-consuming showing without fabricated provenance")
	GameState.initialize_new_game()
	tutorial_done()
	PlayerProgress.story_beat_days.erase(BlacksmithProgressionRecords.PREFIX+"version")
	PlayerProgress.record_story_beat(CommunityRequestFlow.PREFIX+"open_smithy:done",GameState.total_day)
	check(BlacksmithProgressionFlow.service_available() and not BlacksmithProgressionRecords.has("service_intro"),"legacy open workshop keeps rights without mandatory intro")
	check(not BlacksmithProgressionRecords.has("first_enhanced"),"old workshop alone does not fabricate prior enhancement")
	director.refresh()
	player.global_position = director.npc.global_position
	manager.hour_timer.paused = false
	check(director.try_interact(),"legacy workshop can reopen service")
	director.queue_free()
	await frames()
	check(not world.has_meta("blacksmith_open") and not manager.hour_timer.paused,"scene exit while service open restores clock and modal")
	prep.queue_free()
	world.queue_free()
	await frames()
	check(not world_is_open(),"scene exit clears modal state")
	print("CHECK_BLACKSMITH checks=",checks," failures=",failures)
	get_tree().quit(0 if failures == 0 else 1)
func world_is_open() -> bool: return is_instance_valid(world) and world.get_meta("blacksmith_open",false)
