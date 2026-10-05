extends Node
const Tools = preload("res://dev/gemini/request_text_tools.gd")
var checks := 0
var failures := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("FAIL: " + message)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("run")

func frames() -> void:
	for i in range(4): await get_tree().process_frame

func reset(day: int = 1) -> void:
	GameState.initialize_new_game()
	GameState.inventory.clear()
	GameState.store_layout.clear()
	GameState.total_day = day
	GameState.preservation_state = PreservationService.initial_state(day)
	GameState.money = 1000
	PlayerProgress.reset()

func step_day(days: int) -> void:
	GameState.total_day += days
	PreservationService.settle()

func run() -> void:
	reset()
	check(FoodShelfLife.rules().size() == 10, "ten selected foods; stable water/materials stay unchanged")
	for item in FoodShelfLife.rules():
		check(ItemData.has_item(item) and ItemData.is_shelf_allowed(item), "all food rules use existing sellable products " + item)
		check(int(FoodShelfLife.rules()[item]["days"]) > 0, "positive daily duration " + item)
	check(not FoodShelfLife.tracked("water") and not FoodShelfLife.tracked("winter_frost"), "packaged water and seasonal transformation independent")
	GameState.add_item("camp_bread", 2)
	step_day(1)
	GameState.add_item("camp_bread", 3)
	var shelf = load("res://scenes/shop/objects/shelf.tscn").instantiate()
	add_child(shelf)
	shelf.slots = [{"item_id":"camp_bread", "stock":0, "capacity":5}, {"item_id":"camp_bread", "stock":0, "capacity":5}]
	check(FoodShelfLife.restock_slot(shelf, 1, 2) == 2, "older lot moved to later slot")
	check(FoodShelfLife.restock_slot(shelf, 0, 3) == 3 and GameState.get_item_count("camp_bread") == 0, "new lot moves to first slot without duplication")
	step_day(1)
	check(shelf.take_items_by_id("camp_bread", 3) == 3, "FIFO spans slots")
	var receipt: Array = shelf.get_meta("food_receipt")
	check(receipt.size() == 2 and receipt[0]["age"] == 4 and receipt[0]["amount"] == 2 and receipt[1]["age"] == 2, "oldest lot first; partial new lot preserves age")
	check(FoodShelfLife.receipt_total("camp_bread", receipt) == 240, "mixed invoice: two discounted 70G plus fresh 100G")
	check(shelf.return_items_by_id("camp_bread", 3, receipt) == 3, "unpaid lots return with dates")
	check(shelf.get_item_stock("camp_bread") == 5, "return restores quantity once")
	FoodShelfLife.state()["markdown"] = false
	check(FoodShelfLife.receipt_total("camp_bread", receipt) == 300, "player can disable markdown")
	FoodShelfLife.state()["markdown"] = true
	step_day(1)
	check(shelf.get_item_stock("camp_bread") == 3 and FoodShelfLife.state()["waste"]["camp_bread"] == 2, "expired older lot separated while fresher lot stays")
	check(shelf.take_items_by_id("camp_bread", 10) == 3, "only saleable stock available")
	shelf.free()
	check(FoodShelfLife.discard("camp_bread", 2, true) == 2 and GameState.get_item_count("food_compost") == 1, "designated two-to-one compost recycling")
	check(FoodShelfLife.discard("camp_bread", 2, true) == 0 and GameState.get_item_count("food_compost") == 1, "recycling cannot duplicate rewards")
	reset()
	GameState.add_item("bread", 4)
	GameState.add_item("berry_juice", 1)
	check(PreservationService.install("fridge") and PreservationService.install("freezer"), "existing cold units installed")
	check(PreservationService.deposit("fridge", "bread", 1) == 1 and PreservationService.deposit("freezer", "bread", 2) == 2, "physical food transfers into cold stores")
	check(PreservationService.deposit("freezer", "berry_juice", 1) == 0, "unsupported food cannot enter freezer")
	check(PreservationService.deposit("fridge", "berry_juice", 1) == 1, "juice can enter fridge")
	step_day(4)
	check(FoodShelfLife.state()["inventory"]["bread"][0]["age"] == 8, "ambient ages by days")
	check(FoodShelfLife.state()["fridge"]["bread"][0]["age"] == 4, "fridge halves aging")
	check(FoodShelfLife.state()["freezer"]["bread"][0]["age"] == 0, "freezer pauses food aging")
	check(PreservationService.withdraw("fridge", "bread", 1) == 1, "withdraw actual cold food")
	check(FoodShelfLife.peek_inventory("bread", 2)[1]["age"] == 4, "withdraw retains accumulated age")
	check(PreservationService.deposit("fridge", "bread", 1) == 1, "refrigerate oldest ambient lot")
	step_day(1)
	check(FoodShelfLife.state()["fridge"]["bread"][0]["age"] == 9, "moving does not refresh expiry")
	check(PreservationService.withdraw("freezer", "bread", 1) == 1, "frozen lot returns to normal inventory")
	step_day(1)
	check(FoodShelfLife.peek_inventory("bread", 10)[-1]["age"] == 2, "thawed food resumes ambient aging")
	step_day(30)
	check(int(GameState.preservation_state["freezer"]["bread"]) == 1, "frozen food survives long absence")
	check(not GameState.preservation_state["fridge"].has("bread") and not GameState.preservation_state["fridge"].has("berry_juice"), "refrigeration slows but does not grant permanent freshness")
	check(FoodShelfLife.state()["waste"]["bread"] == 3 and FoodShelfLife.state()["waste"]["berry_juice"] == 1, "expired cold and ambient lots accounted once")
	var summary := FoodShelfLife.claim_morning_notice()
	check(not summary.is_empty() and FoodShelfLife.claim_morning_notice().is_empty(), "one consolidated morning notice per day")
	check(FoodShelfLife.discard("berry_juice", 1, true) == 0, "recycling cannot spend an incomplete pair")
	check(FoodShelfLife.discard("berry_juice", 1) == 1, "single expired product may be discarded")
	reset()
	GameState.add_item("camp_bread", 4)
	step_day(1)
	var rack = load("res://scenes/shop/warehouse/warehouse_storage.tscn").instantiate()
	add_child(rack)
	check(rack.deposit_from_inventory_to_slot(0, "camp_bread", 2) == 2, "warehouse transfer")
	GameState.add_item("camp_bread", 2)
	check(rack.deposit_from_inventory_to_slot(1, "camp_bread", 4) == 4, "mixed warehouse lot")
	check(rack.move_item_between_slots(1, 0, 1) == 1, "partial merge preserves oldest lot")
	var slots: Array = rack.get_stored_slots()
	check(FoodShelfLife.quantity(slots[0]["food_batches"]) == 3 and slots[0]["food_batches"][0]["age"] == 2, "warehouse ages persist in merged slots")
	check(rack.apply_stored_slots(slots) and rack.get_stored_slots() == slots, "warehouse restore retains batch metadata")
	check(rack.withdraw_slot_to_inventory(0, 2) == 2 and FoodShelfLife.peek_inventory("camp_bread", 2)[0]["age"] == 2, "warehouse withdrawal retains age")
	GameState.add_item("raw_water", 1)
	check(rack.deposit_from_inventory_to_slot(2, "raw_water", 1) == 1, "non-food rack path retained")
	check(rack.move_item_between_slots(1, 2, 1) == 3, "whole different-item slot swap")
	check(rack.storage_slots[2]["food_batches"].size() == 2, "swapped food retains separate lots")
	GameState.store_layout = [{"build_id":"warehouse_storage", "anchor":Vector2i(0,0), "room_id":"warehouse", "storage_slots":rack.get_stored_slots(), "warehouse_slots":rack.get_stored_slots()}]
	rack.free()
	step_day(2)
	check(GameState.store_layout[0]["storage_slots"][2]["amount"] == 2, "absent-shop saved rack old lot expires")
	check(GameState.store_layout[0]["warehouse_slots"] == GameState.store_layout[0]["storage_slots"], "legacy rack aliases kept consistent")
	check(FoodShelfLife.state()["waste"]["camp_bread"] == 4, "old inventory plus old rack lot; no double count for alias")
	var saved := GameState.create_save_data()
	check(GameState.is_save_data_valid(saved), "full save validates food state and dated rack")
	check(GameState.write_save_file(saved), "actual binary save write")
	var loaded := GameState.read_save_file()
	check(loaded == saved and GameState.apply_save_data(loaded), "binary read/apply retains food state")
	var bad := saved.duplicate(true)
	bad["preservation"]["food"]["freezer"]["bread"] = [{"amount":1,"age":0,"day":GameState.total_day + 1}]
	check(not GameState.is_save_data_valid(bad), "invalid batch date/count rejected")
	bad = saved.duplicate(true)
	bad["store_layout"][0]["storage_slots"][2]["food_batches"][0]["amount"] += 1
	check(not GameState.is_save_data_valid(bad), "saved slot batch/count mismatch rejected")
	bad = saved.duplicate(true)
	bad["store_layout"][0]["storage_slots"][2]["food_batches"] = 42
	check(not GameState.is_save_data_valid(bad), "malformed batch collection rejected without runtime error")
	bad = saved.duplicate(true)
	bad["preservation"]["food"]["waste"][42] = 1
	check(not GameState.is_save_data_valid(bad), "invalid food ledger key safely rejected")
	reset(80)
	GameState.inventory["bread"] = 8
	var legacy := GameState.create_save_data()
	legacy["preservation"].erase("food")
	check(GameState.is_save_data_valid(legacy) and GameState.apply_save_data(legacy), "old saves migrate without format reset")
	check(GameState.get_item_count("bread") == 8 and FoodShelfLife.peek_inventory("bread", 8)[0]["day"] == 80, "legacy stock gets current-day baseline")
	step_day(5)
	check(FoodShelfLife.morning_summary().contains("빵 8개"), "morning suggestion includes stock nearing expiry")
	reset()
	PlayerProgress.record_story_beat("tutorial_event:opening_prologue_v1", 1)
	GameState.add_item("bread", 8)
	step_day(50)
	check(GameState.get_item_count("bread") == 8 and FoodShelfLife.learning(), "first trading lesson cannot lose critical barter food")
	for id in FoodShelfLife.SETTINGS.grace_steps: PlayerProgress.record_story_beat("tutorial_step:" + id + ":done", GameState.total_day)
	FoodShelfLife.settle()
	step_day(1)
	check(FoodShelfLife.peek_inventory("bread", 1)[0]["age"] == 2, "normal aging starts after initial lessons; no retrospective loss")
	reset()
	PlayerProgress.record_story_beat("tutorial_event:opening_prologue_v1", 1)
	GameState.add_item("bread", 8)
	GameState.total_day = 50 # No intermediate inventory queries.
	for id in FoodShelfLife.SETTINGS.grace_steps: PlayerProgress.record_story_beat("tutorial_step:" + id + ":done", 50)
	check(GameState.get_item_count("bread") == 8 and FoodShelfLife.peek_inventory("bread", 1)[0]["age"] == 0, "end of grace never charges unobserved tutorial days")
	reset()
	# Real shop/customer/manual and employee pricing, receipt returns and UI.
	for id in FoodShelfLife.SETTINGS.grace_steps: PlayerProgress.record_story_beat("tutorial_step:" + id + ":done", 1)
	PlayerProgress.record_story_beat(CheckoutTutorial.BEAT_ID, 1)
	GameState.save_store_layout([{"build_id":"door","anchor":Vector2i(0,4),"rotation_index":3}, {"build_id":"register","anchor":Vector2i(4,3),"rotation_index":0}, {"build_id":"shelf_1x1","anchor":Vector2i(2,2),"rotation_index":0}])
	var world = load("res://scenes/shop/main.tscn").instantiate()
	add_child(world)
	await frames()
	world.get_node("TutorialDirector").enabled = false
	world.get_node("TutorialDirector").get_child(0).set_process(false)
	world.get_node("CustomerSpawner").set_process(false)
	for worker in get_tree().get_nodes_in_group("worker"): worker.queue_free()
	await frames()
	shelf = get_tree().get_nodes_in_group("shelf")[0]
	shelf.slots[0]["item_id"] = "camp_bread"
	shelf.slots[0]["stock"] = 0
	GameState.add_item("camp_bread", 3)
	step_day(2)
	check(FoodShelfLife.restock_slot(shelf, 0, 3) == 3, "real shop stocking retains last-day batch")
	var customer = load("res://scenes/shop/actors/customer.tscn").instantiate()
	world.get_node("Actors").add_child(customer)
	customer.set_physics_process(false)
	customer.set_process(false)
	customer.carried_item_id = "camp_bread"
	customer.carried_amount = shelf.take_items_by_id("camp_bread", 1)
	customer.target_shelf = shelf
	FoodShelfLife.capture(customer, shelf)
	check(FoodShelfLife.customer_total(customer) == 70, "actual customer receipt discounted")
	customer._return_unpaid_items_to_shelf()
	check(shelf.get_item_stock("camp_bread") == 3 and customer.carried_amount == 0, "unpaid return no freshening/no duplication")
	customer.carried_item_id = "camp_bread"
	customer.carried_amount = shelf.take_items_by_id("camp_bread", 1)
	FoodShelfLife.capture(customer, shelf)
	var fresh_shelf = load("res://scenes/shop/objects/shelf.tscn").instantiate()
	add_child(fresh_shelf)
	fresh_shelf.slots[0]["item_id"] = "camp_bread"
	fresh_shelf.add_stock_to_slot(0, 5)
	check(customer.choose_best_stocked_shelf([fresh_shelf,shelf], "camp_bread", 3) == shelf, "older partial shelf takes priority over a fuller fresh shelf")
	fresh_shelf.free()
	var register = get_tree().get_nodes_in_group("register")[0]
	customer.target_register = register
	customer.global_position = world.get_node("BuildManager").get_cell_world_position(register.get_checkout_cells()[0])
	register.request_checkout(customer)
	var cashier = world.get_node("ManualCheckoutController")
	var player = world.get_node("Actors/Player")
	var manager = world.get_node("DayManager")
	manager.open_shop()
	manager.hour_timer.paused = true
	player.set_physics_process(false)
	player.global_position = world.get_node("BuildManager").get_cell_world_position(register.get_worker_cells()[0])
	var money: int = GameState.money
	check(cashier.try_interact() and cashier.is_busy(), "real cashier reserves current customer")
	if cashier.is_busy(): cashier._finish_checkout()
	check(customer.purchase_completed and GameState.money == money + 70, "manual checkout charges markdown price")
	customer.checkout_item()
	check(GameState.money == money + 70, "repeated payment no double revenue")
	var other = load("res://scenes/shop/actors/customer.tscn").instantiate()
	world.get_node("Actors").add_child(other)
	other.global_position = customer.global_position
	other.set_physics_process(false)
	other.set_process(false)
	other.carried_item_id = "camp_bread"
	other.carried_amount = shelf.take_items_by_id("camp_bread", 1)
	FoodShelfLife.capture(other, shelf)
	other.checkout_finish_delay = 0.001
	other.complete_checkout_by_worker()
	check(other.purchase_completed and GameState.money == money + 140, "employee uses same receipt total")
	var sale := ShopOfflineSimulator._take_sale(get_tree(), "camp_bread", 1)
	check(sale == {"amount":1, "total":70}, "absent-player simulator same markdown")
	GameState.add_item("camp_bread", 2)
	check(shelf.worker_restock(player) and shelf.get_item_stock("camp_bread") == 2, "employee restock uses actual fresh lots")
	step_day(2)
	var held = load("res://scenes/shop/actors/customer.tscn").instantiate()
	world.get_node("Actors").add_child(held)
	held.global_position = customer.global_position
	held.set_physics_process(false)
	held.carried_item_id = "camp_bread"
	held.carried_amount = shelf.take_items_by_id("camp_bread", 1)
	FoodShelfLife.capture(held, shelf)
	step_day(1)
	check(FoodShelfLife.customer_total(held) == 0 and held.carried_amount == 0, "food expiring in checkout queue cannot be sold")
	held._return_unpaid_items_to_shelf()
	check(shelf.get_item_stock("camp_bread") == 0, "expired held item cannot reenter shelf")
	GameState.add_item("bread", 1)
	FoodShelfLife.restock_slot(shelf, 0, 1) # Assigned camp bread: no bread moves.
	world.get_node("BuildManager").save_store_layout()
	saved = GameState.create_save_data()
	check(GameState.is_save_data_valid(saved), "real-world save after live expiry remains valid")
	var menu = manager.management_menu
	menu.open_menu(ManagementMenu.MenuTab.INVENTORY)
	await get_tree().create_timer(0.8).timeout
	var view = menu.get_node("DimBackground/CenterContainer/MainPanel/MainVBox/Body/ContentArea/InventoryContent/ManagementInventory")
	check(view.get_node("MainVBox/CategoryTabs").has_node("FoodShelfLifeButton"), "food management entry is visible in real inventory")
	var panel: FoodShelfLifePanel
	for node in view.get_children():
		if node is FoodShelfLifePanel: panel = node
	panel.open()
	await frames()
	check(panel.visible and panel.get_ok_button().get_global_rect().end.y <= get_viewport().get_visible_rect().size.y, "management dialog fits screen with return button visible")
	var args := OS.get_cmdline_user_args()
	if args.has("--shot"):
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(args[args.find("--shot") + 1])
	panel.confirmed.emit()
	check(FoodShelfLife.state()["learned"], "actual food-panel acknowledgment completes learning")
	panel.hide()
	menu.close_menu()
	world.queue_free()
	await frames()
	check(GameState.apply_save_data(saved), "real shop state restore")
	check(not RequestTextData.lines("service_text", "prologue_food_dates").is_empty(), "opening food worry registered for runtime")
	var prose := Tools.validate_file(Tools.TEXT_PATH, Tools.load_sources())
	check(prose["errors"].is_empty() and prose["warns"].is_empty(), "writer source and complete text validate")
	print("CHECK_FOOD_SHELF_LIFE checks=",checks," failures=",failures," text=",prose)
	get_tree().quit(0 if failures == 0 else 1)
