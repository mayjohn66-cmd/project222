extends Node
var failures := 0
var world

func check(ok: bool, text_value: String) -> void:
	if ok: print("PASS: ",text_value)
	else:
		failures += 1
		push_error(text_value)

func settle() -> void:
	for i in range(8): await get_tree().process_frame

func click(button: Button) -> void:
	for pressed in [true,false]:
		var event := InputEventMouseButton.new()
		event.position = button.get_global_rect().get_center()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		get_viewport().push_input(event,true)
	await settle()

func key(code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	get_viewport().push_input(event,true)
	await settle()

# 책의 일정 탭 "마을 수첩"에서 제목이 title 인 칸의 목적지 단추
func book_button(menu, title: String) -> Button:
	var notebook := menu.request_list.get_node_or_null("RequestNotebook") as RequestNotebookView
	if notebook == null: return null
	for row in notebook.rows:
		if row["title"] == title:
			notebook._select_category(str(row["category"]))
			notebook._select(str(row["id"]))
			return notebook.detail_page.get_node_or_null("RequestDestination") as Button
	return null

func _ready() -> void: call_deferred("run")

func run() -> void:
	world = load("res://scenes/shop/main.tscn").instantiate()
	world.get_node("TutorialDirector").enabled = false
	world.get_node("VillageLifeDirector").crafting_path_enabled = false
	add_child(world)
	await settle()
	var journal: VillageJournalDirector = world.get_node("VillageJournalDirector")
	var player = world.get_node("Actors/Player")
	var manager = world.get_node("DayManager")
	var menu: ManagementMenu = world.get_node("UI/ManagementMenu")
	await key(KEY_N)
	check(not VillageJournalFlow.available() and not journal.try_interact() and not menu.visible, "journal waits for tutorial completion (N opens nothing)")
	for step in TutorialDirector.SETTINGS.steps:
		PlayerProgress.record_story_beat("tutorial_step:" + str(step["id"]) + ":done",GameState.total_day)
	PlayerProgress.record_story_beat(CheckoutTutorial.BEAT_ID,GameState.total_day)
	world.get_node("TutorialDirector").refresh()
	world.get_node("ResidentRequestDirector").refresh()
	await settle()
	check(VillageJournalFlow.available() and world.get_node_or_null("UI/VillageJournalButton") == null, "journal becomes available without settlement and has no floating button")
	check(VillageJournalFlow.destination(world,"resident:naru") == null and VillageJournalFlow.destination(world,"place:settle_naru") == null, "hidden residents and places cannot be tracked")
	check(not VillageJournalFlow.information("next_request").is_empty(), "next request gives current action and warehouse counts")
	check(RequestNotebookData.entries().is_empty(), "unaccepted future requests are not prewritten in the book")
	check(ResidentRequestFlow.accept(ResidentRequestFlow.current()), "fixture records a real accepted resident request")
	var request_title := str(ResidentRequestFlow.current()["title"])
	player.set_physics_process(false)
	manager.hour_timer.paused = false
	var progress_before := PlayerProgress.to_save_data().duplicate(true)
	var money_before: int = GameState.get_money()
	var inventory_before: Dictionary = GameState.inventory.duplicate(true)
	await key(KEY_N)
	check(menu.visible and menu.current_tab == ManagementMenu.MenuTab.REQUESTS, "N opens the management book on the schedule tab")
	var next_button := book_button(menu, request_title)
	check(next_button != null and not next_button.disabled, "book lists the village journal and the current request NPC can be marked")
	await click(next_button)
	check(journal.tracked_id == "request:neighbor_bread", "actual action selects destination")
	check(book_button(menu, request_title).text == "표시 해제", "book button flips to clear after marking")
	await key(KEY_ESCAPE)
	check(not menu.visible and not manager.hour_timer.paused and not player.is_physics_processing(), "Escape closes the book and restores clock and exact movement state")
	check(journal.marker.is_inside_tree() and journal.marker.visible and journal.guidance.visible, "marker and directional hint appear after closing")
	check(PlayerProgress.to_save_data() == progress_before and GameState.get_money() == money_before and GameState.inventory == inventory_before, "viewing and tracking award nothing and preserve saved progress")
	await key(KEY_N)
	check(menu.visible and menu.current_tab == ManagementMenu.MenuTab.REQUESTS, "N opens the book again")
	await click(book_button(menu, request_title))
	check(journal.tracked_id.is_empty(), "same card clears the marked destination")
	await key(KEY_ESCAPE)
	check(not menu.visible and not journal.marker.visible, "Escape closes the book and no marker remains")
	PlayerProgress.record_story_beat(ResidentRequestFlow.PREFIX + "settle_naru:done",GameState.total_day)
	VillageSettlement.apply_world(world)
	world.get_node("VillageLifeDirector").refresh()
	await settle()
	check(VillageJournalFlow.destination(world,"resident:naru") != null and VillageJournalFlow.destination(world,"place:settle_naru") != null, "settled neighbor and user-placed stall become destinations")
	VillageLifeFlow.greet("naru")
	check(VillageJournalFlow.information("resident:naru").contains("오늘 안부를 나눴습니다"), "today greeting appears in journal")
	GameState.total_day += 1
	check(VillageJournalFlow.information("resident:naru").contains("아직 안부"), "next day updates greeting status without losing friendship")
	var saved := PlayerProgress.to_save_data()
	PlayerProgress.reset()
	PlayerProgress.load_save_data(saved)
	check(VillageJournalFlow.information("place:settle_naru").contains("함께 만든 날") and VillageLifeFlow.friendship("naru") == 1, "journal reconstructs milestones from existing saved data")
	check(VillageJournalFlow.destination(world,"community:path_light") != null, "unlocked community request points at board")
	PlayerProgress.record_story_beat(CommunityRequestFlow.PREFIX + "path_light:done",GameState.total_day)
	VillageSettlement.apply_world(world)
	check(VillageJournalFlow.destination(world,"community:path_light") == VillageSettlement.find_site(world,"VillageGathering/MarketLantern"), "completed community request points at actual landmark")
	await key(KEY_N)
	check(menu.visible and book_button(menu, "행상인 타블렌") != null, "settled neighbors appear in the book journal")
	await settle()
	var args := OS.get_cmdline_user_args()
	if not args.is_empty() and DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(args[0])
	await key(KEY_ESCAPE)
	world.get_node("BuildManager").build_mode = true
	check(not journal.try_interact(), "building blocks journal")
	world.get_node("BuildManager").build_mode = false
	world.get_node("VillageMapEditor").active = true
	check(not journal.try_interact(), "map editing blocks journal")
	world.get_node("VillageMapEditor").active = false
	check(VillageJournalFlow.destination(world,"invalid") == null, "unknown destination is safe")
	journal.tracked_id = "resident:naru"
	PlayerProgress.reset()
	VillageSettlement.apply_world(world)
	world.get_node("VillageLifeDirector").refresh()
	await settle()
	check(not journal.marker.visible and journal.tracked_id.is_empty() and not VillageJournalFlow.available(), "new game hides journal and clears marker")
	print("CHECK_VILLAGE_JOURNAL failures=",failures)
	get_tree().quit(0 if failures == 0 else 1)
