extends Node
var checks := 0
var failures := 0
var world
var panel: VillageJournalPanel
var view: RequestPreparationView
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(message)
func frames() -> void:
	for i in range(8): await get_tree().process_frame
func find(id: String) -> Dictionary:
	for entry in RequestPreparationData.entries():
		if entry["id"] == id: return entry
	return {}
func click(button: Button) -> void:
	for pressed in [true,false]:
		var event := InputEventMouseButton.new()
		event.position = button.get_global_rect().get_center()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		get_viewport().push_input(event,true)
	await frames()
func snap(label: String) -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty() or DisplayServer.get_name() == "headless": return
	view.refresh()
	view.select(true)
	await get_tree().create_timer(0.5,true,false,true).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(args[0] + "-" + label + ".png")
func _ready() -> void: call_deferred("run")
func run() -> void:
	GameState.initialize_new_game()
	PlayerProgress.reset()
	world = load("res://scenes/shop/main.tscn").instantiate()
	world.get_node("TutorialDirector").enabled = false
	add_child(world)
	await frames()
	var manager = world.get_node("DayManager")
	manager.hour_timer.stop()
	manager.customer_spawner.set_process(false)
	var director: VillageJournalDirector = world.get_node("VillageJournalDirector")
	panel = director.panel
	view = panel.preparation_view
	check(RequestPreparationData.entries().is_empty(),"tutorial has no preparation entries")
	check(not view.tabs.visible,"tutorial has no empty preparation tab")
	for step in TutorialDirector.SETTINGS.steps:
		PlayerProgress.record_story_beat("tutorial_step:" + str(step["id"]) + ":done",GameState.total_day)
	PlayerProgress.record_story_beat(CheckoutTutorial.BEAT_ID,GameState.total_day)
	PlayerProgress.record_story_beat(OpeningJourneyFlow.RAW_SALE,GameState.total_day)
	GameState.inventory.clear()
	check(VillageJournalFlow.available(),"completed core makes journal available")
	var request := ResidentRequestFlow.current()
	check(not request.is_empty() and ResidentRequestFlow.accept(request),"actual current resident request accepted")
	var id := "resident:" + str(request["id"])
	var item := str(request["item"])
	var required := int(request["amount"])
	check(find(id).get("requirements",[]).size() == 1,"accepted request exposes real required item")
	check(find("personal:" + str(PersonalRequestFlow.entries()[0]["id"])).is_empty(),"future personal quest excluded")
	check(director.try_interact(),"real journal modal opens")
	await frames()
	check(view.tabs.visible and view.history.visible and not view.preparation.visible,"existing journal opens on history")
	await click(view.preparation_button)
	check(view.showing_preparation and view.preparation.visible and not view.history.visible,"real click selects preparation page")
	var context := view.environment()
	var text := RequestPreparationData.information(world,find(id),context)
	check(text.contains(str(required) + "개 부족") and text.contains("숲") and text.contains("원정"),"missing current material has real expedition source")
	check(RequestItemSources.recipes(world,"bread",1).is_empty(),"unknown modern recipe source not leaked")
	await snap("material")
	GameState.add_item(item,required)
	var shelf = load("res://scenes/shop/warehouse/warehouse_storage.tscn").instantiate()
	world.get_node("WarehouseRoom/Objects").add_child(shelf)
	check(shelf.deposit_from_inventory(item,required) == required,"actual deposit moves quest stock")
	text = RequestPreparationData.information(world,find(id),context)
	check(text.contains("전달 가능 0") and text.contains("창고 선반") and text.contains("꺼낸 뒤"),"shelf stock never counted as delivery stock")
	check(not ResidentRequestFlow.can_deliver(request),"guide cannot bypass physical withdrawal")
	var isolated = load("res://scenes/shop/warehouse/warehouse_storage.tscn").instantiate()
	add_child(isolated)
	GameState.add_item(item,4)
	check(isolated.deposit_from_inventory(item,4) == 4,"other world's storage fixture")
	check(ProductPreparationData.shelf_count(world,item) == required,"other world storage excluded")
	isolated.queue_free()
	var preview = load("res://scenes/shop/warehouse/warehouse_storage.tscn").instantiate()
	preview.set_meta("is_build_preview",true)
	world.get_node("WarehouseRoom/Objects").add_child(preview)
	GameState.add_item(item,3)
	check(preview.deposit_from_inventory(item,3) == 3,"preview storage fixture")
	check(ProductPreparationData.shelf_count(world,item) == required,"building preview stock excluded")
	preview.queue_free()
	var saved_inventory := GameState.inventory.duplicate(true)
	var saved_progress := PlayerProgress.to_save_data().duplicate(true)
	var saved_money := GameState.money
	var saved_storage: Dictionary = shelf.stored_items.duplicate(true)
	for i in range(3):
		view.refresh()
		view.select(false)
		view.select(true)
	check(GameState.inventory == saved_inventory and PlayerProgress.to_save_data() == saved_progress and GameState.money == saved_money and shelf.stored_items == saved_storage,"browsing cannot consume, grant rewards, finish quests or withdraw stock")
	check(shelf.withdraw_slot_to_inventory(shelf.find_item_slot(item),required) == required,"actual withdrawal restores stock")
	check(ResidentRequestFlow.can_deliver(request),"original delivery gate opens after withdrawal")
	check(not ResidentRequestFlow.deliver(request).is_empty(),"actual original delivery succeeds")
	check(find(id).is_empty(),"completed quest disappears from preparation")
	check(ResidentRequestFlow.deliver(request).is_empty(),"duplicate delivery remains blocked")
	view.refresh()
	check(not view.tabs.visible and not view.showing_preparation and view.history.visible,"empty list returns to history and hides preparation tab")
	PlayerProgress.record_story_beat(CraftingPathFlow.key("craft_trail_food","accepted"),GameState.total_day)
	PlayerProgress.learn_recipe("camp_bread")
	PlayerProgress.learn_recipe("dried_fruit")
	var craft := find(CraftingPathFlow.JOURNAL_PREFIX + "craft_trail_food")
	check(craft.get("requirements",[]).size() == 2,"known prototype items shown")
	text = RequestPreparationData.information(world,craft,context)
	check(text.contains("실제로 제작") and text.contains("수령"),"owned prototype quantity does not substitute for actual production")
	var recipe := ProductRecipeData.get_recipe("camp_bread")
	var missing := int(recipe["result_amount"]) + 1
	var batches := ceili(float(missing) / int(recipe["result_amount"]))
	var ingredient_totals := ProductionRecipeService.collect_required_ingredients(recipe,batches)
	var source := "\n".join(RequestItemSources.recipes(world,"camp_bread",missing))
	check(source.contains(str(batches) + "회분"),"recipe quantity rounded up by real output amount")
	for ingredient in ingredient_totals:
		check(source.contains("%s %d개" % [ItemData.get_item_name(str(ingredient)),ingredient_totals[ingredient]]),"real ingredients multiplied by required batches")
	PlayerProgress.record_story_beat(CraftingPathFlow.key("craft_trail_food","done"),GameState.total_day)
	FishingRecords.mark("fishing_intro:accepted")
	FishingRecords.mark("fishing_intro:done")
	PlayerProgress.record_story_beat(ResidentRequestFlow.PREFIX + "gatherer_herbs:done",GameState.total_day)
	FishingRecords.mark("fish_request_neighbor:accepted")
	FishingRecords.mark("catch")
	FishingRecords.caught("fish_stream_minnow")
	FishingRecords.caught("fish_stone_crucian")
	GameState.add_item("fish_stream_minnow",1)
	GameState.add_item("fish_stone_crucian",1)
	var fish_request := find("fishing:fish_request_neighbor")
	check(not fish_request.is_empty(),"accepted fishing request included")
	text = RequestPreparationData.information(world,fish_request,context)
	check(text.contains("한 종류 2개") and text.contains("모두 준비할 필요") and text.count("전달 가능 1 / 필요 2") == 2,"alternative group not summed across species or treated as all required")
	check(not text.contains(ItemData.get_item_name("fish_moon_carp")),"undiscovered rare fish not leaked in group")
	check(not FishingService.consume(FishingData.entry("fish_request_neighbor")["items"],{"fish_any_fresh":"fish_stream_minnow"}),"split stock cannot satisfy single selected species")
	check(PreservationService.install("freezer",true),"actual freezer installed")
	check(PreservationService.deposit("freezer","fish_stream_minnow",1) == 1,"actual fish stored in freezer")
	text = RequestPreparationData.information(world,fish_request,context)
	check(text.contains("냉동 보관 1개") and text.contains("전달 가능 0"),"frozen stock must be physically withdrawn")
	await snap("fish-stock")
	var spring := {"day":1,"hour":12.0,"season":"spring","weather":"clear"}
	var winter := {"day":85,"hour":12.0,"season":"winter","weather":"clear"}
	var winter_fish := ""
	for fish in FishingData.entries("fish"):
		if fish["seasons"] == ["winter"] and fish["locations"].has("fish_bank"): winter_fish = str(fish["id"]); break
	check(not winter_fish.is_empty(),"winter fish fixture has available basic bank")
	var off_season := "\n".join(RequestItemSources.fishing(winter_fish,spring))
	check(off_season.contains("겨울") and off_season.contains("기다려야"),"out of season fish gives waiting advice")
	check(not RequestItemSources.fishing(winter_fish,winter).is_empty() and not "\n".join(RequestItemSources.fishing(winter_fish,winter)).contains("기다려야"),"current fish pool recognized when season matches")
	check(not "\n".join(RequestItemSources.fishing("fish_snow_trout",winter)).contains("숲 연못"),"locked fishing spot not leaked")
	check("\n".join(RequestItemSources.expedition("winter_frost",spring)).contains("기다려야"),"seasonal expedition source waits for actual condition")
	var snapshot := PlayerProgress.to_save_data().duplicate(true)
	var before_rows := RequestPreparationData.entries().duplicate(true)
	PlayerProgress.reset()
	PlayerProgress.load_save_data(snapshot)
	check(RequestPreparationData.entries() == before_rows,"preparation restored solely from existing story save data")
	# A finished previous repeat must not suppress its active next cycle.
	var expansion_id := ""
	for event in VillageExpansionFlow.SETTINGS.events:
		for step_index in range(event["steps"].size()):
			if event["steps"][step_index].get("requirements",[]).is_empty(): continue
			expansion_id = str(event["id"])
			PlayerProgress.story_beat_days[VillageExpansionFlow.key(expansion_id,"active")] = 2
			PlayerProgress.story_beat_days[VillageExpansionFlow.key(expansion_id,"last_done")] = 1
			PlayerProgress.story_beat_days[VillageExpansionFlow.key(expansion_id,"step",2)] = step_index
			break
		if not expansion_id.is_empty(): break
	check(not find(VillageExpansionFlow.JOURNAL_PREFIX + expansion_id).is_empty(),"active repeat shows current needs after past completion")
	PlayerProgress.story_beat_days[VillageExpansionFlow.key(expansion_id,"step",2)] = 999
	check(find(VillageExpansionFlow.JOURNAL_PREFIX + expansion_id).is_empty(),"unknown/finished story step cannot expose future requirements")
	FishingRecords.mark("fish_request_neighbor:done")
	GameState.add_item("fish_grilled",1)
	FishingRecords.mark("fish_request_worker:accepted")
	var goods_rule: Dictionary = FoodShelfLife.rules()["fish_grilled"]
	GameState.total_day += int(goods_rule["days"]) + 1
	text = RequestPreparationData.information(world,find("fishing:fish_request_worker"),view.environment())
	check(GameState.get_item_count("fish_grilled") == 0 and text.contains("전달 가능 0"),"expired food excluded by existing freshness rules")
	view.refresh()
	view.select(true)
	await snap("recipe")
	# The close button must remain on screen even with many long cards.
	await frames()
	check(panel.close_button.get_global_rect().end.y <= get_viewport().get_visible_rect().size.y,"close button stays inside viewport")
	check(view.preparation.get_global_rect().end.y <= panel.close_button.get_global_rect().position.y,"long content scrolls above close button")
	var before_close: bool = manager.hour_timer.paused
	check(before_close,"existing journal keeps clock paused while preparing")
	await click(panel.close_button)
	check(not director.open and not panel.root.visible and not world.get_meta("village_journal_open",false),"closing preparation releases original modal")
	check(not manager.hour_timer.paused,"original clock state restored")
	print("CHECK_REQUEST_PREPARATION checks=",checks," failures=",failures)
	get_tree().quit(0 if failures == 0 else 1)
