extends Node
const Tools = preload("res://dev/gemini/request_text_tools.gd")
const Writer = preload("res://dev/gemini/request_text_runner.gd")
var checks := 0
var failures := 0
var world
var life: VillageLifeDirector
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
	for step in TutorialDirector.SETTINGS.steps: PlayerProgress.record_story_beat("tutorial_step:" + str(step["id"]) + ":done", 1)
	PlayerProgress.record_story_beat(CheckoutTutorial.BEAT_ID, 1)
	for resident in VillageLifeFlow.SETTINGS.residents:
		PlayerProgress.record_story_beat(ResidentRequestFlow.PREFIX + str(resident["request"]) + ":done", 1)
		PlayerProgress.story_beat_days[VillageLifeFlow.PREFIX + "friendship:" + str(resident["id"])] = 3
func talk(giver: String) -> bool:
	life.refresh()
	player.global_position = life.residents[giver].global_position
	return world.get_node("WorldInteractions").try_interact() and life.talking
func drain() -> void:
	for i in range(100):
		if not life.dialogue.open: return
		life.dialogue._advance()
	check(false, "dialogue ends")
func run() -> void:
	world = load("res://scenes/shop/main.tscn").instantiate()
	world.get_node("TutorialDirector").enabled = false
	world.get_node("VillageLifeDirector").crafting_path_enabled = false
	add_child(world)
	await settle()
	life = world.get_node("VillageLifeDirector")
	player = world.get_node("Actors/Player")
	manager = world.get_node("DayManager")
	manager.set_process(false)
	manager.hour_timer.stop()
	manager.current_hour = 6
	manager.hour_timer.paused = false
	player.set_physics_process(false)
	world.get_node("CustomerSpawner").set_process(false)
	check(SeasonalVillageFlow.SETTINGS.events.size() == 4 and SeasonalVillageFlow.events().size() == 8, "four original events plus four life requests registered")
	check(PersonalRequestFlow.entries().size() == 17 + SeasonStockpileFlow.SETTINGS.requests.size() and MarketAfterglowFlow.moments().size() == 11, "existing board requests and afterglows kept separately")
	var sources := Tools.load_sources()
	for entry in SeasonalLifeRequestFlow.SETTINGS.events:
		var id := str(entry["id"])
		var giver := str(entry["giver"])
		var source := str(entry["after_request"])
		var day: int = ["spring", "summer", "autumn", "winter"].find(str(entry["season"])) * CalendarData.DAYS_PER_SEASON + CalendarData.DAYS_PER_SEASON
		GameState.total_day = day - 1
		PlayerProgress.reset()
		check(not SeasonalVillageFlow.accept(id), "tutorial and settlement required: " + id)
		unlock()
		check(SeasonalVillageFlow.locked_reason(entry).contains("개인 부탁"), "own predecessor delivery required: " + id)
		PlayerProgress.record_story_beat(PersonalRequestFlow.PREFIX + source + ":done", day - 2)
		check(not SeasonalVillageFlow.accept(id) and SeasonalVillageFlow.locked_reason(entry).contains("후일담"), "delivery alone cannot replace afterglow: " + id)
		PlayerProgress.record_story_beat(MarketAfterglowFlow.PREFIX + source + ":heard", day - 1)
		check(not SeasonalVillageFlow.accept(id), "wait after latest afterglow: " + id)
		GameState.total_day = day
		PlayerProgress.story_beat_days[VillageLifeFlow.PREFIX + "friendship:" + giver] = 2
		check(not SeasonalVillageFlow.accept(id), "new giver friendship required too: " + id)
		PlayerProgress.story_beat_days[VillageLifeFlow.PREFIX + "friendship:" + giver] = 3
		check(SeasonalVillageFlow.locked_reason(entry).is_empty(), "own season final day can start: " + id)
		GameState.total_day = day + 1
		check(not SeasonalVillageFlow.accept(id), "outside season cannot start automatically: " + id)
		GameState.total_day = day + 112
		check(SeasonalVillageFlow.locked_reason(entry).is_empty(), "unstarted opportunity returns following year: " + id)
		world.get_node("TutorialDirector").refresh()
		VillageSettlement.apply_world(world)
		var journal := SeasonalVillageFlow.JOURNAL_PREFIX + id
		check(VillageJournalFlow.entries().any(func(e: Dictionary) -> bool: return e["id"] == journal), "journal contains life request: " + id)
		check(talk(giver) and life.story_action.get("event", "") == id and life.dialogue.lines.has(RequestTextData.lines("service_text", id + "_intro")[0]), "actual E introduces correct new request: " + id)
		life.dialogue.close()
		check(not SeasonalVillageFlow.accepted(id) and not manager.hour_timer.paused, "partial intro does not accept and restores clock: " + id)
		check(talk(giver), "intro can resume: " + id)
		GameState.total_day += 1
		drain()
		check(not SeasonalVillageFlow.accepted(id), "intro must finish before starting season ends: " + id)
		GameState.total_day = day + 112
		check(talk(giver), "same season intro can restart: " + id)
		drain()
		check(SeasonalVillageFlow.accepted(id) and not SeasonalVillageFlow.accept(id), "full E intro begins only once: " + id)
		GameState.total_day += 1
		var saved := GameState.create_save_data().duplicate(true)
		check(GameState.is_save_data_valid(saved) and GameState.apply_save_data(saved) and SeasonalVillageFlow.locked_reason(entry).is_empty(), "accepted request survives full save outside season: " + id)
		var totals := CommunityRequestFlow.required_items(entry)
		var items := totals.keys()
		for item in items: GameState.remove_item(item, GameState.get_item_count(item))
		GameState.add_item(items[0], int(totals[items[0]]))
		var money: int = GameState.money
		var reputation := ResidentRequestFlow.reputation()
		check(not SeasonalVillageFlow.ready(id) and not SeasonalVillageFlow.finish(id) and GameState.get_item_count(items[0]) == int(totals[items[0]]) and GameState.money == money, "partial materials consumed and rewarded nothing: " + id)
		check(SeasonalVillageFlow.information(id).contains(VillageLifeFlow.resident(giver)["name"]) and SeasonalVillageFlow.information(id).contains("직접 전달"), "journal names correct direct recipient: " + id)
		check(talk(giver) and life.story_action.get("event", "") == id and life.story_action["stage"] == "reminder", "accepted request takes priority over new season intro: " + id)
		drain()
		check(not SeasonalVillageFlow.completed(id) and GameState.get_item_count(items[0]) == int(totals[items[0]]), "reminder never consumes prepared part: " + id)
		for item in items: GameState.add_item(item, maxi(0, int(totals[item]) - GameState.get_item_count(item)))
		var gift := str(entry["gifts"][0]["item"])
		var gift_before := GameState.get_item_count(gift)
		check(SeasonalVillageFlow.ready(id) and VillageJournalFlow.destination(world, journal) == life.residents[giver], "ready outside season guides to actual giver: " + id)
		check(talk(giver) and life.story_action["stage"] == "finish", "E offers actual direct delivery: " + id)
		life.dialogue.close()
		check(not SeasonalVillageFlow.completed(id) and GameState.get_item_count(gift) == gift_before and ResidentRequestFlow.reputation() == reputation, "partial finish cannot give gifts: " + id)
		check(talk(giver), "delivery resumes: " + id)
		GameState.remove_item(items[1], 1)
		drain()
		check(not SeasonalVillageFlow.completed(id) and GameState.get_item_count(items[0]) == int(totals[items[0]]) and GameState.get_item_count(gift) == gift_before and ResidentRequestFlow.reputation() == reputation, "inventory rechecked at full reading atomically: " + id)
		GameState.add_item(items[1], 1)
		world.get_node("BuildManager").build_mode = true
		check(not talk(giver), "build mode blocks E delivery: " + id)
		world.get_node("BuildManager").build_mode = false
		manager.hour_timer.paused = true
		var visitor_types := VillageVisitorFlow.available_types()
		check(talk(giver), "final delivery can resume again: " + id)
		drain()
		check(SeasonalVillageFlow.completed(id) and manager.hour_timer.paused and not player.is_physics_processing(), "full reading delivers and restores original pause and movement: " + id)
		for item in items: check(GameState.get_item_count(item) == 0, "exact warehouse deduction: " + id + ":" + str(item))
		check(GameState.get_item_count(gift) == gift_before + int(entry["gifts"][0]["amount"]) and ResidentRequestFlow.reputation() == reputation + int(entry["reputation"]) and GameState.money == money and VillageVisitorFlow.available_types() == visitor_types, "exact material gift and reputation without cash or customer unlock: " + id)
		check(not SeasonalVillageFlow.finish(id) and not SeasonalVillageFlow.accept(id), "duplicate completion denied: " + id)
		saved = GameState.create_save_data().duplicate(true)
		check(GameState.apply_save_data(saved) and SeasonalVillageFlow.completed(id) and VillageJournalFlow.information(journal).contains(RequestTextData.text("service_text", id + "_finish", "completion")) and VillageJournalFlow.destination(world, journal) == null, "full save keeps goods and final journal memory: " + id)
		GameState.total_day = day + 224
		check(not SeasonalVillageFlow.accept(id) and not SeasonalVillageFlow.finish(id) and GameState.get_item_count(gift) == gift_before + int(entry["gifts"][0]["amount"]), "matching season next year cannot farm rewards: " + id)
		check(not sources["service_text"].has(id), "mechanical event is not Gemini prose: " + id)
		for stage in ["intro", "wait", "finish"]:
			var scene_id: String = id + "_" + str(stage)
			check(sources["service_text"].has(scene_id), "Gemini knows scene: " + scene_id)
			var prompt := Writer.build_prompt("service_text", {"service_text": {scene_id:sources["service_text"][scene_id]}})
			check(prompt.contains(str(sources["service_text"][scene_id]["stage"])), "Gemini keeps direct delivery and carryover context: " + scene_id)
		manager.hour_timer.paused = false
	PlayerProgress.reset()
	for entry in SeasonalVillageFlow.events(): check(not SeasonalVillageFlow.accepted(str(entry["id"])) and not SeasonalVillageFlow.completed(str(entry["id"])), "new game clears seasonal progress: " + str(entry["id"]))
	world.queue_free()
	await settle()
	print("CHECK_SEASONAL_LIFE_REQUESTS checks=", checks, " failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)
