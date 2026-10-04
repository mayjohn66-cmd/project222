extends Node
const Tools = preload("res://dev/gemini/request_text_tools.gd")
const Writer = preload("res://dev/gemini/request_text_runner.gd")
var checks := 0
var failures := 0
var world
var life: VillageLifeDirector
var market: VillageMarketDirector
var manager
var player

func check(ok: bool, label_text: String) -> void:
	checks += 1
	if ok: print("PASS: ", label_text)
	else:
		failures += 1
		push_error(label_text)
func settle() -> void:
	for i in range(8): await get_tree().process_frame
func drain() -> void:
	for i in range(80):
		if not market.dialogue.open: return
		market.dialogue._advance()
	check(false, "market conversation ends")
func unlock() -> void:
	for step in TutorialDirector.SETTINGS.steps: PlayerProgress.record_story_beat("tutorial_step:" + str(step["id"]) + ":done", GameState.total_day)
	PlayerProgress.record_story_beat(CheckoutTutorial.BEAT_ID, GameState.total_day)
	for resident in VillageLifeFlow.SETTINGS.residents:
		PlayerProgress.record_story_beat(ResidentRequestFlow.PREFIX + str(resident["request"]) + ":done", GameState.total_day)
		PlayerProgress.story_beat_days[VillageLifeFlow.PREFIX + "friendship:" + str(resident["id"])] = 7
	PlayerProgress.record_story_beat(PersonalRequestFlow.PREFIX + VillageStoryFlow.SETTINGS.after_request + ":done", GameState.total_day)
	PlayerProgress.record_story_beat(VillageGatheringFlow.COMPLETED, GameState.total_day)
	PlayerProgress.record_story_beat(VillageStoryFlow.SETTINGS.after_event, GameState.total_day)
	VillageStoryFlow.accept()
	VillageStoryFlow.listen("naru")
	VillageStoryFlow.listen("doyun")
	VillageStoryFlow.select("home")
	VillageStoryFlow.finish()
func talk() -> bool:
	life.refresh()
	player.global_position = life.residents["naru"].global_position
	return world.get_node("WorldInteractions").try_interact() and market.talking
func save_reload() -> void:
	var saved := PlayerProgress.to_save_data().duplicate(true)
	PlayerProgress.reset()
	PlayerProgress.load_save_data(saved)
func arrive() -> void:
	var site := VillageMarketFlow.site(world)
	for i in range(VillageMarketFlow.SETTINGS.participants.size()):
		var id := VillageMarketFlow.SETTINGS.participants[i]
		life.residents[id].global_position = site.global_position + Vector2(90 + i * 32, 0)
	player.global_position = site.global_position + Vector2(100, 0)
