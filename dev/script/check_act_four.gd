extends Node
const F = preload("res://script/world/shop/requests/act_four_flow.gd")
const ResultService = preload("res://script/expedition/services/expedition_result_service.gd")
const Tools = preload("res://dev/gemini/request_text_tools.gd")
var checks := 0
var failures := 0
var world
var director
var manager
var life
var original: Array[Dictionary]
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("FAIL: " + message)
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("run")
func place_basics(shop) -> void:
	# 새 게임은 문만 놓인 채 시작하므로(부서진 가게) 이 검사에 필요한 계산대·진열대를 놓아 둔다.
	var layout: Array[Dictionary] = [
		{"build_id":"door", "anchor":Vector2i(0,4), "rotation_index":3},
		{"build_id":"register", "anchor":Vector2i(4,3), "rotation_index":0},
		{"build_id":"shelf_1x1", "anchor":Vector2i(2,2), "rotation_index":0}]
	shop.get_node("BuildManager")._restore_current_area_layout(layout)
func frames(count: int = 6) -> void:
	for i in range(count): await get_tree().process_frame
func saved() -> void:
	var data := PlayerProgress.to_save_data().duplicate(true)
	PlayerProgress.reset()
	PlayerProgress.load_save_data(data)
func drain() -> void:
	for i in range(100):
		if not director.dialogue.open: return
		director.dialogue._advance()
	check(false,"dialogue finishes")
func complete_step(id: String) -> void:
	var current := F.step(id)
	check(F.complete(current),"complete actual ready step " + str(current.get("id",id)))
	check(not F.complete(current),"stale action cannot complete twice")
func neighbors() -> void:
	for entry in VillageLifeFlow.entries(): PlayerProgress.record_story_beat(VillageLifeFlow.PREFIX + "greeted:" + str(entry["id"]),GameState.total_day)
func prerequisites() -> void:
	for step in TutorialDirector.SETTINGS.steps: PlayerProgress.record_story_beat("tutorial_step:" + str(step["id"]) + ":done",1)
	PlayerProgress.record_story_beat(CheckoutTutorial.BEAT_ID,1)
	for entry in VillageLifeFlow.SETTINGS.residents: PlayerProgress.record_story_beat(ResidentRequestFlow.PREFIX + str(entry["request"]) + ":done",1)
	PlayerProgress.record_story_beat(VillageExpansionFlow.key("chapter_winter_lights","last_done"),85)
	PlayerProgress.record_story_beat(VillageRestFlow.PREFIX + "done",80)
	PlayerProgress.record_story_beat(CommunityRequestFlow.PREFIX + VillageRestFlow.SETTINGS.preparation + ":done",79)
	PlayerProgress.record_story_beat(LanternWayfarerFlow.PREFIX + "done",80)
	PlayerProgress.record_story_beat(PowerRepairFlow.PREFIX + "restored",80)
	neighbors()
	VillageSettlement.apply_world(world)
	life.refresh()
func blank_economics() -> void:
	for entry in F.SETTINGS.events:
		for field in ["money","reputation","minimum_reputation","minimum_ruins"]:
			if entry.has(field): entry[field] = null
		for current in entry["steps"]:
			for field in ["requirements","furniture","sales"]:
				for requirement in current.get(field,[]): requirement["amount"] = null
func configure_fixture() -> void:
	# 검증 전용 수치. 실제 .tres에 저장하거나 플레이어 저장에 넣지 않는다.
	for entry in F.SETTINGS.events:
		for field in ["money","reputation","minimum_reputation","minimum_ruins"]:
			if entry.has(field) and entry[field] == null: entry[field] = 0 if field != "money" else 10
		for current in entry["steps"]:
			for field in ["requirements","furniture","sales"]:
				for requirement in current.get(field,[]):
					if requirement.get("amount") == null: requirement["amount"] = 1
