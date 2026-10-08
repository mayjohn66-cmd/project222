extends Node
const Tools = preload("res://dev/gemini/request_text_tools.gd")
var checks := 0
var failures := 0
var world: Node
var director: FishingDirector
func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures += 1; push_error(label)
func frames(count: int = 8) -> void:
	for i in range(count): await get_tree().process_frame
func reset(day: int = 1) -> void:
	GameState.initialize_new_game()
	GameState.inventory.clear()
	GameState.total_day = day
	GameState.preservation_state = PreservationService.initial_state(day)
	PlayerProgress.reset()
func core() -> void:
	for step in OpeningJourneyFlow.SETTINGS.steps:
		if not step.get("optional", false): PlayerProgress.record_story_beat("tutorial_step:" + str(step["id"]) + ":done", GameState.total_day)
	PlayerProgress.record_story_beat(OpeningJourneyFlow.RAW_SALE, GameState.total_day)
	PlayerProgress.record_story_beat(OpeningJourneyFlow.TRADE, GameState.total_day)
	for id in ["neighbor_bread", "gatherer_herbs", "child_berries", "healer_moss", "miner_ore"]: PlayerProgress.record_story_beat("resident_request:" + id + ":accepted", GameState.total_day)
	for kind in FishingData.data()["npc_types"].values(): PlayerProgress.record_story_beat("resident_story:met:" + str(kind), GameState.total_day)
func complete(id: String, choices: Dictionary = {}) -> void:
	check(FishingContent.accept(id, 12, "clear"), "introduction " + id)
	check(FishingContent.complete(id, choices), "completion " + id)
func read_dialogue() -> void:
	director.dialogue.line_index = director.dialogue.lines.size()
	director.dialogue.close()
