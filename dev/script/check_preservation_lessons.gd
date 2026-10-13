extends Node
const Tools = preload("res://dev/gemini/request_text_tools.gd")
const Writer = preload("res://dev/gemini/request_text_runner.gd")
var checks := 0
var failures := 0
var world: Node
var life: VillageLifeDirector
var manager
var player
var oven: ProductionFacility

func check(ok: bool, caption: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(caption)

func frames() -> void:
	for i in range(5): await get_tree().process_frame
func _ready() -> void: call_deferred("verify")
func read_all() -> void:
	while life.talking and life.dialogue.root.visible: life.dialogue._advance()
	if life.request_offer.root.visible:
		var action := life.story_action.duplicate(true)
		var before := PlayerProgress.to_save_data().duplicate(true)
		life.request_offer.decline_button.pressed.emit()
		check(PlayerProgress.to_save_data() == before and not life.talking, "preservation proposal decline leaves no accepted lesson")
		check(talk(str(action["resident"])), "preservation proposal can be retried")
		while life.dialogue.open: life.dialogue._advance()
		life.request_offer.accept_button.pressed.emit()
func talk(giver: String) -> bool:
	PlayerProgress.story_beat_days[VillageLifeFlow.PREFIX + "greeted:" + giver] = GameState.total_day
	life.refresh()
	player.global_position = life.residents[giver].global_position
	return world.get_node("WorldInteractions").try_interact() and life.talking

func reset(day: int) -> void:
	GameState.initialize_new_game()
	GameState.inventory.clear()
	GameState.total_day = day
	GameState.preservation_state = PreservationService.initial_state(day)
	GameState.money = 1000
	for step in TutorialDirector.SETTINGS.steps: PlayerProgress.record_story_beat("tutorial_step:" + str(step["id"]) + ":done",1)
	PlayerProgress.record_story_beat(CheckoutTutorial.BEAT_ID,1)
	for resident in VillageLifeFlow.SETTINGS.residents:
		PlayerProgress.record_story_beat(ResidentRequestFlow.PREFIX + str(resident["request"]) + ":done",1)
		PlayerProgress.story_beat_days[VillageLifeFlow.PREFIX + "friendship:" + str(resident["id"])] = 1
	VillageSettlement.apply_world(world)
	life.refresh()
	manager.current_hour = 6
	manager.hour_timer.stop()
	manager.set_process(false)
	world.get_node("CustomerSpawner").set_process(false)
	player.set_physics_process(false)
	manager.hour_timer.paused = false
	oven.production_state = ProductionFacility.ProductionState.IDLE
	oven.pending_item_id = ""
	oven.pending_amount = 0
	oven.set_process(false)

func verify() -> void:
	world = load("res://scenes/shop/main.tscn").instantiate()
	world.get_node("TutorialDirector").enabled = false
	world.get_node("VillageLifeDirector").crafting_path_enabled = false
	add_child(world)
	await frames()
	life = world.get_node("VillageLifeDirector")
	manager = world.get_node("DayManager")
	player = world.get_node("Actors/Player")
	oven = load("res://scenes/shop/production/production_facility.tscn").instantiate()
	oven.facility_id = "magic_oven"
	oven.set_meta("build_id","magic_oven")
	world.get_node("Objects").add_child(oven)
	await frames()
	reset(1)
	for entry in PreservationLessonFlow.SETTINGS.events:
		var id := str(entry["id"])
		check(not PreservationLessonFlow.accept(id),"no intro before discovering raw material: " + id)
	GameState.add_item("spring_bud",1)
	GameState.remove_item("spring_bud",1)
	check(PreservationLessonFlow.discovered(PreservationLessonFlow.event("preserve_spring_scent")), "discovery remains after sale without forcing loss")
	var save := GameState.create_save_data()
	check(GameState.apply_save_data(save) and PreservationLessonFlow.discovered(PreservationLessonFlow.event("preserve_spring_scent")),"discovery survives full save")
	var journal_count := VillageJournalFlow.entries().filter(func(e: Dictionary) -> bool: return str(e["id"]).begins_with(PreservationLessonFlow.JOURNAL_PREFIX)).size()
	check(journal_count == 3,"three lesson journal entries")
	for entry in PreservationLessonFlow.SETTINGS.events:
		for path in entry["paths"]: await verify_path(entry, path)
	await verify_old_practice()
	await verify_both_ready()
	var sources := Tools.load_sources()
	for moment in PreservationLessonFlow.SETTINGS.moments:
		var id := str(moment["id"])
		check(sources["service_text"].has(id),"writer recognizes new scene: " + id)
		check(Writer.build_prompt("service_text",{"service_text":{id:sources["service_text"][id]}}).contains(str(moment["stage"])),"writer receives exact branch context: " + id)
	for entry in PreservationLessonFlow.SETTINGS.events: check(not sources["service_text"].has(str(entry["id"])),"mechanical event not exported as prose")
	var validation := Tools.validate_file(Tools.TEXT_PATH,sources)
	check(validation["errors"].is_empty() and validation["warns"].is_empty(),"full prose validates: " + str(validation))
	GameState.initialize_new_game()
	for entry in PreservationLessonFlow.SETTINGS.events: check(not PreservationLessonFlow.accepted(str(entry["id"])) and not PreservationLessonFlow.completed(str(entry["id"])) and not PlayerProgress.story_beat_days.has(PreservationLessonFlow.key(str(entry["id"]),"found")),"new game resets lesson and discovery")
	world.queue_free()
	await frames()
	print("CHECK_PRESERVATION_LESSONS checks=",checks," failures=",failures," text=",validation)
	get_tree().quit(0 if failures == 0 else 1)

func verify_path(entry: Dictionary, path: Dictionary) -> void:
	var id := str(entry["id"])
	var giver := str(entry["giver"])
	var raw := str(entry["raw"])
	var sample := str(path["item"])
	reset({"winter_frost":85,"spring_bud":1,"summer_mint":29}[raw])
	GameState.add_item(raw,3)
	check(PreservationLessonFlow.locked_reason(entry).is_empty(),"first material starts without forced loss or advanced story: " + id)
	check(talk(giver) and life.story_action.get("event","") == id and life.story_action["stage"] == "introduction","real NPC E introduces: " + id)
	life.dialogue.close()
	check(not PreservationLessonFlow.accepted(id),"partial intro grants no acceptance")
	check(talk(giver),"intro can resume")
	read_all()
	check(PreservationLessonFlow.accepted(id),"full intro starts lesson")
	check(VillageJournalFlow.destination(world,PreservationLessonFlow.JOURNAL_PREFIX + id) == life.residents[giver],"journal points to real giver")
	GameState.add_item(sample,1)
	check(PreservationLessonFlow.ready_path(id).is_empty(),"preowned or gifted sample not actual practice")
	if path["id"] == "cold":
		var unit := "freezer" if raw == "winter_frost" else "fridge"
		check(PreservationService.install(unit),"install native storage")
		check(PreservationService.deposit(unit,raw,1) == 1 and PreservationService.withdraw(unit,raw,1) == 1,"same-day native round trip")
		check(PreservationLessonFlow.ready_path(id).is_empty(),"same-day round trip is not overnight")
		GameState.advance_calendar_day()
		GameState.add_item(raw,1)
		check(PreservationService.deposit(unit,raw,1) == 1 and PreservationService.withdraw(unit,raw,1) == 1,"new same-day round trip after cleared storage")
		check(PreservationLessonFlow.ready_path(id).is_empty(),"emptying storage clears old overnight candidate")
		check(PreservationService.deposit(unit,raw,1) == 1,"real sample deposited")
		var saved := GameState.create_save_data()
		check(GameState.write_save_file(saved,GameState.SAVE_TEST_PATH) and GameState.apply_save_data(GameState.read_save_file(GameState.SAVE_TEST_PATH)),"stored candidate survives disk save")
		GameState.advance_calendar_day()
		check(PreservationLessonFlow.ready_path(id).is_empty(),"protected item not automatically consumed inside unit")
		check(PreservationService.withdraw(unit,raw,1) == 1,"actual next-day withdrawal")
	else:
		var recipe := "dry_spring_bud" if raw == "spring_bud" else "dry_summer_mint"
		check(oven.start_production(recipe),"start actual drying")
		check(PreservationLessonFlow.ready_path(id).is_empty(),"processing not completed record")
		oven._process(oven.remaining_seconds+1)
		check(PreservationLessonFlow.ready_path(id).is_empty(),"output must be collected")
		check(oven.collect_production(),"actual output signal completes production practice")
	check(PreservationLessonFlow.ready_path(id).get("id","") == path["id"],"correct practice route ready")
	var gift := str(entry["gifts"][0]["item"])
	var before: int = GameState.get_item_count(gift)
	var reputation := ResidentRequestFlow.reputation()
	var money: int = GameState.money
	var sample_before: int = GameState.get_item_count(sample)
	check(talk(giver) and life.story_action["path"] == path["id"],"actual NPC offers route-specific completion")
	life.dialogue.close()
	check(not PreservationLessonFlow.completed(id) and GameState.get_item_count(sample) == sample_before and GameState.get_item_count(gift) == before,"partial finish no consumption/gift")
	check(talk(giver),"finish can resume")
	GameState.remove_item(sample,GameState.get_item_count(sample))
	read_all()
	check(not PreservationLessonFlow.completed(id) and GameState.get_item_count(gift) == before and ResidentRequestFlow.reputation() == reputation,"full reading rechecks stock")
	GameState.add_item(sample,sample_before)
	manager.hour_timer.paused = true
	check(talk(giver),"ready completion restarts")
	read_all()
	check(PreservationLessonFlow.completed(id) and manager.hour_timer.paused and not player.is_physics_processing(),"finish preserves paused clock/player state")
	check(GameState.get_item_count(sample) == sample_before-int(path["amount"]),"exact sample consumption")
	check(GameState.get_item_count(gift) == before+int(entry["gifts"][0]["amount"]) and ResidentRequestFlow.reputation() == reputation+1 and GameState.money == money,"exact small material gift/reputation/no cash")
	check(not PreservationLessonFlow.finish(id,str(path["id"])) and not PreservationLessonFlow.accept(id),"no repeated completion or other route reward")
	var saved := GameState.create_save_data()
	check(GameState.apply_save_data(saved) and PreservationLessonFlow.completed(id),"full save preserves finished route")
	check(VillageJournalFlow.information(PreservationLessonFlow.JOURNAL_PREFIX+id).contains(RequestTextData.text("service_text",id+"_"+str(path["id"]),"completion")) and VillageJournalFlow.destination(world,PreservationLessonFlow.JOURNAL_PREFIX+id) == null,"journal remembers actual method")
	GameState.total_day += 224
	check(not PreservationLessonFlow.finish(id,str(path["id"])) and PreservationLessonFlow.completed(id),"years later never repeats reward")

func verify_both_ready() -> void:
	reset(1)
	var id := "preserve_spring_scent"
	GameState.add_item("spring_bud",4)
	check(PreservationLessonFlow.accept(id),"accept both-path test")
	check(PreservationService.install("fridge") and PreservationService.deposit("fridge","spring_bud",1) == 1,"cold path starts")
	GameState.advance_calendar_day()
	check(PreservationService.withdraw("fridge","spring_bud",1) == 1,"cold path becomes ready")
	check(oven.start_production("dry_spring_bud"),"dry path also starts")
	oven._process(oven.remaining_seconds+1)
	check(oven.collect_production(),"dry path also ready")
	check(PreservationLessonFlow.ready_path(id)["id"] == "cold","both ready uses deterministic current NPC wording")
	var dried: int = GameState.get_item_count("dried_spring_bud")
	check(PreservationLessonFlow.finish(id,"cold") and GameState.get_item_count("dried_spring_bud") == dried,"one sample consumed while alternate preserved")
	check(not PreservationLessonFlow.finish(id,"dry"),"second route cannot collect again")

func verify_old_practice() -> void:
	reset(1)
	var id := "preserve_spring_scent"
	GameState.add_item("spring_bud",3)
	check(PreservationService.install("fridge") and PreservationService.deposit("fridge","spring_bud",1) == 1,"pre-intro cold stock deposited")
	GameState.advance_calendar_day()
	check(PreservationService.withdraw("fridge","spring_bud",1) == 1,"pre-intro real overnight withdrawal")
	check(oven.start_production("dry_spring_bud"),"pre-intro real production")
	oven._process(oven.remaining_seconds+1)
	check(oven.collect_production(),"pre-intro output collected")
	check(PreservationLessonFlow.accept(id) and PreservationLessonFlow.ready_path(id).is_empty(),"old actual practice does not complete new lesson without trying after intro")
	check(PreservationLessonFlow.action("sora")["stage"] == "reminder","existing samples still need post-intro practice")
	var journal = world.get_node("VillageJournalDirector")
	check(journal.try_interact(),"real journal opens with lesson")
	journal.panel.refresh()
	var card: Dictionary = journal.panel.cards[PreservationLessonFlow.JOURNAL_PREFIX + id]
	card["action"].pressed.emit()
	check(journal.tracked_id == PreservationLessonFlow.JOURNAL_PREFIX + id,"actual journal button tracks lesson giver")
	journal.panel.close()
	check(not bool(world.get_meta("village_journal_open",false)),"journal closes without consuming sample")
