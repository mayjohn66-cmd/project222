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
func reload_progress() -> void:
	var saved := PlayerProgress.to_save_data().duplicate(true)
	PlayerProgress.reset()
	PlayerProgress.load_save_data(saved)
func unlock() -> void:
	for step in TutorialDirector.SETTINGS.steps: PlayerProgress.record_story_beat("tutorial_step:" + str(step["id"]) + ":done", GameState.total_day - 3)
	PlayerProgress.record_story_beat(CheckoutTutorial.BEAT_ID, GameState.total_day - 3)
	for resident in VillageLifeFlow.SETTINGS.residents:
		PlayerProgress.record_story_beat(ResidentRequestFlow.PREFIX + str(resident["request"]) + ":done", GameState.total_day - 3)
		PlayerProgress.story_beat_days[VillageLifeFlow.PREFIX + "friendship:" + str(resident["id"])] = 7
	PlayerProgress.record_story_beat(VillageMarketFlow.PREFIX + "done", GameState.total_day - 3)
func talk(resident: String) -> bool:
	life.refresh()
	player.global_position = life.residents[resident].global_position
	return world.get_node("WorldInteractions").try_interact() and life.talking
func drain() -> void:
	for i in range(100):
		if not life.dialogue.open: return
		life.dialogue._advance()
	check(false, "dialogue finishes")
