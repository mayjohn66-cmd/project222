extends Node
const F = preload("res://script/world/shop/requests/village_expansion_flow.gd")
const Tools = preload("res://dev/gemini/request_text_tools.gd")
var checks := 0
var failures := 0
var world
var player
var manager
var life: VillageLifeDirector
var director: VillageExpansionDirector
var board: CommunityBoardDirector
var facilities: Dictionary = {}
var field_host

func check(ok: bool, label_text: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label_text)
func frames() -> void:
	for i in range(8): await get_tree().process_frame
func drain() -> void:
	for i in range(150):
		if not director.dialogue.open: return
		director.dialogue._advance()
	check(false,"dialogue terminates")
func saved() -> void:
	var data := PlayerProgress.to_save_data().duplicate(true)
	PlayerProgress.reset()
	PlayerProgress.load_save_data(data)
func mark_neighbors() -> void:
	for entry in VillageLifeFlow.entries(): PlayerProgress.record_story_beat(VillageLifeFlow.PREFIX + "greeted:" + str(entry["id"]),GameState.total_day)
func unlock() -> void:
	for stage in TutorialDirector.SETTINGS.steps: PlayerProgress.record_story_beat("tutorial_step:" + str(stage["id"]) + ":done",1)
	PlayerProgress.record_story_beat(CheckoutTutorial.BEAT_ID,1)
	for entry in VillageLifeFlow.SETTINGS.residents: PlayerProgress.record_story_beat(ResidentRequestFlow.PREFIX + str(entry["request"]) + ":done",1)
	for stage in CraftingPathFlow.SETTINGS.stages: PlayerProgress.record_story_beat(CraftingPathFlow.key(str(stage["id"]),"done"),1)
	for entry in VillageLifeFlow.entries(): PlayerProgress.story_beat_days[VillageLifeFlow.PREFIX + "friendship:" + str(entry["id"])] = 10
	mark_neighbors()
func fixture(entry: Dictionary) -> void:
	PlayerProgress.reset()
	var offsets := {"spring":0,"summer":28,"autumn":56,"winter":84}
	GameState.total_day = int(offsets.get(entry.get("season",""),0)) + int(entry.get("start_day",14))
	if entry.has("anniversary"): GameState.total_day = 113
	GameState.total_day = maxi(GameState.total_day,int(entry.get("minimum_day",1)))
	GameState.preservation_state = PreservationService.initial_state(GameState.total_day)
	unlock()
	for previous in entry.get("after",[]):
		PlayerProgress.story_beat_days[F.key(str(previous),"last_done")] = 1
		PlayerProgress.story_beat_days[F.key(str(previous),"count")] = 1
	for previous in entry.get("after_personal",[]): PlayerProgress.record_story_beat(PersonalRequestFlow.PREFIX + str(previous) + ":done",1)
	for previous in entry.get("after_regular",[]): PlayerProgress.record_story_beat(RegularCustomerRecords.key(str(previous),"after"),1)
	for previous in entry.get("after_contact",[]): PlayerProgress.record_story_beat(ExpeditionContactFlow.key(str(previous),"after"),1)
	for id in entry.get("neighbors",[]):
		var neighbor := F.resident_entry(str(id))
		if not neighbor.is_empty():
			PlayerProgress.story_beat_days[F.key(str(neighbor["expansion_event"]),"last_done")] = 1
			PlayerProgress.story_beat_days[F.key(str(neighbor["expansion_event"]),"count")] = 1
	for recipe in ProductRecipeData.get_all_recipes():
		if not str(recipe["recipe_id"]) in ["berry_filled_bread","packed_mushroom_meal"]: PlayerProgress.learn_recipe(str(recipe["recipe_id"]))
	manager.current_hour = 6
	player.global_position = Vector2(8000,8000)
	VillageSettlement.apply_world(world)
	life.refresh()
	director.refresh()
