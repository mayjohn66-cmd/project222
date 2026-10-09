extends Node
# Fixed dates/layout/intro and request history are setup fixtures. Slots, scene
# transitions, verified files, resumed stock and dialogue use production paths.
var checks := 0
var failures := 0
var paths: Array[String] = [GameState.SAVE_PATH, GameConfig.SAVE_SLOT_PATHS[0], GameConfig.SAVE_SLOT_PATHS[1]]
var backups := {}
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(label)
func frames(n: int = 12) -> void:
	for i in range(n): await get_tree().process_frame
func click(button: Button) -> void:
	await frames()
	for down in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = button.get_global_rect().get_center()
		if button.get_window() != get_window(): event.position += Vector2(button.get_window().position)
		event.button_index = MOUSE_BUTTON_LEFT; event.pressed = down
		get_viewport().push_input(event, true)
	await frames(24)
func key(code: Key) -> void:
	for down in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code; event.physical_keycode = code; event.pressed = down
		get_viewport().push_input(event, true)
	await frames()
func snap(label: String) -> void:
	if DisplayServer.get_name() == "headless": return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--snap="):
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(arg.trim_prefix("--snap=")+"-"+label+".png")
func show_title():
	if get_tree().current_scene != self: get_tree().current_scene.queue_free(); await frames()
	var title = load(GameConfig.TITLE_SCENE_PATH).instantiate()
	get_tree().root.add_child(title); get_tree().current_scene = title
	await frames()
	return title
func finish_talk(panel: StoryDialoguePanel) -> void:
	for i in range(100):
		if not panel.open: return
		await key(KEY_E)
	check(false, "dialogue must finish")
