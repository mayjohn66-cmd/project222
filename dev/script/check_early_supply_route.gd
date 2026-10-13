extends "res://dev/script/check_gathering_tool_access.gd"
## Integration starts after the separately tested opening checkout/expedition.
## Materials come from real loot/gathering and settlement; no injected money.
func harvest(table: String, item: String, needed: int, tool_bag: ExpeditionBag = null) -> void:
	var loot = load("res://script/expedition/services/expedition_loot_service.gd").new()
	loot.environment = ExpeditionEnvironment.capture()
	var gathering := ExpeditionGatheringService.new()
	var collected := 0
	for attempt in range(100):
		if GameState.get_item_count(item) >= needed: break
		var bag := ExpeditionBag.new() if tool_bag == null else tool_bag
		var result := gathering.resolve_gathering(table,bag,loot)
		if not result.get("handled",false): result = loot.roll_loot_table(table)
		if not result.get("success",false) or result.get("gathered",true) == false: continue
		var id := str(result["item_id"])
		var count := int(result["amount"])
		var cell := Vector2i(0,0) if tool_bag == null else Vector2i(5,3)
		if bag.add_item(id,cell,count) < 0: continue
		var settlement = load("res://script/expedition/services/expedition_result_service.gd").new().deposit_items(bag)
		if settlement["success"]: collected += count
	check(GameState.get_item_count(item) >= needed,"actual loot and return can supply " + item)

func interact_request(director) -> void:
	# 영업 중에는 주민이 손님으로 입장해 부탁을 건네므로(QuestVisitDirector) 서 있는 NPC는 영업 전·후에만 있다.
	# 이 시험은 서 있는 NPC와의 대화를 확인하므로 그 사이만 영업을 닫아 둔다.
	var day = world.get_node("DayManager")
	var was_open: bool = day.shop_open
	day.shop_open = false
	director.refresh()
	var player = world.get_node("Actors/Player")
	if not is_instance_valid(director.npc):
		day.shop_open = was_open
		check(false,"current NPC exists"); return
	player.global_position = director.npc.global_position + Vector2(20,0)
	check(director.try_interact(),"actual NPC interaction")
	drain(director.dialogue)
	day.shop_open = was_open

func click_book(button: Button, menu: ManagementMenu) -> void:
	var parent := button.get_parent()
	while parent != null and not parent is ScrollContainer: parent = parent.get_parent()
	if parent is ScrollContainer: parent.ensure_control_visible(button)
	await frames()
	var position := button.get_global_rect().get_center()
	if menu.has_meta("book_stage") and is_instance_valid(menu.get_meta("book_stage")):
		position += menu.get_meta("book_stage")._offset
	for pressed in [true,false]:
		var event := InputEventMouseButton.new()
		event.position = position
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		get_viewport().push_input(event,true)
	await frames()

