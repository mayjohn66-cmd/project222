extends Node
const Tools = preload("res://dev/gemini/request_text_tools.gd")
var checks := 0
var failures := 0
var world
var life: VillageLifeDirector
var seasonal: SeasonalVillageDirector
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
	for step in TutorialDirector.SETTINGS.steps: PlayerProgress.record_story_beat("tutorial_step:" + str(step["id"]) + ":done", 1)
	PlayerProgress.record_story_beat(CheckoutTutorial.BEAT_ID, 1)
	for resident in VillageLifeFlow.SETTINGS.residents:
		PlayerProgress.record_story_beat(ResidentRequestFlow.PREFIX + str(resident["request"]) + ":done", 1)
		PlayerProgress.story_beat_days[VillageLifeFlow.PREFIX + "friendship:" + str(resident["id"])] = 7
	for id in ["path_light", "flower_corner"]: PlayerProgress.record_story_beat(CommunityRequestFlow.PREFIX + id + ":done", 1)
func talk(id: String) -> bool:
	life.refresh()
	player.global_position = life.residents[id].global_position
	return world.get_node("WorldInteractions").try_interact() and life.talking
func drain(panel: StoryDialoguePanel) -> void:
	for i in range(100):
		if not panel.open: break
		panel._advance()
	if life.request_offer.root.visible:
		var action := life.story_action.duplicate(true)
		var before := PlayerProgress.to_save_data().duplicate(true)
		life.request_offer.decline_button.pressed.emit()
		check(PlayerProgress.to_save_data() == before and not life.talking, "seasonal proposal decline does not accept the event")
		check(talk(str(action["resident"])), "seasonal proposal can be retried")
		for i in range(100):
			if not life.dialogue.open: break
			life.dialogue._advance()
		life.request_offer.accept_button.pressed.emit()
	check(not panel.open, "dialogue finishes")