func _ready() -> void: call_deferred("run")
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
	manager.current_hour = 6
	manager.hour_timer.paused = false
	player.set_physics_process(false)
	var sources := Tools.load_sources()
	check(PersonalRequestFlow.entries().size() == 12 + StoreEventFollowupFlow.SETTINGS.requests.size() + SeasonStockpileFlow.SETTINGS.requests.size() and MarketAfterglowFlow.moments().size() == 6 + StoreEventFollowupFlow.SETTINGS.moments.size(), "three errands and three afterglows coexist with previous content")
	for entry in MarketAfterglowFlow.FOLLOWUPS.requests:
		GameState.total_day = 100
		PlayerProgress.reset()
		var id := str(entry["id"])
		var resident := str(entry["resident"])
		var after := str(entry["after"])
		var moment := MarketAfterglowFlow.moment(id)
		check(not PersonalRequestFlow.accept(id), "tutorial gate " + id)
		unlock()
		check(not PersonalRequestFlow.accept(id) and PersonalRequestFlow.locked_reason(entry).contains("앞선 개인 부탁"), "previous delivery required " + id)
		PlayerProgress.record_story_beat(PersonalRequestFlow.PREFIX + after + ":done", 97)
		PlayerProgress.record_story_beat(CommunityRequestFlow.PREFIX + VillageRestFlow.SETTINGS.preparation + ":done", 98)
		check(not PersonalRequestFlow.accept(id) and PersonalRequestFlow.locked_reason(entry).contains("첫 모임"), "bench preparation alone cannot unlock " + id)
		PlayerProgress.record_story_beat(VillageRestFlow.PREFIX + "done", 99)
		check(not PersonalRequestFlow.accept(id) and PersonalRequestFlow.locked_reason(entry).contains("후일담"), "actual earlier afterglow required " + id)
		PlayerProgress.record_story_beat(MarketAfterglowFlow.PREFIX + after + ":heard", 100)
		check(not PersonalRequestFlow.accept(id), "wait from most recent heard day " + id)
		GameState.total_day = 101
		PlayerProgress.story_beat_days[VillageRestFlow.PREFIX + "done"] = 101
		check(not PersonalRequestFlow.accept(id), "wait from most recent first rest too " + id)
		GameState.total_day = 102
		PlayerProgress.story_beat_days[VillageLifeFlow.PREFIX + "friendship:" + resident] = 6
		check(not PersonalRequestFlow.accept(id), "friendship gate " + id)
		PlayerProgress.story_beat_days[VillageLifeFlow.PREFIX + "friendship:" + resident] = 7
		GameState.total_day += 30
		reload_progress()
		check(PersonalRequestFlow.locked_reason(entry).is_empty() and not PersonalRequestFlow.accepted(id), "no expiry or automatic acceptance " + id)
		world.get_node("TutorialDirector").refresh()
		VillageSettlement.apply_world(world)
		check(talk(resident) and life.dialogue.lines.has(RequestTextData.lines("personal_request", id)[0]), "actual NPC offers CSV request " + id)
		life.dialogue.close()
		player.global_position = VillageSettlement.find_site(world, CommunityRequestFlow.SETTINGS.board_path).global_position
		check(board.try_interact(), "existing board interaction " + id)
		var card: Dictionary = board.panel.cards["personal:" + id]
		card["action"].pressed.emit()
		check(PersonalRequestFlow.accepted(id) and not PersonalRequestFlow.accept(id), "board accepts once " + id)
		reload_progress()
		var totals := CommunityRequestFlow.required_items(entry)
		var items := totals.keys()
		var second := str(items[1])
		for item in items:
			check(ItemData.has_item(str(item)), "existing material " + str(item))
			GameState.remove_item(str(item), GameState.get_item_count(str(item)))
			GameState.add_item(str(item), int(totals[item]) - (1 if str(item) == second else 0))
		var money := GameState.money
		var reputation := ResidentRequestFlow.reputation()
		var first_before := GameState.get_item_count(str(items[0]))
		board.panel.refresh()
		check(card["action"].disabled and PersonalRequestFlow.deliver(id).is_empty() and GameState.get_item_count(str(items[0])) == first_before and GameState.money == money, "missing second material consumes nothing " + id)
		GameState.add_item(second, 1)
		board.panel.refresh()
		check(not card["action"].disabled, "all materials enable delivery " + id)
		var customers := VillageVisitorFlow.available_types()
		var completed := ResidentRequestFlow.completed_count()
		card["action"].pressed.emit()
		check(PersonalRequestFlow.done(id) and GameState.money == money + int(entry["money"]) and ResidentRequestFlow.reputation() == reputation + int(entry["reputation"]), "actual board pays configured reward " + id)
		for item in items: check(GameState.get_item_count(str(item)) == 0, "exact material deduction " + str(item))
		check(PersonalRequestFlow.deliver(id).is_empty() and ResidentRequestFlow.completed_count() == completed and VillageVisitorFlow.available_types() == customers, "no repeat payment or customer milestone change " + id)
		check(MarketAfterglowFlow.pending(resident) == id and VillageJournalFlow.information("personal:" + id).contains("후일담"), "journal guides followup " + id)
		board.panel.close()
		reload_progress()
		check(VillageJournalFlow.destination(world, "personal:" + id) == life.residents[resident], "saved request points to actual resident " + id)
		world.get_node("BuildManager").build_mode = true
		check(not talk(resident), "build mode blocks followup " + id)
		world.get_node("BuildManager").build_mode = false
		check(talk(resident) and life.afterglow_action == id and life.dialogue.lines.has(MarketAfterglowFlow.lines(id)[0]), "actual E starts correct followup " + id)
		life.dialogue.close()
		check(not MarketAfterglowFlow.heard(id) and not manager.hour_timer.paused, "interrupted reading does not complete and restores clock " + id)
		reload_progress()
		manager.hour_timer.paused = true
		player.set_physics_process(true)
		check(talk(resident), "can retry followup " + id)
		drain()
		check(MarketAfterglowFlow.heard(id) and MarketAfterglowFlow.pending(resident).is_empty() and not MarketAfterglowFlow.listen(id), "full reading completes once " + id)
		check(manager.hour_timer.paused and player.is_physics_processing(), "original controls restored " + id)
		check(GameState.money == money + int(entry["money"]) and ResidentRequestFlow.reputation() == reputation + int(entry["reputation"]), "afterglow adds no reward " + id)
		reload_progress()
		check(VillageJournalFlow.information("personal:" + id).contains(RequestTextData.text("service_text", str(moment["id"]), "completion")), "saved journal keeps distinct memory " + id)
		check(sources[Tools.KIND_PERSONAL_REQUEST].has(id) and sources[Tools.KIND_SERVICE_TEXT].has(str(moment["id"])), "writer knows both registered kinds " + id)
		manager.hour_timer.paused = false
		player.set_physics_process(false)
	var prompt := Writer.build_prompt(Tools.KIND_PERSONAL_REQUEST, sources, sources)
	check(prompt.contains("길목 쉼터 첫 모임을 끝까지 함께한 다음 날"), "writer receives real prerequisites")
	var result := Tools.validate_file(Tools.TEXT_PATH, sources)
	if not result["errors"].is_empty() or not result["warns"].is_empty(): print("CSV review: ", result)
	check(result["errors"].is_empty() and result["warns"].is_empty(), "complete CSV has no errors or warnings")
	var last := "sora_page_weights"
	PlayerProgress.story_beat_days.erase(MarketAfterglowFlow.PREFIX + last + ":heard")
	check(talk("sora"), "followup starts before scene exit")
	world.queue_free()
	await settle()
	check(not MarketAfterglowFlow.heard(last), "scene exit preserves unread followup")
	PlayerProgress.reset()
	for entry in MarketAfterglowFlow.FOLLOWUPS.requests:
		var id := str(entry["id"])
		check(not PersonalRequestFlow.accepted(id) and not PersonalRequestFlow.done(id) and not MarketAfterglowFlow.heard(id), "new game clears all new progress " + id)
	print("CHECK_TRAIL_ERRANDS checks=", checks, " failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)
