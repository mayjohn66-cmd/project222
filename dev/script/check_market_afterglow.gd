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

func check(ok: bool, label_text: String) -> void:
	checks += 1
	if ok: print("PASS: ", label_text)
	else:
		failures += 1
		push_error(label_text)
func settle() -> void:
	for i in range(8): await get_tree().process_frame
func drain() -> void:
	for i in range(100):
		if not life.dialogue.open: return
		life.dialogue._advance()
	check(false, "conversation ends")
func unlock() -> void:
	for step in TutorialDirector.SETTINGS.steps: PlayerProgress.record_story_beat("tutorial_step:" + str(step["id"]) + ":done", GameState.total_day)
	PlayerProgress.record_story_beat(CheckoutTutorial.BEAT_ID, GameState.total_day)
	for resident in VillageLifeFlow.SETTINGS.residents:
		PlayerProgress.record_story_beat(ResidentRequestFlow.PREFIX + str(resident["request"]) + ":done", GameState.total_day)
		PlayerProgress.story_beat_days[VillageLifeFlow.PREFIX + "friendship:" + str(resident["id"])] = 7
	PlayerProgress.record_story_beat(VillageGatheringFlow.COMPLETED, GameState.total_day - 2)
func save_reload() -> void:
	var saved := PlayerProgress.to_save_data().duplicate(true)
	PlayerProgress.reset()
	PlayerProgress.load_save_data(saved)
func talk(id: String) -> bool:
	life.refresh()
	player.global_position = life.residents[id].global_position
	return world.get_node("WorldInteractions").try_interact() and life.talking
func open_board() -> bool:
	player.global_position = VillageSettlement.find_site(world, CommunityRequestFlow.SETTINGS.board_path).global_position
	return board.try_interact()
func _ready() -> void:
	RequestOfferPanel.auto_accept_for_test = true  # 주민 제안 확인창은 이 시험의 대상이 아니므로 바로 수락한다(check_request_proposals 가 확인창 자체를 시험한다)
	call_deferred("run")