func checkout(item: String, type_id: String) -> void:
	var shelf = get_tree().get_nodes_in_group("shelf")[0]
	GameState.add_item(item,1)
	shelf.slots[0]["item_id"] = item
	FoodShelfLife.restock_slot(shelf,0,1)
	var buyer = load("res://scenes/shop/actors/customer.tscn").instantiate()
	world.get_node("Actors").add_child(buyer)
	buyer.set_physics_process(false)
	buyer.customer_type_id = type_id
	buyer.customer_group_id = CustomerTypeData.get_group_id(type_id)
	buyer.carried_item_id = item
	buyer.carried_amount = shelf.take_items_by_id(item,1)
	FoodShelfLife.capture(buyer,shelf)
	buyer.checkout_item()
	check(buyer.purchase_completed,"real customer payment " + item)
	buyer.checkout_item()
	buyer.queue_free()
func settle(region: String, explored: bool = true) -> void:
	var bag := ExpeditionBag.new()
	check(bag.add_item("worn_coin",Vector2i(0,0),1) >= 0 and bag.add_item("rune_stone",Vector2i(1,0),1) >= 0,"real expedition loot bag")
	var result: Dictionary = ResultService.new().deposit_items(bag,{"region":region,"explored":explored})
	check(result["success"],"successful expedition settlement")
