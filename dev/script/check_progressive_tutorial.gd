extends Node
const Tools = preload("res://dev/gemini/request_text_tools.gd")
const Writer = preload("res://dev/gemini/request_text_runner.gd")
var checks := 0
var failures := 0
var world
var director: TutorialDirector
var player
var manager
var checkout: CheckoutTutorial

func check(ok: bool, text: String) -> void:
	checks += 1
	if ok: print("PASS: ", text)
	else:
		failures += 1
		push_error(text)

func drain(panel: StoryDialoguePanel) -> void:
	for i in range(80):
		if not panel.open: return
		panel._advance()
	check(false, "dialogue must terminate")

func advance_self() -> void:
	for i in range(8):
		director.refresh()
		if not director.dialogue.open: return
		drain(director.dialogue)

func stock(id: String, amount: int) -> void:
	var shelf = get_tree().get_nodes_in_group("shelf")[0]
	for slot in shelf.slots:
		if int(slot["stock"]) > 0: GameState.add_item(str(slot["item_id"]), int(slot["stock"]))
		slot["item_id"] = ""
		slot["stock"] = 0
	check(GameState.remove_item(id, amount) == amount, "stock consumes owned goods: " + id)
	shelf.slots[0]["item_id"] = id
	shelf.slots[0]["stock"] = amount
	shelf.update_visual()

func talk_merchant() -> void:
	director.refresh()
	check(is_instance_valid(director.npc), "merchant has an actual interactable visitor")
	if not is_instance_valid(director.npc): return
	player.global_position = director.npc.global_position
	check(world.get_node("WorldInteractions").try_interact(), "merchant interaction via E route")
	check(director.dialogue.name_label.text == "행상인 타블렌", "canonical merchant speaks")
	drain(director.dialogue)

func pay_visit() -> void:
	check(is_instance_valid(checkout.guide), "guaranteed actual customer arrives")
	if not is_instance_valid(checkout.guide): return
	drain(checkout.dialogue)
	check(checkout.stage == "checkout" and checkout.guide.carried_amount == 1, "buyer picked one real shelf item")
	drain(checkout.dialogue)
	player.global_position = world.get_node("BuildManager").get_cell_world_position(checkout.guide_cell)
	var cashier = world.get_node("ManualCheckoutController")
	check(cashier.try_interact(), "player can settle native buyer")
	cashier._process(2.0)
	check(checkout.guide.purchase_completed, "actual checkout finished")
	drain(checkout.dialogue)