func _ready() -> void: call_deferred("run")
func run() -> void:
	world = load("res://scenes/shop/main.tscn").instantiate()
	world.get_node("TutorialDirector").enabled = false # Post-tutorial fixture; opening is tested separately.
	world.get_node("VillageLifeDirector").crafting_path_enabled = false # Production progression has its own regression.
	add_child(world)
	await settle()
	life = world.get_node("VillageLifeDirector")
	seasonal = life.get_node("SeasonalVillageDirector")
	player = world.get_node("Actors/Player")
	manager = world.get_node("DayManager")
	player.set_physics_process(false)
	life.set_process(false)
	manager.hour_timer.paused = false
	var seasons := ["spring", "summer", "autumn", "winter"]
	for index in range(4):
		check(CalendarData.get_season_id(index * 28 + 1) == seasons[index] and CalendarData.get_season_id(index * 28 + 28) == seasons[index], "both season boundaries " + seasons[index])
	check(CalendarData.get_season_id(113) == "spring" and CalendarData.get_year(113) == 2, "four seasons remain and repeat next year")
	for index in range(SeasonalVillageFlow.SETTINGS.events.size()):
		var entry := SeasonalVillageFlow.SETTINGS.events[index]
		var id := str(entry["id"])
		var giver := str(entry["giver"])
		var day := index * 28 + 1
		GameState.total_day = day
		manager.current_hour = 12
		PlayerProgress.reset()
		check(not SeasonalVillageFlow.accept(id), "tutorial gate " + id)
		unlock()
		GameState.total_day = ((index + 1) % 4) * 28 + 1
		check(not SeasonalVillageFlow.accept(id) and SeasonalVillageFlow.action(giver).get("event", "") != id, "wrong season hides scene " + id)
		GameState.total_day = day
		var after := str(entry.get("after", ""))
		if not after.is_empty():
			PlayerProgress.story_beat_days.erase(CommunityRequestFlow.PREFIX + after + ":done")
			check(not SeasonalVillageFlow.accept(id), "real prepared landmark required " + id)
			PlayerProgress.record_story_beat(CommunityRequestFlow.PREFIX + after + ":done", 1)
		world.get_node("TutorialDirector").refresh()
		VillageSettlement.apply_world(world)
		check(talk(giver) and life.story_action.get("event") == id and life.dialogue.lines.has(RequestTextData.lines("service_text", id + "_intro")[0]), "actual E introduction " + id)
		life.dialogue.close()
		check(not SeasonalVillageFlow.accepted(id), "partial introduction not accepted " + id)
		check(talk(giver), "intro retry " + id)
		drain(life.dialogue)
		check(SeasonalVillageFlow.accepted(id) and not SeasonalVillageFlow.accept(id), "full intro begins once " + id)
		reload_progress()
		var journal := SeasonalVillageFlow.JOURNAL_PREFIX + id
		check(not VillageJournalFlow.information(journal).is_empty(), "saved journal tracks event " + id)
		if entry["mode"] == "observe":
			var target := SeasonalVillageFlow.site(world, id)
			var neighbor_index := 0
			for npc in life.residents.values():
				npc.set_physics_process(false)
				npc.global_position = Vector2(8000 + neighbor_index * 1000,8000)
				neighbor_index += 1
			player.global_position = target.global_position
			check(VillageJournalFlow.destination(world, journal) == target, "journal points to actual existing landmark " + id)
			if index == 3:
				check(not seasonal.try_interact() and not SeasonalVillageFlow.observe(id, world, 17), "winter observation cannot happen in daytime")
				manager.current_hour = 18
			target.visible = false
			check(not seasonal.try_interact(), "hidden landmark cannot complete " + id)
			target.visible = true
			player.global_position = target.global_position + Vector2(30,0)
			life.residents["naru"].global_position = player.global_position
			check(life.nearest().get("id", "") == "naru" and not seasonal.try_interact(), "closer resident keeps interaction priority " + id)
			life.residents["naru"].global_position = Vector2(8000,8000)
			player.global_position = target.global_position
			world.get_node("BuildManager").build_mode = true
			check(not seasonal.try_interact(), "build mode blocks observation " + id)
			world.get_node("BuildManager").build_mode = false
			check(world.get_node("WorldInteractions").try_interact() and seasonal.talking, "actual landmark E observation " + id)
			seasonal.dialogue.close()
			check(not SeasonalVillageFlow.observed(id) and not manager.hour_timer.paused, "partial observation preserves progress and clock " + id)
			check(seasonal.try_interact(), "observation retries " + id)
			drain(seasonal.dialogue)
			check(SeasonalVillageFlow.observed(id) and not seasonal.try_interact(), "full observation once " + id)
		elif entry["mode"] == "delivery":
			GameState.remove_item("water", GameState.get_item_count("water"))
			GameState.add_item("water", 1)
			check(not SeasonalVillageFlow.ready(id) and talk(giver) and life.story_action["stage"] == "reminder", "insufficient warehouse water guides preparation")
			drain(life.dialogue)
			check(GameState.get_item_count("water") == 1 and not SeasonalVillageFlow.finish(id), "insufficient water not partially consumed")
			GameState.add_item("water", 1)
		else:
			check(not SeasonalVillageFlow.ready(id), "autumn all neighbors required")
			for resident in ["sora", "naru", "doyun"]:
				check(talk(resident) and life.story_action["stage"] == "listen", "free visit order " + resident)
				life.dialogue.close()
				check(not SeasonalVillageFlow.heard(id, resident), "partial autumn reading " + resident)
				check(talk(resident), "autumn reading retry " + resident)
				drain(life.dialogue)
				check(SeasonalVillageFlow.heard(id, resident), "full autumn reading " + resident)
				reload_progress()
		check(SeasonalVillageFlow.ready(id) and VillageJournalFlow.destination(world, journal) == life.residents[giver], "ready guides return to actual giver " + id)
		var inventory: Dictionary = {}
		for gift in entry["gifts"]: inventory[str(gift["item"])] = GameState.get_item_count(str(gift["item"]))
		var water := GameState.get_item_count("water")
		var money := GameState.money
		var reputation := ResidentRequestFlow.reputation()
		var customers := VillageVisitorFlow.available_types()
		check(talk(giver) and life.story_action.get("stage", "") == "finish", "actual final E " + id)
		life.dialogue.close()
		check(not SeasonalVillageFlow.completed(id) and GameState.get_item_count("water") == water, "partial final conversation pays and consumes nothing " + id)
		if entry["mode"] == "delivery":
			check(talk(giver), "summer delivery retries")
			GameState.remove_item("water", 1)
			drain(life.dialogue)
			check(not SeasonalVillageFlow.completed(id) and GameState.get_item_count("water") == 1 and ResidentRequestFlow.reputation() == reputation, "inventory rechecked at full reading without partial consumption")
			GameState.add_item("water", 1)
		GameState.total_day = day + 28
		check(not SeasonalVillageFlow.finish(id) and SeasonalVillageFlow.accepted(id) and VillageJournalFlow.destination(world, journal) == null, "season change pauses without discarding progress " + id)
		reload_progress()
		GameState.total_day = day + 112
		check(SeasonalVillageFlow.ready(id), "next same season resumes saved progress " + id)
		world.get_node("BuildManager").build_mode = true
		check(not talk(giver), "build mode blocks final E " + id)
		world.get_node("BuildManager").build_mode = false
		check(talk(giver), "resume final conversation next year " + id)
		drain(life.dialogue)
		check(SeasonalVillageFlow.completed(id) and not SeasonalVillageFlow.finish(id), "completion and reward once " + id)
		for gift in entry["gifts"]:
			var item := str(gift["item"])
			check(GameState.get_item_count(item) == inventory[item] + int(gift["amount"]), "configured warehouse gift " + id)
		check(GameState.get_item_count("water") == water - (2 if entry["mode"] == "delivery" else 0), "only summer delivery consumes water " + id)
		check(GameState.money == money and ResidentRequestFlow.reputation() == reputation + int(entry["reputation"]) and VillageVisitorFlow.available_types() == customers, "only configured reputation without economy/customer changes " + id)
		reload_progress()
		check(VillageJournalFlow.information(journal).contains(RequestTextData.text("service_text", id + "_finish", "completion")) and VillageJournalFlow.destination(world, journal) == null, "saved memory and no repeat destination " + id)
		GameState.total_day += 112
		check(not SeasonalVillageFlow.accept(id) and not SeasonalVillageFlow.ready(id), "no yearly reward farming " + id)
		manager.hour_timer.paused = false
		player.set_physics_process(false)
	var sources := Tools.load_sources()
	for entry in SeasonalVillageFlow.SETTINGS.moments: check(sources[Tools.KIND_SERVICE_TEXT].has(str(entry["id"])), "writer knows scene " + str(entry["id"]))
	check(not sources[Tools.KIND_SERVICE_TEXT].has("spring_flower_walk"), "mechanical event entries are not prose scenes")
	var prose := Tools.validate_file(Tools.TEXT_PATH, sources)
	if not prose["errors"].is_empty() or not prose["warns"].is_empty(): print("CSV review: ", prose)
	check(prose["errors"].is_empty() and prose["warns"].is_empty(), "all CSV prose passes")
	PlayerProgress.reset()
	unlock()
	GameState.total_day = 85
	manager.current_hour = 18
	SeasonalVillageFlow.accept("winter_lantern_round")
	player.global_position = SeasonalVillageFlow.site(world, "winter_lantern_round").global_position
	check(seasonal.try_interact() and world.get_node("WorldInteractions").blocked(), "observation blocks other interactions before scene exit")
	world.queue_free()
	await settle()
	check(not SeasonalVillageFlow.observed("winter_lantern_round"), "scene exit cannot mark observation read")
	PlayerProgress.reset()
	for entry in SeasonalVillageFlow.SETTINGS.events: check(not SeasonalVillageFlow.accepted(str(entry["id"])) and not SeasonalVillageFlow.completed(str(entry["id"])), "new game resets " + str(entry["id"]))
	print("CHECK_SEASONAL_VILLAGE checks=", checks, " failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)