func board_accept(id: String) -> bool:
	player.global_position = VillageSettlement.find_site(world,CommunityRequestFlow.SETTINGS.board_path).global_position
	if not board.try_interact(): return false
	var card: Dictionary = board.panel.cards.get(F.JOURNAL_PREFIX + id,{})
	if card.is_empty() or card["action"].disabled:
		board.panel.close()
		return false
	card["action"].pressed.emit()
	board.panel.close()
	return F.accepted(id)
func talk(current: Dictionary) -> bool:
	mark_neighbors()
	life.refresh()
	director.refresh()
	var npc = director.npc_for(str(current["resident"]))
	if current.get("mode","") == "gather" and F.step_reason(str(current["event"]),manager.current_hour).is_empty():
		player.global_position = VillageSettlement.find_site(world,str(current["site"])).global_position
	elif is_instance_valid(npc): player.global_position = npc.global_position
	else: return false
	return world.get_node("WorldInteractions").try_interact() and director.talking and str(director.action.get("event","")) == str(current["event"])
func produce(item: String, amount: int) -> void:
	var recipe := ProductRecipeData.get_recipe(item)
	var facility: ProductionFacility = facilities[str(recipe["facility_id"])]
	for ingredient in recipe["ingredients"]: GameState.add_item(str(ingredient["item_id"]),int(ingredient["amount"]) * amount)
	check(facility.start_production(item,amount),"real recipe starts " + item)
	facility._process(facility.remaining_seconds + 1)
	check(facility.collect_production(),"real production collection " + item)
func field_gather(current: Dictionary) -> void:
	if not is_instance_valid(field_host):
		field_host = load("res://scenes/expedition/expedition.tscn").instantiate()
		add_child(field_host)
		await frames()
		field_host.expedition_map = ExpeditionMap.new()
	field_host.current_region_id = str(current["region"])
	field_host.set_expedition_phase(field_host.ExpeditionPhase.RUN)
	field_host.get_node("ExpeditionClock").set_process(false)
	var controller: ExpeditionRoomController = field_host.expedition_room_controller
	var table_id := str(current["region"]) + "_gather"
	for attempt in range(50):
		controller.enter({"result_type":"loot","target_id":table_id},"gather")
		check(await ExpeditionRoomTestDriver.play(controller),"real field movement and E " + str(current["event"]))
		check(field_host.temporary_loot == controller.pending_loot,"quest never duplicates actual field loot")
		if PlayerProgress.story_beat_days.has(F.key(str(current["event"]),"discovered",F.cycle(str(current["event"])) )): return
	check(false,"actual regional drop records discovery " + str(current["event"]))
