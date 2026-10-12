extends "res://tools/code/check_expedition_run.gd"
const Tools = preload("res://dev/gemini/request_text_tools.gd")
const Writer = preload("res://dev/gemini/request_text_runner.gd")
var checks := 0
var failures := 0
const DAYS := {"spring":1,"summer":29,"autumn":57,"winter":85}
func check(ok: bool, caption: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(caption)
func settle() -> void:
	for i in range(5): await get_tree().process_frame
func _ready() -> void: call_deferred("preview" if not OS.get_cmdline_user_args().is_empty() else "verify")

func preview() -> void:
	var prefix := OS.get_cmdline_user_args()[0]
	GameState.set_meta("shop_expedition_prep", true)
	for day in range(85,113):
		var plan := WorldWeatherData.day_plan(day)
		if plan["kind"] != "snow": continue
		GameState.total_day = day
		GameState.set_meta("shop_return_context", {"hour":(plan["start"] + plan["end"]) / 2.0})
		break
	var inst = load("res://scenes/expedition/expedition.tscn").instantiate()
	add_child(inst)
	await settle()
	inst.prep_panel.show_departure_choice()
	inst.prep_panel.show()
	inst.prep_panel.map_content._select_region("river_valley")
	for resolution in [Vector2i(1152,648), Vector2i(768,432)]:
		get_tree().root.size = resolution
		await settle()
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(prefix + "-prep-" + str(resolution.x) + ".png")
	inst.start_expedition_run()
	await settle()
	var candidates := ExpeditionEventData.get_events_by_node_type("river_valley", "gather", 1, inst.expedition_map.environment)
	for event in candidates:
		if event["event_id"] == "river_valley_snowling_gather": inst.expedition_room_controller.enter(event, "gather")
	for resolution in [Vector2i(1152,648), Vector2i(768,432)]:
		get_tree().root.size = resolution
		await settle()
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(prefix + "-room-" + str(resolution.x) + ".png")
	get_tree().quit()

func verify() -> void:
	seed(87032)
	for day in range(1,225):
		var plan := WorldWeatherData.day_plan(day)
		check(plan == WorldWeatherData.day_plan(day), "weather stable after reload: " + str(day))
		check(plan["kind"] != "snow" or CalendarData.get_season_id(day) == "winter", "snow only in winter")
		check(WorldWeatherData.forecast(day, 1)["kind"] == "clear", "outside weather window is clear")
		if plan["kind"] != "clear":
			check(WorldWeatherData.forecast(day, (plan["start"] + plan["end"]) / 2)["kind"] == plan["kind"], "weather active at actual interval")
	ExpeditionEventData.ensure_loaded()
	for season in DAYS:
		for weather in ["clear", "rain", "snow"]:
			var state := {"season":season,"weather":weather}
			for region in ExpeditionMapData.get_region_ids():
				for kind in ExpeditionMapData.get_required_event_node_types(region):
					var candidates := ExpeditionEventData.get_events_by_node_type(region, kind, 1, state)
					check(not candidates.is_empty(), "every environment leaves base path usable")
					for event in candidates:
						check(str(event.get("season_filter", "")).is_empty() or event["season_filter"] == season, "off-season enemy/resource absent")
						check(str(event.get("weather_filter", "")).is_empty() or event["weather_filter"] == weather, "off-weather enemy/resource absent")
						if event["result_type"] in ["battle", "loot"]:
							var table: String = EnemyData.get_loot_table(event["target_id"]) if event["result_type"] == "battle" else event["target_id"]
							for level in [1,4]: check(not ExpeditionEventData.get_random_loot(table, 1.0, level, state).is_empty(), "matching room rewards available every difficulty")
					for event in ExpeditionEventData.events:
						if event["region_id"] != region or event["node_type"] != kind or str(event.get("season_filter", "")).is_empty() and str(event.get("weather_filter", "")).is_empty(): continue
						var expected: bool = (event["season_filter"] == "" or event["season_filter"] == season) and (event["weather_filter"] == "" or event["weather_filter"] == weather)
						check(candidates.any(func(e: Dictionary) -> bool: return e["event_id"] == event["event_id"]) == expected, "specific climate content availability")
	for item in ["spring_bud","summer_mint","autumn_nut","winter_frost","rain_pearl","snow_bloom"]:
		check(ItemData.can_store_in_expedition_bag(item) and ItemData.is_sellable(item), "seasonal item fits native storage and sales")
		check(CustomerDemandData._get_candidate_items({"target_type":"category","target_id":"material"}).has(item), "ordinary material demand can buy seasonal stock")
	await verify_rooms()
	await verify_stockpile()
	# Four seasons, five ordinary regions and map-gated ruins: real movement/basic attacks/E.
	for season in DAYS:
		GameState.total_day = DAYS[season]
		GameState.set_meta("shop_return_context", {"hour":12, "minute":0, "expedition_seconds":0.0})
		for region in ExpeditionMapData.get_region_ids(): await _run_once(region, 1)
	check(report["runs"] == 24 and report["clears"] == 24 and report["stuck"] == 0, "all seasons and regions reach result")
	check(report["boss_had_starter"] == 24 and report["starter_before_boss"] == 0, "starter only at boss preserved")
	print("CHECK_SEASONAL_EXPEDITION checks=", checks, " failures=", failures, " report=", report)
	get_tree().quit(0 if failures == 0 else 1)

func verify_rooms() -> void:
	PlayerProgress.reset()
	GameState.total_day = 90
	GameState.set_meta("shop_return_context", {"hour":12, "minute":30})
	var inst = load("res://scenes/expedition/expedition.tscn").instantiate()
	add_child(inst)
	await settle()
	inst.prep_panel.show_departure_choice()
	inst.prep_panel.show()
	inst.prep_panel.map_content._select_region("river_valley")
	await settle()
	check(inst.prep_panel.region_description_label.text.contains("겨울") and inst.prep_panel.region_description_label.text.contains("서리"), "real departure card hints at winter materials")
	for resolution in [Vector2i(768,432),Vector2i(1152,648)]:
		get_tree().root.size = resolution
		await settle()
		var prep = inst.prep_panel
		print("CLIMATE_LAYOUT viewport=", prep.get_viewport_rect(), " card=", prep.region_info_card.get_global_rect(), " difficulty=", prep.difficulty_next_button.get_global_rect())
		check(prep.get_viewport_rect().encloses(prep.region_info_card.get_global_rect()) and prep.region_info_card.get_global_rect().encloses(prep.difficulty_next_button.get_global_rect()), "long climate description leaves difficulty button inside screen/card")
	get_tree().root.size = Vector2i(1152,648)
	inst.start_expedition_run()
	await settle()
	var original: Dictionary = inst.expedition_map.environment.duplicate(true)
	check(original["season"] == "winter" and original["hour"] == 12.5, "departure captures actual date and minute")
	var checkpoint: Dictionary = inst.expedition_checkpoint_controller.create_data()
	GameState.set_expedition_checkpoint(checkpoint)
	GameState.total_day = 130
	check(inst.expedition_checkpoint_controller.restore() and inst.expedition_map.environment == original, "checkpoint keeps winter in next year spring")
	var legacy := checkpoint.duplicate(true)
	legacy.erase("environment")
	GameState.set_expedition_checkpoint(legacy)
	check(inst.expedition_checkpoint_controller.restore() and inst.expedition_map.environment["season"] == "spring", "old checkpoint receives current environment safely")
	# Actually drive every new gather and enemy room and verify real pending loot.
	for event in ExpeditionEventData.events:
		if not event["event_id"].ends_with("_gather") and not event["event_id"].ends_with("_battle"): continue
		if event.get("season_filter", "").is_empty() and event.get("weather_filter", "").is_empty(): continue
		inst.current_region_id = event["region_id"]
		inst.expedition_map.environment = {"season":event["season_filter"] if not event["season_filter"].is_empty() else "summer", "weather":event["weather_filter"] if not event["weather_filter"].is_empty() else "clear"}
		inst.expedition_room_controller.enter(event, event["node_type"])
		check(inst.expedition_room_controller.view.title_label.text.contains(ExpeditionEnvironment.label(inst.expedition_map.environment)), "room displays correct saved environment")
		check(await ExpeditionRoomTestDriver.play(inst.expedition_room_controller), "actual movement/attack/E clears climate room: " + event["event_id"])
		check(not inst.temporary_loot.is_empty() and str(inst.temporary_loot[0]["item_id"]) in ["spring_bud","summer_mint","autumn_nut","winter_frost","rain_pearl","snow_bloom"], "native rewards from climate room")
		inst.expedition_bag_controller.finish_loot_organization()
	inst.queue_free()
	GameState.clear_expedition_checkpoint()
	await settle()

func verify_stockpile() -> void:
	PlayerProgress.reset()
	GameState.remove_meta("shop_return_context")
	GameState.total_day = 85
	GameState.preservation_state = PreservationService.initial_state(85)
	var world = load("res://scenes/shop/main.tscn").instantiate()
	world.get_node("TutorialDirector").enabled = false
	world.get_node("VillageLifeDirector").crafting_path_enabled = false
	add_child(world)
	await settle()
	world.get_node("DayManager").set_process(false)
	world.get_node("DayManager").hour_timer.stop()
	world.get_node("DayManager").current_hour = 6
	world.get_node("CustomerSpawner").set_process(false)
	for step in TutorialDirector.SETTINGS.steps: PlayerProgress.record_story_beat("tutorial_step:" + str(step["id"]) + ":done", 1)
	PlayerProgress.record_story_beat(CheckoutTutorial.BEAT_ID, 1)
	for resident in VillageLifeFlow.SETTINGS.residents:
		PlayerProgress.record_story_beat(ResidentRequestFlow.PREFIX + str(resident["request"]) + ":done", 1)
		PlayerProgress.story_beat_days[VillageLifeFlow.PREFIX + "friendship:" + str(resident["id"])] = 3
	world.get_node("TutorialDirector").refresh()
	VillageSettlement.apply_world(world)
	var board = world.get_node("CommunityBoardDirector")
	var life = world.get_node("VillageLifeDirector")
	var player = world.get_node("Actors/Player")
	player.set_physics_process(false)
	var sources: Dictionary = Tools.load_sources()
	var text_rows: Array = []
	for entry in SeasonStockpileFlow.SETTINGS.requests:
		var id := str(entry["id"])
		var item := str(entry["requirements"][0]["item"])
		GameState.remove_item(item, GameState.get_item_count(item))
		GameState.total_day = {"winter_frost":85,"dried_spring_bud":1,"dried_summer_mint":29}[item]
		GameState.preservation_state = PreservationService.initial_state(GameState.total_day)
		GameState.add_item(item, 3)
		if item == "winter_frost":
			GameState.money += int(PreservationService.unit("freezer")["cost"])
			check(PreservationService.install("freezer") and PreservationService.deposit("freezer", item, 3) == 3, "winter stock actually frozen")
		var saved := GameState.create_save_data().duplicate(true)
		GameState.remove_item(item, 3)
		check(GameState.apply_save_data(saved) and (PreservationService.count("freezer") == 3 if item == "winter_frost" else GameState.get_item_count(item) == 3), "protected/processed material survives actual full save")
		GameState.total_day = DAYS[entry["stockpile_season"]] + 112
		PreservationService.settle()
		check((PreservationService.count("freezer") == 3 if item == "winter_frost" else GameState.get_item_count(item) == 3), "preserved warehouse remains after seasons and year pass")
		GameState.total_day += 28
		check(not PersonalRequestFlow.accept(id), "request only offered in its demand season")
		GameState.total_day -= 28
		life.refresh()
		player.global_position = life.residents[entry["resident"]].global_position
		check(life.try_interact() and life.dialogue.lines.has(RequestTextData.lines("personal_request", id)[0]), "NPC gives natural seasonal stockpile hint")
		life.dialogue.close()
		player.global_position = VillageSettlement.find_site(world, CommunityRequestFlow.SETTINGS.board_path).global_position
		check(board.try_interact(), "actual E opens delivery board")
		board.panel.refresh()
		board.panel.cards["personal:" + id]["action"].pressed.emit()
		check(PersonalRequestFlow.accepted(id), "real board accepts seasonal request")
		GameState.total_day += 28
		check(PersonalRequestFlow.locked_reason(PersonalRequestFlow.request(id)).is_empty(), "accepted promise survives season change")
		if item == "winter_frost": check(PreservationService.withdraw("freezer", item, 3) == 3, "withdraw ice on actual delivery day")
		check(PersonalRequestFlow.can_deliver(id), "preserved output ready for accepted promise")
		GameState.remove_item(item, 2)
		var money: int = GameState.money
		var rep := ResidentRequestFlow.reputation()
		check(PersonalRequestFlow.deliver(id).is_empty() and GameState.money == money and GameState.get_item_count(item) == 1, "insufficient stock consumes nothing")
		GameState.add_item(item, 2)
		board.panel.refresh()
		board.panel.cards["personal:" + id]["action"].pressed.emit()
		check(PersonalRequestFlow.done(id) and GameState.get_item_count(item) == 1, "native board consumes only requested stored amount")
		check(GameState.money == money + int(entry["money"]) and ResidentRequestFlow.reputation() == rep + 2, "better seasonal payment and exact reputation")
		check(int(entry["money"]) > ItemData.get_item_price(item) * 2 and PersonalRequestFlow.deliver(id).is_empty(), "payment above normal sale only once")
		var completed := GameState.create_save_data().duplicate(true)
		check(GameState.apply_save_data(completed) and PersonalRequestFlow.done(id) and PersonalRequestFlow.deliver(id).is_empty(), "reward cannot repeat after full reload")
		check(VillageJournalFlow.information("personal:" + id).contains(entry["completion"]), "journal remembers stored material value")
		board.panel.close()
		check(sources["personal_request"].has(id), "Gemini knows native request kind")
		text_rows.append(Tools.row_from_source("personal_request", sources["personal_request"][id]))
		check(Writer.build_prompt("personal_request", {"personal_request":{id:sources["personal_request"][id]}}).contains("냉동함"), "writer receives actual preservation context")
	check(Tools.validate_rows(Tools.COLUMNS, text_rows, sources)["errors"].is_empty(), "rough request prose valid for writer")
	world.queue_free()
	await settle()