func run() -> void:
	world = load("res://scenes/shop/main.tscn").instantiate()
	world.get_node("TutorialDirector").enabled = false
	world.get_node("VillageLifeDirector").crafting_path_enabled = false
	add_child(world)
	await settle()
	life = world.get_node("VillageLifeDirector")
	board = world.get_node("CommunityBoardDirector")
	player = world.get_node("Actors/Player")
	manager = world.get_node("DayManager")
	player.set_physics_process(false)
	manager.hour_timer.paused = false
	manager.current_hour = 6
	GameState.total_day = 50
	check(PersonalRequestFlow.entries().size() == PersonalRequestFlow.SETTINGS.requests.size() + MarketAfterglowFlow.SETTINGS.requests.size() + MarketAfterglowFlow.FOLLOWUPS.requests.size() + StoreEventFollowupFlow.SETTINGS.requests.size() + SeasonStockpileFlow.SETTINGS.requests.size() + WorkshopRequestFlow.SETTINGS.requests.size() and MarketAfterglowFlow.SETTINGS.requests.size() == 3, "original requests remain registered alongside followups")
	var sources := Tools.load_sources()
	for entry in MarketAfterglowFlow.SETTINGS.requests:
		var id := str(entry["id"])
		var resident := str(entry["resident"])
		var recipe_id := str(entry["recipe"])
		PlayerProgress.reset()
		check(not PersonalRequestFlow.accept(id) and MarketAfterglowFlow.pending(resident).is_empty(), "locked before tutorial " + id)
		unlock()
		check(not PersonalRequestFlow.accept(id) and PersonalRequestFlow.locked_reason(entry).contains("앞선 개인 부탁"), "previous resident request required " + id)
		PlayerProgress.record_story_beat(PersonalRequestFlow.PREFIX + str(entry["after"]) + ":done", GameState.total_day - 2)
		check(not PersonalRequestFlow.accept(id) and PersonalRequestFlow.locked_reason(entry).contains("첫 장터"), "actual completed market required " + id)
		PlayerProgress.record_story_beat(VillageMarketFlow.PREFIX + "done", GameState.total_day)
		board.panel.refresh()
		check(not PersonalRequestFlow.accept(id) and board.panel.cards["personal:" + id]["action"].disabled, "market day wait on real card " + id)
		check(VillageJournalFlow.destination(world, "personal:" + id) == null, "locked destination hidden " + id)
		GameState.total_day += 1
		check(PersonalRequestFlow.locked_reason(entry).contains("레시피") and not PersonalRequestFlow.accept(id), "unlearned recipe prevents unavailable cooking task " + id)
		var recipe := ProductRecipeData.get_recipe(recipe_id)
		check(not recipe.is_empty() and str(recipe["result_item_id"]) == recipe_id and not recipe["ingredients"].is_empty(), "requested product has existing recipe and ingredients " + id)
		PlayerProgress.learn_recipe(recipe_id)
		PlayerProgress.story_beat_days[VillageLifeFlow.PREFIX + "friendship:" + resident] = 6
		check(not PersonalRequestFlow.accept(id), "friendship threshold retained " + id)
		PlayerProgress.story_beat_days[VillageLifeFlow.PREFIX + "friendship:" + resident] = 7
		PlayerProgress.story_beat_days[PersonalRequestFlow.PREFIX + str(entry["after"]) + ":done"] = GameState.total_day
		check(not PersonalRequestFlow.accept(id), "wait starts from latest previous request too " + id)
		GameState.total_day += 30
		save_reload()
		check(PersonalRequestFlow.locked_reason(entry).is_empty() and not PersonalRequestFlow.accepted(id), "no expiry or automatic acceptance " + id)
		world.get_node("TutorialDirector").refresh()
		VillageSettlement.apply_world(world)
		life.refresh()
		check(talk(resident) and "|".join(life.dialogue.lines).contains(RequestTextData.lines("personal_request", id)[0]), "actual E offers CSV request " + id)
		life.dialogue.close()
		check(not PersonalRequestFlow.accepted(id), "greeting is not board acceptance " + id)
		check(open_board(), "real board opens " + id)
		board.panel.cards["personal:" + id]["action"].pressed.emit()
		check(PersonalRequestFlow.accepted(id) and not PersonalRequestFlow.accept(id), "actual accept button works once " + id)
		save_reload()
		var totals := CommunityRequestFlow.required_items(entry)
		var item := str(totals.keys()[0])
		var amount := int(totals[item])
		GameState.remove_item(item, GameState.get_item_count(item))
		GameState.add_item(item, amount - 1)
		var money := GameState.money
		var reputation := ResidentRequestFlow.reputation()
		board.panel.refresh()
		check(board.panel.cards["personal:" + id]["action"].disabled and PersonalRequestFlow.deliver(id).is_empty() and GameState.get_item_count(item) == amount - 1 and GameState.money == money, "short inventory consumes and rewards nothing " + id)
		GameState.add_item(item, 1)
		board.panel.refresh()
		check(not board.panel.cards["personal:" + id]["action"].disabled, "enough product enables delivery " + id)
		var request_count := ResidentRequestFlow.completed_count()
		var visitors := VillageVisitorFlow.available_types()
		board.panel.cards["personal:" + id]["action"].pressed.emit()
		check(PersonalRequestFlow.done(id) and GameState.get_item_count(item) == 0 and GameState.money == money + 30 and ResidentRequestFlow.reputation() == reputation + 1, "actual button deducts product and pays once " + id)
		check(ResidentRequestFlow.completed_count() == request_count and VillageVisitorFlow.available_types() == visitors, "existing customer unlock rules unchanged " + id)
		check(PersonalRequestFlow.deliver(id).is_empty() and board.panel.cards["personal:" + id]["action"].disabled, "repeat delivery blocked " + id)
		check(MarketAfterglowFlow.pending(resident) == id and VillageJournalFlow.information("personal:" + id).contains("후일담"), "journal guides to pending conversation " + id)
		var args := OS.get_cmdline_user_args()
		if not args.is_empty() and resident == "sora":
			await settle()
			var scroll: ScrollContainer = board.panel.root.get_child(0).get_child(2)
			scroll.scroll_vertical = 10000
			await settle()
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(args[0])
		board.panel.close()
		save_reload()
		check(MarketAfterglowFlow.pending(resident) == id and VillageJournalFlow.destination(world, "personal:" + id) == life.residents[resident], "save keeps pending conversation at actual resident " + id)
		check(talk(resident) and life.afterglow_action == id and life.dialogue.lines.has(MarketAfterglowFlow.lines(id)[0]), "actual E includes requested afterglow " + id)
		life.dialogue.close()
		check(not MarketAfterglowFlow.heard(id) and not manager.hour_timer.paused, "partial afterglow not heard and clock restored " + id)
		save_reload()
		manager.hour_timer.paused = true
		player.set_physics_process(true)
		check(talk(resident), "afterglow resumes " + id)
		drain()
		check(MarketAfterglowFlow.heard(id) and MarketAfterglowFlow.pending(resident).is_empty(), "full afterglow records exactly once " + id)
		check(manager.hour_timer.paused and player.is_physics_processing(), "original clock and movement restored " + id)
		check(GameState.money == money + 30 and ResidentRequestFlow.reputation() == reputation + 1 and GameState.get_item_count(item) == 0, "afterglow consumes and pays no extra " + id)
		save_reload()
		check(VillageJournalFlow.information("personal:" + id).contains(RequestTextData.text("service_text", str(MarketAfterglowFlow.moment(id)["id"]), "completion")) and not MarketAfterglowFlow.listen(id), "saved journal keeps distinct memory without repeat " + id)
		check(sources[Tools.KIND_PERSONAL_REQUEST].has(id) and sources[Tools.KIND_SERVICE_TEXT].has(str(MarketAfterglowFlow.moment(id)["id"])), "writer registers request and followup separately " + id)
		manager.hour_timer.paused = false
		player.set_physics_process(false)
	check(MarketAfterglowFlow.moment("unknown").is_empty() and not MarketAfterglowFlow.listen("unknown"), "unknown followup cannot progress")
	check(Writer.build_prompt(Tools.KIND_PERSONAL_REQUEST, sources, sources).contains("첫 장터를 함께 마친 다음 날"), "writer gets market and recipe context for personal requests")
	var market_targets := {Tools.KIND_SERVICE_TEXT: {"first_market_open": sources[Tools.KIND_SERVICE_TEXT]["first_market_open"]}}
	var market_prompt := Writer.build_prompt(Tools.KIND_SERVICE_TEXT, market_targets, sources)
	check(market_prompt.contains("첫 장터 시작") and not market_prompt.contains("준비한 빵과 물을 함께 나눔"), "market speaker stage does not become unrelated well gathering prompt")
	var last := "sora_market_drink"
	PlayerProgress.story_beat_days.erase(MarketAfterglowFlow.PREFIX + last + ":heard")
	world.get_node("BuildManager").build_mode = true
	check(not talk("sora"), "build mode blocks pending followup")
	world.get_node("BuildManager").build_mode = false
	check(talk("sora"), "pending followup starts before scene exit")
	world.queue_free()
	await settle()
	check(not MarketAfterglowFlow.heard(last), "scene exit never completes pending followup")
	PlayerProgress.reset()
	for entry in MarketAfterglowFlow.SETTINGS.requests:
		check(not PersonalRequestFlow.accepted(str(entry["id"])) and not PersonalRequestFlow.done(str(entry["id"])) and not MarketAfterglowFlow.heard(str(entry["id"])), "new game clears request and afterglow " + str(entry["id"]))
	print("CHECK_MARKET_AFTERGLOW checks=", checks, " failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)
