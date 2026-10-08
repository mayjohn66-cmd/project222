extends Node
var checks := 0
var failures := 0
var world
var book: ProductPreparationBook
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(message)
func frames() -> void:
	for i in range(8): await get_tree().process_frame
func snap(label: String) -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty() or DisplayServer.get_name() == "headless": return
	await get_tree().create_timer(2.0,true,false,true).timeout
	await frames()
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(args[0] + "-" + label + ".png")
func visible_text() -> String:
	var lines: Array[String] = []
	for label in book.detail.get_children():
		if label is Label: lines.append(label.text)
	return "\n".join(lines)
func has_recipe(id: String) -> bool:
	for entry in ProductPreparationData.entries(world,{}):
		if entry["id"] == id: return true
	return false
func machine(id: String, parent: Node) -> ProductionFacility:
	var node = load("res://scenes/shop/production/production_facility.tscn").instantiate()
	node.facility_id = id
	node.set_meta("build_id",id)
	parent.add_child(node)
	return node
func _ready() -> void: call_deferred("run")
func run() -> void:
	GameState.initialize_new_game()
	PlayerProgress.reset()
	world = load("res://scenes/shop/main.tscn").instantiate()
	world.get_node("TutorialDirector").enabled = false
	add_child(world)
	await frames()
	OpeningJourneyFlow.initialize(world)
	var manager = world.get_node("DayManager")
	manager.hour_timer.stop()
	manager.customer_spawner.set_process(false)
	world.get_node("Actors/Player").set_physics_process(false)
	var menu = manager.management_menu
	menu.space_menu.refresh()
	var host = menu.management_production
	book = host.preparation_book
	check(is_instance_valid(book) and book.world == world,"book resolves its own real main world during startup")
	check(menu.production_button.visible == ShopSpaceProgression.UNLOCK_ALL_TABS,"production navigation follows shared tab disclosure setting")
	menu.open_menu(ManagementMenu.MenuTab.PRODUCTION)
	check(menu.current_tab == (ManagementMenu.MenuTab.PRODUCTION if ShopSpaceProgression.UNLOCK_ALL_TABS else ManagementMenu.MenuTab.INVENTORY),"direct production selection follows shared tab disclosure setting")
	for step in TutorialDirector.SETTINGS.steps:
		if not step.get("optional",false): PlayerProgress.record_story_beat("tutorial_step:" + str(step["id"]) + ":done",GameState.total_day)
	PlayerProgress.record_story_beat("tutorial_step:production:intro",GameState.total_day)
	PlayerProgress.learn_recipe("camp_bread")
	menu.space_menu.refresh()
	menu.select_tab(ManagementMenu.MenuTab.PRODUCTION)
	host.refresh_view()
	check(menu.current_tab == ManagementMenu.MenuTab.PRODUCTION and book.mode == "today","first unlocked production opens today's preparation")
	check(book.entries[0]["id"] == "camp_bread" and (ShopSpaceProgression.UNLOCK_ALL_TABS or book.selected == "camp_bread"),"current tutorial product leads list; earlier visits retain selection")
	check(not host.get_node("MainHBox").visible and not host.get_node("FacilityStatusScroll").visible,"old duplicate production panels hidden")
	check(not has_recipe("bake_bread") and not has_recipe("bottled_water") and not has_recipe("herb_drink"),"unlearned and early modern products hidden")
	host.select_recipe("herb_drink")
	check(book.selected != "herb_drink","direct unlearned selection rejected")
	var recipe := ProductRecipeData.get_recipe("camp_bread")
	check(ProductPreparationData.ready(world,recipe) == "생산실 마련","known recipe shows first unbuilt space")
	book.select_entry("camp_bread")
	check(visible_text().contains("타블렌") and visible_text().contains("생산실 문"),"actual tutorial provenance and first space guidance")
	await snap("first-plan")
	ShopSpaceProgression.mark("production")
	check(ProductPreparationData.ready(world,recipe) == "설비 설치","empty built production room requires physical facility")
	PlayerProgress.learn_recipe("berry_juice")
	check(ProductPreparationData.ready(world,ProductRecipeData.get_recipe("berry_juice")) == "첫 상품 수령 먼저","learned drink recipe respects first product furniture gate")
	PlayerProgress.learned_recipe_ids.erase("berry_juice")
	var oven := machine("magic_oven",world.get_node("ProductionRoom/Objects"))
	var tutorial = world.get_node("TutorialDirector")
	tutorial.enabled = true
	tutorial.set_process(false)
	oven.output_collected.connect(tutorial._on_output_collected)
	check(ProductPreparationData.location(world,oven) == "생산실","facility location follows actual parent room")
	check(ProductPreparationData.ready(world,recipe) == "재료 준비","idle machine with missing carried materials")
	var ingredients := ProductionRecipeService.collect_required_ingredients(recipe,1)
	for id in ingredients: GameState.add_item(str(id),int(ingredients[id]))
	var shelf = load("res://scenes/shop/warehouse/warehouse_storage.tscn").instantiate()
	world.get_node("WarehouseRoom/Objects").add_child(shelf)
	var ingredient := str(ingredients.keys()[0])
	var need := int(ingredients[ingredient])
	check(shelf.deposit_from_inventory(ingredient,need) == need,"real storage deposit removes carried materials")
	check(ProductPreparationData.shelf_count(world,ingredient) == need and ProductPreparationData.ready(world,recipe) == "재료 준비","warehouse stock is separate and cannot remotely supply production")
	book.select_entry("camp_bread")
	check(visible_text().contains("창고 선반") and visible_text().contains("부족"),"ingredient detail explains withdrawal and actual shortfall")
	await snap("materials")
	var saved_inventory := GameState.inventory.duplicate(true)
	var saved_progress := PlayerProgress.to_save_data().duplicate(true)
	var saved_money := GameState.money
	var saved_machine := oven.get_production_save_data().duplicate(true)
	book.refresh()
	book.select_tab("learned")
	book.select_entry("camp_bread")
	host._on_start_pressed()
	check(GameState.inventory == saved_inventory and PlayerProgress.to_save_data() == saved_progress and GameState.money == saved_money and oven.get_production_save_data() == saved_machine,"browsing and legacy start handler cannot spend, craft, collect or advance story")
	check(shelf.withdraw_slot_to_inventory(shelf.find_item_slot(ingredient),need) == need,"actual warehouse withdrawal restores usable ingredients")
	check(ProductPreparationData.ready(world,recipe) == "지금 만들 수 있음","withdrawn ingredients become usable")
	book.select_tab("today")
	book.only_ready.button_pressed = true
	check(not book.entries.is_empty(),"ready filter includes genuinely producible recipes")
	check(oven.start_production("camp_bread"),"actual machine still starts production and consumes exact materials")
	book.refresh()
	check(book.entries.is_empty() and ProductPreparationData.ready(world,recipe) == "설비 사용 중","busy machine excluded from ready filter")
	book.only_ready.button_pressed = false
	book.select_tab("facilities")
	book.select_entry(str(oven.get_instance_id()))
	check(visible_text().contains("가공 중") and visible_text().contains(str(recipe["craft_time"])) and visible_text().contains("현지식 빵"),"installed machine details show real output and remaining time")
	await snap("processing")
	var machine_save := oven.get_production_save_data().duplicate(true)
	oven.apply_production_save_data(machine_save)
	check(ProductPreparationData.ready(world,recipe) == "설비 사용 중","restored in-progress facility remains busy")
	oven._process(oven.remaining_seconds + 1)
	check(ProductPreparationData.ready(world,recipe) == "완성품 수령 먼저","finished output requires actual collection")
	book.refresh()
	check(visible_text().contains("완성품 수령 대기"),"facility screen refreshes completed output")
	var before := GameState.get_item_count("camp_bread")
	check(oven.collect_production() and GameState.get_item_count("camp_bread") == before + int(recipe["result_amount"]),"actual collection grants original output amount")
	check(ShopSpaceProgression.first_product(),"actual collection still advances existing room tutorial")
	var first_request: Dictionary = ResidentRequestFlow.SETTINGS.requests[0]
	var request_id := str(first_request["id"])
	var requested := str(first_request["item"])
	check(not ProductPreparationContext.notes().has(requested),"unaccepted resident request has no preparation hint")
	PlayerProgress.record_story_beat(ResidentRequestFlow.PREFIX + request_id + ":accepted",GameState.total_day)
	check(ProductPreparationContext.notes().has(requested),"accepted resident request appears with existing title")
	PlayerProgress.record_story_beat(ResidentRequestFlow.PREFIX + request_id + ":done",GameState.total_day)
	check(not ProductPreparationContext.notes().has(requested),"completed resident request disappears")
	var communal: Dictionary = CommunityRequestFlow.SETTINGS.requests[0]
	var communal_item := str(communal["requirements"][0]["item"])
	PlayerProgress.record_story_beat(CommunityRequestFlow.PREFIX + str(communal["id"]) + ":accepted",GameState.total_day)
	check(ProductPreparationContext.notes().has(communal_item),"accepted community requirements use actual configured item")
	PlayerProgress.record_story_beat(CommunityRequestFlow.PREFIX + str(communal["id"]) + ":done",GameState.total_day)
	var personal: Dictionary = PersonalRequestFlow.entries()[0]
	var personal_item := str(personal["requirements"][0]["item"])
	PlayerProgress.record_story_beat(PersonalRequestFlow.PREFIX + str(personal["id"]) + ":accepted",GameState.total_day)
	check(ProductPreparationContext.notes().has(personal_item),"accepted personal request supplies known ingredient context")
	PlayerProgress.record_story_beat(PersonalRequestFlow.PREFIX + str(personal["id"]) + ":done",GameState.total_day)

	GameState.total_day = 8
	check(ProductPreparationContext.notes().get("berry_juice",[]).is_empty(),"unheard spring market has no future product hint")
	check(StoreEventData.discover_event("spring_market",8),"actual spring market rumor can be heard")
	check(not ProductPreparationContext.notes().get("berry_juice",[]).is_empty(),"heard market links its actual cue product")
	GameState.total_day = 15
	check(not ProductPreparationContext.notes().get("berry_juice",[]).is_empty(),"heard ongoing market retains rumor product context")
	GameState.total_day = 20
	check(ProductPreparationContext.notes().get("berry_juice",[]).is_empty(),"ended market does not advise stock preparation")
	GameState.total_day = 120
	check(ProductPreparationContext.notes().get("berry_juice",[]).is_empty(),"last year's rumor does not unlock this year's event")
	GameState.total_day = 8
	PlayerProgress.learn_recipe("berry_juice")
	ShopSpaceProgression.mark("production")
	PlayerProgress.record_story_beat(CraftingPathFlow.key("craft_trail_food","accepted"),8)
	book.select_tab("today")
	book.select_entry("berry_juice")
	check(visible_text().contains("들은 소문") and visible_text().contains("타블렌") and not visible_text().contains("배율"),"prepared product uses known narrative, real provenance and no demand forecast")
	await snap("heard-story")
	var save := PlayerProgress.to_save_data().duplicate(true)
	PlayerProgress.load_save_data(save)
	check(has_recipe("camp_bread") and has_recipe("berry_juice") and not ProductPreparationContext.notes().get("berry_juice",[]).is_empty(),"saved recipe and heard context restored without new persistent schema")
	var unit: Dictionary = PreservationService.SETTINGS.units[0]
	var cold_item := str(unit["accepts"][0])
	PreservationService.install(str(unit["id"]),true)
	GameState.add_item(cold_item,2)
	check(PreservationService.deposit(str(unit["id"]),cold_item,2) == 2,"actual cold stock deposit succeeds")
	check(ProductPreparationData.preservation_note(cold_item).contains("2개") and ProductPreparationData.preservation_note(cold_item).contains("현장에서 꺼내기"),"cold stock is labeled as separate withdrawal stock")
	var preview := machine("magic_oven",world.get_node("ProductionRoom/Objects"))
	preview.set_meta("is_build_preview",true)
	check(preview not in ProductPreparationData.facilities(world),"build preview does not count as usable machine")
	var foreign := Node2D.new()
	add_child(foreign)
	var foreign_machine := machine("drink_machine",foreign)
	check(foreign_machine not in ProductPreparationData.facilities(world),"other world group member does not count")
	PlayerProgress.story_beat_days.erase(ShopSpaceProgression.VERSION)
	PlayerProgress.story_beat_days.erase(CraftingPathFlow.NEW_GAME)
	PlayerProgress.learn_recipe("bake_bread")
	check(has_recipe("bake_bread") and ShopSpaceProgression.room_ready("production"),"legacy saves preserve existing recipes and room access")
	book.select_tab("learned")
	book.select_entry("camp_bread")
	await frames()
	check(book.list_scroll.size.y > 220 and book.detail_scroll.size.y > 220,"both book pages retain usable scrolling height")
	check(book.list_scroll.get_global_rect().end.x + 40 <= book.detail_scroll.global_position.x,"left and right pages leave binding space")
	for button in book.list.get_children():
		if button is Button: check(button.size.x <= book.list_scroll.size.x,"recipe row fits left page width")
	await snap("learned")

	for known_recipe in ProductRecipeData.get_all_recipes(): PlayerProgress.learn_recipe(str(known_recipe["recipe_id"]))
	book.refresh()
	book.select_entry("mushroom_stew")
	await frames()
	book.list_scroll.scroll_vertical = 100
	book.detail_scroll.scroll_vertical = 40
	await frames()
	var list_position := book.list_scroll.scroll_vertical
	var detail_position := book.detail_scroll.scroll_vertical
	check(list_position > 0,"long actual recipe list scrolls")
	book.refresh()
	await frames()
	check(book.list_scroll.scroll_vertical == list_position and book.detail_scroll.scroll_vertical == detail_position,"state refresh retains both page scroll positions")
	await snap("long-list")
	print("CHECK_PRODUCT_PREPARATION ",checks," checks / ",failures," failures")
	get_tree().paused = false
	get_tree().quit(1 if failures else 0)