func complete_stages(entry: Dictionary, partial: bool = true) -> void:
	var id := str(entry["id"])
	var money_before: int = GameState.money
	var rep_before := ResidentRequestFlow.reputation()
	for index in range(entry["steps"].size()):
		var current := F.step(id)
		if current.is_empty():
			check(false,"stage exists " + id + str(index))
			return
		check(int(current["index"]) == index,"ordered stage " + str(current["id"]))
		if int(current.get("wait_days",0)) > 0:
			check(not F.step_reason(id,manager.current_hour).is_empty() and not F.complete(current,manager.current_hour),"next day gate " + id)
			GameState.total_day += int(current["wait_days"])
			mark_neighbors()
		var totals := CommunityRequestFlow.required_items(current)
		for item in totals: GameState.remove_item(item,GameState.get_item_count(item))
		if not totals.is_empty(): check(not F.complete(current,manager.current_hour) and GameState.money == money_before,"missing stock cannot advance or pay " + id)
		if current.has("region"):
			F.record_gather("wrong_region",str(current["discover_item"]),1)
			F.record_gather(str(current["region"]),str(current["discover_item"]),0)
			check(not PlayerProgress.story_beat_days.has(F.key(id,"discovered",F.cycle(id))),"invalid harvest never proves discovery")
			await field_gather(current)
		if current.get("mode","") == "produce":
			for item in totals: GameState.add_item(item,int(totals[item]))
			check(not F.complete(current,manager.current_hour),"warehouse stock alone cannot replace actual crafting " + id)
			for item in totals:
				GameState.remove_item(item,GameState.get_item_count(item))
				produce(item,int(totals[item]))
		else:
			for item in totals: GameState.add_item(item,int(totals[item]))
		if current.get("mode","") == "gather":
			check(not F.complete(current,6),"gathering is time gated " + id)
			var gathering_day: int = GameState.total_day
			GameState.total_day += 28
			check(not F.complete(current,int(current["start_hour"])) and F.accepted(id),"preparation survives season change without premature gathering")
			GameState.total_day = gathering_day
			GameState.total_day += 21 - CalendarData.get_day_of_season(GameState.total_day)
			check(not F.complete(current,int(current["start_hour"])) and F.accepted(id),"late festival preparation waits for next season rather than expiring")
			GameState.total_day = gathering_day
			manager.current_hour = int(current["start_hour"])
			manager.hour_timer.paused = false
			player.global_position = VillageSettlement.find_site(world,str(current["site"])).global_position
			life.refresh()
			check(VillageRoutine.location(VillageLifeFlow.resident("naru"),manager.current_hour)["path"] == current["site"],"actual residents receive gathering destination")
			var speed := Engine.time_scale
			Engine.time_scale = 20.0
			for frame in range(600):
				if director.all_present(current): break
				await get_tree().physics_frame
			Engine.time_scale = speed
			if not director.all_present(current):
				for resident in current["participants"]:
					var actor = director.npc_for(str(resident))
					print("GATHER_DEBUG ",resident," actor=",actor," position=",actor.global_position if is_instance_valid(actor) else Vector2.INF," site=",VillageSettlement.find_site(world,str(current["site"])).global_position," route=",actor.get("route") if is_instance_valid(actor) else [])
			check(director.all_present(current),"residents walk around buildings to seasonal gathering " + id)
		var stock: Dictionary = {}
		for item in totals: stock[item] = GameState.get_item_count(item)
		manager.hour_timer.paused = index % 2 == 0
		var paused_before: bool = manager.hour_timer.paused
		if partial:
			check(talk(current) and world.get_node("WorldInteractions").blocked(),"real E opens shared modal " + str(current["id"]))
			director.dialogue.close()
			check(F.step(id) == current and manager.hour_timer.paused == paused_before and not player.is_physics_processing(),"partial reading restores exact state without progression")
			for item in totals: check(GameState.get_item_count(item) == stock[item],"partial reading preserves goods")
		check(talk(current),"real E resumes " + str(current["id"]))
		drain()
		check(not director.talking and manager.hour_timer.paused == paused_before,"full reading restores modal and clock")
		check(not F.complete(current,manager.current_hour),"stale action cannot repeat handoff " + id)
		for item in totals: check(GameState.get_item_count(item) == int(stock[item]) - int(totals[item]),"exact handoff once " + item)
		if index < entry["steps"].size() - 1: check(GameState.money == money_before and ResidentRequestFlow.reputation() == rep_before,"no early reward " + id)
		saved()
		await frames()
	check(F.done(id) and not F.accepted(id),"completed story persists " + id)
	check(GameState.money == money_before + int(entry.get("money",0)),"exact final payment " + id)
	check(ResidentRequestFlow.reputation() == rep_before + (0 if int(PlayerProgress.story_beat_days[F.key(id,"count")]) > 1 else int(entry.get("reputation",1))),"first completion reputation only " + id)
	for path in entry.get("unlocks",[]): check(VillageSettlement.find_site(world,str(path)).visible,"actual village site unlocks " + str(path))
	check(VillageJournalFlow.information(F.JOURNAL_PREFIX + id).contains("함께 마친 날"),"journal contains completed memory")
	print("EXPANSION_COMPLETED ",id)
