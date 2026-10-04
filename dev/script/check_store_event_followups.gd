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

func check(ok: bool, caption: String) -> void:
	checks += 1
	if ok: print("PASS: ", caption)
	else:
		failures += 1
		push_error(caption)
func _ready() -> void: call_deferred("run")
func settle() -> void:
	for i in range(8): await get_tree().process_frame
func unlock() -> void:
	for step in TutorialDirector.SETTINGS.steps: PlayerProgress.record_story_beat("tutorial_step:" + str(step["id"]) + ":done", GameState.total_day - 3)
	PlayerProgress.record_story_beat(CheckoutTutorial.BEAT_ID, GameState.total_day - 3)
	for resident in VillageLifeFlow.SETTINGS.residents:
		PlayerProgress.record_story_beat(ResidentRequestFlow.PREFIX + str(resident["request"]) + ":done", GameState.total_day - 3)
		PlayerProgress.story_beat_days[VillageLifeFlow.PREFIX + "friendship:" + str(resident["id"])] = 3
func record_sale(day: int, item: String, amount: int, event_ids: Array) -> void:
	GameState.record_daily_shop_result(day, CalendarData.get_weekday(day), {"sales":1 if amount > 0 else 0, "sold_items":{item:amount}, "active_event_ids":event_ids, "unmet_demand":{item:2}})
func talk(resident: String) -> bool:
	life.refresh()
	player.global_position = life.residents[resident].global_position
	return world.get_node("WorldInteractions").try_interact() and life.talking
func drain() -> void:
	for i in range(100):
		if not life.dialogue.open: return
		life.dialogue._advance()
	check(false, "conversation terminates")