func run() -> void:
	RequestOfferPanel.auto_accept_for_test = true  # 주민 제안 확인창은 이 시험의 대상이 아니므로 바로 수락한다
	check(OS.get_user_data_dir().contains("foodbag_checks"),"isolated progression test project")
	if not OS.get_user_data_dir().contains("foodbag_checks"): get_tree().quit(1); return
	seed(8123)
	GameState.initialize_new_game()
	PlayerProgress.reset()
	check(EarlyProgressionGuide.waiting_text().is_empty(),"tutorial still owns opening guidance")
	# Completed tutorial is the starting fixture. Existing progressive tutorial
	# checks exercise cleanup, first real checkout, barter and raw-material sale.
	for step in TutorialDirector.SETTINGS.steps:
		if not step.get("optional",false): PlayerProgress.record_story_beat("tutorial_step:"+str(step["id"])+":done",GameState.total_day)
	GameState.inventory.clear()
	world = load("res://scenes/shop/main.tscn").instantiate()
	world.get_node("TutorialDirector").enabled = false
	add_child(world)
	await frames()
	var rebuilt: Array[Dictionary] = [
		{"build_id":"door","anchor":Vector2i(0,4),"rotation_index":3},
		{"build_id":"register","anchor":Vector2i(4,3),"rotation_index":0},
		{"build_id":"shelf_1x1","anchor":Vector2i(2,2),"rotation_index":0},
		{"build_id":"shelf_1x1","anchor":Vector2i(2,5),"rotation_index":0}]
	world.get_node("BuildManager")._restore_current_area_layout(rebuilt)
	await frames()
	var manager = world.get_node("DayManager")
	manager.hour_timer.stop()
	var spawner = manager.customer_spawner
	var player = world.get_node("Actors/Player")
	player.set_physics_process(false)
	var director = world.get_node("ResidentRequestDirector")
	check(GameState.get_money() == 0 and GameState.get_owned_equipment_instances().is_empty(),"route starts with no money or collection tools")
	check(EarlyProgressionGuide.waiting_text().is_empty(),"active first request keeps ordinary journal")
	for expected in ["neighbor_bread","gatherer_herbs"]:
		var request := ResidentRequestFlow.current()
		check(request.get("id") == expected,"tool-free request order " + expected)
		interact_request(director)
		harvest("forest_gather",str(request["item"]),int(request["amount"]))
		interact_request(director)
		check(ResidentRequestFlow.done(expected),"gathered material delivered to actual NPC")
	check(GameState.get_money() == 70,"two existing rewards yield 70 G, no injected money")
	check(ResidentRequestFlow.current().is_empty(),"merchant visit is an interlude")
	var note := VillageJournalFlow.information("next_request")
	check(note.contains("타블렌") and note.contains("가게를 열어") and not note.contains("지금까지의 주민 부탁"),"journal explains visit instead of claiming all requests complete")
	check(VillageJournalFlow.destination(world,"next_request") != null,"journal points to an actual entrance while waiting")
	var before := GameState.create_save_data().duplicate(true)
	for i in range(4): VillageJournalFlow.information("next_request"); VillageJournalFlow.destination(world,"next_request")
	check(GameState.create_save_data() == before,"guidance queries change no stock/money/story/save")
	manager.open_shop()
	spawner.spawn_timer.stop()
	var scale := Engine.time_scale
	Engine.time_scale = 15.0
	await spawner.spawn_customer()
	Engine.time_scale = scale
	check(ResidentStoryFlow.pending_introduction().get("type") == "peddler","real pedestrian enters and records merchant visit")
	interact_request(director)
	check(ResidentStoryFlow.introduction_read("peddler"),"actual reunion opens settlement request")
	check(ResidentRequestFlow.current().get("id") == "settle_naru","stall precedes premature water request")
	interact_request(director)
	harvest("forest_gather","dry_branch",4)
	interact_request(director)
	check(GameState.get_money() == 110,"three existing rewards fully fund 80 G bottle")
	VillageSettlement.apply_world(world)
	var life = world.get_node("VillageLifeDirector")
	life.refresh()
	await frames()
	director.refresh()
	check(VillageJournalFlow.information("next_request").contains("안부"),"journal identifies greeting interlude")
	check(VillageJournalFlow.destination(world,"next_request") == life.residents.get("naru"),"greeting points to settled NPC")
	player.global_position = life.residents["naru"].global_position + Vector2(20,0)
	check(world.get_node("WorldInteractions").try_interact() and life.talking,"real E greets merchant")
	drain(life.dialogue)
	var stall := VillageSettlement.find_site(world,ResidentTradeFlow.SETTINGS.site)
	check(VillageJournalFlow.destination(world,"next_request") == stall,"purchase interlude points to actual stall through 3D mirror")
	stall.visible = false
	check(EarlyProgressionGuide.destination(world) == null,"actually hidden locked/removed site is not a destination")
	stall.visible = true
	check(VillageJournalFlow.information("next_request").contains("80 G") and VillageJournalFlow.information("next_request").contains("110 G"),"purchase guide uses current prices and earned balance")
	var earned := GameState.get_money()
	GameState.spend_money(earned)
	check(VillageJournalFlow.information("next_request").contains("80 G 부족") and ResidentMerchantSupply.buy("gathering_bottle").is_empty(),"shortage gives sale recovery, never free tool")
	GameState.add_money(earned) # restore only the previously earned balance
	var journal = world.get_node("VillageJournalDirector")
	var menu = world.get_node("UI/ManagementMenu")
	menu.open_menu(ManagementMenu.MenuTab.SCHEDULE)
	await get_tree().create_timer(1.7,true).timeout
	await frames()
	# 일정 책에는 이제 행사 소식만 있고, 부탁은 부탁 수첩에서 "맡은 뒤에" 보인다(미수락 부탁은 적지 않는다).
	# 그래서 다음 목적지는 일정 책 카드 대신 목적지 API(VillageJournalFlow.destination)로 확인하고 표시/해제를 시험한다.
	var notice_texts: Array = menu.schedule_list.find_children("*","Label",true,false).map(func(l): return l.text)
	check(notice_texts.size() == 1 and str(notice_texts[0]).contains("행사"), "schedule book lists only event news, not stale request cards")
	check(VillageJournalFlow.destination(world,"next_request") != null, "journal still points to the next destination")
	check(journal.set_tracked("next_request") and journal.tracked_id == "next_request", "tracking the next destination works")
	for size in [Vector2i(1152,648),Vector2i(768,432)]:
		get_window().size = size
		await frames()
		var close_target: Control = menu.close_button
		if menu.has_meta("book_stage") and is_instance_valid(menu.get_meta("book_stage")): close_target = menu.get_meta("book_stage").hint
		check(get_viewport().get_visible_rect().encloses(close_target.get_global_rect()),"actual book close hint fits " + str(size))
		await snap("journal-"+str(size.x))
	menu.close_menu()
	await get_tree().create_timer(1.7,true).timeout
	await frames()
	check(not menu.visible,"book close animation restores world interactions")
	var trade = world.get_node("ResidentTradeDirector")
	player.global_position = stall.global_position + Vector2(60,0)
	check(world.get_node("WorldInteractions").try_interact() and trade.open,"real stall opens purchase")
	await click(trade.panel.cards["supply:gathering_bottle"]["action"])
	check(GameState.get_money() == 30 and GameState.get_owned_equipment_count("gathering_bottle") == 1,"button buys one tool using quest rewards only")
	trade.panel.close()
	check(ResidentRequestFlow.current().get("id") == "traveler_water","water now opens")
	var instruction := ExpeditionGatheringToolGuide.required_tool("gather_water")
	check(instruction.contains("이미 보유") and instruction.contains("가방에 넣으세요") and not instruction.contains("구매하고"),"owned tool guide asks packing instead of repurchase")
	var saved := GameState.create_save_data().duplicate(true)
	check(GameState.apply_save_data(saved) and ExpeditionGatheringToolGuide.required_tool("gather_water").contains("이미 보유"),"reload retains purchased-but-unpacked guidance")
	interact_request(director)
	world.queue_free()
	await frames()
	var expedition = load("res://scenes/expedition/expedition.tscn").instantiate()
	add_child(expedition)
	await frames()
	var prep = expedition.prep_panel
	prep.show_departure_choice()
	prep.map_content.region_buttons["forest"].pressed.emit()
	await frames()
	var bag = prep.bag_content
	var uid := -1
	for placement in bag._get_owned_model().placements:
		if placement["item_id"] == "gathering_bottle": uid = int(placement["uid"])
	check(uid > 0 and bag._transfer_owned_to_bag(uid,Vector2i(3,0)),"purchased bottle moves through actual bag UI")
	GameState.save_expedition_bag(bag.bag_model.placements)
	check(ExpeditionGatheringToolGuide.required_tool("gather_water").contains("준비되어"),"packed tool guide recognizes saved bag")
	harvest("gather_water","raw_water",2,bag.bag_model)
	var request := ResidentRequestFlow.current()
	var stock := GameState.get_item_count("raw_water")
	var result := ResidentRequestFlow.deliver(request)
	check(not result.is_empty() and GameState.get_item_count("raw_water") == stock-2 and GameState.get_money() == 60,"real gathered water pays exactly existing 30 G reward")
	check(ResidentRequestFlow.deliver(request).is_empty(),"water reward does not repeat")
	check(EarlyProgressionGuide.waiting_text().is_empty(),"finished route does not invent another purchase")
	check(GameState.apply_save_data(GameState.create_save_data()) and ResidentRequestFlow.done("traveler_water"),"finished request and tool survive reload")
	expedition.queue_free()
	await frames()
	print("CHECK_EARLY_SUPPLY_ROUTE checks=%d failures=%d" % [checks,failures])
	get_tree().quit(0 if failures == 0 else 1)