func verify_sales() -> void:
	var build = world.get_node("BuildManager")
	var layout: Array[Dictionary] = [{"build_id":"door","anchor":Vector2i(0,4),"rotation_index":3},{"build_id":"register","anchor":Vector2i(4,3),"rotation_index":0},{"build_id":"shelf_1x1","anchor":Vector2i(2,2),"rotation_index":0}]
	build._restore_current_area_layout(layout)
	await frames()
	var register = get_tree().get_nodes_in_group("register")[0]
	var shelf = get_tree().get_nodes_in_group("shelf")[0]
	var cashier = world.get_node("ManualCheckoutController")
	manager.open_shop()
	manager.customer_spawner.set_process(false)
	for item in ["berry_filled_bread","packed_mushroom_meal"]:
		produce(item,1)
		check(GameState.remove_item(item,1) == 1,"produced goods stocked for real sale")
		shelf.slots[0]["item_id"] = item
		shelf.slots[0]["stock"] = 1
		var customer = load("res://scenes/shop/actors/customer.tscn").instantiate()
		world.get_node("Actors").add_child(customer)
		customer.set_physics_process(false)
		customer.global_position = build.get_cell_world_position(register.get_checkout_cells()[0])
		check(shelf.take_items_by_id(item,1) == 1,"customer takes new product from shelf")
		customer.carried_item_id = item
		customer.carried_amount = 1
		customer.target_register = register
		register.request_checkout(customer)
		player.global_position = build.get_cell_world_position(register.get_worker_cells()[0])
		var before: int = GameState.money
		check(world.get_node("WorldInteractions").try_interact() and cashier.is_busy(),"manual checkout E for " + item)
		cashier._process(2.0)
		check(customer.purchase_completed and GameState.money == before + ItemData.get_item_price(item),"new product actually sold at configured price")
		customer.queue_free()
		await frames()