func run() -> void:
	original = []
	for source in F.SETTINGS.events: original.append(source.duplicate(true))  # 형식 있는 배열의 duplicate(true)는 안쪽 사전을 복사하지 않으므로 하나씩 깊게 복사한다
	blank_economics()  # 아래 검증은 "수치 미정" 상태에서 시작한다(실제 수치는 맨 끝에서 따로 검사)
	GameState.initialize_new_game()
	world = load("res://scenes/shop/main.tscn").instantiate()
	add_child(world)
	await frames()
	place_basics(world)
	await frames()
	manager = world.get_node("DayManager")
	life = world.get_node("VillageLifeDirector")
	director = life.get_node("ActFourDirector")
	manager.hour_timer.stop()
	manager.customer_spawner.set_process(false)
	manager.customer_spawner.spawn_timer.stop()
	world.get_node("Actors/Player").set_physics_process(false)
	var tutorial = world.get_node("TutorialDirector")
	tutorial.dialogue.close()
	tutorial.enabled = false
	tutorial.set_process(false)
	life.set_process(false)
	director.set_process(false)
	var book = manager.management_menu
	check(F.SETTINGS.events.size() == 11 and F.SETTINGS.milestones.size() == 5,"11 stories and five derived milestones")
	book.select_info_tab(ManagementMenu.InfoTab.BASIC)
	check(not F.started() and not (book.get_meta("act4_button") as Button).visible,"hidden before act four")
	check(not F.accept("a1_road_sign") and F.clues().is_empty(),"no early acceptance or spoilers")
	check(not ResidentRequestFlow.customer_available("road_wayfarer") and not ResidentRequestFlow.customer_available("road_caravan"),"new customer types stay locked initially")
	check(ActorLooks.customer_key("road_caravan") == ActorLooks.customer_key("peddler"),"new caravan uses existing 3D merchant appearance")
	GameState.total_day = 113
	prerequisites()
	check(F.started() and not F.configuration_issues("a1_road_sign").is_empty() and not F.accept("a1_road_sign"),"unset economic quantities do not become free completion")
	configure_fixture()
	for entry in F.SETTINGS.events: check(F.configuration_issues(str(entry["id"])).is_empty(),"configured fixture valid " + str(entry["id"]))
	check(F.accept("a1_road_sign") and not F.accept("a1_road_sign"),"single acceptance")
	saved()
	check(F.accepted("a1_road_sign"),"save retains accepted cycle")
	director.refresh()
	world.get_node("Actors/Player").global_position = life.residents["naru"].global_position
	check(world.get_node("WorldInteractions").try_interact() and director.talking,"actual E opens intro")
	director.dialogue.close()
	check(F.step("a1_road_sign")["index"] == 0 and not manager.hour_timer.paused,"cancel restores timer and preserves intro")
	check(director.try_interact(),"reopen intro")
	drain()
	check(F.step("a1_road_sign")["index"] == 1 and F.milestone_count() == 0,"full introduction does not award milestone")
	check(not F.complete(F.step("a1_road_sign")),"missing materials cannot advance")
	GameState.add_item("dry_branch",1)
	GameState.add_item("stone_shard",1)
	var money := GameState.money
	complete_step("a1_road_sign")
	check(F.milestone_count() == 0 and GameState.money == money,"delivery alone no reward or milestone")
	check(not F.complete(F.step("a1_road_sign")),"next day enforced")
	GameState.total_day += 1
	neighbors()
	complete_step("a1_road_sign")
	check(F.milestone_count() == 1 and GameState.money == money + 10 and ResidentRequestFlow.customer_available("road_wayfarer"),"final day awards configured reward once and unlocks wayfarer")
	check(not F.accept("a2_far_caravan"),"caravan opens next day")
	GameState.total_day += 1
	check(F.accept("a2_far_caravan"),"caravan starts")
	complete_step("a2_far_caravan")
	director.refresh()
	check(is_instance_valid(director.visitors.get("caravan")),"caravan representative physically visits after acceptance")
	GameState.add_item("raw_water",1)
	var stocked_shelf = get_tree().get_nodes_in_group("shelf")[0]
	stocked_shelf.slots[0]["item_id"] = "raw_water"
	FoodShelfLife.restock_slot(stocked_shelf,0,1)
	var first_caravan = load("res://scenes/shop/actors/customer.tscn").instantiate()
	world.get_node("Actors").add_child(first_caravan)
	first_caravan.set_physics_process(false)
	check(not ActFourVisits.prepare(first_caravan,"archer"),"first caravan does not replace another resident introduction")
	check(ActFourVisits.prepare(first_caravan,"") and first_caravan.customer_type_id == "road_caravan" and first_caravan.choose_wanted_item() == "raw_water","stocked quest goods bring actual buying caravan")
	check(not ActFourVisits.prepare(first_caravan,""),"at most one invited caravan per day")
	first_caravan.queue_free()
	checkout("raw_water","villager")
	check(not F.step_reason("a2_far_caravan").is_empty(),"other customer does not count as caravan")
	checkout("raw_water","road_caravan")
	checkout("wild_berry","road_caravan")
	complete_step("a2_far_caravan")
	GameState.total_day += 1
	complete_step("a2_far_caravan")
	check(F.milestone_count() == 2 and ResidentRequestFlow.customer_available("road_caravan"),"actual sales and final dialogue unlock caravan pool")
	check(F.accept("a3_traveler_rest"),"rest starts without ruins branch")
	complete_step("a3_traveler_rest")
	GameState.add_furniture("wood_warehouse_rack",1)
	GameState.add_item("dry_branch",1)
	check(not F.complete(F.step("a3_traveler_rest")),"owned furniture alone is not post-intro crafting")
	PlayerProgress.record_story_beat("shop_space:warehouse",GameState.total_day)  # 새 게임은 창고 공간을 연 뒤에야 창고 선반을 만들 수 있다(ShopSpaceProgression)
	var recipe := FurnitureRecipeData.get_recipe("wood_warehouse_rack")
	for ingredient in recipe["ingredients"]: GameState.add_item(str(ingredient["item_id"]),int(ingredient["amount"]))
	check(FurnitureObjectCatalog.craft("wood_warehouse_rack"),"actual material-consuming furniture craft")
	complete_step("a3_traveler_rest")
	GameState.total_day += 1
	complete_step("a3_traveler_rest")
	check(F.milestone_count() == 3,"rest final advances third milestone")
	manager.current_hour = LanternWayfarerFlow.SETTINGS.start_hour
	director.refresh()
	check(is_instance_valid(director.visitors.get("traveler")),"evening traveler physically appears at completed rest")
	var traveler = director.visitors.get("traveler")
	if is_instance_valid(traveler):
		for other in get_tree().get_nodes_in_group("story_npc"):
			if other != traveler and not other.is_queued_for_deletion(): check(traveler.global_position.distance_to(other.global_position) >= VillageExpansionFlow.SETTINGS.visitor_spacing,"rest visitor does not overlap existing story NPC")
	check(F.accept("a4_on_the_map"),"map starts")
	complete_step("a4_on_the_map")
	GameState.total_day += 1
	complete_step("a4_on_the_map")
	check(F.milestone_count() == 3,"milestone four needs map and first order")
	check(F.accept("a5_regular_order"),"new distant order starts")
	complete_step("a5_regular_order")
	GameState.add_item("camp_bread",1)
	GameState.add_item("dried_fruit",1)
	complete_step("a5_regular_order")
	GameState.total_day += 1
	complete_step("a5_regular_order")
	var order_day := GameState.total_day
	check(F.milestone_count() == 4 and not F.accept("a5_regular_order"),"first order completes fourth milestone and rests")
	GameState.total_day = order_day + 6
	check(not F.accept("a5_regular_order"),"six days insufficient")
	GameState.total_day += 1
	check(F.accept("a5_regular_order"),"weekly repeat available")
	check(not F.accept("a6_crossroad_market"),"first market waits for season change")
	GameState.total_day = 149
	check(F.accept("a6_crossroad_market"),"changed-season market window starts")
	complete_step("a6_crossroad_market")
	checkout("wild_berry","villager")
	checkout("camp_bread","villager")
	complete_step("a6_crossroad_market")
	GameState.total_day += 1
	complete_step("a6_crossroad_market")
	complete_step("a6_crossroad_market")
	check(F.milestone_count() == 4,"three afterglows must all finish")
	complete_step("a6_crossroad_market")
	check(F.milestone_count() == 5 and F.clues().is_empty() and not F.accept("a6_crossroad_market"),"A completed independently without B and no same season repeat")
	saved()
	check(F.milestone_count() == 5,"derived milestones survive save reload")
	settle("forest")
	settle("ruins",false)
	check(not ActFourRecords.found("worn_coin") and ActFourRecords.ruins_runs() == 0,"wrong region and immediate retreat do not count")
	settle("ruins")
	check(ActFourRecords.found("worn_coin") and ActFourRecords.found("rune_stone") and ActFourRecords.ruins_runs() == 1,"real ruins return records item source")
	saved()
	settle("ruins")
	check(ActFourRecords.ruins_runs() == 1,"same run settlement retry and save reload do not inflate ruins count")
	for id in ["b1_old_coin","b2_rune_and_power"]:
		check(F.accept(id),"discovered optional clue starts " + id)
		complete_step(id)
		var before := GameState.inventory.duplicate(true)
		complete_step(id)
		check(GameState.inventory == before,"showing relic does not consume")
		GameState.total_day += 1
		complete_step(id)
	check(F.clues().size() == 2,"only finished clues revealed")
	var merchant = world.get_node("SecretMerchantDirector")
	merchant.spawn_merchant()
	merchant.spawn_merchant()
	check(ActFourRecords.merchant_visits() == 1 and not F.accept("b3_secret_merchant"),"same merchant visit does not increment twice")
	merchant._dismiss_merchant()
	GameState.total_day += 1
	merchant.spawn_merchant()
	check(F.accept("b3_secret_merchant"),"second actual merchant visit opens clue")
	world.get_node("Actors/Player").global_position = merchant.active_npc.global_position
	var interact := InputEventAction.new()
	interact.action = "interact"
	interact.pressed = true
	merchant._unhandled_input(interact)
	check(director.talking and not merchant.shopping,"merchant real E handler prioritizes first clue dialogue")
	drain()
	check(F.step("b3_secret_merchant").get("map_purchase",false),"merchant intro full read advances to purchase")
	merchant._unhandled_input(interact)
	check(merchant.shopping and merchant.panel.open and not director.talking,"purchase waiting releases E to actual merchant sales panel")
	var offer := {"item_id":"treasure_map","price":2500,"stock":1}
	GameState.money = 0
	merchant.panel._on_buy_pressed(offer)
	check(not F.step_reason("b3_secret_merchant").is_empty() and offer["stock"] == 1,"failed purchase no progression")
	GameState.money = 2500
	merchant.panel._on_buy_pressed(offer)
	check(GameState.money == 0 and GameState.get_item_count("treasure_map") > 0 and offer["stock"] == 0,"real map purchase preserves original payment")
	merchant.panel.close()
	merchant._unhandled_input(interact)
	check(director.talking and not merchant.shopping,"after actual map purchase E opens merchant clue")
	drain()
	check(F.step("b3_secret_merchant").get("wait_days",0) == 1,"full merchant clue waits until next day")
	GameState.total_day += 1
	complete_step("b3_secret_merchant")
	check(F.accept("b4_blank_of_map"),"map blank starts")
	complete_step("b4_blank_of_map")
	check(not F.complete(F.step("b4_blank_of_map")),"previous ruins trips do not satisfy new request")
	settle("ruins")
	complete_step("b4_blank_of_map")
	GameState.total_day += 1
	complete_step("b4_blank_of_map")
	check(F.accept("b5_question_stays"),"last question after year and four clues")
	complete_step("b5_question_stays")
	GameState.total_day += 1
	complete_step("b5_question_stays")
	complete_step("b5_question_stays")
	check(F.clues().size() == 5 and F.milestone_count() == 5,"B five questions do not grant extra milestones")
	saved()
	book.open_menu(ManagementMenu.MenuTab.HISTORY)
	book.select_info_tab(ManagementMenu.InfoTab.MILESTONES)
	await frames(20)
	check((book.get_meta("act4_button") as Button).visible and book.history_list.get_child_count() == 2,"book has visible subtab and two pages")
	var left: Control = book.history_list.get_child(0)
	var right: Control = book.history_list.get_child(1)
	check(left.position.x < right.position.x and right.position.x >= left.size.x + BookLayout.GUTTER - 1,"pages respect real book viewport and gutter")
	check(left.size.x <= (book.history_list.size.x - BookLayout.GUTTER) * 0.5 + 1 and right.position.x + right.size.x <= book.history_list.size.x + 1,"text stays in both page widths")
	book.refresh_schedule()
	var market_found := false
	for section in book.schedule_list.get_children():
		for part in section.get_children():
			if part is Label and part.text.contains("길이 모이는 날"): market_found = true
	check(market_found,"calendar records future seasonal markets (village journal section comes first)")
	var view = world.get_node("StoreView3D")
	ActFourDecor3D.sync(view)
	check(view._items.has("act4_sign_face") and view._items.has("act4_rest_rack"),"actual 3D progress sign and delivered rack visible")
	var args := OS.get_cmdline_user_args()
	for i in range(args.size() - 1):
		if args[i] == "--shot" and DisplayServer.get_name() != "headless":
			await get_tree().create_timer(1.2,true).timeout
			await RenderingServer.frame_post_draw
			check(get_viewport().get_texture().get_image().save_png(args[i + 1]) == OK,"save actual book screenshot")
	book.visible = false
	get_tree().paused = false
	var prose := Tools.validate_file(Tools.TEXT_PATH,Tools.load_sources())
	check(prose["errors"].is_empty() and prose["warns"].is_empty(),"all prose passes strict rules " + str(prose))
	var settings: Resource = F.SETTINGS
	settings.set("events",original)
	# 실제 설정(Claude 가 채운 수치): 파일을 새로 읽어 모든 수치가 정수로 채워져 있고, 보상이 기존 사건 규모(제품 가치 + 소액)를 넘지 않는지
	var real: Resource = ResourceLoader.load("res://scenes/shop/requests/default_act_four.tres","",ResourceLoader.CACHE_MODE_IGNORE)
	for entry in real.events:
		var id := str(entry["id"])
		for field in ["money","reputation","minimum_reputation","minimum_ruins"]:
			if entry.has(field): check(entry[field] is int and int(entry[field]) >= 0,"real settings filled " + id + ":" + field)
		for current in entry["steps"]:
			for field in ["requirements","furniture","sales"]:
				for requirement in current.get(field,[]): check(requirement.get("amount") is int and int(requirement["amount"]) > 0,"real amount filled " + id + ":" + str(requirement.get("item")))
		if entry["branch"] == "B": check(not entry.has("money") and not entry.has("reputation"),"B clue stories have no economic reward " + id)
		elif entry.has("money"): check(int(entry["money"]) <= 600 and int(entry["reputation"]) == 1,"A reward within existing scale " + id)
	PlayerProgress.reset()
	book.select_info_tab(ManagementMenu.InfoTab.MILESTONES)
	check(not F.started() and F.milestone_count() == 0 and F.clues().is_empty() and book.current_info_tab == ManagementMenu.InfoTab.BASIC,"new game resets progress and falls back from hidden tab")
	world.queue_free()
	await frames()
	print("CHECK_ACT_FOUR checks=",checks," failures=",failures)
	get_tree().quit(0 if failures == 0 else 1)
