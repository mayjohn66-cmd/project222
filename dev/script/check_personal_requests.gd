extends Node
var failures := 0
func check(ok: bool,label: String) -> void:
	if ok: print("PASS: ",label)
	else:
		failures += 1
		push_error(label)
func _ready() -> void: call_deferred("run")
func run() -> void:
	var world = load("res://scenes/shop/main.tscn").instantiate()
	world.get_node("TutorialDirector").enabled = false
	world.get_node("VillageLifeDirector").crafting_path_enabled = false
	add_child(world)
	for i in range(10): await get_tree().process_frame
	for step in TutorialDirector.SETTINGS.steps: PlayerProgress.record_story_beat("tutorial_step:" + str(step["id"]) + ":done",GameState.total_day)
	PlayerProgress.record_story_beat(CheckoutTutorial.BEAT_ID,GameState.total_day)
	world.get_node("TutorialDirector").refresh()
	var board = world.get_node("CommunityBoardDirector")
	var text_tools = load("res://dev/gemini/request_text_tools.gd")
	var sources: Dictionary = text_tools.load_sources()
	var prose_rows: Array = []
	for entry in PersonalRequestFlow.entries():
		prose_rows.append(text_tools.row_from_source("personal_request",sources["personal_request"][entry["id"]]))
	check(text_tools.validate_rows(text_tools.COLUMNS,prose_rows,sources)["errors"].is_empty(),"new prose passes writer validation")
	check(board.panel.cards.has("personal:naru_provisions"),"personal cards coexist with community cards")
	for entry in PersonalRequestFlow.entries():
		if entry.has("after"): continue # 후속 부탁은 아래에서 선행·모임·날짜 조건을 함께 검증한다.
		if entry.has("stockpile_season"): continue # 계절·장기 보관은 check_seasonal_expedition에서 실제 전달로 검사한다.
		var id := str(entry["id"])
		var resident := str(entry["resident"])
		check(not PersonalRequestFlow.accept(id),"unsettled resident cannot offer " + id)
		PlayerProgress.record_story_beat(ResidentRequestFlow.PREFIX + str(VillageLifeFlow.resident(resident)["request"]) + ":done",GameState.total_day)
		check(not PersonalRequestFlow.accept(id),"friendship gate " + id)
		PlayerProgress.story_beat_days[VillageLifeFlow.PREFIX + "friendship:" + resident] = int(entry["friendship"])
		check(PersonalRequestFlow.accept(id) and not PersonalRequestFlow.accept(id),"accept exactly once " + id)
		var saved := PlayerProgress.to_save_data().duplicate(true)
		PlayerProgress.reset()
		PlayerProgress.load_save_data(saved)
		check(PersonalRequestFlow.accepted(id),"accepted request survives save roundtrip " + id)
		for item in CommunityRequestFlow.required_items(entry): GameState.remove_item(item,GameState.get_item_count(item))
		var money := GameState.money
		check(PersonalRequestFlow.deliver(id).is_empty() and GameState.money == money,"missing materials grant nothing " + id)
		for item in CommunityRequestFlow.required_items(entry): GameState.add_item(item,int(CommunityRequestFlow.required_items(entry)[item]))
		var reputation := ResidentRequestFlow.reputation()
		var count := ResidentRequestFlow.completed_count()
		check(not PersonalRequestFlow.deliver(id).is_empty(),"prepared materials deliver " + id)
		check(GameState.money == money + int(entry["money"]) and ResidentRequestFlow.reputation() == reputation + int(entry["reputation"]),"exact reward " + id)
		check(ResidentRequestFlow.completed_count() == count,"personal quest does not change customer unlock counter")
		for item in CommunityRequestFlow.required_items(entry): check(GameState.get_item_count(item) == 0,"exact material deduction " + id)
		check(PersonalRequestFlow.deliver(id).is_empty(),"no duplicate reward " + id)
		check(VillageJournalFlow.information("personal:" + id).contains("함께 완료한 날"),"journal completion memory " + id)
		var completed_save := PlayerProgress.to_save_data().duplicate(true)
		PlayerProgress.reset()
		PlayerProgress.load_save_data(completed_save)
		check(PersonalRequestFlow.done(id) and PersonalRequestFlow.deliver(id).is_empty(),"completed history survives reload without reward " + id)
	VillageSettlement.apply_world(world)
	world.get_node("VillageLifeDirector").refresh()
	var npc = world.get_node("VillageLifeDirector").residents["naru"]
	var player = world.get_node("Actors/Player")
	player.set_physics_process(false)
	player.global_position = npc.global_position
	check(world.get_node("VillageLifeDirector").try_interact(),"existing greeting remains available")
	world.get_node("VillageLifeDirector").dialogue.close()
	var site := VillageSettlement.find_site(world,CommunityRequestFlow.SETTINGS.board_path)
	player.global_position = site.global_position
	check(board.try_interact(),"actual board opens personal request panel")
	board.panel.refresh()
	check(board.panel.cards["personal:naru_provisions"]["action"].disabled,"completed action disabled")
	PlayerProgress.story_beat_days.erase(PersonalRequestFlow.PREFIX + "naru_provisions:accepted")
	PlayerProgress.story_beat_days.erase(PersonalRequestFlow.PREFIX + "naru_provisions:done")
	board.panel.refresh()
	board.panel.cards["personal:naru_provisions"]["action"].pressed.emit()
	check(PersonalRequestFlow.accepted("naru_provisions"),"actual card action accepts request")
	GameState.add_item("bread",3)
	board.panel.refresh()
	board.panel.cards["personal:naru_provisions"]["action"].pressed.emit()
	check(PersonalRequestFlow.done("naru_provisions"),"actual card action delivers request")
	for size in [Vector2i(1152,648),Vector2i(593,523),Vector2i(800,450)]:
		get_window().size = size
		board.panel._fit_screen()
		for i in range(3): await get_tree().process_frame
		check(get_viewport().get_visible_rect().encloses(board.panel.root.get_global_rect()) and board.panel.root.get_global_rect().encloses(board.panel.close_button.get_global_rect()),"close button remains visible " + str(size))
	get_window().size = Vector2i(1152,648)
	board.panel._fit_screen()
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		for i in range(3): await get_tree().process_frame
		var scroll: ScrollContainer = board.panel.root.get_child(0).get_child(2)
		scroll.scroll_vertical = 10000
		for i in range(3): await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(args[0])
	board.panel.close()
	await _check_followups(world)
	PlayerProgress.reset()
	check(not PersonalRequestFlow.accepted("naru_provisions") and not PersonalRequestFlow.done("naru_provisions"),"new game clears personal history")
	print("CHECK_PERSONAL_REQUESTS failures=",failures)
	get_tree().quit(0 if failures == 0 else 1)