func verify_edges() -> void:
	check(not F.complete({}) and not F.accept("unknown"),"invalid actions fail closed")
	fixture(F.event("birthday_naru"))
	GameState.total_day = 12
	check(not F.accept("birthday_naru"),"birthday does not start before configured window")
	GameState.total_day = 15
	check(F.accept("birthday_naru"),"birthday starts in configured window")
	var accepted_cycle := F.cycle("birthday_naru")
	GameState.total_day = 130
	check(F.cycle("birthday_naru") == accepted_cycle and F.locked_reason("birthday_naru").is_empty(),"late gift retains accepted year with no expiry")
	saved()
	check(F.cycle("birthday_naru") == accepted_cycle,"year crossing persists")
	fixture(F.event("shop_anniversary"))
	PlayerProgress.record_story_beat(CheckoutTutorial.BEAT_ID,3)
	GameState.total_day = 114
	check(not F.accept("shop_anniversary"),"anniversary counts from actual first transaction")
	GameState.total_day = 115
	check(F.accept("shop_anniversary"),"anniversary opens after a whole year")
	for id in ["settle_baker","settle_herbalist"]:
		var entry := F.event(id)
		fixture(entry)
		var k := RegularCustomerRecords.key("regular_cook_aroma","after") if id == "settle_baker" else ExpeditionContactFlow.key("contact_forest_bundle","after")
		PlayerProgress.story_beat_days.erase(k)
		check(not F.accept(id),"new neighbor requires completed real customer purchase story " + id)
	fixture(F.event("product_berry_bread"))
	PlayerProgress.learn_recipe("berry_filled_bread")
	check(not RecipeUnlockData.is_recipe_available("berry_filled_bread"),"recipe knowledge cannot skip introduction")
	check(F.accept("product_berry_bread"),"product introduction can start")
	F.record_output("berry_filled_bread",20)
	check(not PlayerProgress.story_beat_days.has(F.key("product_berry_bread","made:berry_filled_bread",1)),"production before introduction is not credited")
	fixture(F.event("order_work"))
	check(F.accept("order_work") and F.complete(F.step("order_work"),6),"prepare actual handoff stage")
	var current := F.step("order_work")
	GameState.remove_item("herbal_bread",GameState.get_item_count("herbal_bread"))
	check(talk(current),"missing goods open preparation guidance")
	drain()
	check(F.step("order_work") == current,"fully read guidance cannot complete missing goods")
	GameState.add_item("herbal_bread",2)
	check(talk(current),"ready goods open actual handoff")
	GameState.remove_item("herbal_bread",1)
	var money_before: int = GameState.money
	drain()
	check(F.step("order_work") == current and GameState.money == money_before and GameState.get_item_count("herbal_bread") == 1,"stock changed during dialogue cannot cause partial consumption or reward")
	GameState.add_item("herbal_bread",1)
	check(talk(current),"handoff retries after stock restored")
	drain()
	var save := GameState.create_save_data().duplicate(true)
	if not GameState.is_save_data_valid(save):
		var no_preservation := save.duplicate(true)
		no_preservation.erase("preservation")
		print("SAVE_DEBUG preservation=",save.get("preservation")," day=",save.get("total_day")," valid_without_preservation=",GameState.is_save_data_valid(no_preservation)," layout=",save.get("store_layout"))
	check(GameState.is_save_data_valid(save) and GameState.apply_save_data(save) and F.done("order_work"),"complete GameState save restores expansion state")
	fixture(F.event("settle_baker"))
	PlayerProgress.story_beat_days[F.key("settle_baker","last_done")] = 1
	PlayerProgress.story_beat_days[F.key("settle_baker","count")] = 1
	VillageSettlement.apply_world(world)
	life.refresh()
	await frames()
	GameState.total_day += 1
	var before := GameState.get_item_count("wheat")
	check(not VillageLifeFlow.greet("baker_neighbor").is_empty() and GameState.get_item_count("wheat") == before + 1,"new neighbor joins existing daily greeting gifts")
	VillageLifeFlow.greet("baker_neighbor")
	check(GameState.get_item_count("wheat") == before + 1,"same-day greeting cannot duplicate gift")
	var removed_site: StaticBody2D = world.get_node("VillageBuildings/VillageGranary")
	VillageSettlement.apply_world(world)
	check(not removed_site.visible and VillageSettlement.find_site(world,"VillageBuildings/VillageGranary") == null,"content respects user's removed granary")
