extends Node
const Tools = preload("res://dev/gemini/request_text_tools.gd")
const Writer = preload("res://dev/gemini/request_text_runner.gd")
var checks := 0
var failures := 0
var world
var life: VillageLifeDirector
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
		if not life.dialogue.open: return
		life.dialogue._advance()
	check(false, "conversation ends")

func unlock() -> void:
	for step in TutorialDirector.SETTINGS.steps: PlayerProgress.record_story_beat("tutorial_step:" + str(step["id"]) + ":done", GameState.total_day)
	PlayerProgress.record_story_beat(CheckoutTutorial.BEAT_ID, GameState.total_day)
	for resident in VillageLifeFlow.SETTINGS.residents:
		PlayerProgress.record_story_beat(ResidentRequestFlow.PREFIX + str(resident["request"]) + ":done", GameState.total_day)
		PlayerProgress.story_beat_days[VillageLifeFlow.PREFIX + "friendship:" + str(resident["id"])] = 7
	PlayerProgress.record_story_beat(PersonalRequestFlow.PREFIX + VillageStoryFlow.SETTINGS.after_request + ":done", GameState.total_day)
	PlayerProgress.record_story_beat(VillageGatheringFlow.COMPLETED, GameState.total_day)
	PlayerProgress.record_story_beat(VillageStoryFlow.SETTINGS.after_event, GameState.total_day)

func talk(id: String) -> bool:
	life.refresh()
	var npc = life.residents.get(id)
	if not is_instance_valid(npc): return false
	player.global_position = npc.global_position
	return world.get_node("WorldInteractions").try_interact() and life.talking

