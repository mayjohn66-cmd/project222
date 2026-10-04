extends Node

const Tools = preload("res://dev/gemini/request_text_tools.gd")
const Writer = preload("res://dev/gemini/request_text_runner.gd")
var checks := 0
var failures := 0
var world
var player
var manager
var shelf
var visitor: RegularCustomerDirector

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
func _ready() -> void: call_deferred("verify")
func frames() -> void:
	for i in range(8): await get_tree().process_frame
func date(value: int) -> void:
	GameState.total_day = value
	GameState.preservation_state = PreservationService.initial_state(value)
func unlock() -> void:
	for step in TutorialDirector.SETTINGS.steps: PlayerProgress.record_story_beat("tutorial_step:" + str(step["id"]) + ":done",1)
	PlayerProgress.record_story_beat(CheckoutTutorial.BEAT_ID,1)
	for resident in VillageLifeFlow.SETTINGS.residents: PlayerProgress.record_story_beat(ResidentRequestFlow.PREFIX + str(resident["request"]) + ":done",1)
	for entry in ResidentRequestFlow.SETTINGS.customer_milestones: PlayerProgress.record_story_beat(ResidentRequestFlow.PREFIX + "visited:" + str(entry["type"]),1)
	for entry in VillageVisitorFlow.SETTINGS.visitors: PlayerProgress.record_story_beat(ResidentRequestFlow.PREFIX + "visited:" + str(entry["type"]),1)
	VillageSettlement.apply_world(world)
func drain(panel: StoryDialoguePanel) -> void:
	for i in range(100):
		if not panel.open: return
		panel._advance()
	check(false,"dialogue terminates")
func talk(id: String) -> bool:
	player.global_position = Vector2(8000,8000)
	visitor.refresh()
	if not is_instance_valid(visitor.npc) or visitor.current_id != id: return false
	check(player.global_position.distance_to(visitor.npc.global_position) >= visitor.story_flow.SETTINGS.separation,"visitor appears away from player")
	player.global_position = visitor.npc.global_position
	var point: Vector2 = visitor.npc.global_position
	visitor.refresh()
	check(visitor.npc.global_position == point,"approaching visitor stays in place")
	return world.get_node("WorldInteractions").try_interact() and visitor.open
func stock(item: String, amount: int) -> void:
	for slot in shelf.slots:
		if int(slot["stock"]) > 0: GameState.add_item(str(slot["item_id"]),int(slot["stock"]))
		slot["item_id"] = ""
		slot["stock"] = 0
	if amount > 0:
		GameState.add_item(item,amount)
		check(GameState.remove_item(item,amount) == amount,"real owned shelf stock")
		shelf.slots[0]["item_id"] = item
		shelf.slots[0]["stock"] = amount
	shelf.update_visual()
func walk(room: ExpeditionRoomModel, point: Vector2) -> bool:
	var grid := ExpeditionRoomTestDriver._walk_grid(room)
	for step in range(2000):
		if room.player_position.distance_to(point) <= 0.65: return true
		room.step(1.0/60.0,ExpeditionRoomTestDriver._walk_direction(room,point,grid),false)
	return false
