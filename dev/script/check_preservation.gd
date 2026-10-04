extends Node
const Tools = preload("res://dev/gemini/request_text_tools.gd")
var checks := 0
var failures := 0

func check(ok: bool, caption: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(caption)

func frames() -> void:
	for i in range(5): await get_tree().process_frame

func reset(day: int) -> void:
	GameState.initialize_new_game()
	GameState.inventory.clear()
	GameState.store_layout.clear()
	GameState.total_day = day
	GameState.preservation_state = PreservationService.initial_state(day)
	GameState.money = 1000

func _ready() -> void: call_deferred("verify")

func verify() -> void:
	reset(28)
	GameState.add_item("spring_bud", 6)
	GameState.add_item("winter_frost", 3)
	GameState.add_item("rain_pearl", 2)
	GameState.add_item("autumn_nut", 2)
	check(PreservationService.deposit("fridge", "spring_bud", 1) == 0, "no storage before installation")
	var money: int = GameState.money
	check(PreservationService.install("fridge") and GameState.money == money - 120, "install exact fridge cost")
	check(not PreservationService.install("fridge") and GameState.money == money - 120, "duplicate installation never charges")
	GameState.money = 0
	check(not PreservationService.install("freezer"), "insufficient installation funds")
	GameState.money = 1000
	check(PreservationService.install("freezer"), "freezer independent installation")
	check(PreservationService.deposit("fridge", "winter_frost", 1) == 0, "fridge cannot preserve ice")
	check(PreservationService.deposit("fridge", "rain_pearl", 1) == 0, "nonperishable material not cold input")
	check(PreservationService.deposit("fridge", "spring_bud", 4) == 4, "deposit owns actual quantities")
	check(PreservationService.deposit("freezer", "winter_frost", 2) == 2, "ice freezer transfer")
	var shelf = load("res://scenes/shop/objects/shelf.tscn").instantiate()
	add_child(shelf)
	shelf.slots[0]["item_id"] = "spring_bud"
	shelf.slots[0]["stock"] = 2
	var rack = load("res://scenes/shop/warehouse/warehouse_storage.tscn").instantiate()
	add_child(rack)
	GameState.add_item("spring_bud", 2)
	check(rack.deposit_from_inventory("spring_bud", 2) == 2, "ordinary rack transfer")
	GameState.advance_calendar_day()
	check(GameState.total_day == 29 and GameState.get_item_count("spring_bud") == 0 and GameState.get_item_count("wilted_greens") == 2, "spring stock wilts at actual summer boundary")
	check(GameState.get_item_count("winter_frost") == 0 and GameState.get_item_count("raw_water") == 1, "warm ice melts without deleting quantity")
	check(shelf.slots[0]["item_id"] == "wilted_greens" and shelf.slots[0]["stock"] == 2, "sales shelf changes same quantity")
	check(rack.get_item_count("wilted_greens") == 2 and rack.get_item_count("spring_bud") == 0, "ordinary warehouse is warm")
	check(PreservationService.count("fridge") == 4 and PreservationService.count("freezer") == 2, "protected counts not transformed with warm stock")
	check(GameState.get_item_count("rain_pearl") == 2 and GameState.get_item_count("autumn_nut") == 2, "old stable materials unchanged")
	var save := GameState.create_save_data()
	check(GameState.is_save_data_valid(save), "new full save passes native validation")
	check(GameState.write_save_file(save, GameState.SAVE_TEST_PATH), "write protected stock through native save")
	check(GameState.apply_save_data(GameState.read_save_file(GameState.SAVE_TEST_PATH)), "restore protected stock from disk")
	check(PreservationService.count("freezer") == 2 and PreservationService.count("fridge") == 4, "protected stock ownership restored")
	var corrupt := save.duplicate(true)
	corrupt["preservation"]["freezer"]["winter_frost"] = 99
	check(not GameState.is_save_data_valid(corrupt), "reject capacity-overflow save")
	corrupt = save.duplicate(true)
	corrupt["preservation"]["fridge"]["winter_frost"] = 1
	check(not GameState.is_save_data_valid(corrupt), "reject ice hidden in fridge save")
	corrupt = save.duplicate(true)
	corrupt["preservation"]["installed"].append("fridge")
	check(not GameState.is_save_data_valid(corrupt), "reject duplicate installed units")
	shelf.queue_free()
	rack.queue_free()
	await frames()
	for i in range(224): GameState.advance_calendar_day()
	check(PreservationService.count("freezer") == 2 and PreservationService.count("fridge") == 4, "two years in installed storage")
	check(PreservationService.withdraw("freezer", "winter_frost", 1) == 1, "withdraw exact ice count")
	check(GameState.get_item_count("winter_frost") == 1, "same-day ice usable for delivery")
	var water: int = GameState.get_item_count("raw_water")
	GameState.advance_calendar_day()
	check(GameState.get_item_count("winter_frost") == 0 and GameState.get_item_count("raw_water") == water + 1, "withdrawn ice melts following dawn")
	check(PreservationService.count("freezer") == 1, "remaining frozen ice unaffected")
	check(PreservationService.withdraw("fridge", "spring_bud", 2) == 2, "withdraw protected plant")
	var wilted: int = GameState.get_item_count("wilted_greens")
	GameState.advance_calendar_day()
	check(GameState.get_item_count("spring_bud") == 0 and GameState.get_item_count("wilted_greens") == wilted + 2, "withdrawn off-season plant wilts next dawn")
	check(PreservationService.withdraw("fridge", "spring_bud", -1) == 0 and PreservationService.deposit("fridge", "spring_bud", -1) == 0, "negative transfer blocked")
	GameState.add_item("summer_mint", 20)
	check(PreservationService.deposit("fridge", "summer_mint", 50) == 10 and PreservationService.count("fridge") == 12, "capacity counts units across item types")
	check(PreservationService.deposit("fridge", "summer_mint", 1) == 0, "full unit rejects without consuming")
	var old := GameState.create_save_data()
	old.erase("preservation")
	check(GameState.apply_save_data(old) and not PreservationService.installed("fridge"), "legacy save initializes new facilities empty")
	check(GameState.preservation_state["last_day"] == GameState.total_day, "legacy stock starts on load day without retroactive loss")
	reset(55)
	GameState.add_item("summer_mint", 2)
	GameState.advance_calendar_day()
	check(GameState.get_item_count("summer_mint") == 2, "summer plant keeps through its harvest season")
	GameState.advance_calendar_day()
	check(GameState.get_item_count("summer_mint") == 0 and GameState.get_item_count("wilted_greens") == 2, "summer plant wilts on autumn dawn")
	# Store absent during expedition: both versions of warehouse serialization transform.
	GameState.store_layout = [{"shelf_slots":[{"item_id":"winter_frost","stock":2,"capacity":5}]}, {"storage_slots":[{"item_id":"spring_bud","amount":3}],"warehouse_slots":[{"item_id":"spring_bud","amount":3}]}]
	GameState.advance_calendar_day()
	check(GameState.store_layout[0]["shelf_slots"][0]["item_id"] == "raw_water", "unloaded shelf melts during calendar catchup")
	check(GameState.store_layout[1]["storage_slots"][0]["item_id"] == "wilted_greens" and GameState.store_layout[1]["warehouse_slots"][0]["amount"] == 3, "unloaded warehouse fields both updated")
	await verify_processing()
	await verify_ui()
	var validation := Tools.validate_file(Tools.TEXT_PATH, Tools.load_sources())
	check(validation["errors"].is_empty() and validation["warns"].is_empty(), "all native prose still validates: " + str(validation))
	print("CHECK_PRESERVATION checks=", checks, " failures=", failures, " text=", validation)
	get_tree().quit(0 if failures == 0 else 1)

func verify_processing() -> void:
	reset(28)
	var oven: ProductionFacility = load("res://scenes/shop/production/production_facility.tscn").instantiate()
	oven.facility_id = "magic_oven"
	oven.set_meta("build_id", "magic_oven")
	add_child(oven)
	await frames()
	for pair in [["spring_bud","dry_spring_bud","dried_spring_bud"], ["summer_mint","dry_summer_mint","dried_summer_mint"]]:
		GameState.add_item(pair[0], 2)
		check(RecipeUnlockData.is_recipe_available(pair[1]), "basic preservation recipe accessible")
		check(oven.start_production(pair[1], 2), "native production consumes fresh input")
		check(GameState.get_item_count(pair[0]) == 0, "exact input consumption")
		var saved := oven.get_production_save_data()
		check(oven.apply_production_save_data(saved), "processing survives native facility restore")
		oven._process(oven.remaining_seconds + 1)
		check(oven.collect_production() and GameState.get_item_count(pair[2]) == 2, "collect actual processed item")
		check(not oven.collect_production(), "no repeated processed output")
	for i in range(224): GameState.advance_calendar_day()
	check(GameState.get_item_count("dried_spring_bud") == 2 and GameState.get_item_count("dried_summer_mint") == 2, "properly dried materials stable for two years")
	GameState.add_item("wilted_greens", 5)
	check(not oven.start_production("dry_spring_bud"), "wilted stock cannot replace fresh production input")
	check(PersonalRequestFlow.request("sora_autumn_buds")["requirements"][0]["item"] == "dried_spring_bud", "autumn premium request requires real preserved output")
	check(PersonalRequestFlow.request("doyun_winter_mint")["requirements"][0]["item"] == "dried_summer_mint", "winter premium request requires real preserved output")
	oven.queue_free()
	await frames()

func verify_ui() -> void:
	reset(85)
	GameState.add_item("winter_frost", 3)
	GameState.add_item("spring_bud", 3)
	var menu: ManagementMenu = load("res://scenes/shared/ui/management/management_menu.tscn").instantiate()
	add_child(menu)
	await frames()
	menu.open_menu()
	var view = menu.management_inventory
	var button: Button = view.get_node("MainVBox/CategoryTabs/PreservationButton")
	button.pressed.emit()
	await frames()
	var panel: PreservationPanel
	for child in view.get_children():
		if child is PreservationPanel: panel = child
	check(panel != null and panel.visible, "real inventory button opens cold-storage panel while menu paused")
	var install_button: Button = panel.rows.get_child(2)
	install_button.pressed.emit()
	check(PreservationService.installed("fridge"), "real installation button")
	var row := panel.rows.get_child(2)
	row.get_child(1).pressed.emit()
	check(PreservationService.count("fridge") == 1 and GameState.get_item_count("spring_bud") == 2, "real deposit button")
	panel.rows.get_child(2).get_child(2).pressed.emit()
	check(PreservationService.count("fridge") == 0 and GameState.get_item_count("spring_bud") == 3, "real withdraw button")
	for resolution in [Vector2i(1152,648), Vector2i(768,432)]:
		get_tree().root.size = resolution
		panel.hide()
		panel.open()
		await frames()
		var viewport_rect: Rect2 = view.get_viewport_rect()
		var dialog_rect := Rect2(Vector2(panel.position), Vector2(panel.size))
		print("PRESERVATION_LAYOUT screen=", resolution, " viewport=", viewport_rect, " dialog=", dialog_rect, " return=", panel.get_ok_button().get_global_rect())
		check(viewport_rect.encloses(dialog_rect) and Rect2(Vector2.ZERO,Vector2(panel.size)).encloses(panel.get_ok_button().get_global_rect()), "dialog and return button fit logical viewport " + str(resolution))
		if not OS.get_cmdline_user_args().is_empty():
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(OS.get_cmdline_user_args()[0] + "-" + str(resolution.x) + ".png")
	panel.hide()
	menu.close_menu()
	check(not get_tree().paused, "exit returns menu clock pause ownership")
	menu.queue_free()
	await frames()
	var expedition = load("res://scenes/expedition/expedition.tscn").instantiate()
	add_child(expedition)
	await frames()
	check(not expedition.get_node("UI/ManagementMenu").management_inventory.has_node("MainVBox/CategoryTabs/PreservationButton"), "fixed store storage cannot be used remotely during expedition")
	expedition.queue_free()
	await frames()