func _ready() -> void: call_deferred("run")
func run() -> void:
	GameState.initialize_new_game()
	world = load("res://scenes/shop/main.tscn").instantiate()
	add_child(world)
	for i in range(4): await get_tree().process_frame
	director = world.get_node("TutorialDirector")
	director.set_process(false)
	manager = world.get_node("DayManager")
	manager.hour_timer.stop()
	manager.customer_spawner.set_process(false)
	checkout = world.get_node("CheckoutTutorial")
	checkout.set_process(false)
	player = world.get_node("Actors/Player")
	player.set_physics_process(false)
	check(player.money == 0 and GameState.get_item_count("bread") == 8 and GameState.get_item_count("water") == 6, "first money is earned; only carried shop food starts")
	check(PlayerProgress.story_beat_days.has(CraftingPathFlow.NEW_GAME) and not CraftingPathFlow.recipe_ready("bake_bread"), "genuine new game records the product evolution gate")
	check(GameState.get_item_count("potion") == 0 and GameState.get_item_count("iron_ore") == 0 and GameState.get_item_count("rusty_sword") == 0, "native supplies are not free starter stock")
	var no_staff := true
	for worker in get_tree().get_nodes_in_group("worker"):
		if worker.is_hired or worker.visible or worker.on_duty: no_staff = false
	check(no_staff, "no automatically hired staff at arrival")
	check(director.flow.current()["id"] == "cleanup" and not is_instance_valid(director.npc), "arrival starts with player alone")
	check(director.dialogue.open and director.dialogue.name_label.text == PlayerProgress.display_player_name(), "situation is player monologue")
	check(not director.flow.goal_met(director.flow.current(), world) and OpeningCleanup.cleaned_count() == 0, "shop starts smashed: nothing cleaned yet")
	check(GameState.get_furniture_count("door") == 0 and GameState.get_furniture_count("register") == 1 and GameState.get_furniture_count("shelf_1x1") == 1 and GameState.get_furniture_count("shelf_2x1") == 0 and GameState.get_furniture_count("shelf_3x1") == 0, "only the salvaged register and one shelf wait in storage")
	check(get_tree().get_nodes_in_group("shelf").is_empty(), "no shelf stands in the smashed shop")
	var layout := GameState.get_store_layout().duplicate(true)
	OpeningJourneyFlow.initialize(world)
	check(GameState.get_store_layout() == layout and GameState.get_furniture_count("door") == 0, "bootstrap cannot duplicate or replace store")
	director.dialogue.close()
	check(not director.flow.seen("cleanup"), "aborted monologue does not mark intro")
	advance_self()
	check(director.flow.current()["id"] == "cleanup" and director.flow.seen("cleanup"), "monologue then asks to clean the rubble")
	# 잔해 더미를 하나씩 [E]로 치운다: 서 있는 자리에서만, 한 번씩만 자재를 얻는다.
	player.global_position = director._cell_world(Vector2(0.5, 7.0))
	check(not director.try_interact() and OpeningCleanup.cleaned_count() == 0, "too far from rubble cleans nothing")
	for i in range(OpeningCleanup.PILES.size()):
		player.global_position = director._cell_world(OpeningCleanup.PILES[i]["stand"])
		check(director.try_interact() and OpeningCleanup.done(i), "E cleans rubble pile %d" % i)
	check(GameState.get_item_count("iron_ore") >= 2, "cleaning yields the iron ore for a simple shelf")
	var branches_after: int = GameState.get_item_count("iron_ore")
	player.global_position = director._cell_world(OpeningCleanup.PILES[0]["stand"])
	director.try_interact()
	check(GameState.get_item_count("iron_ore") == branches_after, "a cleaned pile gives nothing again")
	advance_self()
	check(director.flow.current()["id"] == "craft_shelf" and director.flow.seen("craft_shelf"), "cleaning leads to crafting a shelf")
	check(not director.flow.goal_met(director.flow.current(), world), "shelf is not crafted yet")
	check(FurnitureObjectCatalog.craft("shelf_1x1") and GameState.get_furniture_count("shelf_1x1") == 2, "crafting a simple shelf uses the gathered materials")
	advance_self()
	check(director.flow.current()["id"] == "setup" and director.flow.seen("setup"), "crafting leads to rebuilding the shop")
	check(not director.flow.goal_met(director.flow.current(), world), "register and shelf are not placed yet")
	# 건축 모드 대신 같은 복원 경로로 건진 계산대·진열대와 새 진열대를 놓는다.
	var rebuilt: Array[Dictionary] = [
		{"build_id":"door", "anchor":Vector2i(0,4), "rotation_index":3},
		{"build_id":"register", "anchor":Vector2i(4,3), "rotation_index":0},
		{"build_id":"shelf_1x1", "anchor":Vector2i(2,2), "rotation_index":0},
		{"build_id":"shelf_1x1", "anchor":Vector2i(2,5), "rotation_index":0}]
	world.get_node("BuildManager")._restore_current_area_layout(rebuilt)
	check(director.flow.goal_met(director.flow.current(), world), "placing register and shelf completes rebuilding")
	advance_self()
	check(director.flow.current()["id"] == "stock" and director.flow.seen("stock"), "situation leads to stocking")
	check(not director.flow.validate_gifts([{"kind":"item","id":"invalid","amount":1}]), "invalid gifts rejected before grants")
	stock("bread", 3)
	advance_self()
	check(director.flow.current()["id"] == "checkout" and not director.flow.seen("checkout"), "stock leads to first shop opening")
	manager.open_shop()
	check(checkout.dialogue.name_label.text == "델빈", "local buyer is not shop instructor")
	var money_before: int = player.money
	var bread_before: int = GameState.get_item_count("bread")
	pay_visit()
	check(player.money == money_before + ItemData.get_item_price("bread"), "first coin payment gives exactly actual item price")
	check(GameState.get_item_count("bread") == bread_before and GameState.get_item_count("rusty_sword") == 0, "first purchase does not gift food or equipment")
	advance_self()
	check(director.flow.current()["id"] == "barter", "actual first payment leads to wandering merchant")
	manager.close_shop_manually()
	manager.hour_timer.stop()
	talk_merchant()
	check(director.barter_panel.root.visible and director.flow.seen("barter"), "full offer opens explicit barter choice")
	for size in [Vector2i(1152,648), Vector2i(593,523), Vector2i(800,450)]:
		get_window().size = size
		for i in range(4): await get_tree().process_frame
		director.barter_panel._fit_screen()
		var area := get_viewport().get_visible_rect()
		check(area.encloses(director.barter_panel.close_button.get_global_rect()), "barter close remains visible at " + str(size))
		check(area.encloses(director.barter_panel.cards["arrival_barter"]["action"].get_global_rect()), "barter confirm remains visible at " + str(size))
	director.barter_panel.close()
	check(not OpeningJourneyFlow.traded() and not director.talking, "canceling barter spends nothing and restores control")
	var bread_owned: int = GameState.get_item_count("bread")
	GameState.remove_item("bread", bread_owned)
	check(not OpeningJourneyFlow.trade() and GameState.get_item_count("rusty_sword") == 0, "insufficient food cannot receive gear")
	GameState.add_item("bread", bread_owned)
	talk_merchant()
	money_before = player.money
	var water_owned: int = GameState.get_item_count("water")
	director.barter_panel.action_requested.emit("arrival_barter")
	check(OpeningJourneyFlow.traded() and GameState.get_item_count("bread") == bread_owned - 2 and GameState.get_item_count("water") == water_owned - 1, "barter spends exact real food")
	check(player.money == money_before and GameState.get_item_count("rusty_sword") == 1 and GameState.get_item_count("leather_armor") == 1, "barter grants native gear without coin charge")
	check(not OpeningJourneyFlow.trade(), "barter cannot repeat")
	var saved := GameState.create_save_data().duplicate(true)
	check(GameState.is_save_data_valid(saved) and GameState.apply_save_data(saved), "barter and pending progression survive real save roundtrip")
	check(OpeningJourneyFlow.traded() and not OpeningJourneyFlow.trade(), "reload cannot charge barter twice")
	drain(director.dialogue)
	advance_self()
	check(director.flow.current()["id"] == "expedition", "gear motivates exploration before crafting")
	check(not director.flow.goal_met(director.flow.current(),world), "unreturned expedition does not progress")
	PlayerProgress.record_expedition_completed()
	advance_self()
	check(director.flow.current()["id"] == "raw_sale" and GameState.get_furniture_count("magic_oven") == 0, "return leads to raw sale with no compulsory oven")
	manager.open_shop()
	check(not is_instance_valid(checkout.guide), "food on shelf does not substitute for native material")
	GameState.add_item("forest_herb",2)
	stock("forest_herb",2)
	check(not director.flow.goal_met(director.flow.current(),world), "stocking material alone is not a sale")
	checkout.try_start()
	check(checkout.material_visit and is_instance_valid(checkout.guide), "Delbin returns for actual native goods")
	drain(checkout.dialogue)
	drain(checkout.dialogue)
	manager.close_shop_manually()
	checkout._process(0.0)
	manager.hour_timer.stop()
	check(not PlayerProgress.story_beat_days.has(OpeningJourneyFlow.RAW_SALE), "unpaid material buyer cannot complete tutorial")
	check(get_tree().get_nodes_in_group("shelf")[0].get_item_stock("forest_herb") == 2, "closing returns unpaid native goods to shelf")
	await get_tree().process_frame
	manager.open_shop()
	check(is_instance_valid(checkout.guide) and checkout.material_visit, "interrupted material sale reliably resumes on reopening")
	money_before = player.money
	pay_visit()
	check(player.money == money_before + ItemData.get_item_price("forest_herb") and PlayerProgress.story_beat_days.has(OpeningJourneyFlow.RAW_SALE), "native material actual payment records completion")
	advance_self()
	check(director.flow.current().get("id") == "food_care" and ResidentRequestFlow.tutorial_finished() and not director.is_guiding(), "optional food care never locks resident flow")
	var cashier = world.get_node("ManualCheckoutController")
	var food_panel: RegisterDashboardPanel = cashier.food_cleanup
	check(cashier.try_interact() and food_panel.visible, "optional lesson opens at actual empty cashier station")
	check(get_tree().paused and not director.flow.goal_met(director.flow.current(),world), "food lesson waits for acknowledgment while world pauses")
	check(not food_panel.cleanup_page, "idle register starts with products instead of cleanup")
	food_panel.show_page(true)
	food_panel.confirmed.emit()
	check(not get_tree().paused, "returning from cleanup restores world processing")
	advance_self()
	check(director.flow.done("food_care") and director.flow.current().is_empty() and ResidentRequestFlow.tutorial_finished(), "read food-care panel completes optional guidance; production still waits")
	check(not director.flow.done("production"), "production remains a later option")
	for id in ["neighbor_bread", "traveler_water"]: PlayerProgress.record_story_beat(ResidentRequestFlow.PREFIX + id + ":done",1)
	PlayerProgress.record_story_beat(ResidentRequestFlow.PREFIX + "visited:peddler",1)
	var reunion := ResidentStoryFlow.pending_introduction()
	check(reunion.get("type", "") == "peddler" and reunion.get("lines", []) == RequestTextData.lines("service_text", "arrival_peddler_return"), "existing merchant intro becomes an actual reunion after barter")
	manager.close_shop_manually()
	manager.hour_timer.stop()
	PlayerProgress.record_story_beat(ResidentRequestFlow.PREFIX + "settle_naru:done",1)
	director.refresh()
	check(director.flow.current()["id"] == "production" and not director.is_guiding(), "first settlement makes crafting available without locking resident flow")
	talk_merchant()
	check(GameState.get_furniture_count("magic_oven") == 1 and GameState.get_item_count("scroll_camp_bread") == 1 and GameState.get_item_count("wheat") == 4, "later starter gifts are local goods only")
	check(not director.flow.goal_met(director.flow.current(),world), "owned bread is not proof of production")
	var facility = load("res://scenes/shop/production/production_facility.tscn").instantiate()
	world.get_node("Objects").add_child(facility)
	director.refresh()
	facility.configure_facility("magic_oven")
	facility.pending_item_id = "camp_bread"
	facility.pending_amount = 1
	facility.production_state = ProductionFacility.ProductionState.READY
	check(facility.collect_production(), "real output collected")
	talk_merchant()
	check(director.flow.current().is_empty(), "optional crafting ends on collected output")
	var sources := Tools.load_sources()
	check(sources[Tools.KIND_TUTORIAL_STEP].size() == 10 and sources[Tools.KIND_TUTORIAL_DIALOGUE].size() == 6, "all revised tutorial prose registered in story tool")
	check(sources[Tools.KIND_SERVICE_TEXT].has("arrival_peddler_return"), "merchant reunion registered for prose drafting")
	var step_prompt := Writer.build_prompt(Tools.KIND_TUTORIAL_STEP, sources, sources)
	check(step_prompt.contains("플레이어 독백") and step_prompt.contains("현대 기기는 플레이어만 이해"), "Gemini receives player monologue and modern-knowledge boundary")
	var buyer_prompt := Writer.build_prompt(Tools.KIND_TUTORIAL_DIALOGUE, sources, sources)
	check(buyer_prompt.contains("초반 현지 손님의 실제 구매") and buyer_prompt.contains("원정 원재료를 다시 구매"), "Gemini receives real first and return purchases")
	check(Tools.load_voices().get("setup", {}).get("name") == "플레이어 독백", "new scene voice overrides previous guide voice")
	PlayerProgress.reset()
	for id in ["setup","stock","checkout","expedition","production"]: PlayerProgress.record_story_beat("tutorial_step:" + id + ":done",1)
	check(ResidentRequestFlow.tutorial_finished() and director.flow.current().is_empty(), "old completed tutorial save does not replay new barter")
	PlayerProgress.story_beat_days.erase("tutorial_step:production:done")
	PlayerProgress.record_story_beat("tutorial_step:production:intro",1)
	check(ResidentRequestFlow.tutorial_finished() and director.flow.current().get("id") == "production", "old crafting-stage save resumes without new intro")
	var protected_layout := GameState.get_store_layout().duplicate(true)
	var protected_money: int = player.money
	OpeningJourneyFlow.initialize(world)
	check(GameState.get_store_layout() == protected_layout and player.money == protected_money, "migration preserves prior layout and money")
	world.queue_free()
	await get_tree().process_frame
	GameState.employee_states["worker_001"] = {"is_hired":true}
	GameState.initialize_new_game()
	check(GameState.employee_states.is_empty() and GameState.get_money() == 0, "starting a new game clears previous hired staff and funds")
	print("CHECK_PROGRESSIVE_TUTORIAL checks=", checks, " failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)
