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
		PlayerProgress.story_beat_days[VillageLifeFlow.PREFIX + "friendship:" + str(resident["id"])] = 7
	for entry in SeasonalVillageFlow.SETTINGS.events: PlayerProgress.record_story_beat(SeasonalVillageFlow.key(str(entry["id"]), "done"), 1)
func talk(giver: String) -> bool:
	life.refresh()
	player.global_position = life.residents[giver].global_position
	return world.get_node("WorldInteractions").try_interact() and life.talking
func drain() -> void:
	for i in range(100):
		if not life.dialogue.open: return
		life.dialogue._advance()
	check(false, "dialogue terminates")
func save_reload() -> bool:
	var saved := GameState.create_save_data().duplicate(true)
	return GameState.is_save_data_valid(saved) and GameState.apply_save_data(saved)
func run() -> void:
	world = load("res://scenes/shop/main.tscn").instantiate()
	add_child(world)
	await settle()
	life = world.get_node("VillageLifeDirector")
	player = world.get_node("Actors/Player")
	manager = world.get_node("DayManager")
	manager.set_process(false)
	manager.hour_timer.stop()
	manager.current_hour = 6
	player.set_physics_process(false)
	world.get_node("CustomerSpawner").set_process(false)
	check(ResidentMemoryFlow.SETTINGS.events.size() == 3 and SeasonalVillageFlow.events().size() == 8 and PersonalRequestFlow.entries().size() == 17, "three relation events leave existing quest counts intact")
	var sources := Tools.load_sources()
	var texts: Array[String] = []
	for entry in ResidentMemoryFlow.SETTINGS.events:
		var id := str(entry["id"])
		var giver := str(entry["giver"])
		for option in entry["choices"]:
			var scene_id := str(option["id"])
			GameState.total_day = 300
			PlayerProgress.reset()
			manager.hour_timer.paused = false
			check(not ResidentMemoryFlow.accept(id) and ResidentMemoryFlow.action(giver).is_empty(), "tutorial and settlement gate: " + scene_id)
			unlock()
			if entry.has("after_request"):
				var request := str(entry["after_request"])
				check(not ResidentMemoryFlow.accept(id), "Sora own request required: " + scene_id)
				PlayerProgress.record_story_beat(PersonalRequestFlow.PREFIX + request + ":done", 297)
				check(not ResidentMemoryFlow.accept(id), "Sora own full afterglow required: " + scene_id)
				PlayerProgress.record_story_beat(MarketAfterglowFlow.PREFIX + request + ":heard", 298)
			check(not ResidentMemoryFlow.accept(id), "one relevant completed material request required: " + scene_id)
			var source_index: int = entry["choices"].find(option)
			PlayerProgress.record_story_beat(SeasonalVillageFlow.key(str(entry["after_any_seasonal"][source_index]), "done"), 300)
			check(not ResidentMemoryFlow.accept(id), "completion day waits: " + scene_id)
			GameState.total_day = 301
			var friendship_key := VillageLifeFlow.PREFIX + "friendship:" + giver
			PlayerProgress.story_beat_days[friendship_key] = 6
			check(not ResidentMemoryFlow.accept(id), "seven greeting days required: " + scene_id)
			PlayerProgress.story_beat_days[friendship_key] = 7
			check(ResidentMemoryFlow.locked_reason(entry).is_empty(), "one relevant request suffices without all seasons: " + scene_id)
			world.get_node("TutorialDirector").refresh()
			VillageSettlement.apply_world(world)
			life.refresh()
			var layout: Dictionary = world.get_node("StoreExterior").get_village_layout_snapshot().duplicate(true)
			var journal := ResidentMemoryFlow.JOURNAL_PREFIX + id
			check(VillageJournalFlow.entries().any(func(e: Dictionary) -> bool: return e["id"] == journal) and VillageJournalFlow.destination(world, journal) == life.residents[giver], "journal guides to real resident: " + scene_id)
			check(talk(giver) and life.story_action.get("event", "") == id, "E uses new introduction: " + scene_id)
			life.dialogue.close()
			check(not ResidentMemoryFlow.accepted(id) and not life.talking and not manager.hour_timer.paused, "aborted intro grants no acceptance: " + scene_id)
			check(talk(giver), "intro resumes: " + scene_id)
			drain()
			check(ResidentMemoryFlow.accepted(id) and not ResidentMemoryFlow.accept(id) and not ResidentMemoryFlow.select(id, "unknown"), "intro accepts once and rejects invalid answer: " + scene_id)
			GameState.total_day += 30
			check(save_reload() and ResidentMemoryFlow.accepted(id) and ResidentMemoryFlow.locked_reason(entry).is_empty(), "accepted story survives thirty days and full save: " + scene_id)
			check(talk(giver), "choice question starts: " + scene_id)
			life.dialogue.close()
			check(not life.memory_panel.root.visible, "partial question cannot open choices: " + scene_id)
			check(talk(giver), "question resumes: " + scene_id)
			drain()
			check(life.memory_panel.root.visible and life.talking and manager.hour_timer.paused and world.get_node("WorldInteractions").blocked(), "choice transition retains modal pause: " + scene_id)
			var visible_cards := 0
			for card in life.memory_panel.cards.values():
				if card["info"].get_parent().visible: visible_cards += 1
			check(visible_cards == 2, "only this resident's two choices visible: " + scene_id)
			for size in [Vector2i(1152,648), Vector2i(593,523), Vector2i(800,450)]:
				get_window().size = size
				life.memory_panel._fit_screen()
				await settle()
				check(get_viewport().get_visible_rect().encloses(life.memory_panel.root.get_global_rect()) and life.memory_panel.root.get_global_rect().encloses(life.memory_panel.close_button.get_global_rect()), "choice window and close fit screen: " + scene_id + str(size))
			get_window().size = Vector2i(1152,648)
			life.memory_panel._fit_screen()
			var cancel := InputEventAction.new()
			cancel.action = "ui_cancel"
			cancel.pressed = true
			life.memory_panel._input(cancel)
			check(ResidentMemoryFlow.chosen(id).is_empty() and not life.talking and not manager.hour_timer.paused and not life.memory_panel.root.visible, "Esc defers answer without reopening: " + scene_id)
			check(talk(giver), "deferred answer can reopen: " + scene_id)
			drain()
			life._select_resident_memory("wrong_resident_choice")
			check(life.memory_panel.root.visible and ResidentMemoryFlow.chosen(id).is_empty(), "invalid button id rejected: " + scene_id)
			var gift := str(entry["gifts"][0]["item"])
			var before := GameState.get_item_count(gift)
			var reputation := ResidentRequestFlow.reputation()
			var money: int = GameState.money
			var customers := VillageVisitorFlow.available_types()
			life.memory_panel.cards[scene_id]["action"].pressed.emit()
			check(ResidentMemoryFlow.chosen(id) == scene_id and life.dialogue.open and not life.memory_panel.root.visible and RequestTextData.lines("service_text", scene_id)[0] in life.dialogue.lines, "actual button records chosen branch and response: " + scene_id)
			check(not ResidentMemoryFlow.completed(id) and GameState.get_item_count(gift) == before and ResidentRequestFlow.reputation() == reputation and not ResidentMemoryFlow.select(id, str(entry["choices"][1]["id"])), "answer alone pays nothing and cannot change: " + scene_id)
			life.dialogue.close()
			check(save_reload() and ResidentMemoryFlow.chosen(id) == scene_id and not ResidentMemoryFlow.completed(id), "full save retains interrupted response choice: " + scene_id)
			check(VillageJournalFlow.information(journal).contains(RequestTextData.text("service_text", scene_id, "title")), "pending journal names saved answer: " + scene_id)
			world.get_node("BuildManager").build_mode = true
			check(not talk(giver), "building blocks response: " + scene_id)
			world.get_node("BuildManager").build_mode = false
			manager.hour_timer.paused = true
			check(talk(giver) and life.story_action["stage"] == "finish", "saved response resumes without choosing again: " + scene_id)
			drain()
			check(ResidentMemoryFlow.completed(id) and GameState.get_item_count(gift) == before + int(entry["gifts"][0]["amount"]) and ResidentRequestFlow.reputation() == reputation + int(entry["reputation"]), "exact equal one-time gift and reputation: " + scene_id)
			check(manager.hour_timer.paused and not player.is_physics_processing() and not world.has_meta("village_life_dialogue"), "original pause and movement restored: " + scene_id)
			check(GameState.money == money and VillageVisitorFlow.available_types() == customers and world.get_node("StoreExterior").get_village_layout_snapshot() == layout, "no money customer or layout changes: " + scene_id)
			check(save_reload() and ResidentMemoryFlow.completed(id) and VillageJournalFlow.information(journal).contains(RequestTextData.text("service_text", scene_id, "completion")), "full save and journal keep distinct completion: " + scene_id)
			texts.append(RequestTextData.text("service_text", scene_id, "completion"))
			check(talk(giver) and life.story_action["stage"] == "memory" and RequestTextData.text("service_text", scene_id, "completion") in life.dialogue.lines, "resident retells correct selected memory: " + scene_id)
			drain()
			check(not ResidentMemoryFlow.finish(id) and GameState.get_item_count(gift) == before + int(entry["gifts"][0]["amount"]) and ResidentRequestFlow.reputation() == reputation + int(entry["reputation"]), "rereading pays nothing: " + scene_id)
			GameState.total_day += 112
			check(ResidentMemoryFlow.completed(id) and not ResidentMemoryFlow.finish(id), "next year cannot repeat reward: " + scene_id)
		check(not sources["service_text"].has(id), "mechanical event excluded from prose: " + id)
	for moment in ResidentMemoryFlow.SETTINGS.moments:
		var id := str(moment["id"])
		check(sources["service_text"].has(id) and Writer.build_prompt("service_text", {"service_text": {id:sources["service_text"][id]}}).contains(str(moment["stage"])), "Gemini keeps actual branch context: " + id)
	check(texts.size() == 6 and texts[0] != texts[1] and texts[2] != texts[3] and texts[4] != texts[5], "each resident's choices keep distinct memories")
	PlayerProgress.reset()
	for entry in ResidentMemoryFlow.SETTINGS.events:
		var id := str(entry["id"])
		check(not ResidentMemoryFlow.accepted(id) and not ResidentMemoryFlow.completed(id) and ResidentMemoryFlow.chosen(id).is_empty(), "new game clears memory: " + id)
	world.queue_free()
	await settle()
	print("CHECK_RESIDENT_MEMORIES checks=", checks, " failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)
