extends Node
const Tools = preload("res://dev/gemini/request_text_tools.gd")
const Writer = preload("res://dev/gemini/request_text_runner.gd")
var failures := 0
var checks := 0
var world
var life: VillageLifeDirector
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
	for step in TutorialDirector.SETTINGS.steps: PlayerProgress.record_story_beat("tutorial_step:" + str(step["id"]) + ":done", 90)
	PlayerProgress.record_story_beat(CheckoutTutorial.BEAT_ID, 90)
	for resident in VillageLifeFlow.SETTINGS.residents:
		PlayerProgress.record_story_beat(ResidentRequestFlow.PREFIX + str(resident["request"]) + ":done", 90)
		PlayerProgress.story_beat_days[VillageLifeFlow.PREFIX + "friendship:" + str(resident["id"])] = 7
	PlayerProgress.record_story_beat(VillageMarketFlow.PREFIX + "done", 91)
	PlayerProgress.record_story_beat(VillageRestFlow.PREFIX + "done", 93)
	for id in VillageGoodwillFlow.SETTINGS.after_requests:
		PlayerProgress.record_story_beat(PersonalRequestFlow.PREFIX + id + ":done", 94)
		PlayerProgress.record_story_beat(MarketAfterglowFlow.PREFIX + id + ":heard", 95)
func talk(id: String) -> bool:
	life.refresh()
	player.global_position = life.residents[id].global_position
	return world.get_node("WorldInteractions").try_interact() and life.talking
func drain() -> void:
	for i in range(100):
		if not life.dialogue.open: return
		life.dialogue._advance()
	check(false, "conversation finishes")