func run() -> void:
	world = load("res://scenes/shop/main.tscn").instantiate()
	add_child(world)
	await settle()
	life = world.get_node("VillageLifeDirector")
	board = world.get_node("CommunityBoardDirector")
	player = world.get_node("Actors/Player")
	manager = world.get_node("DayManager")
	manager.set_process(false)
	manager.hour_timer.stop()
	manager.current_hour = 6
	manager.hour_timer.paused = false
	player.set_physics_process(false)
	world.get_node("CustomerSpawner").set_process(false)
	check(StoreEventFollowupFlow.SETTINGS.requests.size() == 5 and PersonalRequestFlow.entries().size() == 17 and MarketAfterglowFlow.moments().size() == 11, "five requests and five afterglows extend existing content")
	var sources := Tools.load_sources()
	for entry in StoreEventFollowupFlow.SETTINGS.requests:
		var id := str(entry["id"])
		var event_id := str(entry["after_store_event"])
		var item := str(entry["sale_item"])
		var resident := str(entry["resident"])
		var occurrence := StoreEventData.get_event_occurrence(event_id, 1)
		var start := int(occurrence["start_day"])
		var end := int(occurrence["end_day"])
		PlayerProgress.reset()
		GameState.daily_shop_history.clear()
		GameState.total_day = start
		check(not PersonalRequestFlow.accept(id), "tutorial and settlement required: " + id)
		unlock()
		check(PersonalRequestFlow.locked_reason(entry).contains("앞선 개인 부탁"), "earlier simple request still required: " + id)
		PlayerProgress.record_story_beat(PersonalRequestFlow.PREFIX + str(entry["after"]) + ":done", start - 2)
		check(PersonalRequestFlow.locked_reason(entry).contains("레시피"), "unlearned recipe cannot offer unavailable cooking: " + id)
		PlayerProgress.learn_recipe(str(entry["recipe"]))
		PlayerProgress.story_beat_days[VillageLifeFlow.PREFIX + "friendship:" + resident] = 2
		check(not PersonalRequestFlow.accept(id), "friendship required: " + id)
		PlayerProgress.story_beat_days[VillageLifeFlow.PREFIX + "friendship:" + resident] = 3
		check(not PersonalRequestFlow.accept(id) and StoreEventFollowupFlow.locked_reason(entry).contains("판매한 영업 기록"), "qualifying daily sales required: " + id)
		record_sale(start, item, 0, [event_id])
		check(StoreEventFollowupFlow.qualifying_sale(entry).is_empty(), "unmet demand is not sale: " + id)
		record_sale(start, "iron_ore", 1, [event_id])
		check(StoreEventFollowupFlow.qualifying_sale(entry).is_empty(), "unrelated sold item does not qualify: " + id)
		record_sale(start, item, 1, [])
		check(StoreEventFollowupFlow.qualifying_sale(entry).is_empty(), "event must be present in recorded business day: " + id)
		GameState.daily_shop_history.clear()
		record_sale(start - 1, item, 1, [event_id])
		check(StoreEventFollowupFlow.qualifying_sale(entry).is_empty(), "stale event marker outside real period rejected: " + id)
		GameState.daily_shop_history.clear()
		record_sale(start + 1, item, 1, [event_id])
		check(StoreEventFollowupFlow.qualifying_sale(entry).is_empty(), "future record rejected: " + id)
		GameState.daily_shop_history.clear()
		# 실제 결제 -> 플레이어 품목 통계 -> 기존 하루 영업 기록의 연결.
		player.reset_shop_stats()
		var customer = load("res://scenes/shop/actors/customer.tscn").instantiate()
		world.get_node("Actors").add_child(customer)
		customer.set_physics_process(false)
		customer.carried_item_id = item
		customer.carried_amount = 1
		var sale_money: int = GameState.money
		customer.checkout_item()
		var stats: Dictionary = player.get_daily_shop_stats()
		stats["active_event_ids"] = [event_id]
		GameState.record_daily_shop_result(start, CalendarData.get_weekday(start), stats)
		check(int(stats["sold_items"].get(item, 0)) == 1 and GameState.money == sale_money + ItemData.get_item_price(item) and not StoreEventFollowupFlow.qualifying_sale(entry).is_empty(), "actual checkout archived as qualifying item sale: " + id)
		customer.queue_free()
		check(not PersonalRequestFlow.accept(id), "request waits for event end: " + id)
		GameState.total_day = end
		check(not PersonalRequestFlow.accept(id), "last event day remains preparation period: " + id)
		GameState.total_day = end + 1
		check(PersonalRequestFlow.locked_reason(entry).is_empty() and not PersonalRequestFlow.accepted(id), "day after event opens request without auto acceptance: " + id)
		check(not VillageMarketFlow.completed(), "independent of first village market: " + id)
		var saved := GameState.create_save_data().duplicate(true)
		check(GameState.is_save_data_valid(saved) and GameState.apply_save_data(saved) and PersonalRequestFlow.locked_reason(entry).is_empty(), "save retains qualifying sales and unlocked request: " + id)
		GameState.total_day += 112
		check(PersonalRequestFlow.locked_reason(entry).is_empty(), "later season and next year do not expire old sale: " + id)
		world.get_node("TutorialDirector").refresh()
		VillageSettlement.apply_world(world)
		life.refresh()
		check(talk(resident) and life.dialogue.lines.has(RequestTextData.lines("personal_request", id)[0]), "actual resident E offers CSV request: " + id)
		life.dialogue.close()
		check(not PersonalRequestFlow.accepted(id), "hearing request is not acceptance: " + id)
		player.global_position = VillageSettlement.find_site(world, CommunityRequestFlow.SETTINGS.board_path).global_position
		check(board.try_interact(), "real board opens: " + id)
		board.panel.cards["personal:" + id]["action"].pressed.emit()
		check(PersonalRequestFlow.accepted(id) and not PersonalRequestFlow.accept(id), "real acceptance button once: " + id)
		var progress := PlayerProgress.to_save_data().duplicate(true)
		PlayerProgress.reset()
		PlayerProgress.load_save_data(progress)
		GameState.daily_shop_history.clear()
		check(PersonalRequestFlow.locked_reason(entry).is_empty(), "accepted request survives removed history after save: " + id)
		var totals := CommunityRequestFlow.required_items(entry)
		var target := str(totals.keys()[0])
		var amount := int(totals[target])
		GameState.remove_item(target, GameState.get_item_count(target))
		GameState.add_item(target, amount - 1)
		var money: int = GameState.money
		var reputation := ResidentRequestFlow.reputation()
		board.panel.refresh()
		check(board.panel.cards["personal:" + id]["action"].disabled and PersonalRequestFlow.deliver(id).is_empty() and GameState.get_item_count(target) == amount - 1 and GameState.money == money, "short stock cannot consume or pay: " + id)
		GameState.add_item(target, 1)
		board.panel.refresh()
		board.panel.cards["personal:" + id]["action"].pressed.emit()
		check(PersonalRequestFlow.done(id) and GameState.get_item_count(target) == 0 and GameState.money == money + int(entry["money"]) and ResidentRequestFlow.reputation() == reputation + int(entry["reputation"]), "delivery button consumes warehouse goods and pays once: " + id)
		check(PersonalRequestFlow.deliver(id).is_empty() and MarketAfterglowFlow.pending(resident) == id, "repeat delivery denied and independent afterglow pending: " + id)
		check(VillageJournalFlow.information("personal:" + id).contains("후일담") and VillageJournalFlow.destination(world, "personal:" + id) == life.residents[resident], "journal guides to actual resident: " + id)
		board.panel.close()
		check(talk(resident) and life.afterglow_action == id, "E starts correct afterglow without first market: " + id)
		life.dialogue.close()
		check(not MarketAfterglowFlow.heard(id) and not manager.hour_timer.paused, "partial reading cannot finish and restores time: " + id)
		manager.hour_timer.paused = true
		check(talk(resident), "afterglow can resume: " + id)
		drain()
		check(MarketAfterglowFlow.heard(id) and MarketAfterglowFlow.pending(resident).is_empty() and manager.hour_timer.paused, "full reading saves memory and restores original pause: " + id)
		check(GameState.money == money + int(entry["money"]) and ResidentRequestFlow.reputation() == reputation + int(entry["reputation"]) and GameState.get_item_count(target) == 0, "afterglow pays and consumes nothing additional: " + id)
		progress = PlayerProgress.to_save_data().duplicate(true)
		PlayerProgress.reset()
		PlayerProgress.load_save_data(progress)
		var moment := MarketAfterglowFlow.moment(id)
		check(VillageJournalFlow.information("personal:" + id).contains(RequestTextData.text("service_text", str(moment["id"]), "completion")) and not MarketAfterglowFlow.listen(id), "saved journal keeps final memory once: " + id)
		check(sources["personal_request"].has(id) and sources["service_text"].has(str(moment["id"])) and not sources["personal_request"].has(str(moment["id"])), "Gemini registers correct separate kinds: " + id)
		var prompt := Writer.build_prompt("personal_request", {"personal_request": {id:sources["personal_request"][id]}}, sources)
		check(prompt.contains(str(entry["context"])) and prompt.contains("전체 매장 판매 기록"), "Gemini preserves actual mechanics and buyer uncertainty: " + id)
		manager.hour_timer.paused = false
	PlayerProgress.reset()
	check(not PersonalRequestFlow.accepted("naru_thanks_snack") and not PersonalRequestFlow.done("naru_thanks_snack") and not MarketAfterglowFlow.heard("naru_thanks_snack"), "new game resets once-only progress")
	world.queue_free()
	await settle()
	print("CHECK_STORE_EVENT_FOLLOWUPS checks=", checks, " failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)
