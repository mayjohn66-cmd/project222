extends Node
var checks := 0
var failures := 0
var world
var menu: ManagementMenu
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(message)
func frames() -> void:
	for i in range(8): await get_tree().process_frame
func views(node: Node) -> Array[StoreEventPreparationView]:
	var result: Array[StoreEventPreparationView] = []
	for child in node.get_children():
		if child is StoreEventPreparationView: result.append(child)
		result.append_array(views(child))
	return result
func click(button: Button) -> void:
	await get_tree().create_timer(2.0,true,false,true).timeout
	var parent: Node = button.get_parent()
	while parent != null and not parent is ScrollContainer: parent = parent.get_parent()
	if parent is ScrollContainer: parent.ensure_control_visible(button)
	await frames()
	for pressed in [true,false]:
		var input := InputEventMouseButton.new()
		input.position = button.get_global_rect().get_center()
		if menu.has_meta("book_stage") and is_instance_valid(menu.get_meta("book_stage")): input.position += menu.get_meta("book_stage")._offset
		input.button_index = MOUSE_BUTTON_LEFT
		input.pressed = pressed
		get_viewport().push_input(input,true)
	await frames()
func snap(label: String) -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty() or DisplayServer.get_name() == "headless": return
	await get_tree().create_timer(2.0,true,false,true).timeout
	if label in ["scroll","rumor","stock"]:
		var shown := views(menu.schedule_list)
		if not shown.is_empty():
			var target: Control = shown[0].label
			var parent: Node = target.get_parent()
			while parent != null and not parent is ScrollContainer: parent = parent.get_parent()
			if parent is ScrollContainer: parent.ensure_control_visible(target)
			await frames()
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(args[0] + "-" + label + ".png")
func _ready() -> void: call_deferred("run")
func run() -> void:
	if not OS.get_user_data_dir().contains("foodbag_checks"):
		push_error("Run this check in the isolated foodbag_checks project.")
		get_tree().quit(1)
		return
	GameState.initialize_new_game()
	PlayerProgress.reset()
	world = load("res://scenes/shop/main.tscn").instantiate()
	world.get_node("TutorialDirector").enabled = false
	add_child(world)
	await frames()
	var manager = world.get_node("DayManager")
	manager.hour_timer.stop()
	manager.customer_spawner.set_process(false)
	world.get_node("Actors/Player").set_physics_process(false)
	menu = manager.management_menu
	menu.open_menu(ManagementMenu.MenuTab.SCHEDULE)
	check(views(menu.schedule_list).is_empty(),"unheard tutorial schedule exposes no product preparation")
	for step in TutorialDirector.SETTINGS.steps: PlayerProgress.record_story_beat("tutorial_step:" + str(step["id"]) + ":done",1)
	var raw := StoreEventData.get_event("spring_market")
	GameState.total_day = int(raw["discovery_start_day"])
	check(StoreEventData.discover_event("spring_market",GameState.total_day),"actual rumor discovery accepted")
	var event := StoreEventData.get_event_occurrence("spring_market",GameState.total_day)
	check(StoreEventPreparation.items(event) == ["bread","berry_juice"],"only rumor cue products included")
	check(StoreEventPreparation.recipes("berry_juice").is_empty(),"unlearned recipe remains hidden")
	check(StoreEventNextStepGuide.missing("iron_ore").is_empty(),"raw material is not sent to an invented manufacturing recipe")
	var missing := StoreEventPreparation.summary(world,event)
	check(missing.contains(UiText.t("store.preparation.unavailable")),"empty unknown product offers a reachable learning path without rushing this event")
	var scroll := str(RecipeUnlockData.by_recipe["berry_juice"]["scroll_item_id"])
	GameState.add_item(scroll,1) # Owned scroll fixture; actual learning UI is tested by check_room_preparation.
	var untouched := GameState.create_save_data().duplicate(true)
	missing = StoreEventPreparation.summary(world,event)
	check(missing.contains(ItemData.get_item_name(scroll)) and missing.contains("‘배우기’"),"owned unlearned scroll gets concrete inventory action")
	check(StoreEventPreparation.recipes("berry_juice").is_empty() and GameState.create_save_data() == untouched,"clue lookup cannot learn consume scroll or reward")
	menu.refresh_schedule()
	await frames()
	await snap("scroll")
	PlayerProgress.learn_recipe("berry_juice") # Learned-history fixture; guidance performs no learning.
	check(StoreEventPreparation.summary(world,event).contains(UiText.t("store.preparation.learned")),"known empty product points to existing recipe and real facility work")
	GameState.remove_item(scroll,1)
	check(not StoreEventPreparation.recipes("berry_juice").is_empty(),"learned actual output recipe included")
	var earlier := PlayerProgress.to_save_data().duplicate(true)
	PlayerProgress.record_story_beat(ShopSpaceProgression.VERSION,1)
	PlayerProgress.record_story_beat("tutorial_step:production:intro",1)
	check(StoreEventNextStepGuide.missing("berry_juice") == UiText.t("store.preparation.production_room"),"learned event product cannot skip unopened production room")
	PlayerProgress.reset()
	PlayerProgress.load_save_data(earlier)
	# Existing full book can keep a ready-only filter from an earlier visit.
	var book: ProductPreparationBook = menu.management_production.preparation_book
	book.only_ready.set_pressed_no_signal(true)
	menu.refresh_schedule()
	await frames()
	var view := views(menu.schedule_list)[0]
	check(view.world == world,"card resolves its own main world")
	check(view.actions.get_child_count() == 1,"only learned matching recipe has a button")
	view.open_recipe("bread","berry_juice")
	check(menu.current_tab == ManagementMenu.MenuTab.SCHEDULE,"wrong output recipe cannot be opened from a clue")
	check(view.label.text.contains("진열 0개 / 소지 0개"),"empty stock not represented as available goods")
	await snap("rumor")
	await click(view.actions.get_child(0))
	check(menu.current_tab == ManagementMenu.MenuTab.PRODUCTION and book.mode == "learned" and book.selected == "berry_juice" and not book.only_ready.button_pressed,"real button selects recipe even if materials are missing and previous filter was active")
	await snap("recipe")
	menu.select_tab(ManagementMenu.MenuTab.SCHEDULE)
	view = views(menu.schedule_list)[0]
	var layout: Array[Dictionary] = [{"build_id":"shelf_1x1","anchor":Vector2i(2,2),"rotation_index":0}]
	world.get_node("BuildManager")._restore_current_area_layout(layout)
	await frames()
	var shelf
	for node in get_tree().get_nodes_in_group("shelf"):
		if world.is_ancestor_of(node) and not node.get_meta("is_build_preview",false): shelf = node; break
	shelf.product_id = "berry_juice"
	shelf.stock = 0
	GameState.add_item("berry_juice",3)
	view.refresh()
	check(view.label.text.contains("진열 0개 / 소지 3개") and view.label.text.contains("진열대에 보충"),"carried stock needs real shelf refill")
	var storage = load("res://scenes/shop/warehouse/warehouse_storage.tscn").instantiate()
	world.get_node("WarehouseRoom/Objects").add_child(storage)
	check(storage.deposit_from_inventory("berry_juice",1) == 1,"real warehouse deposit succeeds")
	check(PreservationService.install("fridge",true) and PreservationService.deposit("fridge","berry_juice",1) == 1,"real cold deposit succeeds")
	view.refresh()
	check(view.label.text.contains("진열 0개 / 소지 1개") and view.label.text.contains("창고 선반 1개") and view.label.text.contains("냉장 보관 1개"),"separate storage not counted as shelf or carried stock")
	check(shelf.worker_restock(GameState),"original physical restock succeeds")
	await get_tree().create_timer(0.7,true,false,true).timeout
	check(view.label.text.contains("진열 1개 / 소지 0개"),"actual restock reflected")
	var preview = load(shelf.scene_file_path)
	var fake = preview.instantiate()
	fake.set_meta("is_build_preview",true)
	world.add_child(fake)
	fake.product_id = "berry_juice"; fake.stock = 5
	var other := Node2D.new()
	add_child(other)
	var unrelated = preview.instantiate()
	other.add_child(unrelated)
	unrelated.product_id = "berry_juice"; unrelated.stock = 5
	check(StoreEventPreparation.displayed(world,"berry_juice") == 1,"preview and other worlds excluded")
	fake.queue_free(); other.queue_free()
	check(shelf.take_items_by_id("berry_juice",1) == 1,"actual customer shelf pickup reduces stock")
	view.refresh()
	check(view.label.text.contains("진열 0개 / 소지 0개") and view.label.text.contains("보관 중인 상품은 꺼낸 뒤 진열"),"picked-up goods no longer treated as shelf stock")
	var inventory := GameState.inventory.duplicate(true)
	var progress := PlayerProgress.to_save_data().duplicate(true)
	var money := GameState.money
	var kept: Dictionary = storage.stored_items.duplicate(true)
	for i in range(3): view.refresh()
	check(GameState.inventory == inventory and PlayerProgress.to_save_data() == progress and GameState.money == money and storage.stored_items == kept,"browsing cannot craft withdraw reward or finish stories")
	await snap("stock")
	GameState.add_item("berry_juice",1)
	shelf.worker_restock(GameState)
	GameState.total_day += int(FoodShelfLife.rules()["berry_juice"]["days"])
	view.refresh()
	check(StoreEventPreparation.displayed(world,"berry_juice") == 0,"expired displayed food removed through original expiry rules")
	check(view.label.text.contains("기한"),"food preparation mentions existing shelf life")
	GameState.total_day = int(event["end_day"]) + 1
	check(StoreEventPreparation.items(event).is_empty(),"finished occurrence has no preparation")
	menu.refresh_schedule()
	check(views(menu.schedule_list).is_empty(),"finished memo keeps history without preparation")
	GameState.total_day = int(raw["discovery_start_day"]) + CalendarData.DAYS_PER_YEAR
	check(StoreEventPreparation.items(StoreEventData.get_event_occurrence("spring_market",GameState.total_day)).is_empty(),"last year's rumor does not reveal next year's preparation")
	check(StoreEventData.discover_event("spring_market",GameState.total_day),"new yearly rumor can be heard")
	check(StoreEventPreparation.items(event).is_empty(),"old occurrence card cannot become next year advice")
	var current := StoreEventData.get_event_occurrence("spring_market",GameState.total_day)
	check(not StoreEventPreparation.items(current).is_empty(),"current heard annual occurrence has preparation")
	var discovery := GameState.get_discovered_store_events().duplicate(true)
	GameState.discovered_store_events.clear()
	GameState.discovered_store_events = discovery
	check(StoreEventPreparation.items(current) == ["bread","berry_juice"],"existing discovery save alone restores preparation")
	GameState.total_day = 17
	GameState.discovered_store_events["fish_store_spring"] = 17
	var fish_event := StoreEventData.get_event_occurrence("fish_store_spring",17)
	check(StoreEventPreparation.items(fish_event).is_empty(),"saved fish rumor cannot bypass fishing content gate")
	FishingRecords.mark("fishing_first_sale:done")
	PlayerProgress.record_story_beat("resident_request:neighbor_bread:accepted",17)
	check(StoreEventPreparation.items(fish_event).is_empty(),"fish market product hidden until learned")
	PlayerProgress.learn_recipe("recipe_fish_grilled")
	check(StoreEventPreparation.items(fish_event) == ["fish_grilled"],"known fish market product follows existing availability")
	check(not StoreEventPreparation.recipes("fish_grilled").is_empty(),"known fish recipe provides preparation link")
	var common := StoreEventData.get_event("trail_supplies")
	GameState.total_day = int(common["discovery_start_day"])
	check(StoreEventData.discover_event("trail_supplies",GameState.total_day),"common rumor heard")
	GameState.total_day += int(common["repeat_days"])
	check(StoreEventPreparation.items(StoreEventData.get_event_occurrence("trail_supplies",GameState.total_day)).is_empty(),"previous common cycle not reused")
	# All current non-fishing events: no unknown/finished cases or numerical demand quotas.
	for definition in StoreEventData.events.values():
		if str(definition["event_id"]).begins_with("fish_store_"): continue
		var occurrence := StoreEventSchedule.occurrence(definition,1)
		GameState.total_day = int(occurrence["discovery_start_day"])
		var id := str(definition["event_id"])
		GameState.discovered_store_events[id] = GameState.total_day
		occurrence = StoreEventData.get_event_occurrence(id,GameState.total_day)
		var text := StoreEventPreparation.summary(world,occurrence)
		check(not text.is_empty() and not text.contains("기간:") and not text.contains("배율") and not text.contains("필요량"),"heard common/seasonal clue shows stock without forecasting: " + id)
		GameState.total_day = int(occurrence["end_day"]) + 1
		check(StoreEventPreparation.summary(world,occurrence).is_empty(),"ended clue has no stock guidance: " + id)
	GameState.total_day = int(current["discovery_start_day"])
	menu.refresh_schedule()
	await frames()
	await get_tree().create_timer(2.0,true,false,true).timeout
	if menu.has_meta("book_stage") and is_instance_valid(menu.get_meta("book_stage")):
		var hint: Control = menu.get_meta("book_stage").hint
		check(hint.is_visible_in_tree() and get_viewport().get_visible_rect().encloses(hint.get_global_rect()),"actual ESC close hint stays visible below long cards")
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	get_viewport().push_input(escape,true)
	await get_tree().create_timer(2.0,true,false,true).timeout
	check(not get_tree().paused,"closing book restores game pause state")
	print("CHECK_STORE_EVENT_PREPARATION checks=",checks," failures=",failures)
	get_tree().quit(0 if failures == 0 else 1)
