extends Node
## 실제 주민/게시판 입력, 수첩 조회의 무변경, 기존 저장·완료 기록을 검사한다.
var checks := 0
var failures := 0
var world
var player
var manager
var resident: ResidentRequestDirector
var board: CommunityBoardDirector

func check(ok: bool, label: String) -> void:
	checks += 1
	if ok: print("PASS: ", label)
	else: failures += 1; push_error(label)

func frames(count: int = 8) -> void:
	for i in range(count): await get_tree().process_frame

func drain(dialogue: StoryDialoguePanel) -> void:
	for i in range(100):
		if not dialogue.open: return
		dialogue._advance()
	check(false, "dialogue terminates")

func click(button: Button) -> void:
	check(is_instance_valid(button), "input target exists")
	if not is_instance_valid(button): return
	var parent := button.get_parent()
	while parent != null and not parent is ScrollContainer: parent = parent.get_parent()
	if parent is ScrollContainer: parent.ensure_control_visible(button)
	await frames()
	var point := button.get_global_rect().get_center()
	if button.get_viewport() != get_viewport():
		var menu_node: Control = world.get_node("UI/ManagementMenu")
		var stage = menu_node.get_meta("book_stage", null)
		if is_instance_valid(stage):
			point += stage._offset
			if button.get_parent() == menu_node.inventory_button.get_parent():
				for flag in stage.left_flags.items:
					if int(flag["tab"]) == button.get_index(): point = (flag["rect"] as Rect2).get_center()
	for down in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = down
		get_viewport().push_input(event, true)
	await frames()

func key(code: Key) -> void:
	for down in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.pressed = down
		get_viewport().push_input(event, true)
	await frames()

func snapshot(name: String) -> void:
	if DisplayServer.get_name() == "headless": return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--notebook-capture="):
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(arg.trim_prefix("--notebook-capture=") + "-" + name + ".png")

func record(id: String) -> Dictionary:
	for row in RequestNotebookData.entries():
		if row["id"] == id: return row
	return {}

func label_text(node: Node) -> String:
	var text: String = node.text if node is Label else ""
	for child in node.get_children(): text += "\n" + label_text(child)
	return text

func start_resident() -> void:
	resident.refresh()
	player.global_position = resident.npc.global_position
	check(world.get_node("WorldInteractions").try_interact(), "resident proposal uses actual interaction route")
	drain(resident.dialogue)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("run")