func _ready() -> void: call_deferred("run")
func run() -> void:
	world = load("res://scenes/shop/main.tscn").instantiate()
	world.get_node("TutorialDirector").enabled = false # Post-tutorial fixture; opening is tested separately.
	add_child(world)
	await settle()
	life = world.get_node("VillageLifeDirector")
	market = life.get_node("VillageMarketDirector")
	manager = world.get_node("DayManager")
	player = world.get_node("Actors/Player")
	player.set_physics_process(false)
	manager.current_hour = 6
	manager.hour_timer.paused = false
	PlayerProgress.reset()
	check(not VillageMarketFlow.accept() and not VillageMarketFlow.prepare() and not VillageMarketFlow.active(12), "locked before tutorial")
	unlock()
	PlayerProgress.story_beat_days.erase(VillageStoryFlow.PREFIX + "done")
	check(not VillageMarketFlow.accept() and VillageMarketFlow.locked_reason().contains("이세르"), "story completion required")
	VillageStoryFlow.finish()
	world.get_node("TutorialDirector").refresh()
	VillageSettlement.apply_world(world)
	life.refresh()
	var layout: Dictionary = world.get_node("StoreExterior").get_village_layout_snapshot().duplicate(true)
	var count := ResidentRequestFlow.completed_count()
	check(VillageJournalFlow.destination(world, VillageMarketFlow.JOURNAL_ID) == life.residents["naru"], "journal guides to existing giver before preparing")
	check(talk() and market.stage == "intro", "actual E offers market invitation on existing Naru")
	check(world.get_node("WorldInteractions").blocked() and manager.hour_timer.paused, "invitation holds modal clock")
	market.dialogue.close()
	check(not VillageMarketFlow.accepted() and not manager.hour_timer.paused, "partial invitation does not accept")
	check(talk(), "invitation can restart")
	drain()
	check(VillageMarketFlow.accepted() and not market.talking, "full invitation begins preparation")
	var bread := GameState.get_item_count("bread")
	var berries := GameState.get_item_count("wild_berry")
	GameState.remove_item("bread", bread)
	GameState.remove_item("wild_berry", berries)
	GameState.add_item("bread", 2)
	GameState.add_item("wild_berry", 2)
	check(not VillageMarketFlow.can_prepare() and not VillageMarketFlow.prepare() and GameState.get_item_count("bread") == 2, "missing one item consumes no supplied item")
	check(talk() and market.panel.root.visible and market.panel.cards["prepare"]["action"].disabled, "preparation E opens disabled delivery panel when short")
	market.panel.close()
	check(not VillageMarketFlow.prepared() and GameState.get_item_count("wild_berry") == 2, "closing panel consumes nothing")
	GameState.add_item("wild_berry", 1)
	check(talk() and not market.panel.cards["prepare"]["action"].disabled, "enough goods enable real delivery button")
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		await settle()
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(args[0])
	# Inventory can change while the panel is open: action must revalidate.
	GameState.remove_item("bread", 1)
	market.panel.cards["prepare"]["action"].pressed.emit()
	check(not VillageMarketFlow.prepared() and market.panel.root.visible and GameState.get_item_count("wild_berry") == 3, "stale enabled button rechecks without partial consumption")
	GameState.add_item("bread", 1)
	market.panel.refresh()
	market.panel.cards["prepare"]["action"].pressed.emit()
	check(VillageMarketFlow.prepared() and GameState.get_item_count("bread") == 0 and GameState.get_item_count("wild_berry") == 0 and not market.talking, "delivery button consumes exactly one batch and closes")
	check(not VillageMarketFlow.prepare(), "duplicate delivery rejected")
	save_reload()
	check(VillageMarketFlow.accepted() and VillageMarketFlow.prepared() and VillageMarketFlow.earliest_day() == GameState.total_day + 1, "preparation date survives saving")
	check(not VillageMarketFlow.active(12) and VillageRoutine.location(VillageLifeFlow.resident("sora"), 12)["label"] != "첫 장터", "cannot attend or gather on preparation day")
	check(talk() and market.stage == "wait", "giver explains waiting without taking goods again")
	drain()
	GameState.total_day += 1
	check(not VillageMarketFlow.active(11) and VillageMarketFlow.active(12) and VillageMarketFlow.active(16) and not VillageMarketFlow.active(17), "noon through before 17 event window")
	for id in VillageMarketFlow.SETTINGS.participants:
		check(VillageRoutine.location(VillageLifeFlow.resident(id), 12)["path"] == VillageMarketFlow.SETTINGS.site_path, "participant heads to existing stall " + id)
	manager.current_hour = 12
	player.global_position = Vector2(-3000, -3000)
	var starts: Dictionary = {}
	for id in VillageMarketFlow.SETTINGS.participants: starts[id] = life.residents[id].global_position
	life.refresh()
	for id in VillageMarketFlow.SETTINGS.participants:
		check(life.residents[id].global_position == starts[id], "schedule never teleports participant " + id)
		life.residents[id].set_physics_process(false)
	for i in range(6000):
		for id in VillageMarketFlow.SETTINGS.participants: life.residents[id]._physics_process(1.0 / 60.0)
		if i % 60 == 0: await get_tree().physics_frame
		if VillageMarketFlow.all_present(world): break
	for id in VillageMarketFlow.SETTINGS.participants:
		var npc = life.residents[id]
		print("ARRIVAL ", id, " distance=", npc.global_position.distance_to(VillageMarketFlow.site(world).global_position), " remaining=", npc.global_position.distance_to(npc.destination), " route=", npc.route.size(), " position=", npc.global_position, " target=", npc.destination)
	check(VillageMarketFlow.all_present(world), "all three actually walk along existing routes to event radius")
	check(life.residents["sora"].global_position.distance_to(starts["sora"]) > 20, "Sora walks from home to first market")
	check(VillageJournalFlow.destination(world, VillageMarketFlow.JOURNAL_ID) == VillageMarketFlow.site(world), "journal guides to real stall after preparation")
	var site := VillageMarketFlow.site(world)
	player.global_position = site.global_position + Vector2(100, 0)
	site.visible = false
	check(VillageMarketFlow.site(world) == null and not VillageMarketFlow.all_present(world) and not VillageMarketFlow.finish(12, world), "hidden stall cannot host or reward event")
	site.visible = true
	site.set_meta("settlement_layout_removed", true)
	check(VillageMarketFlow.site(world) == null, "removed stall is not recreated by quest")
	site.remove_meta("settlement_layout_removed")
	life.residents["sora"].global_position = site.global_position + Vector2(800, 0)
	check(world.get_node("WorldInteractions").try_interact() and not market.talking and not VillageMarketFlow.completed(), "event waits for distant resident")
	life.residents["sora"].visible = false
	check(not VillageMarketFlow.all_present(world), "hidden resident cannot count as present")
	life.refresh()
	arrive()
	manager.summary_open = true
	check(not market.try_interact(), "summary modal blocks celebration")
	manager.summary_open = false
	check(world.get_node("WorldInteractions").try_interact() and market.stage == "event", "actual E at stall begins shared event")
	check(market.dialogue.lines.size() >= 10 and "타블렌" in market.dialogue.lines[0] and world.get_node("WorldInteractions").blocked(), "shared event uses speaker CSV scenes and modal")
	var money := GameState.money
	var wheat := GameState.get_item_count("wheat")
	var reputation := ResidentRequestFlow.reputation()
	market.dialogue.close()
	check(not VillageMarketFlow.completed() and GameState.money == money and not manager.hour_timer.paused, "interrupted shared event grants nothing")
	GameState.total_day += 20
	save_reload()
	check(VillageMarketFlow.active(12) and VillageMarketFlow.prepared(), "missed days never expire or require second batch")
	life.refresh()
	arrive()
	manager.hour_timer.paused = true
	player.set_physics_process(true)
	check(world.get_node("WorldInteractions").try_interact(), "event retries after long absence")
	drain()
	check(VillageMarketFlow.completed() and GameState.get_item_count("wheat") == wheat + 3 and GameState.money == money + 40 and ResidentRequestFlow.reputation() == reputation + 1, "full event pays exact one-time initial rewards")
	check(manager.hour_timer.paused and player.is_physics_processing(), "preexisting clock and physics state restored")
	check(not VillageMarketFlow.finish(12, world) and not VillageMarketFlow.active(12) and market.interaction_hint().is_empty(), "completed event never repays or captures daily interactions")
	check(VillageRoutine.location(VillageLifeFlow.resident("sora"), 12)["label"] == "노점 주변", "normal routines resume after celebration")
	check(ResidentRequestFlow.completed_count() == count and GameState.get_item_count("bread") == 0 and GameState.get_item_count("wild_berry") == 0, "keeps original customer thresholds and no second consumption")
	save_reload()
	check(VillageMarketFlow.completed() and VillageJournalFlow.information(VillageMarketFlow.JOURNAL_ID).contains(RequestTextData.text("service_text", "first_market_end", "completion")), "saved journal keeps actual ending and completed date")
	check(world.get_node("StoreExterior").get_village_layout_snapshot() == layout and life.residents.size() == 3, "existing map and actors preserved")
	var sources := Tools.load_sources()
	for moment in VillageMarketFlow.SETTINGS.moments:
		check(sources[Tools.KIND_SERVICE_TEXT].has(str(moment["id"])), "writer registers scene " + str(moment["id"]))
	check(Writer.build_prompt(Tools.KIND_SERVICE_TEXT, sources, sources).contains("다음 날"), "writer gets preparation day context")
	PlayerProgress.reset()
	check(not VillageMarketFlow.accepted() and not VillageMarketFlow.prepared() and not VillageMarketFlow.completed(), "new game clears market progress")
	unlock()
	manager.current_hour = 6
	life.refresh()
	player.global_position = life.residents["naru"].global_position
	world.get_node("BuildManager").build_mode = true
	check(not market.try_interact(), "build mode blocks invitation")
	world.get_node("BuildManager").build_mode = false
	manager.hour_timer.paused = false
	player.set_physics_process(false)
	check(talk(), "invitation starts before scene exit")
	world.queue_free()
	await settle()
	check(not is_instance_valid(world) and not VillageMarketFlow.accepted(), "scene exit cannot count partial invitation")
	print("CHECK_VILLAGE_MARKET checks=", checks, " failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)
