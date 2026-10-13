extends Node
const Tools = preload("res://dev/gemini/request_text_tools.gd")
const Writer = preload("res://dev/gemini/request_text_runner.gd")
var checks := 0
var failures := 0
var world
var life: VillageLifeDirector
var board: CommunityBoardDirector
var player
var manager
var facilities: Dictionary = {}

func check(ok: bool, label_text: String) -> void:
	checks += 1
	if ok: print("PASS: ",label_text)
	else:
		failures += 1
		push_error(label_text)
func settle() -> void:
	for i in range(8): await get_tree().process_frame
func drain() -> void:
	for i in range(200):
		if not life.dialogue.open: return
		life.dialogue._advance()
	check(false,"conversation terminates")
func unlock() -> void:
	for step in TutorialDirector.SETTINGS.steps: PlayerProgress.record_story_beat("tutorial_step:" + str(step["id"]) + ":done",GameState.total_day)
	PlayerProgress.record_story_beat(CheckoutTutorial.BEAT_ID,GameState.total_day)
	for resident in VillageLifeFlow.SETTINGS.residents:
		PlayerProgress.record_story_beat(ResidentRequestFlow.PREFIX + str(resident["request"]) + ":done",GameState.total_day)
		PlayerProgress.story_beat_days[VillageLifeFlow.PREFIX + "friendship:" + str(resident["id"])] = 3
		PlayerProgress.record_story_beat(VillageLifeFlow.PREFIX + "greeted:" + str(resident["id"]),GameState.total_day)
func save_reload() -> void:
	var saved := PlayerProgress.to_save_data().duplicate(true)
	PlayerProgress.reset()
	PlayerProgress.load_save_data(saved)
func talk(resident: String) -> bool:
	# Greeting gifts are a separate existing system, not part of the request reward.
	PlayerProgress.record_story_beat(VillageLifeFlow.PREFIX + "greeted:" + resident,GameState.total_day)
	life.refresh()
	player.global_position = life.residents[resident].global_position
	return world.get_node("WorldInteractions").try_interact() and life.talking
func open_board() -> bool:
	player.global_position = VillageSettlement.find_site(world,CommunityRequestFlow.SETTINGS.board_path).global_position
	return board.try_interact()
func produce(recipe_id: String, count: int) -> void:
	var recipe := ProductRecipeData.get_recipe(recipe_id)
	var facility: ProductionFacility = facilities[str(recipe["facility_id"])]
	for ingredient in recipe["ingredients"]: GameState.add_item(str(ingredient["item_id"]),int(ingredient["amount"]) * count)
	check(facility.start_production(recipe_id,count),"real production starts " + recipe_id)
	facility._process(facility.remaining_seconds + 1)
	check(facility.collect_production(),"real output enters warehouse " + recipe_id)

func _ready() -> void:
	RequestOfferPanel.auto_accept_for_test = true  # 주민 제안 확인창은 이 시험의 대상이 아니므로 바로 수락한다(check_request_proposals 가 확인창 자체를 시험한다)
	call_deferred("run")