func run() -> void:
	if not OS.get_user_data_dir().contains("foodbag_checks"):
		push_error("Requires an isolated foodbag_checks APPDATA")
		get_tree().quit(1)
		return
	GameState.initialize_new_game()
	world = load("res://scenes/shop/main.tscn").instantiate()
	world.get_node("TutorialDirector").enabled = false
	add_child(world)
	await frames()
	player = world.get_node("Actors/Player")
	manager = world.get_node("DayManager")
	manager.hour_timer.stop()
	resident = world.get_node("ResidentRequestDirector")
	board = world.get_node("CommunityBoardDirector")
	world.get_node("QuestVisitDirector").set_process(false)
	world.get_node("VillageLifeDirector").set_process(false)
	resident.set_process(false)
	for step in TutorialDirector.SETTINGS.steps: PlayerProgress.record_story_beat("tutorial_step:" + str(step["id"]) + ":done", GameState.total_day)
	PlayerProgress.record_story_beat(CheckoutTutorial.BEAT_ID, GameState.total_day)
	check(record("request:neighbor_bread").is_empty(), "unaccepted resident request is not prewritten in notebook")
	manager.hour_timer.paused = false
	player.set_physics_process(true)
	resident.refresh()
	player.global_position = resident.npc.global_position
	check(resident.try_interact(), "resident speaks before asking for a response")
	check(not ResidentRequestFlow.accepted("neighbor_bread"), "starting dialogue does not automatically accept")
	resident.dialogue.close()
	check(not resident.request_offer.root.visible and not resident.talking and not ResidentRequestFlow.accepted("neighbor_bread"), "interrupting dialogue cancels without writing a record")
	start_resident()
	check(resident.request_offer.root.visible and not ResidentRequestFlow.accepted("neighbor_bread"), "fully read proposal waits for accept or decline")
	var before := PlayerProgress.to_save_data().duplicate(true)
	var inventory := GameState.inventory.duplicate(true)
	var money := GameState.get_money()
	for size in [Vector2i(1152,648), Vector2i(593,523), Vector2i(800,450)]:
		get_window().size = size
		await frames()
		var area := get_viewport().get_visible_rect()
		check(area.encloses(resident.request_offer.root.get_global_rect()), "proposal fits " + str(size))
		check(area.encloses(resident.request_offer.accept_button.get_global_rect()) and area.encloses(resident.request_offer.decline_button.get_global_rect()), "both responses stay visible " + str(size))
	await snapshot("resident-offer")
	await key(KEY_ESCAPE)
	check(PlayerProgress.to_save_data() == before and GameState.inventory == inventory and GameState.get_money() == money, "Escape decline spends and records nothing")
	check(not manager.hour_timer.paused and player.is_physics_processing() and not resident.talking, "decline restores exact clock and movement state")
	start_resident()
	await click(resident.request_offer.decline_button)
	check(record("request:neighbor_bread").is_empty(), "decline button leaves no notebook record and can retry")
	start_resident()
	await click(resident.request_offer.accept_button)
	check(ResidentRequestFlow.accepted("neighbor_bread") and not resident.talking, "accept click records only the agreement and restores control")
	check(GameState.inventory == inventory and GameState.get_money() == money, "acceptance does not deliver goods or award money")
	var request := ResidentRequestFlow.current()
	GameState.remove_item(str(request["item"]), GameState.get_item_count(str(request["item"])))
	check(float(RequestNotebookData.detail(record("request:neighbor_bread"))["progress"]) == 0, "accepted empty inventory shows zero progress")
	GameState.add_item(str(request["item"]), int(request["amount"]))
	check(float(RequestNotebookData.detail(record("request:neighbor_bread"))["progress"]) == 100, "real carried goods update notebook readiness")
	var menu: ManagementMenu = world.get_node("UI/ManagementMenu")
	get_window().size = Vector2i(1152,648)
	menu.open_menu(ManagementTabs.MenuTab.REQUESTS)
	await get_tree().create_timer(2.0, true).timeout
	var notebook := menu.request_list.get_node("RequestNotebook") as RequestNotebookView
	check(notebook != null and notebook.selection_buttons.has("request:neighbor_bread"), "book shows accepted request in left-hand list")
	check(notebook.detail_page.get_node("RequestProgress").value == 100, "selected request detail shows actual preparation progress")
	check(notebook.get_child(0).get_global_rect().end.x < notebook.detail_page.get_global_rect().position.x, "list and detail use separate book pages")
	check(menu.request_button.text == "부탁" and menu.inventory_button.get_parent().get_child_count() == 8, "requests have an independent eighth post-it")
	check(ManagementTabs.MenuTab.HISTORY == 6 and ManagementTabs.MenuTab.REQUESTS == 7, "existing tab indices remain unchanged")
	var colors := {}
	for i in range(8): colors[ManagementMenu.PRESENTATION.bookmark_color(i).to_html()] = true
	check(colors.size() == 8 and InteractionUiStyle.button("normal").bg_color == InteractionUiStyle.PAPER, "post-its use distinct paper colors while regular buttons retain the palette")
	await snapshot("request-tab")
	GameState.discovered_store_events = {"spring_market": 1, "dungeon_raid": 1}
	await click(menu.schedule_button)
	await get_tree().create_timer(1.6, true).timeout
	check(menu.current_tab == ManagementTabs.MenuTab.SCHEDULE and menu.schedule_content.visible and not menu.request_content.visible, "left-hand schedule post-it opens the original event page")
	check(menu.schedule_list.get_node_or_null("RequestNotebook") == null and label_text(menu.schedule_list).contains("공용 이벤트") and label_text(menu.schedule_list).contains("계절 이벤트"), "event calendar retains both kinds without quest records")
	await snapshot("event-tab")
	await click(menu.request_button)
	await get_tree().create_timer(1.6, true).timeout
	check(menu.current_tab == ManagementTabs.MenuTab.REQUESTS and menu.request_content.visible and not menu.schedule_content.visible, "right-hand request post-it returns to the notebook")
	await click(menu.inventory_button)
	await get_tree().create_timer(1.6, true).timeout
	check(menu.current_tab == ManagementTabs.MenuTab.INVENTORY, "all seven pages turn back to inventory")
	var stage = menu.get_meta("book_stage", null)
	if is_instance_valid(stage):
		for i in range(menu.inventory_button.get_parent().get_child_count()):
			var flag: Button = menu.inventory_button.get_parent().get_child(i)
			if flag.visible:
				var rect := flag.get_global_rect()
				rect.position += stage._offset
				check(get_viewport().get_visible_rect().encloses(rect), "post-it stays inside screen: " + flag.text)
	await snapshot("all-postits")
	await click(menu.request_button)
	await get_tree().create_timer(1.6, true).timeout
	check(menu.current_tab == ManagementTabs.MenuTab.REQUESTS and (stage == null or stage.at_rest()), "all seven pages turn forward to requests and settle")
	notebook = menu.request_list.get_node("RequestNotebook") as RequestNotebookView
	var save_before := PlayerProgress.to_save_data().duplicate(true)
	var goods_before := GameState.inventory.duplicate(true)
	await click(notebook.detail_page.get_node("RequestDestination"))
	check(world.get_node("VillageJournalDirector").tracked_id == "request:neighbor_bread", "detail destination button tracks the real quest giver")
	await snapshot("active-book")
	check(PlayerProgress.to_save_data() == save_before and GameState.inventory == goods_before, "reading and tracking do not accept, deliver or award")
	menu.close_menu()
	await get_tree().create_timer(2.0, true).timeout
	resident.refresh()
	player.global_position = resident.npc.global_position
	check(resident.try_interact(), "return to quest giver delivers through existing route")
	drain(resident.dialogue)
	check(record("request:neighbor_bread")["category"] == "done" and float(RequestNotebookData.detail(record("request:neighbor_bread"))["progress"]) == 100, "completed notebook keeps delivered counts after inventory is consumed")
	check(ResidentRequestFlow.deliver(request).is_empty(), "completed delivery cannot award twice")
	# 게시판 선행 조건만 준비한다. 가격·보상·재료는 기존 데이터를 사용한다.
	PlayerProgress.record_story_beat(ResidentRequestFlow.PREFIX + "settle_naru:done", GameState.total_day)
	VillageSettlement.apply_world(world)
	VillageLifeFlow.greet("naru")
	await frames()
	var site := VillageSettlement.find_site(world, CommunityRequestFlow.SETTINGS.board_path)
	player.global_position = site.global_position
	check(board.try_interact(), "existing board interaction opens proposal list")
	await click(board.panel.cards["path_light"]["action"])
	check(board.request_offer.root.visible and not CommunityRequestFlow.accepted("path_light"), "board action opens confirmation instead of accepting")
	before = PlayerProgress.to_save_data().duplicate(true)
	await click(board.request_offer.decline_button)
	check(PlayerProgress.to_save_data() == before and board.panel.root.visible, "board decline returns to list with no new record")
	await click(board.panel.cards["path_light"]["action"])
	await click(board.request_offer.accept_button)
	check(CommunityRequestFlow.accepted("path_light") and not CommunityRequestFlow.done("path_light"), "board accept records agreement without delivery")
	check(not record("community:path_light").is_empty(), "community agreement is written to notebook")
	board.panel.close()
	for entry in VillageLifeFlow.entries():
		PlayerProgress.record_story_beat(ResidentRequestFlow.PREFIX + str(entry["request"]) + ":done", GameState.total_day)
		PlayerProgress.story_beat_days[VillageLifeFlow.PREFIX + "friendship:" + str(entry["id"])] = 7
	VillageSettlement.apply_world(world)
	var personal := ""
	for entry in PersonalRequestFlow.entries():
		if PersonalRequestFlow.locked_reason(entry).is_empty(): personal = str(entry["id"]); break
	check(not personal.is_empty(), "an actual available personal request exists")
	player.global_position = site.global_position
	check(board.try_interact(), "personal request uses existing board")
	board._on_action("personal:" + personal)
	check(board.request_offer.root.visible and not PersonalRequestFlow.accepted(personal), "personal request also waits for response")
	await click(board.request_offer.decline_button)
	check(record("personal:" + personal).is_empty(), "rejected personal request is not recorded")
	board._on_action("personal:" + personal)
	await click(board.request_offer.accept_button)
	check(PersonalRequestFlow.accepted(personal) and not record("personal:" + personal).is_empty(), "accepted personal request appears in notebook")
	board.panel.close()
	var saved := PlayerProgress.to_save_data().duplicate(true)
	PlayerProgress.reset()
	PlayerProgress.load_save_data(saved)
	check(record("request:neighbor_bread")["category"] == "done" and not record("personal:" + personal).is_empty(), "notebook reconstructs accepted and completed records after load")
	menu.open_menu(ManagementTabs.MenuTab.REQUESTS)
	await get_tree().create_timer(2.0, true).timeout
	notebook = menu.request_list.get_node("RequestNotebook") as RequestNotebookView
	await click(notebook.category_buttons["done"])
	await click(notebook.selection_buttons["request:neighbor_bread"])
	await snapshot("completed-book")
	await click(notebook.category_buttons["active"])
	await click(notebook.selection_buttons["personal:" + personal])
	check(notebook.selected_id == "personal:" + personal and notebook.detail_page.get_node("RequestReward").text.contains("답례"), "left selection changes right-hand goal and reward")
	await snapshot("personal-book")
	menu.close_menu()
	await get_tree().create_timer(2.0, true).timeout
	world.queue_free()
	await frames()
	print("CHECK_REQUEST_PROPOSALS checks=%d failures=%d" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)