func _ready() -> void: call_deferred("run")
func run() -> void:
	GameState.initialize_new_game()
	world = load("res://scenes/shop/main.tscn").instantiate()
	world.get_node("TutorialDirector").enabled = false
	world.get_node("VillageLifeDirector").crafting_path_enabled = false
	add_child(world)
	await frames()
	life = world.get_node("VillageLifeDirector")
	director = life.get_node("VillageExpansionDirector")
	board = world.get_node("CommunityBoardDirector")
	player = world.get_node("Actors/Player")
	manager = world.get_node("DayManager")
	manager.set_process(false)
	manager.hour_timer.stop()
	manager.customer_spawner.set_process(false)
	life.set_process(false)
	director.set_process(false)
	player.set_physics_process(false)
	for node_name in ["RegularCustomerDirector","ExpeditionContactDirector","WeatherLifeDirector"]: life.get_node(node_name).set_process(false)
	for id in ["magic_oven","drink_machine"]:
		var facility = load("res://scenes/shop/production/production_facility.tscn").instantiate()
		facility.facility_id = id
		facility.set_meta("build_id",id)
		world.get_node("Objects").add_child(facility)
		facilities[id] = facility
	await frames()
	director.refresh()
	var categories: Dictionary = {}
	var sources := Tools.load_sources()
	check(F.SETTINGS.events.size() == 24 and F.SETTINGS.moments.size() == 69,"24 stories and 69 playable stages")
	for entry in F.SETTINGS.events:
		var id := str(entry["id"])
		categories[entry["category"]] = true
		PlayerProgress.reset()
		check(not F.accept(id),"tutorial gate " + id)
		fixture(entry)
		await frames()
		check(F.locked_reason(id).is_empty(),"prerequisites ready " + id + ": " + F.locked_reason(id))
		for stage in entry["steps"]:
			check(sources[Tools.KIND_SERVICE_TEXT].has(stage["id"]) and not RequestTextData.lines("service_text",stage["id"]).is_empty(),"CSV and writer scene registered " + str(stage["id"]))
			for item in CommunityRequestFlow.required_items(stage): check(ItemData.has_item(item) and int(CommunityRequestFlow.required_items(stage)[item]) > 0,"real valid requirement " + item)
			for recipe in stage.get("teach",[]): check(not ProductRecipeData.get_recipe(str(recipe)).is_empty(),"real teach recipe " + str(recipe))
		for path in entry.get("unlocks",[]): check(VillageSettlement.find_site(world,str(path)) != null and not VillageSettlement.find_site(world,str(path)).visible,"existing site stays locked until final " + str(path))
		check(VillageJournalFlow.destination(world,F.JOURNAL_PREFIX + id) == VillageSettlement.find_site(world,CommunityRequestFlow.SETTINGS.board_path),"journal points to board before acceptance")
		if entry["category"] == "settlement":
			var npc = director.visitors.get(str(entry["steps"][0]["resident"]))
			check(is_instance_valid(npc),"returning customer appears as actual settlement visitor")
			if is_instance_valid(npc):
				player.global_position = npc.global_position
				check(world.get_node("WorldInteractions").try_interact() and director.talking and director.action.get("preview",false),"visitor E previews settlement without automatic acceptance")
				drain()
				check(not F.accepted(id),"settlement preview preserves board choice")
		check(board_accept(id) and not F.accept(id),"actual board accepts once " + id)
		saved()
		check(F.accepted(id),"accepted story survives reload " + id)
		await complete_stages(entry)
		check(not F.accept(id),"same cycle cannot repeat " + id)
		if entry.get("repeat","") == "annual":
			GameState.total_day += 112
			mark_neighbors()
			check(F.locked_reason(id).is_empty() and board_accept(id),"annual story returns next year " + id)
			await complete_stages(entry,false)
		if id == "order_trail":
			GameState.total_day += 6
			check(not F.accept(id),"repeat order rests for six days")
			GameState.total_day += 1
			check(board_accept(id),"repeat order returns after seven days")
			await complete_stages(entry,false)
	check(categories.size() == 8,"all eight requested content categories implemented")
	for entry in F.SETTINGS.residents:
		check(CustomerTypeData.has_customer_type(str(entry["type"])) and sources[Tools.KIND_RESIDENT_GREETING].has(entry["id"]),"new resident has existing appearance and registered dialogue")
	await verify_edges()
	fixture(F.event("product_packed_meal"))
	check(F.accept("product_packed_meal") and F.complete(F.step("product_packed_meal"),6),"introduce packed meal recipe")
	PlayerProgress.story_beat_days[F.key("product_berry_bread","last_done")] = 1
	PlayerProgress.learn_recipe("berry_filled_bread")
	await verify_sales()
	var prose := Tools.validate_file(Tools.TEXT_PATH,sources)
	for error in prose["errors"]: print("PROSE ERROR: ",error)
	for warning in prose["warns"]: print("PROSE WARNING: ",warning)
	check(prose["errors"].is_empty() and prose["warns"].is_empty(),"whole dialogue CSV strict validation")
	PlayerProgress.reset()
	check(not F.done("settle_baker") and not F.accepted("order_trail") and not RecipeUnlockData.is_recipe_available("packed_mushroom_meal"),"new game clears story cycles and recipes")
	if is_instance_valid(field_host): field_host.queue_free()
	world.queue_free()
	await frames()
	print("CHECK_VILLAGE_EXPANSION checks=",checks," failures=",failures)
	get_tree().quit(0 if failures == 0 else 1)
