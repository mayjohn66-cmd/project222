extends Node
var checks := 0
var failures := 0
var world: Node
var manager
var view: DaySummaryPreparation
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(message)
func frames(count: int = 8) -> void:
	for i in range(count): await get_tree().process_frame
func key(code: Key) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code; event.physical_keycode = code; event.pressed = pressed
		get_viewport().push_input(event, true)
	await frames()
func click(button: Button) -> void:
	check(is_instance_valid(button), "actual pointer target exists")
	if not is_instance_valid(button): return
	await frames()
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = button.get_global_rect().get_center()
		if button.get_window() != get_window(): event.position += Vector2(button.get_window().position)
		event.button_index = MOUSE_BUTTON_LEFT; event.pressed = pressed
		get_viewport().push_input(event, true)
	await frames()
func snap(name: String) -> void:
	if DisplayServer.get_name() == "headless": return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--snap="):
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(arg.trim_prefix("--snap=") + "-" + name + ".png")
func close_day() -> void:
	manager.current_hour = GameConfig.DAY_START_HOUR - 1
	manager._on_hour_timer_timeout()
	for i in range(1200):
		if manager.summary_open: break
		await get_tree().process_frame
	check(manager.summary_open and get_tree().paused and manager.hour_timer.is_stopped(), "real hour boundary reaches stopped and paused settlement")
	await frames()