func _check_followups(world: Node) -> void:
	var saved := PlayerProgress.to_save_data().duplicate(true)
	var initial_day := GameState.total_day
	var board = world.get_node("CommunityBoardDirector")
	var life = world.get_node("VillageLifeDirector")
	var player = world.get_node("Actors/Player")
	for entry in PersonalRequestFlow.entries():
		if not entry.has("after"): continue
		if bool(entry.get("after_market", false)) or bool(entry.get("after_rest", false)) or entry.has("after_store_event"): continue # 장터·쉼터·매장 행사 후속은 각 조건을 해당 콘텐츠 검사에서 별도 확인.
		PlayerProgress.load_save_data(saved)
		GameState.total_day = initial_day
		var id := str(entry["id"])
		var resident := str(entry["resident"])
		var after := str(entry["after"])
		var friend_key := VillageLifeFlow.PREFIX + "friendship:" + resident
		PlayerProgress.story_beat_days[friend_key] = int(entry["friendship"])
		PlayerProgress.story_beat_days.erase(PersonalRequestFlow.PREFIX + after + ":done")
		check(not PersonalRequestFlow.accept(id) and PersonalRequestFlow.locked_reason(entry).contains("앞선 개인 부탁"),"followup requires its own first request: " + id)
		PlayerProgress.record_story_beat(PersonalRequestFlow.PREFIX + after + ":done",initial_day)
		PlayerProgress.story_beat_days.erase(VillageGatheringFlow.COMPLETED)
		check(not PersonalRequestFlow.accept(id) and PersonalRequestFlow.locked_reason(entry).contains("저녁 모임"),"preparing the gathering alone does not unlock followup: " + id)
		PlayerProgress.record_story_beat(VillageGatheringFlow.COMPLETED,initial_day)
		board.panel.refresh()
		check(not PersonalRequestFlow.accept(id) and board.panel.cards["personal:" + id]["action"].disabled,"same-day followup remains locked on real board: " + id)
		check(VillageJournalFlow.destination(world,"personal:" + id) == null and VillageJournalFlow.information("personal:" + id).contains("1일 후"),"journal explains wait and hides locked destination: " + id)
		GameState.total_day += int(entry["days_after"])
		PlayerProgress.story_beat_days[friend_key] = int(entry["friendship"]) - 1
		check(not PersonalRequestFlow.accept(id),"followup still requires enough greeting days: " + id)
		PlayerProgress.story_beat_days[friend_key] = int(entry["friendship"])
		check(PersonalRequestFlow.locked_reason(entry).is_empty(),"next day unlocks followup with no automatic acceptance: " + id)
		check(not PersonalRequestFlow.accepted(id),"unlock does not accept for player: " + id)
		# Either prerequisite may finish later; wait from the most recent event.
		PlayerProgress.story_beat_days[PersonalRequestFlow.PREFIX + after + ":done"] = GameState.total_day
		check(not PersonalRequestFlow.accept(id),"late first request starts its own wait: " + id)
		GameState.total_day += 30
		var old_state := PlayerProgress.to_save_data().duplicate(true)
		PlayerProgress.reset()
		PlayerProgress.load_save_data(old_state)
		check(PersonalRequestFlow.locked_reason(entry).is_empty(),"old save and long absence preserve followup opportunity: " + id)
		VillageSettlement.apply_world(world)
		life.refresh()
		player.set_physics_process(false)
		player.global_position = life.residents[resident].global_position
		check(life.try_interact(),"resident offers followup during actual greeting: " + id)
		check("|".join(life.dialogue.lines).contains(RequestTextData.lines("personal_request",id)[0]),"greeting uses followup CSV lines: " + id)
		life.dialogue.close()
		var site := VillageSettlement.find_site(world,CommunityRequestFlow.SETTINGS.board_path)
		player.global_position = site.global_position
		check(board.try_interact(),"actual board opens for followup: " + id)
		board.panel.cards["personal:" + id]["action"].pressed.emit()
		check(PersonalRequestFlow.accepted(id) and not PersonalRequestFlow.accept(id),"real card accepts once: " + id)
		var accepted_save := PlayerProgress.to_save_data().duplicate(true)
		PlayerProgress.reset()
		PlayerProgress.load_save_data(accepted_save)
		var totals := CommunityRequestFlow.required_items(entry)
		var items: Array = totals.keys()
		check(items.size() == 2,"followup uses two existing resources: " + id)
		for item in items: GameState.remove_item(item,GameState.get_item_count(item))
		GameState.add_item(items[0],int(totals[items[0]]))
		var money := GameState.money
		var reputation := ResidentRequestFlow.reputation()
		check(PersonalRequestFlow.deliver(id).is_empty() and GameState.get_item_count(items[0]) == totals[items[0]] and GameState.money == money,"partial preparation never deducts or rewards: " + id)
		for item in items: GameState.add_item(item,maxi(0,int(totals[item]) - GameState.get_item_count(item)))
		var counter := ResidentRequestFlow.completed_count()
		board.panel.refresh()
		board.panel.cards["personal:" + id]["action"].pressed.emit()
		check(PersonalRequestFlow.done(id) and board.panel.cards["personal:" + id]["action"].disabled,"real card delivers and becomes completed: " + id)
		check(GameState.money == money + int(entry["money"]) and ResidentRequestFlow.reputation() == reputation + int(entry["reputation"]),"followup exact small reward: " + id)
		for item in items: check(GameState.get_item_count(item) == 0,"followup exact resource deduction: " + id + "/" + str(item))
		check(ResidentRequestFlow.completed_count() == counter,"followup keeps original new-customer thresholds: " + id)
		check(VillageJournalFlow.information("personal:" + id).contains(str(entry["completion"])) and VillageJournalFlow.destination(world,"personal:" + id) == life.residents[resident],"journal keeps memory and points to resident: " + id)
		var done_state := PlayerProgress.to_save_data().duplicate(true)
		PlayerProgress.reset()
		PlayerProgress.load_save_data(done_state)
		check(PersonalRequestFlow.done(id) and PersonalRequestFlow.deliver(id).is_empty(),"reload cannot duplicate completed followup reward: " + id)
		board.panel.close()
		await get_tree().process_frame
	PlayerProgress.load_save_data(saved)
	GameState.total_day = initial_day
	PlayerProgress.reset()
	for entry in PersonalRequestFlow.entries():
		if entry.has("after"): check(not PersonalRequestFlow.accepted(str(entry["id"])) and not PersonalRequestFlow.done(str(entry["id"])),"new game clears followup history: " + str(entry["id"]))
