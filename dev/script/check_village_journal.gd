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

func _ready() -> void: call_deferred("run")

func run() -> void:
	world = load("res://scenes/shop/main.tscn").instantiate()
	add_child(world)
	await settle()
	var journal: VillageJournalDirector = world.get_node("VillageJournalDirector")
	var player = world.get_node("Actors/Player")
	var manager = world.get_node("DayManager")
	check(not journal.button.visible and not journal.try_interact(), "journal waits for tutorial completion")
	for step in TutorialDirector.SETTINGS.steps:
		PlayerProgress.record_story_beat("tutorial_step:" + str(step["id"]) + ":done",GameState.total_day)
	PlayerProgress.record_story_beat(CheckoutTutorial.BEAT_ID,GameState.total_day)
	world.get_node("TutorialDirector").refresh()
	world.get_node("ResidentRequestDirector").refresh()
	await settle()
	check(journal.button.visible, "journal becomes available without settlement")
	check(VillageJournalFlow.destination(world,"resident:naru") == null and VillageJournalFlow.destination(world,"place:settle_naru") == null, "hidden residents and places cannot be tracked")
	check(not VillageJournalFlow.information("next_request").is_empty(), "next request gives current action and warehouse counts")
	player.set_physics_process(false)
	manager.hour_timer.paused = false
	var progress_before := PlayerProgress.to_save_data().duplicate(true)
	var money_before: int = GameState.get_money()
	var inventory_before: Dictionary = GameState.inventory.duplicate(true)
	await click(journal.button)
	check(journal.open and manager.hour_timer.paused and world.get_node("WorldInteractions").blocked(), "actual HUD button opens journal and blocks conflicting actions")
	check(not journal.panel.cards["next_request"]["action"].disabled, "current request NPC can be marked")
	await click(journal.panel.cards["next_request"]["action"])
	check(journal.tracked_id == "next_request", "actual action selects destination")
	await key(KEY_ESCAPE)
	check(not journal.open and not manager.hour_timer.paused and not player.is_physics_processing(), "Escape restores clock and exact movement state")
	check(journal.marker.is_inside_tree() and journal.marker.visible and journal.guidance.visible, "marker and directional hint appear after closing")
	check(PlayerProgress.to_save_data() == progress_before and GameState.get_money() == money_before and GameState.inventory == inventory_before, "viewing and tracking award nothing and preserve saved progress")
	await key(KEY_N)
	check(journal.open and not journal.marker.visible, "N opens journal and hides world marker")
	await click(journal.panel.cards["next_request"]["action"])
	await key(KEY_N)
	check(not journal.open and journal.tracked_id.is_empty() and not journal.marker.visible, "same card clears marker and N closes")
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
	for dimensions in [Vector2i(1152,648),Vector2i(593,523),Vector2i(800,450)]:
		get_window().size = dimensions
		await settle()
		check(get_viewport().get_visible_rect().encloses(journal.panel.root.get_global_rect()) and journal.panel.root.get_global_rect().encloses(journal.panel.close_button.get_global_rect()), "journal scroll keeps footer inside screen")
	get_window().size = Vector2i(1152,648)
	await settle()
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
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
	check(not journal.button.visible and not journal.marker.visible and journal.tracked_id.is_empty() and not VillageJournalFlow.available(), "new game hides journal and clears marker")
	print("CHECK_VILLAGE_JOURNAL failures=",failures)
	get_tree().quit(0 if failures == 0 else 1)
