extends Node
const Tools = preload("res://dev/gemini/request_text_tools.gd")
const Writer = preload("res://dev/gemini/request_text_runner.gd")
var checks := 0
var failures := 0
var world
var life: VillageLifeDirector
var player
var facilities: Dictionary = {}

func check(ok: bool, message: String) -> void:
	checks += 1
	if ok: print("PASS: ",message)
	else:
		failures += 1
		push_error(message)

func settle() -> void:
	for i in range(8): await get_tree().process_frame

func drain() -> void:
	for i in range(100):
		if not life.dialogue.open: break
		life.dialogue._advance()
	if life.request_offer.root.visible:
		var action := life.story_action.duplicate(true)
		var before := PlayerProgress.to_save_data().duplicate(true)
		life.request_offer.decline_button.pressed.emit()
		check(PlayerProgress.to_save_data() == before and not life.talking, "declining crafting proposal neither teaches recipes nor writes acceptance")
		check(talk(str(action["resident"])), "crafting proposal can be heard again")
		for i in range(100):
			if not life.dialogue.open: break
			life.dialogue._advance()
		life.request_offer.accept_button.pressed.emit()
	check(not life.dialogue.open,"dialogue terminates")

func talk(giver: String) -> bool:
	life.refresh()
	var npc = life.residents.get(giver)
	if not is_instance_valid(npc): return false
	player.global_position = npc.global_position
	return world.get_node("WorldInteractions").try_interact() and life.talking

func produce(recipe_id: String, count: int) -> void:
	var recipe := ProductRecipeData.get_recipe(recipe_id)
	var facility: ProductionFacility = facilities[str(recipe["facility_id"])]
	for ingredient in recipe["ingredients"]:
		GameState.add_item(str(ingredient["item_id"]),int(ingredient["amount"]) * count)
	check(facility.start_production(recipe_id,count),"actual production begins: " + recipe_id)
	facility._process(facility.remaining_seconds + 1)
	check(facility.production_state == ProductionFacility.ProductionState.READY,"actual processing completes: " + recipe_id)
	check(facility.collect_production(),"actual output collected: " + recipe_id)

func save_reload() -> void:
	var saved := PlayerProgress.to_save_data().duplicate(true)
	PlayerProgress.reset()
	PlayerProgress.load_save_data(saved)

func _ready() -> void:
	CheckoutOptions.force_for_test(true)  # 시험은 스캔 없이 시간 결제(스캔은 check_manual_checkout)
	call_deferred("run")