func verify() -> void:
	GameState.initialize_new_game()
	world = load("res://scenes/shop/main.tscn").instantiate()
	world.get_node("TutorialDirector").enabled = false
	world.get_node("VillageLifeDirector").crafting_path_enabled = false
	add_child(world)
	await frames()
	visitor = world.get_node("VillageLifeDirector/ExpeditionContactDirector")
	visitor.set_process(false)
	world.get_node("VillageLifeDirector/RegularCustomerDirector").set_process(false)
	world.get_node("VillageLifeDirector").set_process(false)
	player = world.get_node("Actors/Player")
	player.set_physics_process(false)
	manager = world.get_node("DayManager")
	manager.set_process(false)
	manager.hour_timer.stop()
	manager.hour_timer.paused = false
	world.get_node("CustomerSpawner").set_process(false)
	var layout: Array[Dictionary] = [{"build_id":"door","anchor":Vector2i(0,4),"rotation_index":3},{"build_id":"register","anchor":Vector2i(4,3),"rotation_index":0},{"build_id":"shelf_1x1","anchor":Vector2i(2,2),"rotation_index":0}]
	world.get_node("BuildManager")._restore_current_area_layout(layout)
	await frames()
	shelf = get_tree().get_nodes_in_group("shelf")[0]
	check(ExpeditionContactFlow.SETTINGS.events.size() == 3,"three expedition contacts")
	check(PersonalRequestFlow.entries().size() == 20 + WorkshopRequestFlow.SETTINGS.requests.size() and RegularCustomerFlow.SETTINGS.events.size() == 3,"existing content counts unchanged")
	for entry in ExpeditionContactFlow.SETTINGS.events:
		var id := str(entry["id"])
		var region := str(entry["region"])
		PlayerProgress.reset()
		date(5)
		check(ExpeditionContactFlow.encounter(region,"none","unknown").is_empty() and not ExpeditionContactFlow.meet(id),"core tutorial and first settlement gate")
		unlock()
		for result in ["battle","loot"]: check(ExpeditionContactFlow.encounter(region,result,"unknown").is_empty(),"no contact in combat or loot room")
		check(ExpeditionContactFlow.encounter(region,"none","gather").is_empty(),"does not replace gathering")
		check(ExpeditionContactFlow.encounter("hidden_ruins","none","unknown").is_empty(),"unconfigured region unchanged")
		var host = load("res://scenes/expedition/expedition.tscn").instantiate()
		add_child(host)
		await frames()
		host.expedition_map = ExpeditionMap.new()
		host.current_region_id = region
		host.set_expedition_phase(host.ExpeditionPhase.RUN)
		var controller: ExpeditionRoomController = host.expedition_room_controller
		for variation in range(12):
			controller.enter({"result_type":"heal","value":20},"unknown")
			var point := controller.contact.position
			check(point != Vector2.INF and walk(controller.model,point),"random regional layout has a genuinely walkable contact: " + id)
			check(point.distance_to(controller.model.object_position) >= ExpeditionContactFlow.SETTINGS.room_separation,"contact separated from original rest object")
			check(not controller.model.object_consumed and controller.pending_loot.is_empty(),"walking does not auto-consume rest or create loot")
		controller.enter({"result_type":"heal","value":20},"unknown")
		check(await ExpeditionRoomTestDriver.play(controller) and not ExpeditionContactFlow.has(id,"met"),"can use original rest and leave without talking to contact")
		controller.enter({"result_type":"heal","value":20},"unknown")
		controller.view.set_physics_process(false)
		check(controller.model.exit_open and controller.contact.hint().is_empty(),"optional contact neither locks exit nor speaks from afar")
		check(walk(controller.model,controller.contact.position),"walk to NPC without teleporting or changing walls")
		check(controller.model.interaction_label() == "말 걸기","nearby interaction delegates to contact")
		var stock_before := GameState.get_item_count(str(entry["requirements"][0]["item"]))
		var bag_before: Array = host.expedition_bag.placements.duplicate(true)
		GameState.set_meta("shop_return_context",{"expedition_seconds":10.0})
		controller.view.interact_button.pressed.emit()
		check(controller.contact.open and controller._menu_open() and not host.get_node("ExpeditionClock").is_processing(),"native E button opens dialogue and pauses room and clock")
		var at := controller.model.player_position
		var elapsed := controller.model.elapsed
		var seconds: float = GameState.get_meta("shop_return_context")["expedition_seconds"]
		controller.view.set_physics_process(true)
		Input.action_press("move_up")
		for i in range(8): await get_tree().physics_frame
		Input.action_release("move_up")
		check(controller.model.player_position == at and controller.model.elapsed == elapsed,"held movement cannot run underneath dialogue")
		check(float(GameState.get_meta("shop_return_context")["expedition_seconds"]) == seconds,"dialogue does not add expedition absence time")
		controller.view.set_physics_process(false)
		controller.contact.dialogue.close()
		check(not ExpeditionContactFlow.has(id,"met") and host.get_node("ExpeditionClock").is_processing(),"interrupted meeting records nothing and restores clock")
		host.get_node("ExpeditionClock").set_process(false)
		controller.model.interact()
		drain(controller.contact.dialogue)
		check(not host.get_node("ExpeditionClock").is_processing(),"previously stopped clock remains stopped after full reading")
		host.get_node("ExpeditionClock").set_process(true)
		check(ExpeditionContactFlow.has(id,"met") and not controller.contact.open,"full actual meeting records once")
		check(host.expedition_bag.placements == bag_before and GameState.get_item_count(str(entry["requirements"][0]["item"])) == stock_before,"meeting consumes neither bag nor warehouse")
		check(not controller.model.object_consumed and controller.pending_loot.is_empty(),"meeting preserves rest interaction and original reward")
		check(not ExpeditionContactFlow.meet(id) and ExpeditionContactFlow.encounter(region,"none","unknown").is_empty(),"already met person not cloned in subsequent room")
		GameState.remove_meta("shop_return_context")
		var met_save := GameState.create_save_data().duplicate(true)
		check(GameState.is_save_data_valid(met_save) and GameState.apply_save_data(met_save) and ExpeditionContactFlow.has(id,"met"),"meeting survives full save")
		controller._retreat()
		check(host.current_expedition_phase == host.ExpeditionPhase.RESULT and ExpeditionContactFlow.has(id,"met"),"retreat keeps genuine social memory")
		host.queue_free()
		await frames()
		check(ExpeditionContactFlow.phase(id) == "rest" and not talk(id),"no same-day village hand-in")
		date(120) # Accepted encounter has no season/expiry.
		var totals := CommunityRequestFlow.required_items(entry)
		for item in totals: GameState.remove_item(item,GameState.get_item_count(item))
		check(ExpeditionContactFlow.phase(id) == "wait" and talk(id),"village waits across seasons for real stock")
		check(world.get_node("WorldInteractions").blocked() and manager.hour_timer.paused,"shared visitor dialogue blocks and pauses correctly")
		drain(visitor.dialogue)
		for item in totals: GameState.add_item(item,int(totals[item]))
		check(talk(id) and visitor.action_stage == "finish","same person receives ready materials via E")
		check(VillageJournalFlow.destination(world,ExpeditionContactFlow.JOURNAL_PREFIX+id) == visitor.npc,"journal targets actual contact visitor")
		var removed: String = totals.keys()[0]
		GameState.remove_item(removed,1)
		drain(visitor.dialogue)
		check(not ExpeditionContactFlow.has(id,"done") and ResidentRequestFlow.reputation() == 0,"inventory race cannot give partial hand-in or reward")
		GameState.add_item(removed,1)
		var gift := str(entry["gifts"][0]["item"])
		var gift_before := GameState.get_item_count(gift)
		var money_before: int = GameState.money
		check(talk(id),"hand-in can retry")
		visitor.dialogue.close()
		check(not ExpeditionContactFlow.has(id,"done") and GameState.get_item_count(gift) == gift_before,"partial village dialogue cannot consume or grant")
		check(talk(id),"hand-in retry available")
		drain(visitor.dialogue)
		for item in totals: check(GameState.get_item_count(item) == 0,"exact stock consumed")
		check(GameState.get_item_count(gift) == gift_before+int(entry["gifts"][0]["amount"]) and ResidentRequestFlow.reputation() == int(entry["reputation"]),"one-time configured gift and reputation")
		check(GameState.money == money_before and not ExpeditionContactFlow.complete_action(id,"finish"),"no cash reward or duplicate hand-in")
		check(ExpeditionContactFlow.phase(id) == "rest","shopping waits until another day")
		date(121)
		var item := str(entry["purchase_item"])
		stock(item,0)
		world.get_node("CustomerSpawner").spawn_customer()
		check(get_tree().get_nodes_in_group("expedition_contact_customer").is_empty(),"empty shelves cannot fabricate contact purchase")
		for actor in get_tree().get_nodes_in_group("customer"): actor.queue_free()
		await frames()
		stock(item,2)
		world.get_node("CustomerSpawner").spawn_customer()
		var buyers := get_tree().get_nodes_in_group("expedition_contact_customer")
		check(buyers.size() == 1,"native spawner selects returning expedition contact")
		if buyers.size() == 1:
			var customer = buyers[0]
			customer.set_physics_process(false)
			customer.global_position = world.get_node("BuildManager").get_cell_world_position(Vector2i(3,4))
			check(customer.get_customer_type_id() == str(entry["type"]) and customer.choose_wanted_item() == item,"actual returning shopper identity and commodity")
			check(not ExpeditionContactVisits.prepare(customer,"peddler"),"pending resident introduction remains prior")
			check(not ExpeditionContactVisits.prepare(customer),"same in-flight representative cannot reserve another visit")
			check(not ExpeditionContactFlow.record_sale(customer,item,1),"unpaid API call cannot record visit")
			visitor.refresh()
			check(not is_instance_valid(visitor.npc) or visitor.current_id != id,"shopping person not cloned as E visitor")
			customer.target_shelf = shelf
			customer.carried_item_id = item
			customer.carried_amount = shelf.take_items_by_id(item,customer.wanted_amount)
			customer.checkout_item()
			check(ExpeditionContactFlow.has(id,"bought") and GameState.money == money_before+ItemData.get_item_price(item),"actual paid shelf goods advance purchase once")
			customer.checkout_item()
			check(GameState.money == money_before+ItemData.get_item_price(item) and not ExpeditionContactFlow.record_sale(customer,item,1),"duplicate checkout cannot repeat")
			customer.queue_free()
		await frames()
		check(ExpeditionContactFlow.phase(id) == "rest","purchase does not immediately skip to afterglow")
		date(122)
		check(talk(id) and visitor.action_stage == "after","next-day afterglow via actual E")
		visitor.dialogue.close()
		check(not ExpeditionContactFlow.has(id,"after"),"partial afterglow not recorded")
		check(talk(id),"afterglow remains readable")
		drain(visitor.dialogue)
		check(ExpeditionContactFlow.phase(id) == "complete" and not ExpeditionContactFlow.complete_action(id,"after"),"afterglow and rewards cannot repeat")
		check(GameState.get_item_count(gift) == gift_before+int(entry["gifts"][0]["amount"]),"afterglow adds no gift")
		check(VillageJournalFlow.information(ExpeditionContactFlow.JOURNAL_PREFIX+id).contains(RequestTextData.text("service_text",id+"_after","completion")),"journal keeps correct memory")
		var saved := GameState.create_save_data().duplicate(true)
		check(GameState.is_save_data_valid(saved) and GameState.apply_save_data(saved) and ExpeditionContactFlow.phase(id) == "complete","full completion survives save/load")
	var sources := Tools.load_sources()
	for entry in ExpeditionContactFlow.SETTINGS.events: check(not sources[Tools.KIND_SERVICE_TEXT].has(str(entry["id"])),"mechanical events excluded from writing")
	for moment in ExpeditionContactFlow.SETTINGS.moments:
		var id := str(moment["id"])
		check(sources[Tools.KIND_SERVICE_TEXT].has(id),"writer knows new moment")
		check(Writer.build_prompt(Tools.KIND_SERVICE_TEXT,{Tools.KIND_SERVICE_TEXT:{id:sources[Tools.KIND_SERVICE_TEXT][id]}},sources).contains(str(moment["stage"])),"writer preserves mechanical scene context")
	var prose := Tools.validate_file(Tools.TEXT_PATH,sources)
	check(prose["errors"].is_empty() and prose["warns"].is_empty(),"all prose valid")
	PlayerProgress.reset()
	for entry in ExpeditionContactFlow.SETTINGS.events: check(not ExpeditionContactFlow.has(str(entry["id"]),"met"),"new game clears encounter")
	world.queue_free()
	await frames()
	print("CONTACT_TEXT ",prose)
	print("CHECK_EXPEDITION_CONTACTS checks=",checks," failures=",failures)
	get_tree().quit(0 if failures == 0 else 1)
