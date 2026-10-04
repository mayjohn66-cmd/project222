extends Node
var failures := 0
var world

func check(ok: bool, label: String) -> void:
	if ok: print("PASS: ", label)
	else:
		failures += 1
		push_error(label)

func drain(dialogue: StoryDialoguePanel) -> void:
	for i in range(40):
		if not dialogue.open: break
		dialogue._advance()

func _ready() -> void: call_deferred("run")

func run() -> void:
	world = load("res://scenes/shop/main.tscn").instantiate()
	world.get_node("TutorialDirector").enabled = false # Post-tutorial fixture; opening is tested separately.
	add_child(world)
	for i in range(5): await get_tree().process_frame
	VillageSettlement.apply_world(world)
	check(ResidentStoryFlow.stage() == 0, "new game begins without settlements")
	check(not world.get_node("VillageExtraHouses/EastCottage").visible, "first house initially absent")
	check(world.get_node("VillageExtraHouses/EastCottage").collision_layer == 0, "absent house cannot block player")
	check(not world.get_node("VillageDecor/MarketStall").visible and not world.get_node("VillageDecor/VillageWell").visible, "stall and well initially absent")
	check(not world.get_node("VillageBuildings/VillageBakery").visible, "future buildings do not appear early")
	for step in TutorialDirector.SETTINGS.steps:
		PlayerProgress.record_story_beat("tutorial_step:" + str(step["id"]) + ":done", GameState.total_day)
	PlayerProgress.record_story_beat(CheckoutTutorial.BEAT_ID, GameState.total_day)
	for request in ResidentRequestFlow.SETTINGS.requests:
		PlayerProgress.record_story_beat(ResidentRequestFlow.PREFIX + str(request["id"]) + ":done", GameState.total_day)
	world.get_node("TutorialDirector").refresh()
	check(ResidentStoryFlow.pending_introduction().is_empty() and ResidentStoryFlow.current_request().is_empty(), "unlocks alone do not count as meeting a visitor")
	var director = world.get_node("ResidentRequestDirector")
	var player = world.get_node("Actors/Player")
	var manager = world.get_node("DayManager")
	for index in range(3):
		var introduction: Dictionary = ResidentStoryFlow.SETTINGS.introductions[index]
		var type_id := str(introduction["type"])
		ResidentRequestFlow.record_visit(type_id)
		director.refresh()
		check(ResidentStoryFlow.pending_introduction().get("type") == type_id, "actual visit queues introduction %d" % index)
		player.global_position = director.npc.global_position + Vector2(25,10)
		var money_before: int = GameState.get_money()
		var reputation_before := ResidentRequestFlow.reputation()
		var previous_paused: bool = manager.hour_timer.paused
		check(director.try_interact(), "E starts first greeting %d" % index)
		check(director.dialogue.name_label.text == str(introduction["npc"]), "named resident greets player")
		check(GameState.get_money() == money_before and ResidentRequestFlow.reputation() == reputation_before, "greeting does not award quest rewards")
		drain(director.dialogue)
		check(manager.hour_timer.paused == previous_paused, "greeting restores previous clock state")
		check(not ResidentStoryFlow.meet(type_id), "introduction cannot repeat")
		director.refresh()
		var request := ResidentRequestFlow.current()
		check(request.get("requires_intro") == type_id, "greeting leads to that resident's settlement request")
		player.global_position = director.npc.global_position + Vector2(25,10)
		director.try_interact()
		drain(director.dialogue)
		check(ResidentRequestFlow.accepted(str(request["id"])), "settlement request accepted through NPC")
		GameState.add_item(str(request["item"]), int(request["amount"]))
		player.global_position = director.npc.global_position + Vector2(25,10)
		check(director.try_interact(), "NPC receives materials and completes settlement")
		drain(director.dialogue)
		VillageSettlement.apply_world(world)
		var landmark: Dictionary = ResidentStoryFlow.SETTINGS.landmarks[index]
		var building = VillageSettlement.find_site(world, str(landmark["path"]))
		check(building.visible and building.collision_layer > 0, "completed landmark has matching visual and collision")
		check(ResidentStoryFlow.stage() == index + 1, "settlement grows one stage at a time")
		check(GameState.get_money() == money_before + int(request["money"]) and ResidentRequestFlow.reputation() == reputation_before + 1, "settlement pays small reward and reputation once")
		check(ResidentRequestFlow.deliver(request).is_empty(), "settlement cannot consume or pay twice")
		var saved := PlayerProgress.to_save_data()
		PlayerProgress.reset()
		PlayerProgress.load_save_data(saved)
		world.get_node("StoreExterior").refresh_village_layout()
		check(VillageSettlement.find_site(world, str(landmark["path"])).visible and ResidentStoryFlow.stage() == index + 1, "save load and exterior rebuild preserve settlement")
	check(ResidentRequestFlow.total_completed_count() == 9 and ResidentRequestFlow.completed_count() == 6, "followups preserve original customer milestone count")
	check(ResidentStoryFlow.place_name() == "함께 만든 작은 마을", "three residents form a small village")
	var bench := VillageSettlement.find_site(world, "VillageGathering/WellBench")
	check(bench == null or bench.visible, "shared well opens bench if one is placed")
	var cottages := 0
	for house in world.get_node("VillageExtraHouses").get_children():
		if house.visible: cottages += 1
	check(cottages == 1, "first resident opens one house rather than every copied house")
	var editor = world.get_node("VillageMapEditor")
	editor.active = true
	VillageSettlement.apply_world(world)
	check(VillageSettlement.find_site(world,"VillageBuildings/VillageBakery").visible, "map editor can still arrange future buildings")
	editor.active = false
	VillageSettlement.apply_world(world)
	check(not VillageSettlement.find_site(world,"VillageBuildings/VillageBakery").visible, "leaving editor restores story growth")
	world.get_node("StoreExterior").remove_layout_object("VillageDecor/VillageWell")
	VillageSettlement.apply_world(world)
	check(not world.get_node("VillageDecor/VillageWell").visible, "growth respects a removed map object")
	PlayerProgress.reset()
	VillageSettlement.apply_world(world)
	check(ResidentStoryFlow.stage() == 0 and world.get_node("VillageExtraHouses/EastCottage").collision_layer == 0, "new game clears town growth and hidden collision")
	print("CHECK_RESIDENT_SETTLEMENT failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)