func run() -> void:
	if not OS.get_user_data_dir().contains("foodbag_checks"):
		push_error("Run in isolated foodbag_checks project to protect user saves")
		get_tree().quit(2); return
	var original := GameState.create_save_data()
	for path in paths:
		backups[path] = FileAccess.get_file_as_bytes(path) if FileAccess.file_exists(path) else null
	GameState.initialize_new_game(); PlayerProgress.reset()
	GameState.total_day = 35; GameState.current_day = 7; GameState.money = 321
	PlayerProgress.player_name = "한별"; PlayerProgress.player_gender = "female"
	PlayerProgress.record_story_beat(OpeningJourneyFlow.VERSION, 1)
	PlayerProgress.record_story_beat("tutorial_step:cleanup:done", 1)
	PlayerProgress.record_story_beat("tutorial_step:setup:intro", 1)
	var world = load(GameConfig.MAIN_SCENE_PATH).instantiate()
	world.get_node("TutorialDirector").enabled = false
	get_tree().root.add_child(world); get_tree().current_scene = world
	await frames()
	var manager = world.get_node("DayManager")
	var layout: Array[Dictionary] = [
		{"build_id":"door", "anchor":Vector2i(5,0), "rotation_index":0},
		{"build_id":"register", "anchor":Vector2i(6,2), "rotation_index":0},
		{"build_id":"shelf_1x1", "anchor":Vector2i(2,2), "rotation_index":0}]
	manager.build_manager._restore_current_area_layout(layout); await frames()
	var menu: GameMenu = manager.game_menu
	await click(menu.menu_button); await click(menu.save_button)
	# Clear an isolated test slot only; restore every file's prior bytes on exit.
	DirAccess.remove_absolute(ProjectSettings.globalize_path(paths[1]))
	menu._refresh_save_slot_buttons()
	await click(menu.save_slot_1_button)
	check(FileAccess.file_exists(paths[1]) and not menu.save_slot_panel.visible, "actual save menu writes and closes slot")
	var stored := GameState.read_save_file(paths[1])
	check(stored.get("total_day") == 35 and stored.get("money") == 321, "verified file contains date and money")
	var invalid := stored.duplicate(true); invalid["progress"] = "damaged"
	var before := GameState.create_save_data()
	check(not SaveProgressGuard.valid(invalid) and not GameState.is_save_data_valid(invalid), "malformed progress rejected before application")
	check(GameState.create_save_data() == before, "checking invalid save leaves current state intact")
	check(GameState.write_save_file(invalid, paths[2]), "write structurally damaged isolated file fixture")
	await click(menu.menu_button); await click(menu.save_button)
	check(menu.save_slot_1_button.text.contains("여름 7일") and menu.save_slot_1_button.text.contains("한별"), "save menu describes actual stored date and player")
	check(menu.save_slot_2_button.text.contains("사용할 수 없는"), "save menu distinguishes invalid data without applying it")
	await snap("save-slots")
	await click(menu.save_slot_1_button)
	check(menu.overwrite_save_dialog.visible, "existing slot asks before overwrite")
	var bytes_before := FileAccess.get_file_as_bytes(paths[1])
	await click(menu.overwrite_save_dialog.get_cancel_button())
	check(FileAccess.get_file_as_bytes(paths[1]) == bytes_before, "cancel overwrite preserves original bytes")
	await click(menu.save_slot_close_button)
	manager._on_game_menu_return_title_requested(); await frames(24)
	var title = get_tree().current_scene
	check(title.scene_file_path == GameConfig.TITLE_SCENE_PATH and not get_tree().paused, "real return action opens unpaused title")
	await click(title.continue_button)
	check(title.load_slot_1_button.text.contains("여름 7일") and title.load_slot_1_button.text.contains("06:00") and title.load_slot_1_button.text.contains("한별"), "continue slots distinguish date and store preparation")
	check(title.load_slot_2_button.disabled, "damaged progress cannot be selected to load")
	var state_before := GameState.create_save_data()
	title._refresh_load_slot_buttons()
	check(GameState.create_save_data() == state_before, "previewing saves never replaces live progress")
	await snap("load-slots")
	GameState.money = 999; PlayerProgress.player_name = "다른이름"
	await click(title.load_slot_1_button)
	world = get_tree().current_scene; manager = world.get_node("DayManager")
	var guide: TutorialDirector = world.get_node("TutorialDirector")
	check(world.scene_file_path == GameConfig.MAIN_SCENE_PATH and GameState.total_day == 35 and GameState.money == 321, "actual title slot restores world and saved date/money")
	check(PlayerProgress.player_name == "한별" and PlayerProgress.player_gender == "female", "name and selected appearance restored")
	check(guide.flow.current().get("id") == "setup" and guide.flow.seen("setup") and not OpeningPrologueFlow.pending(), "saved partial tutorial does not restart cleaning or prologue")
	check(not manager.shop_open and manager.hour_timer.is_stopped() and manager.current_hour == 6, "store resume stays in safe morning preparation")
	check(GameState.get_item_count("bread") == int(stored["inventory"].get("bread",0)), "resume grants no extra starter food")
	for step in OpeningJourneyFlow.SETTINGS.steps:
		if not step.get("optional",false): PlayerProgress.record_story_beat("tutorial_step:"+str(step["id"])+":done", 35)
	if guide.dialogue.open: guide.dialogue.close()
	guide.refresh()
	var resident = world.get_node("ResidentRequestDirector")
	resident.refresh(); await frames()
	var request := ResidentRequestFlow.current()
	check(not request.is_empty(), "post-tutorial request fixture available")
	check(ResidentRequestFlow.accept(request), "accepted request prepared through existing flow")
	GameState.add_item(str(request["item"]), int(request["amount"]))
	var money_before := GameState.money
	check(manager.save_preparation_checkpoint(paths[1]), "accepted request and prepared goods save through checkpoint")
	var title2 = await show_title(); await click(title2.continue_button); await click(title2.load_slot_1_button)
	world = get_tree().current_scene; manager=world.get_node("DayManager"); resident=world.get_node("ResidentRequestDirector")
	resident.refresh(); await frames()
	check(ResidentRequestFlow.accepted(str(request["id"])) and not ResidentRequestFlow.done(str(request["id"])), "actual scene recreation keeps unfinished accepted request")
	var player = world.get_node("Actors/Player")
	resident.npc.set_physics_process(false); player.global_position=resident.npc.global_position+Vector2(20,0)
	await key(KEY_E)
	check(ResidentRequestFlow.done(str(request["id"])) and GameState.money == money_before+int(request["money"]), "actual resumed NPC delivery pays exact reward once")
	await finish_talk(resident.dialogue)
	check(ResidentRequestFlow.deliver(request).is_empty(), "repeated delivery cannot duplicate reward")
	check(manager.save_preparation_checkpoint(paths[1]), "completed request checkpoint saves")
	title2 = await show_title(); await click(title2.continue_button); await click(title2.load_slot_1_button)
	check(ResidentRequestFlow.done(str(request["id"])) and GameState.money == money_before+int(request["money"]), "second actual load retains completion and single reward")
	world = get_tree().current_scene; world.queue_free(); await frames(); get_tree().current_scene=self
	var legacy := stored.duplicate(true)
	for field in ["progress","total_day","preservation","employee_states","employee_salary_records","resume_scene_id","expedition_checkpoint"]: legacy.erase(field)
	check(GameState.is_save_data_valid(legacy) and GameState.apply_save_data(legacy), "old file without optional progress/date/storage fields accepted")
	check(GameState.total_day == 7 and PlayerProgress.player_name.is_empty(), "legacy date fallback and default name kept")
	check(SaveSlotSummary.describe(legacy,0).contains("봄 7일") and SaveSlotSummary.describe(legacy,0).contains("알 수 없음"), "legacy preview matches actual fallback date")
	check(GameState.apply_save_data(stored), "restore saved fixture before expedition preparation")
	GameState.clear_expedition_checkpoint()
	var expedition = load(GameConfig.EXPEDITION_SCENE_PATH).instantiate()
	get_tree().root.add_child(expedition); get_tree().current_scene=expedition; await frames(24)
	check(expedition.save_expedition_checkpoint(paths[1]), "real expedition preparation checkpoint writes")
	var expedition_saved := GameState.read_save_file(paths[1])
	check(SaveSlotSummary.describe(expedition_saved,0).contains("원정 체크포인트"), "expedition file identifies distinct resume destination")
	title2=await show_title(); await click(title2.continue_button); await click(title2.load_slot_1_button)
	check(get_tree().current_scene.scene_file_path == GameConfig.EXPEDITION_SCENE_PATH and get_tree().current_scene.current_expedition_phase == get_tree().current_scene.ExpeditionPhase.PREP, "actual title slot selects and restores expedition preparation")
	expedition = get_tree().current_scene
	expedition.start_expedition_run(); await frames(24)
	check(expedition.current_expedition_phase == expedition.ExpeditionPhase.RUN, "real departure reaches safe route map")
	if expedition.current_expedition_phase == expedition.ExpeditionPhase.RUN:
		var checkpoint: Dictionary = expedition.create_expedition_checkpoint_data()
		check(expedition.save_expedition_checkpoint(paths[1]), "actual route map checkpoint saves")
		title2 = await show_title(); await click(title2.continue_button); await click(title2.load_slot_1_button)
		expedition = get_tree().current_scene
		check(expedition.current_expedition_phase == expedition.ExpeditionPhase.RUN and expedition.map_panel.visible and not expedition.battle_active, "actual load restores route selection without replaying combat")
		check(expedition.current_map_node_id == checkpoint["current_map_node_id"] and expedition.expedition_map.layers == checkpoint["map_layers"] and expedition.expedition_map.environment == checkpoint["environment"], "saved map position, paths and captured season/weather remain identical")
		check(expedition.expedition_bag.placements == checkpoint["bag_placements"] and expedition.combat_player_hp == checkpoint["combat_player_hp"], "saved bag and health remain identical")
	get_tree().current_scene.queue_free(); await frames(); get_tree().current_scene=self
	check(GameState.apply_save_data(original), "restore isolated in-memory state")
	for path in paths:
		if backups[path] == null: DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
		else:
			var file := FileAccess.open(path,FileAccess.WRITE); file.store_buffer(backups[path]); file.close()
	print("CHECK_SAVE_RESUME checks=",checks," failures=",failures)
	get_tree().quit(0 if failures==0 else 1)
