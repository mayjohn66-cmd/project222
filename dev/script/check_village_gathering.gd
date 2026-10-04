extends Node
var failures := 0
func check(ok: bool,label: String) -> void:
	if ok: print("PASS: ",label)
	else:
		failures += 1
		push_error(label)
func settle() -> void:
	for i in range(8): await get_tree().process_frame
func _ready() -> void: call_deferred("run")
func run() -> void:
	var world = load("res://scenes/shop/main.tscn").instantiate()
	world.get_node("TutorialDirector").enabled = false # Post-tutorial fixture; opening is tested separately.
	add_child(world)
	await settle()
	var life: VillageLifeDirector = world.get_node("VillageLifeDirector")
	var gathering: VillageGatheringDirector = world.get_node("VillageGatheringDirector")
	var manager = world.get_node("DayManager")
	var player = world.get_node("Actors/Player")
	var board = world.get_node("CommunityBoardDirector")
	check(not VillageGatheringFlow.active(18),"unprepared gathering is unavailable")
	for step in TutorialDirector.SETTINGS.steps: PlayerProgress.record_story_beat("tutorial_step:" + str(step["id"]) + ":done",GameState.total_day)
	PlayerProgress.record_story_beat(CheckoutTutorial.BEAT_ID,GameState.total_day)
	world.get_node("TutorialDirector").refresh()
	for resident in VillageLifeFlow.SETTINGS.residents:
		PlayerProgress.record_story_beat(ResidentRequestFlow.PREFIX + str(resident["request"]) + ":done",GameState.total_day)
		PlayerProgress.story_beat_days[VillageLifeFlow.PREFIX + "friendship:" + str(resident["id"])] = 3
	check(not CommunityRequestFlow.accept("well_gathering"),"flower corner required before preparations")
	PlayerProgress.record_story_beat(CommunityRequestFlow.PREFIX + "flower_corner:done",GameState.total_day)
	PlayerProgress.story_beat_days[VillageLifeFlow.PREFIX + "friendship:naru"] = 2
	check(not CommunityRequestFlow.accept("well_gathering"),"all three participants need friendship")
	PlayerProgress.story_beat_days[VillageLifeFlow.PREFIX + "friendship:naru"] = 3
	VillageSettlement.apply_world(world)
	player.set_physics_process(false)
	player.global_position = VillageSettlement.find_site(world,CommunityRequestFlow.SETTINGS.board_path).global_position
	check(board.try_interact(),"actual board opens preparation")
	board.panel.cards["well_gathering"]["action"].pressed.emit()
	check(CommunityRequestFlow.accepted("well_gathering"),"preparation explicitly accepted")
	for item in ["bread","water"]: GameState.remove_item(item,GameState.get_item_count(item))
	GameState.add_item("bread",3)
	check(CommunityRequestFlow.deliver("well_gathering").is_empty() and GameState.get_item_count("bread") == 3,"missing water causes no partial deduction")
	GameState.add_item("water",3)
	var money := GameState.money
	var reputation := ResidentRequestFlow.reputation()
	board.panel.refresh()
	board.panel.cards["well_gathering"]["action"].pressed.emit()
	check(VillageGatheringFlow.pending() and GameState.money == money + 40 and ResidentRequestFlow.reputation() == reputation + 1,"preparation grants exact reward and opens event")
	check(GameState.get_item_count("bread") == 0 and GameState.get_item_count("water") == 0,"preparation consumes exact materials")
	check(CommunityRequestFlow.deliver("well_gathering").is_empty(),"preparation reward cannot repeat")
	board.panel.close()
	var saved := PlayerProgress.to_save_data().duplicate(true)
	PlayerProgress.reset()
	PlayerProgress.load_save_data(saved)
	GameState.total_day += 30
	check(VillageGatheringFlow.pending() and not VillageGatheringFlow.active(0) and VillageGatheringFlow.active(18),"saved preparation has no expiry and returns each evening")
	manager.current_hour = 18
	manager.hour_timer.paused = false
	player.global_position = Vector2(-3000,-3000)
	life.refresh()
	await settle()
	var site := VillageGatheringFlow.site(world)
	check(site != null,"gathering uses existing visible bench")
	check(VillageJournalFlow.destination(world,"gathering:well_evening") == site,"journal guides to actual bench")
	for id in VillageGatheringFlow.SETTINGS.participants:
		var npc: VillageResident = life.residents[id]
		check(npc.routine_label == "저녁 모임","resident schedule joins gathering " + id)
		npc.set_physics_process(false)
		for i in range(6000):
			npc._physics_process(1.0 / 60.0)
			if npc.global_position.distance_to(npc.destination) < 2.1: break
		check(npc.global_position.distance_to(site.global_position) <= VillageGatheringFlow.SETTINGS.arrival_distance,"resident physically reaches meeting " + id)
	check(VillageGatheringFlow.all_present(world),"all three neighbors are physically present")
	player.global_position = site.global_position
	world.get_node("BuildManager").build_mode = true
	check(not gathering.try_interact(),"construction blocks gathering")
	world.get_node("BuildManager").build_mode = false
	manager.current_hour = 12
	check(not gathering.try_interact(),"gathering cannot begin before evening")
	manager.current_hour = 18
	check(world.get_node("WorldInteractions").try_interact() and gathering.talking,"actual E interaction starts gathering before nearby resident greeting")
	check(manager.hour_timer.paused and not player.is_physics_processing() and world.get_node("WorldInteractions").blocked(),"group scene pauses clock movement and other panels")
	check(not life.residents["naru"].title.visible and not world.get_node("ResidentRequestDirector").panel.root.visible,"group dialogue hides overlapping names and request guidance")
	check("행상인 타블렌:" in "|".join(gathering.dialogue.lines) and "채굴꾼 코르빈:" in "|".join(gathering.dialogue.lines) and "여행자 이세르:" in "|".join(gathering.dialogue.lines),"all speakers use current display names")
	gathering.dialogue.close()
	check(VillageGatheringFlow.pending() and not manager.hour_timer.paused,"interrupted scene restores clock and remains retryable")
	check(life.residents["naru"].title.visible,"closing group scene restores resident names")
	check(gathering.try_interact(),"interrupted gathering starts again")
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		gathering.dialogue._advance()
		gathering.dialogue._advance()
		gathering.dialogue._advance()
		await settle()
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(args[0])
	for i in range(40):
		if not gathering.dialogue.open: break
		gathering.dialogue._advance()
	check(VillageGatheringFlow.completed() and not VillageGatheringFlow.pending(),"finishing group scene records memory exactly once")
	check(not manager.hour_timer.paused and not player.is_physics_processing(),"original clock and physics flags restored")
	check(not gathering.try_interact() and not VillageGatheringFlow.finish(),"completed gathering cannot replay or double record")
	check(VillageJournalFlow.information("gathering:well_evening").contains("함께 쉬어 간 날"),"journal keeps shared memory date")
	saved = PlayerProgress.to_save_data().duplicate(true)
	PlayerProgress.reset()
	PlayerProgress.load_save_data(saved)
	check(VillageGatheringFlow.completed(),"completion survives save reload")
	check(VillageRoutine.location(VillageLifeFlow.resident("naru"),18)["label"] == "우물 곁","resident resumes normal evening schedule")
	PlayerProgress.reset()
	check(not VillageGatheringFlow.completed() and not VillageGatheringFlow.pending(),"new game clears gathering memory and preparation")
	print("CHECK_VILLAGE_GATHERING failures=",failures)
	get_tree().quit(0 if failures == 0 else 1)