func run() -> void:
	if not OS.get_user_data_dir().contains("foodbag_checks"):
		push_error("Use the isolated foodbag_checks project to protect player saves.")
		get_tree().quit(2); return
	var original := GameState.create_save_data()
	GameState.initialize_new_game(); PlayerProgress.reset()
	GameState.total_day = 27; GameState.current_day = 6
	GameState.inventory.clear(); GameState.preservation_state = PreservationService.initial_state(27)
	GameState.money = 100
	for step in OpeningJourneyFlow.SETTINGS.steps:
		if not step.get("optional", false): PlayerProgress.record_story_beat("tutorial_step:" + str(step["id"]) + ":done", 27)
	PlayerProgress.record_story_beat(OpeningJourneyFlow.RAW_SALE, 27)
	var periods: Array[String] = ["evening"]
	check(GameState.set_employee_state("worker_001", true, periods), "existing hire/evening schedule fixture accepted")
	world = load("res://scenes/shop/main.tscn").instantiate()
	world.get_node("TutorialDirector").enabled = false
	get_tree().root.add_child(world); get_tree().current_scene = world
	await frames(12)
	manager = world.get_node("DayManager")
	view = manager.day_summary_center
	manager.customer_spawner.set_process(false)
	var layout: Array[Dictionary] = [
		{"build_id":"door", "anchor":Vector2i(5,0), "rotation_index":0},
		{"build_id":"register", "anchor":Vector2i(6,2), "rotation_index":0},
		{"build_id":"shelf_1x1", "anchor":Vector2i(2,2), "rotation_index":0},
		{"build_id":"warehouse_rack", "anchor":Vector2i(4,4), "rotation_index":0},
		{"build_id":"fridge_unit", "anchor":Vector2i(0,4), "rotation_index":0},
		{"build_id":"freezer_unit", "anchor":Vector2i(2,5), "rotation_index":0}]
	manager.build_manager._restore_current_area_layout(layout)
	await frames()
	check(manager.can_open_shop(), "real door and register exist for next morning")
	var shelf = get_tree().get_nodes_in_group("shelf")[0]
	var storage = get_tree().get_nodes_in_group("warehouse_storage")[0]
	GameState.add_item("fish_stream_minnow", 1)
	GameState.add_item("fish_stone_crucian", 1)
	check(storage.deposit_from_inventory_to_slot(0, "fish_stone_crucian", 1) == 1, "actual warehouse deposit fixture")
	GameState.add_item("fish_blossom_minnow", 1)
	shelf.slots[0]["item_id"] = "fish_blossom_minnow"
	check(FoodShelfLife.restock_slot(shelf, 0, 1) == 1, "actual shelf restock carries original food age")
	GameState.add_item("fish_reed_loach", 1)
	GameState.add_item("fish_snow_trout", 1)
	PreservationService.install("fridge", true); PreservationService.install("freezer", true) # Existing installed-state fixture.
	check(PreservationService.deposit("fridge", "fish_reed_loach", 1) == 1 and PreservationService.deposit("freezer", "fish_snow_trout", 1) == 1, "actual installed units accept fish")
	world.get_node("Actors/Player").record_successful_sale(70, "camp_bread", 1)
	var before := GameState.create_save_data().duplicate(true)
	DaySummaryPreparation.notes(world, manager)
	check(GameState.create_save_data() == before, "preparation notes consume/pay/advance nothing")
	await close_day()
	check(not world.get_node("UI/WorldInteractionHint").visible and view.z_index > world.get_node("UI/HUD").z_index, "summary hides ambient hints and renders above clock HUD")
	check(GameState.total_day == 27 and GameState.money == 100 and GameState.employee_salary_records["worker_001"]["accrued_days"] == 0, "opening summary leaves date and salary untouched")
	check(view.result_text.text == manager.summary_text.text and view.result_text.text.contains("70G"), "actual existing statistics retained through original source path")
	check(view.guidance.text.contains("계산대 안쪽") and view.guidance.text.contains(UiText.t("day.preparation.cold")) and view.guidance.text.contains(UiText.t("day.preparation.staff")), "relevant food, installed cold storage and hired worker preparation visible")
	check(view.confirm == manager.next_day_button and view.confirm.text.contains("06:00"), "original confirmation action now names next-morning preparation")
	check(not manager.save_preparation_checkpoint("user://day_preparation_check.dat") and manager.save_failure_reason.contains("06:00") and not manager.save_failure_reason.contains("9시"), "saving during settlement is blocked with current preparation time")
	# Long translated statistics are a layout fixture; preserve the recorded result.
	var original_text: String = manager.summary_text.text
	manager.summary_text.text += "\n" + "긴 상품 설명과 정산 기록을 읽습니다.\n".repeat(40)
	await frames()
	check(view.scroll.get_v_scroll_bar().max_value > view.scroll.size.y, "long summary is scrollable instead of pushing confirmation away")
	check(get_viewport().get_visible_rect().encloses(view.confirm.get_global_rect()), "fixed confirmation stays inside viewport")
	await key(KEY_ESCAPE)
	check(manager.summary_open and get_tree().paused, "escape cannot bypass pending settlement")
	await snap("long-summary")
	manager.summary_text.text = original_text
	await click(view.confirm)
	check(world.get_node("UI/WorldInteractionHint").visible, "confirmation restores previous interaction hint visibility")
	check(GameState.total_day == 28 and not manager.summary_open and not get_tree().paused and not manager.shop_open and manager.hour_timer.is_stopped(), "actual confirm advances once into stopped closed-store morning")
	check(GameState.employee_salary_records["worker_001"]["accrued_days"] == 1 and GameState.money == 100, "ordinary day accrues existing employee wage without charging early")
	check(GameState.get_employee_state("worker_001")["work_periods"] == periods and get_tree().get_nodes_in_group("worker")[0].can_edit_work_schedule(), "next morning preserves prior roster and allows editing")
	check(GameState.get_item_count("fish_stream_minnow") == 1 and storage.get_item_count("fish_stone_crucian") == 1 and shelf.get_item_stock("fish_blossom_minnow") == 1, "one next-morning transition ages all ambient containers once")
	var director: FoodShelfLifeDirector
	for child in world.get_node("TutorialDirector").get_children():
		if child is FoodShelfLifeDirector: director = child
	check(director != null, "existing morning food director installed")
	director.elapsed = 1.0; director._process(0.01)
	check(int(FoodShelfLife.state()["notice_day"]) == 28 and FoodShelfLife.claim_morning_notice().is_empty(), "first morning notice is claimed once")
	manager.confirm_next_day()
	check(GameState.total_day == 28 and GameState.employee_salary_records["worker_001"]["accrued_days"] == 1, "duplicate confirm cannot advance date or payroll")
	check(manager.save_preparation_checkpoint("user://day_preparation_check.dat"), "actual stopped morning checkpoint saves successfully")
	var saved := GameState.read_save_file("user://day_preparation_check.dat")
	check(GameState.apply_save_data(saved), "verified saved food and payroll state reloads")
	check(GameState.get_employee_state("worker_001")["work_periods"] == periods, "actual checkpoint restores the same employee roster")
	check(FoodShelfLife.claim_morning_notice().is_empty(), "same-day save reload never repeats claimed food notice")
	GameState.unpaid_employee_salary = 100 # Prior unpaid wages fixture; no new payment policy.
	await close_day()
	check(view.scroll.scroll_vertical == 0 and view.guidance.text.contains(UiText.t("day.preparation.salary_period")) and view.guidance.text.contains("100 G"), "next summary resets scroll and explains existing season-end salary/debt")
	await snap("season-end")
	view.scroll.scroll_vertical = int(view.scroll.get_v_scroll_bar().max_value)
	await frames()
	await snap("preparation-tips")
	var period_due := roundi(float(EmployeeData.get_monthly_salary("worker_001")) * 2.0 / CalendarData.DAYS_PER_SEASON)
	await click(view.confirm)
	check(GameState.total_day == 29 and GameState.money == 0 and GameState.get_unpaid_employee_salary() == period_due, "real season-end pays only held cash and retains remaining wage debt")
	check(GameState.get_item_count("fish_stream_minnow") == 0 and storage.get_item_count("fish_stone_crucian") == 0 and shelf.get_item_stock("fish_blossom_minnow") == 0, "second morning separates expired ambient foods in inventory, warehouse and display")
	check(int(GameState.preservation_state["fridge"].get("fish_reed_loach", 0)) == 1 and int(GameState.preservation_state["freezer"].get("fish_snow_trout", 0)) == 1, "cold storage retains its existing food time treatment")
	check(FoodShelfLife.state()["waste"].size() == 3, "expired containers report exactly three distinct waste foods")
	var cashier = world.get_node("ManualCheckoutController")
	var register = get_tree().get_nodes_in_group("register")[0]
	var player = world.get_node("Actors/Player")
	player.global_position = manager.build_manager.get_cell_world_position(register.get_worker_cells()[0])
	await key(KEY_E)
	check(cashier.food_cleanup.visible and get_tree().paused, "real empty-register E opens product overview in morning")
	await click(cashier.food_cleanup.rows.get_node("CleanupTab") if cashier.food_cleanup.rows.has_node("CleanupTab") else cashier.food_cleanup.rows.get_child(0).get_node("CleanupTab"))
	check(cashier.food_cleanup.cleanup_page and cashier.food_cleanup.cleanup_seen, "actual cleanup tab reaches separated expired stock")
	var discard: Button
	for candidate in cashier.food_cleanup.rows.find_children("*", "Button", true, false):
		if candidate.text == "폐기": discard = candidate; break
	check(discard != null, "expired stock exposes disposal action")
	if discard != null: await click(discard)
	check(FoodShelfLife.state()["waste"].size() == 2 and GameState.money == 0, "actual disposal removes one waste row without sale reward")
	await snap("cleanup")
	await click(cashier.food_cleanup.get_ok_button())
	check(not get_tree().paused and manager.hour_timer.is_stopped(), "closing cleanup returns to stopped morning preparation")
	manager.current_hour = 7
	check(not manager.save_preparation_checkpoint("user://day_preparation_check.dat") and manager.save_failure_reason.contains("06:00"), "late-hour rejected save points to actual preparation time")
	manager.current_hour = GameConfig.DAY_START_HOUR
	player.global_position = get_tree().get_nodes_in_group("door")[0].global_position
	await key(KEY_E)
	check(manager.shop_open and not manager.hour_timer.is_stopped(), "door E begins next day and starts its existing clock")
	manager.close_shop_manually(); manager.hour_timer.stop()
	PlayerProgress.reset()
	var early := DaySummaryPreparation.notes(world, manager)
	check(early.size() == 2 and not "\n".join(early).contains("직원") and not "\n".join(early).contains("냉장"), "tutorial settlement avoids later-system preparation tips")
	world.queue_free(); await frames()
	check(GameState.apply_save_data(original), "restore original isolated in-memory state")
	print("CHECK_DAY_PREPARATION checks=", checks, " failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)