func _ready() -> void: call_deferred("run")
func run() -> void:
	world = load("res://scenes/shop/main.tscn").instantiate()
	world.get_node("TutorialDirector").enabled = false
	world.get_node("VillageLifeDirector").crafting_path_enabled = false
	add_child(world)
	await settle()
	life = world.get_node("VillageLifeDirector")
	player = world.get_node("Actors/Player")
	manager = world.get_node("DayManager")
	manager.current_hour = 6
	manager.hour_timer.paused = false
	player.set_physics_process(false)
	GameState.total_day = 100
	PlayerProgress.reset()
	check(not VillageGoodwillFlow.accept() and VillageGoodwillFlow.action("sora").is_empty(), "tutorial required")
	unlock()
	for resident in VillageGoodwillFlow.SETTINGS.participants:
		var key := ResidentRequestFlow.PREFIX + str(VillageLifeFlow.resident(resident)["request"]) + ":done"
		PlayerProgress.story_beat_days.erase(key)
		check(not VillageGoodwillFlow.accept(), "settlement required " + resident)
		PlayerProgress.record_story_beat(key, 90)
	PlayerProgress.story_beat_days.erase(VillageRestFlow.PREFIX + "done")
	check(not VillageGoodwillFlow.accept(), "bench preparation cannot replace full first rest")
	PlayerProgress.record_story_beat(VillageRestFlow.PREFIX + "done", 93)
	for id in VillageGoodwillFlow.SETTINGS.after_requests:
		PlayerProgress.story_beat_days.erase(PersonalRequestFlow.PREFIX + id + ":done")
		check(not VillageGoodwillFlow.accept(), "each previous delivery required " + id)
		PlayerProgress.record_story_beat(PersonalRequestFlow.PREFIX + id + ":done", 94)
		PlayerProgress.story_beat_days.erase(MarketAfterglowFlow.PREFIX + id + ":heard")
		check(not VillageGoodwillFlow.accept(), "each actual previous afterglow required " + id)
		PlayerProgress.record_story_beat(MarketAfterglowFlow.PREFIX + id + ":heard", 95)
	PlayerProgress.story_beat_days[MarketAfterglowFlow.PREFIX + "sora_page_weights:heard"] = 100
	check(not VillageGoodwillFlow.accept() and VillageGoodwillFlow.locked_reason().contains("다음 날"), "wait from latest reading")
	GameState.total_day = 101
	check(VillageGoodwillFlow.locked_reason().is_empty() and not VillageGoodwillFlow.accepted(), "next day unlocks without automatic start")
	GameState.total_day = 150
	reload_progress()
	check(VillageGoodwillFlow.locked_reason().is_empty(), "no deadline")
	world.get_node("TutorialDirector").refresh()
	VillageSettlement.apply_world(world)
	life.refresh()
	check(VillageGoodwillFlow.action("naru").is_empty() and not VillageGoodwillFlow.listen("naru") and not VillageGoodwillFlow.finish(), "introduction required before listening or reward")
	check(VillageJournalFlow.destination(world, VillageGoodwillFlow.JOURNAL_ID) == life.residents["sora"], "journal points to giver")
	check(talk("sora") and life.story_action.get("flow") == "goodwill" and life.dialogue.lines.has(RequestTextData.lines("service_text", "goodwill_intro")[0]), "actual E offers CSV introduction")
	life.dialogue.close()
	check(not VillageGoodwillFlow.accepted() and not manager.hour_timer.paused, "interrupted introduction does not start")
	check(talk("sora"), "intro can retry")
	drain()
	check(VillageGoodwillFlow.accepted() and not VillageGoodwillFlow.accept() and not VillageGoodwillFlow.heard("sora"), "intro fully read starts once without counting giver story")
	reload_progress()
	check(VillageGoodwillFlow.action("sora")["stage"] == "listen" and not VillageGoodwillFlow.listen("unknown"), "giver has own story and unknown id blocked")
	# The giver can be heard first; other neighbors may be visited in either order.
	var money := GameState.money
	var reputation := ResidentRequestFlow.reputation()
	var customers := VillageVisitorFlow.available_types()
	var inventory: Dictionary = {}
	for gift in VillageGoodwillFlow.SETTINGS.gifts: inventory[str(gift["item"])] = GameState.get_item_count(str(gift["item"]))
	for id in ["sora", "doyun", "naru"]:
		manager.hour_timer.paused = true
		player.set_physics_process(true)
		check(talk(id) and life.dialogue.lines.has(RequestTextData.lines("service_text", "goodwill_" + id)[0]), "actual E correct neighbor story " + id)
		life.dialogue.close()
		check(not VillageGoodwillFlow.heard(id) and manager.hour_timer.paused and player.is_physics_processing(), "partial reading preserves original controls " + id)
		reload_progress()
		check(talk(id), "neighbor story retry " + id)
		drain()
		check(VillageGoodwillFlow.heard(id) and not VillageGoodwillFlow.listen(id), "full reading once " + id)
		reload_progress()
		check(VillageJournalFlow.information(VillageGoodwillFlow.JOURNAL_ID).contains(VillageLifeFlow.resident(id)["name"] + " · 안부를 들었어요"), "journal remembers heard neighbor " + id)
		check(GameState.money == money and ResidentRequestFlow.reputation() == reputation, "listening gives no money or reputation " + id)
		for item in inventory: check(GameState.get_item_count(item) == inventory[item], "no event item paid while listening " + id + "/" + item)
		if id == "sora":
			check(talk("sora") and life.story_action["stage"] == "reminder", "giver reminds about missing neighbors")
			drain()
			check(not VillageGoodwillFlow.finish(), "reminder cannot finish early")
		manager.hour_timer.paused = false
		player.set_physics_process(false)
	check(VillageGoodwillFlow.ready() and VillageGoodwillFlow.next_resident() == "sora", "all stories guide return to giver")
	check(VillageGoodwillFlow.action("naru").is_empty(), "heard neighbors retain other existing interactions")
	var stale := VillageGoodwillFlow.action("sora").duplicate(true)
	stale["resident"] = "naru"
	check(not VillageGoodwillFlow.complete_action(stale), "wrong giver cannot grant gift")
	world.get_node("BuildManager").build_mode = true
	check(not talk("sora"), "build mode blocks gift conversation")
	world.get_node("BuildManager").build_mode = false
	check(talk("sora") and life.story_action["stage"] == "finish" and life.dialogue.lines.has("답례: " + VillageGoodwillFlow.reward_description()), "real finish displays configured gift")
	life.dialogue.close()
	check(not VillageGoodwillFlow.completed(), "partial final conversation grants nothing")
	for item in inventory: check(GameState.get_item_count(item) == inventory[item], "partial finish leaves inventory " + item)
	reload_progress()
	check(talk("sora"), "finish retries after save")
	drain()
	check(VillageGoodwillFlow.completed() and not VillageGoodwillFlow.finish() and VillageGoodwillFlow.action("sora").is_empty(), "full finish pays once and yields existing dialogue")
	for gift in VillageGoodwillFlow.SETTINGS.gifts:
		var item := str(gift["item"])
		check(GameState.get_item_count(item) == inventory[item] + int(gift["amount"]), "configured item gift in warehouse " + item)
	check(GameState.money == money and ResidentRequestFlow.reputation() == reputation + VillageGoodwillFlow.SETTINGS.reputation and VillageVisitorFlow.available_types() == customers, "only configured reputation and existing customer thresholds")
	reload_progress()
	check(VillageJournalFlow.destination(world, VillageGoodwillFlow.JOURNAL_ID) == null, "completed story no longer sends player to repeat reward")
	for id in VillageGoodwillFlow.SETTINGS.participants: check(VillageJournalFlow.information(VillageGoodwillFlow.JOURNAL_ID).contains(RequestTextData.text("service_text", "goodwill_" + id, "completion")), "saved journal rereads distinct memory " + id)
	check(VillageJournalFlow.information(VillageGoodwillFlow.JOURNAL_ID).contains(RequestTextData.text("service_text", "goodwill_finish", "completion")), "saved journal keeps joint gift memory")
	var sources := Tools.load_sources()
	for moment in VillageGoodwillFlow.SETTINGS.moments:
		var id := str(moment["id"])
		check(sources[Tools.KIND_SERVICE_TEXT].has(id), "writer registers scene " + id)
	var targets := {Tools.KIND_SERVICE_TEXT:{"goodwill_finish":sources[Tools.KIND_SERVICE_TEXT]["goodwill_finish"]}}
	check(Writer.build_prompt(Tools.KIND_SERVICE_TEXT, targets, sources).contains("중단하면 지급하지 않음"), "writer knows real final reading and reward timing")
	var prose := Tools.validate_file(Tools.TEXT_PATH, sources)
	if not prose["errors"].is_empty() or not prose["warns"].is_empty(): print("CSV review: ", prose)
	check(prose["errors"].is_empty() and prose["warns"].is_empty(), "complete CSV has no errors or warnings")
	PlayerProgress.story_beat_days.erase(VillageGoodwillFlow.PREFIX + "done")
	check(talk("sora"), "finish begins before scene exit")
	world.queue_free()
	await settle()
	check(not VillageGoodwillFlow.completed(), "scene exit cannot complete or reward")
	PlayerProgress.reset()
	check(not VillageGoodwillFlow.accepted() and not VillageGoodwillFlow.completed(), "new game clears event")
	for id in VillageGoodwillFlow.SETTINGS.participants: check(not VillageGoodwillFlow.heard(id), "new game clears neighbor memory " + id)
	print("CHECK_VILLAGE_GOODWILL checks=", checks, " failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)
