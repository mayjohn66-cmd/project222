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
var original_weather := ""
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
	check(player.global_position.distance_to(visitor.npc.global_position) >= WeatherLifeFlow.SETTINGS.separation,"visitor away from player")
	player.global_position = visitor.npc.global_position
	var point: Vector2 = visitor.npc.global_position
	visitor.refresh()
	check(visitor.npc.global_position == point,"approaching does not move visitor")
	return world.get_node("WorldInteractions").try_interact() and visitor.open
func stock(item: String, amount: int) -> void:
	for slot in shelf.slots:
		if int(slot["stock"]) > 0: GameState.add_item(str(slot["item_id"]),int(slot["stock"]))
		slot["item_id"] = ""
		slot["stock"] = 0
	if amount > 0:
		GameState.add_item(item,amount)
		check(GameState.remove_item(item,amount) == amount,"owned stock moves to shelf")
		shelf.slots[0]["item_id"] = item
		shelf.slots[0]["stock"] = amount
	shelf.update_visual()
func clear_customers() -> void:
	for actor in get_tree().get_nodes_in_group("customer"): actor.queue_free()
	await frames()
func verify() -> void:
	original_weather = WeatherSystem.debug_kind
	GameState.initialize_new_game()
	world = load("res://scenes/shop/main.tscn").instantiate()
	world.get_node("TutorialDirector").enabled = false
	world.get_node("VillageLifeDirector").crafting_path_enabled = false
	add_child(world)
	await frames()
	visitor = world.get_node("VillageLifeDirector/WeatherLifeDirector")
	for name in ["WeatherLifeDirector","RegularCustomerDirector","ExpeditionContactDirector"]: world.get_node("VillageLifeDirector/"+name).set_process(false)
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
	check(WeatherLifeFlow.SETTINGS.events.size() == 3,"three weather stories")
	check(PersonalRequestFlow.entries().size() == 20 and RegularCustomerFlow.SETTINGS.events.size() == 3 and ExpeditionContactFlow.SETTINGS.events.size() == 3,"prior content retained")
	for entry in WeatherLifeFlow.SETTINGS.events:
		var id := str(entry["id"])
		PlayerProgress.reset()
		var start_day := 35 if entry["season_filter"] == "summer" else 90 if entry["season_filter"] == "winter" else 5
		date(start_day)
		WeatherSystem.debug_kind = str(entry["weather_filter"])
		check(WeatherLifeFlow.phase(id) == "locked" and not talk(id),"core tutorial and settlement required")
		unlock()
		var recipe := str(entry.get("recipe",""))
		if not recipe.is_empty():
			check(WeatherLifeFlow.phase(id) == "recipe_locked","unlearned native bread recipe gate")
			PlayerProgress.learn_recipe(recipe)
		check(WeatherLifeFlow.phase(id) == "intro","matching weather opens introduction")
		WeatherSystem.debug_kind = "rain" if entry["weather_filter"] == "clear" else "clear"
		check(WeatherLifeFlow.phase(id) == "weather_wait","incorrect weather cannot introduce")
		WeatherSystem.debug_kind = str(entry["weather_filter"])
		if entry["season_filter"] != "any":
			date(5)
			check(WeatherLifeFlow.phase(id) == "weather_wait","season gate remains even with F7 weather")
			date(start_day)
		else:
			date(60)
			check(WeatherLifeFlow.phase(id) == "intro","rain story also occurs in autumn")
			date(start_day)
		# Verify the natural schedule and the actual shop clock, not just debug overrides.
		WeatherSystem.debug_kind = ""
		var found := false
		for candidate in range(start_day,start_day+28):
			var plan := WeatherSystem.day_plan(candidate)
			if str(plan["kind"]) != str(entry["weather_filter"]): continue
			date(candidate)
			if entry["season_filter"] != "any" and CalendarData.get_season_id(candidate) != entry["season_filter"]: continue
			manager.current_hour = int((float(plan["start"])+float(plan["end"]))/2.0)
			check(WeatherLifeFlow.phase(id) == "intro","natural day plan agrees with active shop clock")
			if entry["weather_filter"] != "clear":
				manager.current_hour = 0
				check(WeatherLifeFlow.phase(id) == "weather_wait","rain/snow is not whole-day forecast")
			found = true
			break
		check(found,"natural weather candidate exists")
		date(start_day)
		WeatherSystem.debug_kind = str(entry["weather_filter"])
		check(talk(id),"real E opens weather introduction")
		var store = world.get_node("StoreView3D")
		store._sync_actors(0.0)
		store._collect_2d_to_hide()
		check(store._actors.has(visitor.npc.get_instance_id()),"visitor registered as an actual 3D figure")
		check(not visitor.npc.get_node("Visual").visible and visitor.npc.visible,"3D hides only sprite and keeps actor interactive")
		check(world.get_node("WorldInteractions").blocked() and manager.hour_timer.paused,"shared blocked state and clock pause")
		check(VillageJournalFlow.destination(world,WeatherLifeFlow.JOURNAL_PREFIX+id) == visitor.npc,"journal points to actual NPC")
		visitor.dialogue.close()
		check(not WeatherLifeFlow.has(id,"intro") and not manager.hour_timer.paused,"partial introduction unrecorded and clock restored")
		check(talk(id),"introduction retry")
		drain(visitor.dialogue)
		check(WeatherLifeFlow.phase(id) == "visit","complete introduction invites real shopping")
		WeatherSystem.debug_kind = "clear"
		date(120)
		check(WeatherLifeFlow.phase(id) == "visit","accepted shopping survives new season and weather")
		var saved_intro := GameState.create_save_data().duplicate(true)
		check(GameState.is_save_data_valid(saved_intro) and GameState.apply_save_data(saved_intro) and WeatherLifeFlow.has(id,"intro"),"accepted story survives full save/load")
		date(120)
		var item := str(entry["purchase_item"])
		var amount := int(entry["purchase_amount"])
		stock(item,amount-1)
		world.get_node("CustomerSpawner").spawn_customer()
		check(get_tree().get_nodes_in_group("weather_life_customer").is_empty(),"not enough shelf stock cannot fabricate a promised purchase")
		await clear_customers()
		stock(item,amount)
		world.get_node("CustomerSpawner").spawn_customer()
		var buyers := get_tree().get_nodes_in_group("weather_life_customer")
		check(buyers.size() == 1,"native spawner selects weather representative")
		var money_before: int = GameState.money
		if buyers.size() == 1:
			var customer = buyers[0]
			customer.set_physics_process(false)
			customer.global_position = world.get_node("BuildManager").get_cell_world_position(Vector2i(3,4))
			check(customer.choose_wanted_item() == item and customer.wanted_amount == amount and customer.get_customer_type_id() == entry["type"],"actual type commodity and quantity")
			check(not WeatherLifeVisits.prepare(customer,"peddler") and not WeatherLifeVisits.prepare(customer),"first introduction and in-flight visit priority")
			check(not WeatherLifeFlow.record_sale(customer,item,amount),"unpaid cannot advance")
			customer.purchase_completed = true
			check(not WeatherLifeFlow.record_sale(customer,item,amount-1) and not WeatherLifeFlow.record_sale(customer,"stone_shard",amount),"wrong item or quantity cannot advance")
			customer.purchase_completed = false
			visitor.refresh()
			check(not is_instance_valid(visitor.npc) or visitor.current_id != id,"shopping visitor not cloned")
			customer.target_shelf = shelf
			customer.carried_item_id = item
			customer.carried_amount = shelf.take_items_by_id(item,amount)
			customer.checkout_item()
			check(WeatherLifeFlow.has(id,"bought") and GameState.money == money_before + amount*ItemData.get_item_price(item),"real checkout pays normal price and records purchase")
			customer.checkout_item()
			check(not WeatherLifeFlow.record_sale(customer,item,amount) and GameState.money == money_before + amount*ItemData.get_item_price(item),"duplicate checkout rejected")
		await clear_customers()
		check(WeatherLifeFlow.phase(id) == "rest","gratitude waits another day")
		date(121)
		var gift := str(entry["gifts"][0]["item"])
		var gift_before := GameState.get_item_count(gift)
		var paid_money: int = GameState.money
		check(talk(id) and visitor.action_stage == "finish","next-day real E gratitude")
		visitor.dialogue.close()
		check(not WeatherLifeFlow.has(id,"done") and GameState.get_item_count(gift) == gift_before,"partial gratitude cannot grant gift")
		check(talk(id),"gratitude retry")
		drain(visitor.dialogue)
		check(WeatherLifeFlow.has(id,"done") and GameState.get_item_count(gift) == gift_before+int(entry["gifts"][0]["amount"]) and ResidentRequestFlow.reputation() == int(entry["reputation"]),"one-time actual gift and reputation")
		check(not WeatherLifeFlow.complete_action(id,"finish") and GameState.money == paid_money,"no duplicate or cash gift")
		date(122)
		check(talk(id) and visitor.action_stage == "after","next-day memory")
		drain(visitor.dialogue)
		check(WeatherLifeFlow.phase(id) == "complete" and GameState.get_item_count(gift) == gift_before+int(entry["gifts"][0]["amount"]),"afterglow gives no repeated reward")
		check(VillageJournalFlow.information(WeatherLifeFlow.JOURNAL_PREFIX+id).contains(RequestTextData.text("service_text",id+"_after","completion")),"journal keeps memory")
		var saved := GameState.create_save_data().duplicate(true)
		check(GameState.is_save_data_valid(saved) and GameState.apply_save_data(saved) and WeatherLifeFlow.phase(id) == "complete","completion persists after full load")
	var sources := Tools.load_sources()
	for entry in WeatherLifeFlow.SETTINGS.events: check(not sources[Tools.KIND_SERVICE_TEXT].has(str(entry["id"])),"mechanical event excluded from prose source")
	for moment in WeatherLifeFlow.SETTINGS.moments:
		var id := str(moment["id"])
		check(sources[Tools.KIND_SERVICE_TEXT].has(id),"writer knows scene")
		check(Writer.build_prompt(Tools.KIND_SERVICE_TEXT,{Tools.KIND_SERVICE_TEXT:{id:sources[Tools.KIND_SERVICE_TEXT][id]}},sources).contains(str(moment["stage"])),"writer preserves scene constraints")
	var prose := Tools.validate_file(Tools.TEXT_PATH,sources)
	check(prose["errors"].is_empty() and prose["warns"].is_empty(),"full prose validation")
	PlayerProgress.reset()
	for entry in WeatherLifeFlow.SETTINGS.events: check(not WeatherLifeFlow.has(str(entry["id"]),"intro") and not WeatherLifeFlow.has(str(entry["id"]),"done"),"fresh game clears weather memory")
	WeatherSystem.debug_kind = original_weather
	world.queue_free()
	await frames()
	print("WEATHER_TEXT ",prose)
	print("CHECK_WEATHER_LIFE checks=",checks," failures=",failures)
	get_tree().quit(0 if failures == 0 else 1)
