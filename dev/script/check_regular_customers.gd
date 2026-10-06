extends Node
const Tools = preload("res://dev/gemini/request_text_tools.gd")
const Writer = preload("res://dev/gemini/request_text_runner.gd")
var world
var director: RegularCustomerDirector
var player
var manager
var shelf
var checks := 0
var failures := 0
func check(ok: bool, caption: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(caption)
func _ready() -> void: call_deferred("verify")
func frames() -> void:
	for i in range(8): await get_tree().process_frame
func drain() -> void:
	for i in range(100):
		if not director.dialogue.open: return
		director.dialogue._advance()
	check(false,"dialogue terminates")
func date(day: int) -> void:
	GameState.total_day = day
	GameState.preservation_state = PreservationService.initial_state(day)
func unlock() -> void:
	for step in TutorialDirector.SETTINGS.steps: PlayerProgress.record_story_beat("tutorial_step:" + str(step["id"]) + ":done",1)
	PlayerProgress.record_story_beat(CheckoutTutorial.BEAT_ID,1)
	for resident in VillageLifeFlow.SETTINGS.residents: PlayerProgress.record_story_beat(ResidentRequestFlow.PREFIX + str(resident["request"]) + ":done",1)
	for id in ["welcome_garden"]: PlayerProgress.record_story_beat(CommunityRequestFlow.PREFIX + id + ":done",1)
	PlayerProgress.record_story_beat(PersonalRequestFlow.PREFIX + "naru_neighbor_basket:done",1)
	VillageSettlement.apply_world(world)
func stock(item: String, amount: int) -> void:
	for slot in shelf.slots:
		if int(slot["stock"]) > 0: GameState.add_item(str(slot["item_id"]),int(slot["stock"]))
		slot["item_id"] = ""
		slot["stock"] = 0
	GameState.add_item(item,amount)
	check(GameState.remove_item(item,amount) == amount,"owned stock transferred to shelf")
	shelf.slots[0]["item_id"] = item
	shelf.slots[0]["stock"] = amount
	shelf.update_visual()
func buyer(type_id: String):
	var customer = load("res://scenes/shop/actors/customer.tscn").instantiate()
	world.get_node("Actors").add_child(customer)
	customer.set_physics_process(false)
	customer.global_position = world.get_node("BuildManager").get_cell_world_position(Vector2i(3,4))
	customer.customer_type_selected = true
	customer.customer_type_id = type_id
	customer.customer_group_id = CustomerTypeData.get_group_id(type_id)
	return customer
func purchase(customer) -> int:
	var item: String = customer.choose_wanted_item()
	customer.target_shelf = shelf
	customer.carried_item_id = item
	customer.carried_amount = shelf.take_items_by_id(item,customer.wanted_amount)
	var amount: int = customer.carried_amount
	var money: int = GameState.money
	customer.checkout_item()
	check(customer.purchase_completed and GameState.money == money + ItemData.get_item_price(item) * amount,"real checkout charges exact carried shelf goods")
	money = GameState.money
	customer.checkout_item()
	check(GameState.money == money,"duplicate checkout cannot pay or record again")
	return amount
func talk(id: String) -> bool:
	player.global_position = Vector2(8000,8000)
	director.refresh()
	if not is_instance_valid(director.npc): return false
	if director.current_id != id: return false
	check(player.global_position.distance_to(director.npc.global_position) >= RegularCustomerFlow.SETTINGS.separation,"NPC starts away from the player")
	player.global_position = director.npc.global_position
	var at: Vector2 = director.npc.global_position
	director.refresh()
	check(director.npc.global_position == at,"nearby conversation visitor does not teleport on refresh")
	return world.get_node("WorldInteractions").try_interact() and director.open
func verify() -> void:
	GameState.initialize_new_game()
	world = load("res://scenes/shop/main.tscn").instantiate()
	world.get_node("TutorialDirector").enabled = false
	world.get_node("VillageLifeDirector").crafting_path_enabled = false
	add_child(world)
	await frames()
	director = world.get_node("VillageLifeDirector/RegularCustomerDirector")
	director.set_process(false)
	player = world.get_node("Actors/Player")
	player.set_physics_process(false)
	manager = world.get_node("DayManager")
	manager.set_process(false)
	manager.hour_timer.stop()
	manager.hour_timer.paused = false
	manager.current_hour = 12
	world.get_node("CustomerSpawner").set_process(false)
	var layout: Array[Dictionary] = [{ "build_id":"door","anchor":Vector2i(0,4),"rotation_index":3},{"build_id":"register","anchor":Vector2i(4,3),"rotation_index":0},{"build_id":"shelf_1x1","anchor":Vector2i(2,2),"rotation_index":0}]
	world.get_node("BuildManager")._restore_current_area_layout(layout)
	await frames()
	shelf = get_tree().get_nodes_in_group("shelf")[0]
	check(RegularCustomerFlow.SETTINGS.events.size() == 3,"three recurring customer stories registered")
	check(PersonalRequestFlow.entries().size() == 20 + WorkshopRequestFlow.SETTINGS.requests.size() and MarketAfterglowFlow.moments().size() == 11 + WorkshopRequestFlow.SETTINGS.moments.size(),"existing personal requests and afterglows unchanged")
	for entry in RegularCustomerFlow.SETTINGS.events:
		var id := str(entry["id"])
		var type_id := str(entry["type"])
		var item := str(entry["purchase_item"])
		PlayerProgress.reset()
		date(5)
		check(RegularCustomerFlow.phase(id) == "locked" and not RegularCustomerFlow.complete_action(id,"intro"),"tutorial gate: " + id)
		unlock()
		check(RegularCustomerFlow.phase(id) == "first_purchase","visit record alone cannot replace actual first purchase")
		var key := ResidentRequestFlow.PREFIX + "visited:" + type_id
		PlayerProgress.record_story_beat(key,1)
		check(not RegularCustomerRecords.has(id,"first"),"historical type visit is not a purchase")
		stock(item,3)
		var aborted = buyer(type_id)
		check(not RegularCustomerVisits.prepare(aborted,"peddler"),"resident introduction keeps spawn priority")
		check(RegularCustomerVisits.prepare(aborted,type_id),"matching resident first introduction can also become regular")
		aborted.target_shelf = shelf
		aborted.carried_item_id = aborted.choose_wanted_item()
		aborted.carried_amount = shelf.take_items_by_id(item,1)
		aborted.go_to_exit()
		check(not RegularCustomerRecords.has(id,"first") and shelf.get_item_stock(item) == 3,"unpaid goods returned without story progress")
		aborted.queue_free()
		await frames()
		var first = buyer(type_id)
		check(RegularCustomerVisits.prepare(first),"first story shopper prepared")
		var duplicate = buyer(type_id)
		check(not RegularCustomerVisits.prepare(duplicate),"second simultaneous shopper cannot impersonate same regular")
		duplicate.queue_free()
		check(purchase(first) == 1 and RegularCustomerRecords.day(id,"first") == 5,"actual first paid purchase records date")
		first.queue_free()
		await frames()
		check(RegularCustomerFlow.phase(id) == "rest" and not talk(id),"first purchase cannot skip to introduction on same day")
		date(6)
		check(talk(id),"real E introduction after first purchase")
		check(world.get_node("WorldInteractions").blocked() and manager.hour_timer.paused,"dialogue blocks interactions and pauses clock")
		director.dialogue.close()
		check(not RegularCustomerRecords.has(id,"intro") and not manager.hour_timer.paused,"partial intro preserves eligibility and timer")
		check(talk(id),"interrupted intro retries")
		drain()
		check(RegularCustomerRecords.has(id,"intro") and RegularCustomerFlow.phase(id) == "rest","full intro enables next-day repeat only")
		date(7)
		stock(item,1)
		var repeat = buyer("villager")
		check(not RegularCustomerVisits.prepare(repeat),"repeat needs enough real shelf stock")
		stock(item,4)
		for milestone in ResidentRequestFlow.SETTINGS.customer_milestones:
			PlayerProgress.record_story_beat(ResidentRequestFlow.PREFIX + "visited:" + str(milestone["type"]),1)
		for visitor in VillageVisitorFlow.SETTINGS.visitors:
			PlayerProgress.record_story_beat(ResidentRequestFlow.PREFIX + "visited:" + str(visitor["type"]),1)
		world.get_node("CustomerSpawner").spawn_customer()
		var spawned := get_tree().get_nodes_in_group("regular_customer")
		check(spawned.size() == 1,"actual spawner reserves one returning regular")
		if spawned.size() == 1:
			check(spawned[0].get_customer_type_id() == type_id and str(spawned[0].get_meta("regular_story_id","")) == id,"actual pedestrian keeps selected story identity")
			check(spawned[0].choose_wanted_item() == item and spawned[0].wanted_amount == int(entry["repeat_amount"]),"actual spawned customer wants the configured companion purchase")
			spawned[0].queue_free()
		await frames()
		check(RegularCustomerVisits.prepare(repeat) and repeat.get_customer_type_id() == type_id,"ready return receives priority over random type")
		check(repeat.choose_wanted_item() == item and repeat.wanted_amount == int(entry["repeat_amount"]),"repeat buys exact configured commodity and amount")
		director.refresh()
		check(not is_instance_valid(director.npc) or director.current_id != id,"active shopping regular not cloned as conversation NPC")
		# Only enough paid goods advance the repeat; a stock race remains retryable.
		check(not RegularCustomerRecords.record_sale(repeat,item,1),"partial amount cannot complete companion purchase")
		check(purchase(repeat) == int(entry["repeat_amount"]) and RegularCustomerRecords.day(id,"repeat") == 7,"second real sale advances repeat date")
		repeat.queue_free()
		await frames()
		check(RegularCustomerFlow.phase(id) == "rest","paid repeat cannot immediately open request")
		date(8)
		check(talk(id),"request follows actual repeat purchase")
		director.dialogue.close()
		check(not RegularCustomerRecords.has(id,"accepted"),"aborted request not accepted")
		check(talk(id),"request can restart")
		drain()
		check(RegularCustomerRecords.has(id,"accepted"),"request accepted by full reading")
		var journal := RegularCustomerFlow.JOURNAL_PREFIX + id
		check(VillageJournalFlow.entries().any(func(e: Dictionary) -> bool: return e["id"] == journal),"journal lists story")
		date(120) # No season or expiry on an accepted request.
		var totals := CommunityRequestFlow.required_items(entry)
		for material in totals: GameState.remove_item(material,GameState.get_item_count(material))
		check(RegularCustomerFlow.phase(id) == "wait" and not RegularCustomerFlow.complete_action(id,"finish"),"missing materials cannot spend or award")
		check(talk(id),"reminder remains available in later season")
		drain()
		for material in totals: GameState.add_item(material,int(totals[material]))
		check(talk(id) and director.action_stage == "finish","ready delivery starts actual E dialogue")
		check(VillageJournalFlow.destination(world,journal) == director.npc,"journal destination is real visitor")
		var stolen: String = totals.keys()[0]
		GameState.remove_item(stolen,1)
		drain()
		check(not RegularCustomerRecords.has(id,"done") and ResidentRequestFlow.reputation() == 0,"stock decrease during final dialogue gives no partial reward")
		GameState.add_item(stolen,1)
		var gift_item := str(entry["gifts"][0]["item"])
		var gift_before: int = GameState.get_item_count(gift_item)
		var money_before: int = GameState.money
		var reputation_before := ResidentRequestFlow.reputation()
		check(talk(id),"final delivery retries after inventory recheck")
		director.dialogue.close()
		check(not RegularCustomerRecords.has(id,"done") and GameState.get_item_count(gift_item) == gift_before,"partial final reading cannot grant")
		check(talk(id),"final complete reading available")
		drain()
		check(RegularCustomerRecords.has(id,"done") and GameState.get_item_count(gift_item) == gift_before + int(entry["gifts"][0]["amount"]),"exact one-time configured gift")
		for material in totals: check(GameState.get_item_count(material) == 0,"exact required stock consumed")
		check(GameState.money == money_before and ResidentRequestFlow.reputation() == reputation_before + int(entry["reputation"]),"only configured reputation and item gift")
		check(not RegularCustomerFlow.complete_action(id,"finish"),"cannot repeat gift")
		var saved := GameState.create_save_data().duplicate(true)
		check(GameState.is_save_data_valid(saved) and GameState.apply_save_data(saved) and RegularCustomerRecords.has(id,"done"),"complete story survives full save")
		date(121)
		check(talk(id) and director.action_stage == "after","next-day customer afterglow")
		director.dialogue.close()
		check(not RegularCustomerRecords.has(id,"after"),"partial afterglow cannot mark memory")
		check(talk(id),"afterglow can resume")
		drain()
		check(RegularCustomerFlow.phase(id) == "complete" and not RegularCustomerFlow.complete_action(id,"after"),"completed memory cannot repeat")
		check(GameState.money == money_before and GameState.get_item_count(gift_item) == gift_before + int(entry["gifts"][0]["amount"]),"afterglow provides no extra goods or money")
		check(VillageJournalFlow.information(journal).contains(RequestTextData.text("service_text",id + "_after","completion")),"journal retains customer-specific final memory")
	var sources := Tools.load_sources()
	for entry in RegularCustomerFlow.SETTINGS.events: check(not sources[Tools.KIND_SERVICE_TEXT].has(str(entry["id"])),"mechanical events excluded from prose")
	for moment in RegularCustomerFlow.SETTINGS.moments:
		var id := str(moment["id"])
		check(sources[Tools.KIND_SERVICE_TEXT].has(id),"Gemini source knows new scene")
		var prompt := Writer.build_prompt(Tools.KIND_SERVICE_TEXT,{Tools.KIND_SERVICE_TEXT:{id:sources[Tools.KIND_SERVICE_TEXT][id]}},sources)
		check(prompt.contains(str(moment["stage"])) and prompt.contains(str(moment["npc"])),"prose prompt preserves exact scene context")
	var prose := Tools.validate_file(Tools.TEXT_PATH,sources)
	print("REGULAR_TEXT ",prose)
	check(prose["errors"].is_empty() and prose["warns"].is_empty(),"complete CSV valid without warnings")
	PlayerProgress.reset()
	for entry in RegularCustomerFlow.SETTINGS.events: check(not RegularCustomerRecords.has(str(entry["id"]),"first") and not RegularCustomerRecords.has(str(entry["id"]),"done"),"new progress resets customer story")
	world.queue_free()
	await frames()
	check(not get_tree().paused,"scene exit keeps tree usable")
	print("CHECK_REGULAR_CUSTOMERS checks=",checks," failures=",failures)
	get_tree().quit(0 if failures == 0 else 1)
