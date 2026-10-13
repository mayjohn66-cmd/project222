extends Node
var failures := 0

func check(ok: bool, caption: String) -> void:
	if ok: print("PASS: ", caption)
	else:
		failures += 1
		push_error(caption)

func drain(dialogue: StoryDialoguePanel) -> void:
	for i in range(40):
		if not dialogue.open: break
		dialogue._advance()
	var owner = dialogue.get_parent()
	if owner is ResidentRequestDirector and owner.request_offer.root.visible:
		owner.request_offer.accept_button.pressed.emit()

func _ready() -> void: call_deferred("run")

func run() -> void:
	var world = load("res://scenes/shop/main.tscn").instantiate()
	world.get_node("TutorialDirector").enabled = false # Post-tutorial fixture; opening is tested separately.
	add_child(world)
	for i in range(4): await get_tree().process_frame
	var director = world.get_node("ResidentRequestDirector")
	var player = world.get_node("Actors/Player")
	var manager = world.get_node("DayManager")
	var spawner = world.get_node("CustomerSpawner")
	var build = world.get_node("BuildManager")
	check(ResidentRequestFlow.current().is_empty() and not is_instance_valid(director.npc), "requests wait until all tutorial rewards claimed")
	check(not ResidentRequestFlow.customer_available("peddler"), "special customer initially locked")
	for i in range(400):
		var type_id := str(CustomerTypeData.get_random_customer_type(1).get("customer_type_id", ""))
		if not ResidentRequestFlow.customer_available(type_id):
			check(false, "locked type cannot appear in ordinary or offline selection")
			break
	for step in TutorialDirector.SETTINGS.steps:
		PlayerProgress.record_story_beat("tutorial_step:" + str(step["id"]) + ":done", GameState.total_day)
	PlayerProgress.record_story_beat(CheckoutTutorial.BEAT_ID, GameState.total_day)
	world.get_node("TutorialDirector").refresh()
	var layout: Array[Dictionary] = [
		{"build_id":"door", "anchor":Vector2i(0,4), "rotation_index":3},
		{"build_id":"register", "anchor":Vector2i(4,3), "rotation_index":0},
		{"build_id":"shelf_1x1", "anchor":Vector2i(2,2), "rotation_index":0,
		"shelf_slots":[{"item_id":"water", "stock":3, "capacity":5}]}]
	build._restore_current_area_layout(layout)
	director.refresh()
	check(is_instance_valid(director.npc), "resident arrives after tutorial")
	check(not director.try_interact(), "resident cannot be spoken to from far away")
	player.global_position = director.npc.global_position + Vector2(25,10)
	var request := ResidentRequestFlow.current()
	var money_before: int = GameState.get_money()
	var item_id := str(request["item"])
	var stock_before: int = GameState.get_item_count(item_id)
	check(director.try_interact(), "E accepts resident request")
	check(GameState.get_item_count(item_id) == stock_before and ResidentRequestFlow.completed_count() == 0, "acceptance does not consume inventory or give rewards")
	check(manager.hour_timer.paused and not player.is_physics_processing(), "dialogue pauses clock and player")
	drain(director.dialogue)
	check(not world.has_meta("progressive_tutorial_dialogue"), "dialogue restores interaction state")
	GameState.remove_item(item_id, GameState.get_item_count(item_id))
	check(ResidentRequestFlow.deliver(request).is_empty() and GameState.get_money() == money_before, "insufficient delivery cannot grant money")
	director.refresh()
	check(director.try_interact(),"E reminder remains accessible without requested stock")
	var reminder := "\n".join(director.dialogue.lines)
	check(not reminder.contains("먼저 꺼내") and not reminder.contains("창고로 옮겨"),"actual NPC reminder does not repeat inventory instructions")
	check(VillageJournalFlow.information("next_request").contains("소지품 기준"),"journal's quantity matches the same carried inventory")
	drain(director.dialogue)
	var saved := PlayerProgress.to_save_data()
	PlayerProgress.reset()
	PlayerProgress.load_save_data(saved)
	check(ResidentRequestFlow.accepted(str(request["id"])) and ResidentRequestFlow.reputation() == 0, "accepted request resumes after load")
	GameState.add_item(item_id, int(request["amount"]))
	player.global_position = director.npc.global_position + Vector2(25,10)
	check(director.try_interact(), "E delivers stock and pays reward")
	check(GameState.get_item_count(item_id) == 0 and GameState.get_money() == money_before + int(request["money"]), "delivery removes requested items and pays exact reward")
	check(ResidentRequestFlow.reputation() == 1, "delivery grants persistent reputation")
	check(spawner.spawn_timer.wait_time < spawner.base_spawn_interval, "NPC delivery immediately refreshes visit frequency")
	drain(director.dialogue)
	check(ResidentRequestFlow.deliver(request).is_empty(), "completed request cannot pay twice")
	# Water prerequisites have their own merchant progression integration check.
	PlayerProgress.record_story_beat(ResidentRequestFlow.PREFIX + "settle_naru:done", GameState.total_day)
	GameState.create_owned_equipment_instance("gathering_bottle", 0)
	for index in range(1,6):
		request = ResidentRequestFlow.current()
		ResidentRequestFlow.accept(request)
		GameState.add_item(str(request["item"]), int(request["amount"]))
		var result := ResidentRequestFlow.deliver(request)
		check(not result.is_empty(), "request %d can complete" % (index + 1))
		if index == 1:
			check(ResidentRequestFlow.customer_available("peddler") and not ResidentRequestFlow.customer_available("gem_hunter"), "two requests unlock only peddler")
			check(result["unlocked"] == ["peddler"], "milestone announces exact new type")
			check(ResidentRequestFlow.pending_introduction() == "peddler", "new type queued for first real visit")
		if index == 3:
			check(ResidentRequestFlow.customer_available("gem_hunter") and not ResidentRequestFlow.customer_available("relic_hunter"), "four requests unlock gem hunter")
	check(ResidentRequestFlow.customer_available("relic_hunter"), "six requests unlock relic hunter")
	spawner.refresh_spawn_interval()
	check(spawner.spawn_timer.wait_time < spawner.base_spawn_interval, "resident reputation increases arrival frequency")
	saved = PlayerProgress.to_save_data()
	PlayerProgress.reset()
	PlayerProgress.load_save_data(saved)
	check(ResidentRequestFlow.completed_count() == 6 and ResidentRequestFlow.reputation() == 6 and ResidentRequestFlow.customer_available("relic_hunter"), "rewards and unlocks survive save round trip")
	manager.open_shop()
	spawner.spawn_timer.stop()
	spawner.spawn_customer()
	var deadline := Time.get_ticks_msec() + 25000
	while ResidentRequestFlow.pending_introduction() == "peddler" and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	check(ResidentRequestFlow.pending_introduction() == "gem_hunter", "introduced customer actually enters before visit is recorded")
	var introduced := false
	for customer in get_tree().get_nodes_in_group("customer"):
		if customer.get_customer_type_id() == "peddler" and customer.visit_recorded: introduced = true
	check(introduced, "introduced customer uses actual shop customer and visit flow")
	director.refresh()
	check(is_instance_valid(director.npc) and ResidentStoryFlow.pending_introduction().get("type") == "peddler", "first real visit offers greeting after base requests")
	PlayerProgress.reset()
	check(ResidentRequestFlow.completed_count() == 0 and ResidentRequestFlow.reputation() == 0 and not ResidentRequestFlow.customer_available("peddler"), "new game clears reputation and customer unlocks")
	print("CHECK_RESIDENT_REQUESTS failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)