func run() -> void:
	world = load("res://scenes/shop/main.tscn").instantiate()
	world.get_node("TutorialDirector").enabled = false
	add_child(world)
	await settle()
	life = world.get_node("VillageLifeDirector")
	player = world.get_node("Actors/Player")
	player.set_physics_process(false)
	world.get_node("DayManager").current_hour = 6
	PlayerProgress.reset()
	check(not CraftingPathFlow.accept("craft_trail_food"),"path unavailable before first trades")
	for step in TutorialDirector.SETTINGS.steps:
		if not bool(step.get("optional",false)): PlayerProgress.record_story_beat("tutorial_step:" + str(step["id"]) + ":done",GameState.total_day)
	PlayerProgress.record_story_beat(CraftingPathFlow.NEW_GAME,GameState.total_day)
	check(not CraftingPathFlow.accept("craft_trail_food"),"own settlement required")
	for resident in VillageLifeFlow.SETTINGS.residents:
		var giver := str(resident["id"])
		PlayerProgress.record_story_beat(ResidentRequestFlow.PREFIX + str(resident["request"]) + ":done",GameState.total_day)
		PlayerProgress.story_beat_days[VillageLifeFlow.PREFIX + "friendship:" + giver] = 1
		PlayerProgress.record_story_beat(VillageLifeFlow.PREFIX + "greeted:" + giver,GameState.total_day)
	check(not CraftingPathFlow.accept("craft_trail_food"),"optional local bread tutorial required")
	PlayerProgress.record_story_beat("tutorial_step:production:done",GameState.total_day)
	check(not CraftingPathFlow.accept("craft_trail_food"),"friendship cannot be skipped")
	PlayerProgress.story_beat_days[VillageLifeFlow.PREFIX + "friendship:naru"] = 2
	check(not CraftingPathFlow.accept("unknown") and not CraftingPathFlow.accept("craft_clear_water"),"invalid or future stages rejected")
	VillageSettlement.apply_world(world)
	await settle()
	life.refresh()
	for id in ["magic_oven","drink_machine"]:
		var facility = load("res://scenes/shop/production/production_facility.tscn").instantiate()
		facility.facility_id = id
		facility.set_meta("build_id",id)
		world.get_node("Objects").add_child(facility)
		facilities[id] = facility
	await settle()
	life.refresh()
	check(VillageLifeFlow.SETTINGS.well_item == "raw_water" and VillageLifeFlow.resident("naru")["gift"] == "camp_bread","locals provide native materials and food")
	PlayerProgress.learn_recipe("bake_bread")
	PlayerProgress.learn_recipe("bottled_water")
	GameState.add_item("wheat",10)
	GameState.add_item("raw_water",10)
	check(not RecipeUnlockData.is_recipe_available("bake_bread") and not RecipeUnlockData.is_recipe_available("bottled_water"),"early scroll knowledge cannot bypass modern product progression")
	check(not RecipeUnlockData.is_scroll_worth_dropping("scroll_bake_bread") and not RecipeUnlockData.is_scroll_worth_dropping("scroll_bottled_water"),"modern scrolls do not drop early")
	var wheat_before := GameState.get_item_count("wheat")
	check(not facilities["magic_oven"].start_production("bake_bread") and GameState.get_item_count("wheat") == wheat_before,"direct production API blocks premature modern recipe without consuming ingredients")
	PlayerProgress.story_beat_days.erase(CraftingPathFlow.NEW_GAME)
	check(RecipeUnlockData.is_recipe_available("bake_bread") and facilities["magic_oven"].can_start_production("bake_bread"),"old saves retain learned modern recipes")
	PlayerProgress.record_story_beat(CraftingPathFlow.NEW_GAME,GameState.total_day)
	PlayerProgress.learn_recipe("camp_bread")
	produce("camp_bread",2)
	check(CraftingPathFlow.crafted("craft_trail_food","camp_bread") == 0,"production before invitation cannot fulfill a later sample")
	check(talk("naru") and life.story_action.get("id") == "craft_trail_food_intro","actual resident E offers first product invitation")
	life.dialogue.close()
	check(not CraftingPathFlow.accepted("craft_trail_food") and not RecipeUnlockData.is_recipe_available("dried_fruit"),"interrupted introduction grants no new recipe")
	check(talk("naru"),"introduction can restart")
	drain()
	check(CraftingPathFlow.accepted("craft_trail_food") and RecipeUnlockData.is_recipe_available("berry_juice") and RecipeUnlockData.is_recipe_available("dried_fruit"),"full NPC invitation learns actual recipe bundle")
	check(VillageJournalFlow.destination(world,"crafting:craft_trail_food") == life.residents["naru"],"journal guides to real product partner")
	GameState.add_item("dried_fruit",1)
	check(not CraftingPathFlow.ready("craft_trail_food"),"existing stock and gifts cannot replace actual crafting")
	produce("camp_bread",3)
	check(CraftingPathFlow.crafted("craft_trail_food","camp_bread") == 2,"actual signal records outputs once with a cap")
	save_reload()
	check(CraftingPathFlow.accepted("craft_trail_food") and CraftingPathFlow.crafted("craft_trail_food","camp_bread") == 2,"accepted recipes and real craft progress survive saving")
	produce("dried_fruit",1)
	check(CraftingPathFlow.ready("craft_trail_food"),"both crafted samples and warehouse goods permit delivery")
	var reputation_before := ResidentRequestFlow.reputation()
	var bread_before := GameState.get_item_count("camp_bread")
	check(talk("naru") and life.story_action.get("stage") == "finish","actual NPC completion takes priority")
	life.dialogue.close()
	check(not CraftingPathFlow.done("craft_trail_food") and GameState.get_item_count("camp_bread") == bread_before and ResidentRequestFlow.reputation() == reputation_before,"interrupted sample delivery consumes and rewards nothing")
	check(talk("naru"),"completion can restart")
	var fruit_stock := GameState.get_item_count("dried_fruit")
	GameState.remove_item("dried_fruit",fruit_stock)
	drain()
	check(not CraftingPathFlow.done("craft_trail_food") and GameState.get_item_count("camp_bread") == bread_before,"warehouse recheck prevents partial consumption if sample disappears during dialogue")
	GameState.add_item("dried_fruit",fruit_stock)
	check(talk("naru"),"restored crafted sample permits another completion")
	drain()
	check(CraftingPathFlow.done("craft_trail_food") and GameState.get_item_count("camp_bread") == bread_before - 2 and ResidentRequestFlow.reputation() == reputation_before + 1,"full dialogue consumes exact samples and rewards reputation once")
	PlayerProgress.story_beat_days[VillageLifeFlow.PREFIX + "friendship:doyun"] = 3
	check(CraftingPathFlow.locked_reason(CraftingPathFlow.stage("craft_clear_water")).contains("쉬었다가"),"next-day gate applies even with sufficient friendship")
	check(not CraftingPathFlow.finish("craft_trail_food") and not CraftingPathFlow.accept("craft_clear_water"),"no repeated reward or same-day next stage")
	var money_before: int = GameState.money
	for id in ["craft_clear_water","craft_shared_meal","craft_first_shelf"]:
		GameState.total_day += 1
		var entry := CraftingPathFlow.stage(id)
		var giver := str(entry["giver"])
		PlayerProgress.story_beat_days[VillageLifeFlow.PREFIX + "friendship:" + giver] = int(entry["friendship"])
		PlayerProgress.record_story_beat(VillageLifeFlow.PREFIX + "greeted:" + giver,GameState.total_day)
		check(talk(giver) and life.story_action.get("id") == id + "_intro","ordered real NPC introduction: " + id)
		drain()
		check(CraftingPathFlow.accepted(id),"introduction records acceptance: " + id)
		for recipe_id in entry["recipes"]: check(RecipeUnlockData.is_recipe_available(str(recipe_id)),"new learned recipe is available: " + str(recipe_id))
		if id == "craft_first_shelf":
			GameState.add_item("bread",2)
			GameState.add_item("water",2)
			check(not CraftingPathFlow.ready(id),"leftover starting convenience goods cannot fulfill recreation")
		for requirement in entry["requirements"]:
			var item := str(requirement["item"])
			for recipe_id in entry["recipes"]:
				if ProductRecipeData.get_recipe(str(recipe_id))["result_item_id"] == item: produce(str(recipe_id),int(requirement["amount"]))
		check(CraftingPathFlow.ready(id),"real crafted bundle is ready: " + id)
		check(talk(giver) and life.story_action.get("stage") == "finish","actual NPC sample handoff: " + id)
		drain()
		check(CraftingPathFlow.done(id) and not CraftingPathFlow.finish(id),"sample handoff completes once: " + id)
	check(GameState.money == money_before and ResidentRequestFlow.reputation() == reputation_before + 4,"four stages grant reputation, no fabricated money")
	check(CraftingPathFlow.current().is_empty(),"complete path has no fifth stage")
	check(CraftingPathFlow.information("craft_first_shelf").contains("처음 팔았던"),"journal preserves recreation memory")
	check(ProductRecipeData.get_recipe("bake_bread")["result_item_id"] == "bread" and ProductRecipeData.get_recipe("bottled_water")["result_item_id"] == "water","final products match actual original sale item IDs")
	produce("bake_bread",1)
	produce("bottled_water",1)
	check(CraftingPathFlow.crafted("craft_first_shelf","bread") == 2,"repeat production remains usable without repeating quest rewards")
	save_reload()
	check(CraftingPathFlow.done("craft_first_shelf") and RecipeUnlockData.is_recipe_available("bake_bread"),"completed path and modern crafting persist")
	check(CustomerDemandData._get_candidate_items({"target_type":"category","target_id":"food"}).has("camp_bread"),"native bread participates in ordinary customer food demand")
	# Earlier sample bread has now crossed its daily shelf life. Produce a real
	# new lot for the subsequent sale test instead of relying on expired leftovers.
	produce("camp_bread",1)
	await verify_sales()
	var sources := Tools.load_sources()
	for entry in CraftingPathFlow.SETTINGS.stages:
		for moment in ["intro","preparing","finish"]:
			var id := str(entry["id"]) + "_" + str(moment)
			check(sources[Tools.KIND_SERVICE_TEXT].has(id) and not RequestTextData.lines("service_text",id).is_empty(),"story tool and runtime register scene: " + id)
		check(not sources[Tools.KIND_SERVICE_TEXT].has(entry["id"]),"mechanical stage is not a prose scene")
	check(Writer.build_prompt(Tools.KIND_SERVICE_TEXT,{Tools.KIND_SERVICE_TEXT:{"craft_first_shelf_intro":sources[Tools.KIND_SERVICE_TEXT]["craft_first_shelf_intro"]}},sources).contains("소개 완독 시 실제 제조법 학습"),"writer prompt preserves real unlock and role context")
	PlayerProgress.reset()
	check(not CraftingPathFlow.accepted("craft_trail_food") and CraftingPathFlow.crafted("craft_trail_food","camp_bread") == 0,"new game clears recipes and craft progress")
	print("CHECK_CRAFTING_PATH checks=",checks," failures=",failures)
	get_tree().quit(0 if failures == 0 else 1)