func run() -> void:
	GameState.initialize_new_game()
	world = load("res://scenes/shop/main.tscn").instantiate()
	world.get_node("TutorialDirector").enabled = false
	world.get_node("VillageLifeDirector").crafting_path_enabled = false
	add_child(world)
	await settle()
	life = world.get_node("VillageLifeDirector")
	board = world.get_node("CommunityBoardDirector")
	player = world.get_node("Actors/Player")
	manager = world.get_node("DayManager")
	manager.set_process(false)
	manager.hour_timer.stop()
	manager.current_hour = 6
	manager.customer_spawner.set_process(false)
	player.set_physics_process(false)
	for id in ["magic_oven","drink_machine"]:
		var facility = load("res://scenes/shop/production/production_facility.tscn").instantiate()
		facility.facility_id = id
		facility.set_meta("build_id",id)
		world.get_node("Objects").add_child(facility)
		facilities[id] = facility
	await settle()
	life.refresh()
	check(PersonalRequestFlow.entries().size() == 23 and MarketAfterglowFlow.moments().size() == 14,"three requests and three memories added to existing content")
	check(WorkshopRequestFlow.locked_reason({}).is_empty() and not WorkshopRequestFlow.locked_reason({"after_craft":"unknown"}).is_empty(),"ordinary requests unaffected and invalid craft gate fails closed")
	var sources := Tools.load_sources()
	for entry in WorkshopRequestFlow.SETTINGS.requests:
		var id := str(entry["id"])
		var resident := str(entry["resident"])
		var craft := str(entry["after_craft"])
		var recipe_id := str(entry["recipe"])
		PlayerProgress.reset()
		GameState.total_day = 50
		check(not PersonalRequestFlow.accept(id),"no request before tutorial " + id)
		unlock()
		check(not PersonalRequestFlow.accept(id) and PersonalRequestFlow.locked_reason(entry).contains("시제품"),"learned recipe alone cannot skip shared prototype " + id)
		PlayerProgress.learn_recipe(recipe_id)
		check(not PersonalRequestFlow.accept(id),"scroll knowledge does not skip product story " + id)
		for stage in CraftingPathFlow.SETTINGS.stages:
			if stage["id"] == craft: break
			PlayerProgress.record_story_beat(CraftingPathFlow.key(str(stage["id"]),"done"),GameState.total_day - 2)
		check(CraftingPathFlow.accept(craft),"actual product stage can begin " + id)
		check(not PersonalRequestFlow.accept(id),"prototype introduction alone is insufficient " + id)
		for item in CraftingPathFlow.stage(craft)["requirements"]:
			GameState.remove_item(str(item["item"]),GameState.get_item_count(str(item["item"])))
			produce(str(item["item"]),int(item["amount"]))
		check(CraftingPathFlow.finish(craft) and CraftingPathFlow.done(craft),"real produced prototypes finish prerequisite " + id)
		board.panel.refresh()
		check(not PersonalRequestFlow.accept(id) and board.panel.cards["personal:" + id]["action"].disabled,"same-day craft completion leaves board locked " + id)
		GameState.total_day += 1
		PlayerProgress.story_beat_days[VillageLifeFlow.PREFIX + "friendship:" + resident] = 2
		check(not PersonalRequestFlow.accept(id),"three greeting days required " + id)
		PlayerProgress.story_beat_days[VillageLifeFlow.PREFIX + "friendship:" + resident] = 3
		PlayerProgress.learned_recipe_ids.erase(recipe_id)
		check(not PersonalRequestFlow.accept(id),"missing recipe remains explained " + id)
		PlayerProgress.learn_recipe(recipe_id)
		save_reload()
		check(PersonalRequestFlow.locked_reason(entry).is_empty() and not PersonalRequestFlow.accepted(id),"next day unlock never automatically accepts " + id)
		VillageSettlement.apply_world(world)
		life.refresh()
		var store = world.get_node("StoreView3D")
		store._sync_actors(0.0)
		check(store._actors.has(life.residents[resident].get_instance_id()) and life.residents[resident].visible,"actual request giver remains visible in 3D " + id)
		check(talk(resident) and life.dialogue.lines.has(RequestTextData.lines("personal_request",id)[0]),"actual resident offers CSV request " + id)
		life.dialogue.close()
		check(not PersonalRequestFlow.accepted(id),"greeting does not accept " + id)
		# Previously produced stock is valid; these are delivery requests, not production counters.
		GameState.remove_item(recipe_id,GameState.get_item_count(recipe_id))
		produce(recipe_id,int(entry["requirements"][0]["amount"]))
		check(open_board(),"existing board opens " + id)
		board.panel.cards["personal:" + id]["action"].pressed.emit()
		check(PersonalRequestFlow.accepted(id) and not PersonalRequestFlow.accept(id),"real board accepts exactly once " + id)
		save_reload()
		GameState.total_day += 30
		var amount := int(entry["requirements"][0]["amount"])
		# 식품은 날짜가 지나면 사라진다(food_shelf_life.csv). 이 시험은 부탁이 이어지는지 보므로 재고만 다시 채운다.
		GameState.remove_item(recipe_id,GameState.get_item_count(recipe_id))
		GameState.add_item(recipe_id,amount)
		check(PersonalRequestFlow.can_deliver(id),"accepted request survives season change and absence " + id)
		GameState.remove_item(recipe_id,1)
		var money := GameState.money
		var reputation := ResidentRequestFlow.reputation()
		board.panel.refresh()
		check(board.panel.cards["personal:" + id]["action"].disabled and PersonalRequestFlow.deliver(id).is_empty() and GameState.money == money and GameState.get_item_count(recipe_id) == amount - 1,"insufficient finished product consumes and pays nothing " + id)
		GameState.add_item(recipe_id,1)
		board.panel.refresh()
		var visitors := VillageVisitorFlow.available_types()
		var original_count := ResidentRequestFlow.completed_count()
		board.panel.cards["personal:" + id]["action"].pressed.emit()
		check(PersonalRequestFlow.done(id) and GameState.get_item_count(recipe_id) == 0 and GameState.money == money + int(entry["money"]) and ResidentRequestFlow.reputation() == reputation + 1,"real delivery consumes exact product and pays once " + id)
		check(int(entry["money"]) == ItemData.get_item_price(recipe_id) * amount + 30,"product retail payment plus small thanks " + id)
		check(VillageVisitorFlow.available_types() == visitors and ResidentRequestFlow.completed_count() == original_count,"existing visitor gates preserved " + id)
		check(PersonalRequestFlow.deliver(id).is_empty() and board.panel.cards["personal:" + id]["action"].disabled,"completed card cannot repeat payment " + id)
		board.panel.close()
		save_reload()
		check(MarketAfterglowFlow.pending(resident).is_empty() and not MarketAfterglowFlow.listen(id) and VillageJournalFlow.information("personal:" + id).contains("다음 날"),"same-day usage memory waits and journal explains " + id)
		GameState.total_day += 1
		check(MarketAfterglowFlow.pending(resident) == id and VillageJournalFlow.destination(world,"personal:" + id) == life.residents[resident],"next day journal points to resident " + id)
		world.get_node("BuildManager").build_mode = true
		check(not talk(resident),"building blocks memory conversation " + id)
		world.get_node("BuildManager").build_mode = false
		manager.hour_timer.paused = false
		check(talk(resident) and life.afterglow_action == id and life.dialogue.lines.has(MarketAfterglowFlow.lines(id)[0]),"actual E includes usage memory " + id)
		life.dialogue.close()
		check(not MarketAfterglowFlow.heard(id) and not manager.hour_timer.paused,"partial reading never completes and restores clock " + id)
		save_reload()
		manager.hour_timer.paused = true
		player.set_physics_process(true)
		check(talk(resident),"unfinished memory resumes " + id)
		drain()
		check(MarketAfterglowFlow.heard(id) and MarketAfterglowFlow.pending(resident).is_empty() and manager.hour_timer.paused and player.is_physics_processing(),"full reading records once and restores previous states " + id)
		check(GameState.money == money + int(entry["money"]) and ResidentRequestFlow.reputation() == reputation + 1 and GameState.get_item_count(recipe_id) == 0,"memory never gives extra items or reward " + id)
		save_reload()
		check(not MarketAfterglowFlow.listen(id) and VillageJournalFlow.information("personal:" + id).contains(RequestTextData.text("service_text",str(MarketAfterglowFlow.moment(id)["id"]),"completion")),"saved memory does not repeat " + id)
		check(sources[Tools.KIND_PERSONAL_REQUEST].has(id) and sources[Tools.KIND_SERVICE_TEXT].has(str(MarketAfterglowFlow.moment(id)["id"])),"writer registers both kinds " + id)
		player.set_physics_process(false)
	var request_prompt := Writer.build_prompt(Tools.KIND_PERSONAL_REQUEST,sources,sources)
	var memory_prompt := Writer.build_prompt(Tools.KIND_SERVICE_TEXT,sources,sources)
	check(request_prompt.contains("시제품 나눔 완료 다음 날") and request_prompt.contains("재제작 필수 아님") and memory_prompt.contains("교류로 배운 상품의 사용 후일담"),"writer preserves actual stage and reward context")
	var prose := Tools.validate_file(Tools.TEXT_PATH,sources)
	for error in prose["errors"]: print("PROSE ERROR: ",error)
	for warning in prose["warns"]: print("PROSE WARNING: ",warning)
	check(prose["errors"].is_empty() and prose["warns"].is_empty(),"whole dialogue CSV passes strict validation")
	world.queue_free()
	await settle()
	PlayerProgress.reset()
	for entry in WorkshopRequestFlow.SETTINGS.requests:
		var id := str(entry["id"])
		check(not PersonalRequestFlow.accepted(id) and not PersonalRequestFlow.done(id) and not MarketAfterglowFlow.heard(id),"new game clears request and memory " + id)
	print("CHECK_WORKSHOP_REQUESTS checks=",checks," failures=",failures)
	get_tree().quit(0 if failures == 0 else 1)