func _ready() -> void: call_deferred("run")
func run() -> void:
	var original := GameState.create_save_data()
	reset()
	check(FishingData.entries("fish").size() == 12 and FishingData.entries("locations").size() == 3, "twelve fish and three fishing locations")
	check(not FishingContent.location_available("fish_bank", 12, "clear"), "core tutorial hides fishing")
	check(not FishingRecords.recipe_available("recipe_fish_grilled__fish_stream_minnow"), "new recipes locked in new and legacy saves")
	check(not FishingService.make_rod("fishing_rod_wood", 12, "clear"), "no rod before introduction")
	core()
	check(FishingContent.location_available("fish_bank", 12, "clear"), "first bank accessible after actual core and known neighbor")
	check(not FishingContent.location_available("fish_reeds", 12, "clear"), "reeds not unlocked early")
	FishingRecords.mark("observed:fish_bank")
	complete("fishing_intro")
	check(FishingContent.accept("fishing_rod", 12, "clear"), "rod introduction")
	GameState.add_item("dry_branch", 2)
	check(not FishingService.make_rod("fishing_rod_wood", 12, "clear") and GameState.get_item_count("dry_branch") == 2, "failed rod does not consume partial materials")
	GameState.add_item("amber_sap", 1)
	check(FishingService.make_rod("fishing_rod_wood", 12, "clear"), "actual rod craft")
	check(GameState.get_item_count("dry_branch") == 0 and GameState.get_item_count("amber_sap") == 0 and FishingService.has_rod(), "rod material consumption")
	check(not FishingService.make_rod("fishing_rod_wood", 12, "clear"), "rod cannot duplicate")
	check(FishingContent.complete("fishing_rod"), "rod step requires actual receipt")
	check(FishingService.pool("fish_bank", "winter", "night", "clear").size() == 3, "first successful cast only basic fish")
	check(FishingService.receive("fish_stream_minnow"), "actual catch")
	complete("fishing_first_catch")
	check(FishingRecords.discovered() == 1, "unique catch discovery")
	GameState.add_item("fish_stone_crucian", 1)
	check(FishingRecords.discovered() == 1, "ownership does not count as actual catch")
	FishingRecords.sold("bread", 1)
	check(not FishingRecords.has("sale"), "nonfish receipt cannot finish fishing sale")
	FishingRecords.sold("fish_stream_minnow", 1)
	complete("fishing_first_sale")
	check(FishingContent.accept("fish_request_neighbor", 12, "clear"), "first neighbor request")
	var before := GameState.get_money()
	check(not FishingContent.complete("fish_request_neighbor", {"fish_any_fresh":"fish_stream_minnow"}), "insufficient delivery blocked")
	check(GameState.get_money() == before, "no reward before actual delivery")
	FishingService.receive("fish_stream_minnow")
	check(FishingContent.complete("fish_request_neighbor", {"fish_any_fresh":"fish_stream_minnow"}), "chosen fresh fish delivery")
	var paid := GameState.get_money()
	check(paid > before and not FishingContent.complete("fish_request_neighbor", {"fish_any_fresh":"fish_stream_minnow"}) and GameState.get_money() == paid, "request pays only once")
	complete("recipe_fish_grilled")
	check(RecipeUnlockData.is_recipe_available("recipe_fish_grilled__fish_stone_crucian"), "learned lesson unlocks explicit fish choices")
	var recipe := ProductRecipeData.get_recipe("recipe_fish_grilled__fish_stone_crucian")
	GameState.add_item("forest_herb", 1)
	check(ProductionRecipeService.consume_ingredients(recipe,1), "actual selected fish and herb consumption")
	check(GameState.get_item_count("fish_stone_crucian") == 0 and GameState.get_item_count("forest_herb") == 0, "selected fish only consumed")
	check(not RecipeUnlockData.is_recipe_available("recipe_fish_soup__fish_stream_minnow"), "unknown lessons stay hidden")
	FishingRecords.collected("fish_grilled", 1)
	GameState.add_item("fish_grilled", 1)
	complete("fish_request_worker")
	complete("recipe_fish_soup")
	check(FishingRecords.recipe_available("recipe_fish_soup__fish_stream_minnow"), "soup lesson reachable before soup delivery")
	FishingService.receive("fish_stone_crucian")
	FishingService.receive("fish_reed_loach")
	check(FishingContent.location_available("fish_reeds", 12, "clear") and FishingContent.location_available("fish_pond",12,"clear"), "nonseasonal catches and request open both walking sites")
	check(FishingContent.accept("fishing_keep",12,"clear"), "preservation introduction")
	PreservationService.install("freezer",true)
	GameState.add_item("fish_frost_smelt", 1)
	check(PreservationService.deposit("freezer","fish_frost_smelt",1) == 1, "fish freezer uses existing actual storage")
	check(FishingContent.complete("fishing_keep"), "storage step requires real deposit after introduction")
	GameState.total_day += 100
	check(PreservationService.withdraw("freezer","fish_frost_smelt",1) == 1 and GameState.get_item_count("fish_frost_smelt") == 1, "frozen winter identity survives season change")
	GameState.total_day += 2
	check(GameState.get_item_count("fish_frost_smelt") == 0, "thawed fish expires without resetting age")
	GameState.add_item("fish_stream_minnow",1)
	GameState.total_day += 1
	check(FoodShelfLife.unit_price("fish_stream_minnow",FoodShelfLife.peek_inventory("fish_stream_minnow",1)[0]) < ItemData.get_item_price("fish_stream_minnow"), "last day fish markdown")
	GameState.total_day += 1
	check(GameState.get_item_count("fish_stream_minnow") == 0, "expired fish removed from usable stock")
	check(not ProductionRecipeService.consume_ingredients(recipe,1), "expired fish cannot become fresh food")
	for day in [1,29,57,85]:
		GameState.total_day = day
		var season := CalendarData.get_season_id(day)
		for place in FishingData.entries("locations"):
			for time in ["morning","day","evening","night"]:
				for weather in ["clear","rain","snow"]:
					var pool := FishingService.pool(str(place["id"]),season,time,weather)
					check(not pool.is_empty(), "basic fish always available")
					for fish in pool:
						check(fish["seasons"].has(season) and fish["locations"].has(place["id"]), "fish environment filters")
	check(FishingService.pool("fish_reeds","summer","day","clear").all(func(f):return f["id"]!="fish_rain_catfish"), "rain catfish absent on clear days")
	check(FishingService.pool("fish_pond","spring","day","clear").all(func(f):return f["id"]!="fish_moon_carp"), "moon carp absent in daytime")
	GameState.total_day = 29
	check(not FishingContent.conditions(FishingData.entry("fish_request_summer_kept"),12,"clear"), "no impossible winter request in first summer")
	PlayerProgress.story_beat_days[FishingRecords.PREFIX+"caught:fish_frost_smelt"] = 10
	check(FishingContent.conditions(FishingData.entry("fish_request_summer_kept"),12,"clear"), "winter history opens later summer request")
	check(FishingContent.accept("fish_request_summer_kept",12,"clear"), "seasonal request introduced")
	GameState.total_day = 57
	GameState.add_item("fish_frost_smelt",1)
	check(FishingContent.complete("fish_request_summer_kept",{"fish_winter_kept":"fish_frost_smelt"}), "accepted requests continue outside season")
	FishingRecords.mark("caught:fish_moon_carp")
	check(FishingContent.accept("fish_event_moon",2,"clear"), "moon memory introduction")
	GameState.add_item("fish_moon_carp",1)
	check(FishingContent.complete("fish_event_moon",{},"release") and GameState.get_item_count("fish_moon_carp") == 0, "release really removes moon fish")
	check(not FishingContent.complete("fish_event_moon",{},"keep"), "memory choice immutable")
	GameState.total_day = 21
	check(StoreEventData.is_event_active("fish_store_spring",21), "spring fish demand active with learned grill")
	check(StoreEventData.discover_event("fish_store_spring",21), "real rumor discovery")
	FishingRecords.sold("bread",1)
	check(not FishingRecords.has("receipt:fish_store_spring:1"), "unrelated sale no event response")
	FishingRecords.sold("fish_grilled",1)
	check(FishingRecords.has("receipt:fish_store_spring:1"), "actual relevant receipt unlocks response")
	check(StoreEventDemandData.get_active_demand_entries("normal",21).any(func(e):return e["target_id"]=="fish_grilled"), "fish event feeds actual customer demand picker")
	check(StoreEventData.can_share_event("fish_store_spring",133), "next year rumor independent")
	# Serialized file uses an explicit test filename; the user's save slots are untouched.
	GameState.total_day = 133
	PreservationService.settle()
	var save := GameState.create_save_data()
	check(GameState.is_save_data_valid(save), "complete fishing state valid for existing saver")
	check(GameState.write_save_file(save,"user://fishing_runtime_check.dat"), "write isolated test file")
	PlayerProgress.reset()
	check(GameState.apply_save_data(GameState.read_save_file("user://fishing_runtime_check.dat")), "load fishing file")
	check(FishingRecords.done("fish_request_summer_kept") and FishingRecords.has("moon:release") and PlayerProgress.is_recipe_learned("recipe_fish_grilled"), "history lessons choices survive disk roundtrip")
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://fishing_runtime_check.dat"))

	# Full content ladder using actual facility start/process/collection.
	reset(); core()
	for id in ["fishing_intro","fishing_rod","fishing_first_catch","fishing_first_sale","fishing_keep","fish_request_neighbor","fish_request_worker"]: FishingRecords.mark(id+":done")
	FishingRecords.mark("catch")
	for id in ["recipe_fish_grilled","recipe_fish_soup"]: PlayerProgress.learn_recipe(id)
	complete("recipe_fish_dried")
	var oven = load("res://scenes/shop/production/production_facility.tscn").instantiate()
	oven.set_meta("build_id","magic_oven")
	add_child(oven)
	await frames()
	GameState.add_item("fish_stream_minnow",2)
	check(oven.start_production("recipe_fish_dried__fish_stream_minnow",2), "real oven accepts selected drying job")
	oven._process(1000)
	var preserved_stock := GameState.inventory.duplicate(true)
	GameState.inventory.clear()
	for i in range(12): GameState.add_item(str(ItemData.items.keys()[i]),999)
	check(not oven.collect_production() and oven.has_collectable_output(), "full inventory leaves completed fish food in facility")
	GameState.inventory = preserved_stock
	check(oven.collect_production() and GameState.get_item_count("fish_dried") == 2 and FishingRecords.has("collected:fish_dried"), "real oven creates and records dried fish")
	check(not oven.collect_production(), "facility output cannot duplicate")
	complete("fish_request_road")
	PlayerProgress.learn_recipe("camp_bread")
	complete("recipe_fish_bread")
	GameState.add_item("fish_grilled",2)
	complete("fish_request_children")
	complete("recipe_fish_lunch")
	check(FishingContent.accept("fish_request_rain",12,"rain"), "weather request introduction")
	GameState.add_item("fish_soup",1)
	check(FishingContent.complete("fish_request_rain"), "rain request delivery continues in clear weather")
	GameState.add_item("fish_blossom_minnow",1); GameState.add_item("forest_herb",1)
	complete("fish_request_spring",{"fish_spring_exclusive":"fish_blossom_minnow"})
	GameState.total_day = 57
	GameState.add_item("fish_lunch",1)
	complete("fish_request_autumn")
	GameState.total_day = 85
	complete("recipe_fish_winter_stew")
	GameState.add_item("fish_winter_stew",1)
	complete("fish_request_winter")
	PlayerProgress.learn_recipe("reed_tea")
	GameState.add_item("fish_dried",1); GameState.add_item("reed_tea",1)
	complete("fish_request_evening")
	for rid in FishingData.data()["recipe_variants"]:
		GameState.inventory.clear()
		var r := ProductRecipeData.get_recipe(str(rid))
		for ingredient in r["ingredients"]: GameState.add_item(str(ingredient["item_id"]),int(ingredient["amount"]))
		check(oven.start_production(str(rid)), "all recipe variants start " + str(rid))
		oven._process(1000)
		check(oven.collect_production(), "all recipe variants collect " + str(rid))
	oven.queue_free()
	for spec in [["fish_event_spring",1,12,"clear"],["fish_event_summer",29,19,"clear"],["fish_event_autumn",57,12,"clear"],["fish_event_winter",85,12,"clear"],["fish_event_rain",85,12,"rain"]]:
		GameState.total_day = int(spec[1])
		check(FishingContent.accept(str(spec[0]),float(spec[2]),str(spec[3])), "seasonal observation intro " + str(spec[0]))
		check(not FishingContent.complete(str(spec[0])), "observation cannot auto complete")
		FishingRecords.mark("observed:"+str(spec[0]))
		check(FishingContent.complete(str(spec[0])), "observed seasonal event completes")
	check(FishingContent.accept("fish_event_table",12,"clear"), "table introduction")
	GameState.add_item("fish_grilled",2)
	check(not FishingContent.complete("fish_event_table") and GameState.get_item_count("fish_grilled") >= 2, "meeting cannot donate before people gather")
	# Physical meeting confirmation is checked by the director at the commit boundary.
	check(FishingContent.complete("fish_event_table",{},"keep",true), "meeting consumes actual donated dishes")
	for id in ["fish_stream_minnow","fish_stone_crucian","fish_reed_loach","fish_frost_smelt","fish_blossom_minnow"]: FishingRecords.caught(id)
	check(FishingContent.accept("fish_event_memory",12,"clear"), "memory reachable without every fish or rare fish")
	FishingRecords.mark("observed:fish_event_memory")
	check(FishingContent.complete("fish_event_memory"), "memory completes after observation")
	for spec in [["fish_store_spring",21],["fish_store_summer",49],["fish_store_autumn",77],["fish_store_winter",105]]:
		check(StoreEventData.is_event_active(str(spec[0]),int(spec[1])), "each annual fish demand active")
	GameState.total_day = 105
	PreservationService.settle()
	GameState.inventory.clear()
	check(GameState.apply_save_data(GameState.create_save_data()), "full ladder reload")
	reset()
	check(not FishingRecords.market_item_available("fish_stream_minnow") and not FishingRecords.market_item_available("fish_grilled"), "new game hides future fish demand")
	for i in range(200):
		var demand := CustomerDemandData.get_random_wanted_request("normal",1)
		check(not str(demand.get("item_id", "")).begins_with("fish_"), "early normal customers never request unknown fishing goods")

	var prose := Tools.validate_file(Tools.TEXT_PATH, Tools.load_sources())
	check(prose["errors"].is_empty() and prose["warns"].is_empty(), "all fishing runtime texts registered and validated")
	print("FISHING_TEXT ",prose)
	# Main world, actual controls and physical fishing banks.
	reset(); core()
	FishingRecords.mark("fishing_intro:done")
	FishingRecords.mark("fishing_rod:done")
	GameState.add_item("fishing_rod_wood",1)
	world = load("res://scenes/shop/main.tscn").instantiate()
	world.get_node("TutorialDirector").enabled = false
	get_tree().root.add_child(world)
	get_tree().current_scene = world
	await frames(12)
	FishingData.data()["settings"]["enabled"] = false
	var disabled := FishingDirector.new()
	world.add_child(disabled)
	check(disabled.interaction_hint().is_empty() and not disabled.try_interact(),"disabled module offers no interaction or null access")
	check(not FishingContent.location_available("fish_bank",12,"clear"),"disabled module hides fishing banks")
	FishingRecords.mark("fishing_first_sale:done")
	PlayerProgress.learn_recipe("recipe_fish_grilled")
	check(not StoreEventData.is_event_active("fish_store_spring",21),"disabled module hides annual fish demand")
	FishingData.data()["settings"]["enabled"] = true
	disabled.queue_free()
	director = world.get_node_or_null("FishingDirector")
	check(director != null and director.spots.points.size() == 3, "main world installs three real fishing spots")
	var player = world.get_node("Actors/Player")
	var manager = world.get_node("DayManager")
	player.global_position = director.spots.position_for("fish_bank")
	check(world.get_node("WorldInteractions").try_interact(), "E interaction opens fishing bank")
	check(director.mode == "menu" and manager.hour_timer.paused and not player.is_physics_processing(), "fishing menu leases clock and movement")
	director.cast()
	check(director.mode == "closed" and not FishingRecords.has("catch"), "preparation cannot produce timefree fish")
	manager.hour_timer.start(999)
	manager.hour_timer.paused = false
	director.location = "fish_bank"
	director.open_menu(); director.cast()
	check(director.mode == "waiting" and not manager.hour_timer.paused, "casting keeps world time running")
	director.close()
	check(not FishingRecords.has("catch") and player.is_physics_processing(), "cancel grants nothing and restores movement")
	director.open_menu(); director.cast(); director.remaining = 0
	director._process(0.01)
	check(director.mode == "bite" and not director.reel_button.disabled, "bite reaches player controlled reel")
	var input := InputEventKey.new()
	input.keycode = KEY_E; input.physical_keycode = KEY_E; input.pressed = true
	director._input(input)
	check(director.mode == "closed" and FishingRecords.discovered() == 1, "actual E reels exactly one fish")
	var caught_count := FishingRecords.discovered()
	director.reel()
	check(FishingRecords.discovered() == caught_count, "repeated reel after closure no additional discovery")
	GameState.inventory.clear()
	for i in range(12): GameState.add_item(str(ItemData.items.keys()[i]),999)
	FishingRecords.mark("fishing_rod:done")
	GameState.inventory["fishing_rod_wood"] = 1
	GameState.inventory.erase(str(ItemData.items.keys()[0]))
	var fish_id := "fish_snow_trout"
	check(not FishingService.capacity(fish_id), "full inventory blocks new fish stack")
	director.mode = "bite"; director._lock(false); director.pending_fish = fish_id
	director.panel.clear("검사"); director.status = director.panel.text("입질")
	director.reel()
	check(director.mode == "full" and GameState.get_item_count(fish_id) == 0 and not FishingRecords.has("caught:"+fish_id), "failed receipt does not discover or grant")
	director.close()
	GameState.inventory.clear(); GameState.add_item("fishing_rod_wood",1)
	director.location = "fish_bank"
	director.open_menu(); director.cast()
	manager.hour_timer.paused = true
	director._process(30)
	check(director.mode == "closed" and director.pending_fish.is_empty() and manager.hour_timer.paused, "clock pause cancels acquisition without undoing another pause")
	manager.hour_timer.paused = false
	director.pending_entry = {"id":"fishing_first_catch","kind":"progression","npc_id":"gatherer_herbs","title":"처음 움직인 찌"}
	director._open_entry()
	director.dialogue.close()
	check(not FishingRecords.accepted("fishing_first_catch"), "closed dialogue is not read introduction")
	director.pending_entry = {"id":"fishing_first_catch","kind":"progression","npc_id":"gatherer_herbs","title":"처음 움직인 찌"}
	director._open_entry(); read_dialogue()
	check(FishingRecords.accepted("fishing_first_catch"), "fully read real dialogue accepts step")
	var npc := director._visitor("naru")
	check(is_instance_valid(npc) and not npc.route.is_empty(), "real NPC walking route to fishing bank")
	if is_instance_valid(npc):
		player.global_position = director.spots.position_for("fish_bank") + Vector2(120,50)
		var old: Vector2 = npc.global_position
		for i in range(30): npc._physics_process(0.1)
		check(npc.global_position.distance_to(old) > 5, "visitor actually walks rather than teleporting conversation")
	# Optional visual evidence in rendered runs.
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--snap="):
			player.global_position = director.spots.position_for("fish_bank")
			director.location = "fish_bank"
			director.open_menu()
			await get_tree().create_timer(1.0).timeout
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(arg.trim_prefix("--snap=")+"-menu.png")
			director.cast()
			await get_tree().create_timer(1.0).timeout
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(arg.trim_prefix("--snap=")+"-cast.png")
			director.close()
	world.queue_free()
	await frames()
	check(not get_tree().paused,"scene cleanup releases fishing pause")
	check(GameState.apply_save_data(original), "restore original in-memory state")
	print("CHECK_FISHING_RUNTIME checks=",checks," failures=",failures)
	get_tree().quit(0 if failures == 0 else 1)
