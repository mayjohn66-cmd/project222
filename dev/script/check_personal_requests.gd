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
	PlayerProgress.reset()
	check(not PersonalRequestFlow.accepted("naru_provisions") and not PersonalRequestFlow.done("naru_provisions"),"new game clears personal history")
	print("CHECK_PERSONAL_REQUESTS failures=",failures)
	get_tree().quit(0 if failures == 0 else 1)