func save_reload() -> void:
	var saved := PlayerProgress.to_save_data().duplicate(true)
	PlayerProgress.reset()
	PlayerProgress.load_save_data(saved)

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
	manager = world.get_node("DayManager")
	player = world.get_node("Actors/Player")
	player.set_physics_process(false)
	manager.current_hour = 6
	manager.hour_timer.paused = false
	PlayerProgress.reset()
	check(not VillageStoryFlow.accept() and not VillageStoryFlow.listen("naru") and not VillageStoryFlow.select("home") and not VillageStoryFlow.finish(), "quest actions unavailable before tutorial and prerequisites")
	unlock()
	var notes_key := PersonalRequestFlow.PREFIX + VillageStoryFlow.SETTINGS.after_request + ":done"
	PlayerProgress.story_beat_days.erase(notes_key)
	check(not VillageStoryFlow.accept() and VillageStoryFlow.locked_reason().contains("우물 곁 기록"), "previous notes request is required")
	PlayerProgress.record_story_beat(notes_key, GameState.total_day)
	PlayerProgress.story_beat_days.erase(VillageStoryFlow.SETTINGS.after_event)
	check(not VillageStoryFlow.accept() and VillageStoryFlow.locked_reason().contains("길손"), "completed reunion is required in content order")
	PlayerProgress.record_story_beat(VillageStoryFlow.SETTINGS.after_event, GameState.total_day)
	PlayerProgress.story_beat_days.erase(VillageGatheringFlow.COMPLETED)
	check(not VillageStoryFlow.accept(), "actual evening gathering also required")
	PlayerProgress.record_story_beat(VillageGatheringFlow.COMPLETED, GameState.total_day)
	world.get_node("TutorialDirector").refresh()
	VillageSettlement.apply_world(world)
	life.refresh()
	var layout: Dictionary = world.get_node("StoreExterior").get_village_layout_snapshot().duplicate(true)
	var base_count := ResidentRequestFlow.completed_count()
	var original_money := GameState.money
	check(talk("naru"), "actual participant conversation works before acceptance")
	drain()
	check(not VillageStoryFlow.heard("naru"), "earlier daily greeting does not count as requested story")
	check(VillageJournalFlow.destination(world,VillageStoryFlow.JOURNAL_ID) == life.residents["sora"], "journal initially guides to giver")
	check(talk("sora") and life.story_action.get("stage") == "introduction", "existing Sora offers story during actual E conversation")
	life.dialogue.close()
	check(not VillageStoryFlow.accepted() and not manager.hour_timer.paused, "interrupted invitation does not accept and restores clock")
	check(talk("sora"), "invitation can restart")
	drain()
	check(VillageStoryFlow.accepted() and not VillageStoryFlow.ready() and not life.talking, "full invitation accepts without auto counting participants")
	check(not VillageStoryFlow.listen("unknown") and not VillageStoryFlow.listen("sora") and not VillageStoryFlow.select("lantern"), "unknown participant giver and early choice are rejected")
	save_reload()
	GameState.total_day += 30
	check(VillageStoryFlow.accepted() and VillageStoryFlow.locked_reason().is_empty(), "accepted story survives saving and long absence with no deadline")
	check(VillageJournalFlow.destination(world,VillageStoryFlow.JOURNAL_ID) == life.residents["naru"], "journal guides to first unheard resident")
	# Either participant order is valid; read Doyun first.
	check(talk("doyun") and life.story_action.get("stage") == "listen", "actual participant dialogue appends requested story")
	check("집에 돌아와" in "|".join(life.dialogue.lines), "participant scene loads its CSV text")
	life.dialogue.close()
	check(not VillageStoryFlow.heard("doyun"), "interrupted participant does not count")
	check(talk("doyun"), "participant story can restart")
	drain()
	check(VillageStoryFlow.heard("doyun") and not VillageStoryFlow.ready(), "one complete story recorded")
	check(talk("sora") and life.story_action.get("stage") == "reminder", "giver reminds player of missing story")
	drain()
	check(not life.story_panel.root.visible and not VillageStoryFlow.ready(), "reminder cannot open choices before both stories")
	check(talk("naru"), "second participant actual dialogue works")
	drain()
	check(VillageStoryFlow.heard("naru") and VillageStoryFlow.ready(), "complete second story opens return to giver")
	check(not VillageStoryFlow.listen("naru"), "repeat listening cannot duplicate progress")
	save_reload()
	check(VillageStoryFlow.ready() and VillageJournalFlow.destination(world,VillageStoryFlow.JOURNAL_ID) == life.residents["sora"], "saved stories guide back to Sora")
	check(talk("sora"), "return conversation starts")
	life.dialogue.close()
	check(not life.story_panel.root.visible, "interrupted return does not open choice screen")
	check(talk("sora"), "return conversation restarts")
	drain()
	check(life.story_panel.root.visible and world.get_node("WorldInteractions").blocked() and manager.hour_timer.paused, "complete return transfers to modal memory selection")
	check(life.story_panel.cards.size() == 3, "three equal memories offered")
	life.story_panel.close()
	check(VillageStoryFlow.chosen().is_empty() and not life.talking and not manager.hour_timer.paused, "postponing selection records nothing and restores previous state")
	check(talk("sora"), "postponed selection can reopen")
	drain()
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		await settle()
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(args[0])
	var herb_before := GameState.get_item_count("forest_herb")
	var reputation := ResidentRequestFlow.reputation()
	var bread_before := GameState.get_item_count("bread")
	var iron_before := GameState.get_item_count("iron_ore")
	check(not VillageStoryFlow.select("unknown"), "unknown memory cannot be selected")
	life.story_panel.cards["lantern"]["action"].pressed.emit()
	check(VillageStoryFlow.chosen() == "lantern" and life.dialogue.open and not life.story_panel.root.visible, "actual memory button saves choice and begins conclusion")
	check(not VillageStoryFlow.select("home") and not VillageStoryFlow.completed() and GameState.get_item_count("forest_herb") == herb_before, "choice is fixed but not rewarded until conclusion")
	life.dialogue.close()
	save_reload()
	check(VillageStoryFlow.chosen() == "lantern" and not VillageStoryFlow.completed(), "interrupted conclusion preserves choice after reload")
	manager.hour_timer.paused = true
	player.set_physics_process(true)
	check(talk("sora") and life.story_action.get("stage") == "finish", "selected memory resumes conclusion without choosing again")
	drain()
	check(VillageStoryFlow.completed() and GameState.get_item_count("forest_herb") == herb_before + 2 and ResidentRequestFlow.reputation() == reputation + 1, "conclusion grants exact small herb and reputation reward")
	check(manager.hour_timer.paused and player.is_physics_processing(), "preexisting paused clock and enabled physics restored")
	check(GameState.money == original_money and GameState.get_item_count("bread") == bread_before and GameState.get_item_count("iron_ore") == iron_before, "story consumes no materials and pays no money")
	check(ResidentRequestFlow.completed_count() == base_count and not VillageStoryFlow.finish(), "story never changes original customer thresholds or repeats reward")
	check(VillageJournalFlow.information(VillageStoryFlow.JOURNAL_ID).contains("길을 밝힌 불빛") and VillageJournalFlow.information(VillageStoryFlow.JOURNAL_ID).contains(RequestTextData.text("service_text","village_story_lantern","completion")), "journal preserves selected title and actual memory text")
	save_reload()
	check(VillageStoryFlow.completed() and VillageStoryFlow.chosen() == "lantern", "completed memory survives saving")
	check(talk("sora") and life.story_action.get("stage") == "memory", "giver retells completed memory during normal greeting")
	check("낯선 길손" in "|".join(life.dialogue.lines), "memory reread uses selected conclusion CSV")
	drain()
	check(GameState.get_item_count("forest_herb") == herb_before + 2 and ResidentRequestFlow.reputation() == reputation + 1, "rereading does not duplicate story reward")
	# Verify alternative memories retain different journal text and the same reward.
	for id in ["evening","home"]:
		for key in PlayerProgress.story_beat_days.keys():
			if str(key).begins_with(VillageStoryFlow.PREFIX): PlayerProgress.story_beat_days.erase(key)
		PlayerProgress.story_beat_days.erase(ResidentRequestFlow.PREFIX + "reputation:story/sora_village_story")
		check(VillageStoryFlow.accept() and VillageStoryFlow.listen("naru") and VillageStoryFlow.listen("doyun"), "alternative has complete conversation progress " + id)
		check(talk("sora"), "alternative return opens " + id)
		drain()
		herb_before = GameState.get_item_count("forest_herb")
		reputation = ResidentRequestFlow.reputation()
		life.story_panel.cards[id]["action"].pressed.emit()
		check(life.dialogue.lines.has(RequestTextData.lines("service_text","village_story_" + id)[0]), "alternative button loads distinct conclusion " + id)
		drain()
		check(VillageStoryFlow.completed() and VillageStoryFlow.chosen() == id and GameState.get_item_count("forest_herb") == herb_before + 2 and ResidentRequestFlow.reputation() == reputation + 1, "alternative keeps same reward amount " + id)
		check(VillageJournalFlow.information(VillageStoryFlow.JOURNAL_ID).contains(RequestTextData.text("service_text","village_story_" + id,"completion")), "alternative journal memory differs " + id)
	check(world.get_node("StoreExterior").get_village_layout_snapshot() == layout and life.residents.size() == 3, "quest preserves map and existing three actors")
	var sources := Tools.load_sources()
	for moment in VillageStoryFlow.SETTINGS.moments:
		check(sources[Tools.KIND_SERVICE_TEXT].has(str(moment["id"])), "writer registers story scene " + str(moment["id"]))
	var prompt := Writer.build_prompt(Tools.KIND_SERVICE_TEXT,sources,sources)
	check(prompt.contains("불빛·저녁 모임·정착") and prompt.contains("끝까지 들으면"), "writer receives choices and full conversation conditions")
	PlayerProgress.reset()
	check(VillageStoryFlow.chosen().is_empty() and not VillageStoryFlow.accepted() and not VillageStoryFlow.heard("naru") and not VillageStoryFlow.completed(), "new game clears story progress")
	unlock()
	life.refresh()
	player.global_position = life.residents["sora"].global_position
	world.get_node("BuildManager").build_mode = true
	check(not life.try_interact(), "build mode blocks story")
	world.get_node("BuildManager").build_mode = false
	manager.hour_timer.paused = false
	player.set_physics_process(false)
	check(talk("sora"), "start invitation before leaving scene")
	world.queue_free()
	await settle()
	check(not is_instance_valid(world) and not VillageStoryFlow.accepted(), "unloading whole scene does not accept interrupted story")
	print("CHECK_VILLAGE_STORY checks=", checks, " failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)