func verify_sales() -> void:
	var build = world.get_node("BuildManager")
	var layout: Array[Dictionary] = [
		{"build_id":"door","anchor":Vector2i(0,4),"rotation_index":3},
		{"build_id":"register","anchor":Vector2i(4,3),"rotation_index":0},
		{"build_id":"shelf_1x1","anchor":Vector2i(2,2),"rotation_index":0}
	]
	build._restore_current_area_layout(layout)
	await settle()
	var register = get_tree().get_nodes_in_group("register")[0]
	var shelf = get_tree().get_nodes_in_group("shelf")[0]
	var cashier = world.get_node("ManualCheckoutController")
	PlayerProgress.record_story_beat(CheckoutTutorial.BEAT_ID,GameState.total_day)
	world.get_node("DayManager").open_shop()
	world.get_node("DayManager").customer_spawner.set_process(false)
	for item in ["camp_bread","bread","water"]:
		check(GameState.remove_item(item,1) == 1,"crafted sale stock comes from actual warehouse: " + item)
		shelf.slots[0]["item_id"] = item
		shelf.slots[0]["stock"] = 1
		var customer = load("res://scenes/shop/actors/customer.tscn").instantiate()
		world.get_node("Actors").add_child(customer)
		customer.set_physics_process(false)
		customer.global_position = build.get_cell_world_position(register.get_checkout_cells()[0])
		check(shelf.take_items_by_id(item,1) == 1,"customer takes crafted shelf goods: " + item)
		customer.carried_item_id = item
		customer.carried_amount = 1
		customer.target_register = register
		register.request_checkout(customer)
		player.global_position = build.get_cell_world_position(register.get_worker_cells()[0])
		var money_before: int = player.money
		var sales_before: int = player.successful_sales
		check(world.get_node("WorldInteractions").try_interact() and cashier.is_busy(),"actual cashier E accepts crafted goods: " + item)
		cashier._process(2.0)
		check(customer.purchase_completed and player.money == money_before + ItemData.get_item_price(item) and player.successful_sales == sales_before + 1,"crafted goods produce real payment and sales record: " + item)
		customer.queue_free()
		await settle()
