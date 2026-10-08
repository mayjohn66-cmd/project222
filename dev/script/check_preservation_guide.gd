extends Node
var checks := 0
var failures := 0
var world
var player
var panel: PreservationPanel
func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(text)
func frames() -> void:
	for i in range(8): await get_tree().process_frame
func text_of(node: Node) -> String:
	var result: String = node.text + "\n" if node is Label else ""
	for child in node.get_children(): result += text_of(child)
	return result
func row(item: String) -> HBoxContainer:
	for child in panel.rows.get_children():
		if child is HBoxContainer and child.get_meta("preservation_item","") == item: return child
	return null
func click(button: Button) -> void:
	var item: String = button.get_parent().get_meta("preservation_item","")
	var index := button.get_index()
	panel.contents_scroll.ensure_control_visible(button)
	await frames()
	# Live inventory changes may rebuild rows while the simulated pointer waits.
	button = row(item).get_child(index)
	var point := button.get_global_rect().get_center() + Vector2(panel.position)
	for pressed in [true,false]:
		var input := InputEventMouseButton.new()
		input.position = point
		input.button_index = MOUSE_BUTTON_LEFT
		input.pressed = pressed
		get_viewport().push_input(input,true)
	await frames()
func snap(label: String) -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty() or DisplayServer.get_name() == "headless": return
	await get_tree().create_timer(0.6).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(args[0]+"-"+label+".png")
func _ready() -> void: call_deferred("run")
func run() -> void:
	get_tree().root.gui_embed_subwindows = true
	GameState.initialize_new_game()
	PlayerProgress.reset()
	GameState.inventory.clear()
	GameState.total_day = 28
	GameState.preservation_state = PreservationService.initial_state(28)
	world = load("res://scenes/shop/main.tscn").instantiate()
	world.get_node("TutorialDirector").enabled = false
	world.get_node("VillageLifeDirector").crafting_path_enabled = false
	add_child(world)
	await frames()
	var manager = world.get_node("DayManager")
	manager.hour_timer.stop()
	manager.set_process(false)
	world.get_node("CustomerSpawner").set_process(false)
	player = world.get_node("Actors/Player")
	player.set_physics_process(false)
	var unit = BuildObjectData.get_build_scene("fridge_unit").instantiate()
	unit.set_meta("build_id","fridge_unit")
	world.get_node("Objects").add_child(unit)
	await frames()
	player.global_position = unit.global_position + Vector2(0,20)
	check(player.try_interact_with_preservation_unit(),"real furniture interaction")
	await frames()
	panel = player.get_node("PreservationWorldPanel")
	check(panel.visible and panel.unit_filter == "fridge","physical fridge panel")
	check(PreservationService.installed("fridge"),"physical installation unchanged")
	check(row("winter_frost") == null and row("summer_mint") == null and row("fish_stream_minnow") == null,"unseen seasonal materials and fish hidden")
	check(not panel.intro.text.contains(ItemData.get_item_name("winter_frost")),"unknown ice not named in intro")
	check(row("berry_juice") == null,"unlearned future product hidden")
	PlayerProgress.learn_recipe("berry_juice")
	panel.refresh()
	check(row("berry_juice") != null,"learned recipe visible without stock")
	check(row("berry_juice").get_child(1).disabled and row("berry_juice").get_child(2).disabled,"zero quantity cannot transfer")
	GameState.add_item("spring_bud",3)
	GameState.add_item("winter_frost",1)
	GameState.add_item("bread",2)
	panel.refresh()
	check(row("spring_bud") != null and row("bread") != null,"current materials and food visible")
	check(panel.intro.text.contains(ItemData.get_item_name("winter_frost")) and panel.intro.text.contains("냉동"),"known ice points to freezer")
	check(row("winter_frost") == null,"fridge still rejects ice")
	check(row("spring_bud").get_child(0).text.contains("소지 3"),"carried stock correctly named")
	check(PreservationGuide.item_note("fridge","spring_bud").contains("다음 아침"),"spring last day warns next morning")
	GameState.total_day = 1
	check(not PreservationGuide.ambient_hint("spring_bud").contains("다음 아침"),"in-season buds do not wilt tomorrow")
	GameState.total_day = 28
	GameState.preservation_state["last_day"] = 28
	check(not PreservationGuide.move_note("fridge","spring_bud",false).contains("얼음"),"bud withdrawal has no ice warning")
	for step in TutorialDirector.SETTINGS.steps: PlayerProgress.record_story_beat("tutorial_step:"+str(step["id"])+":done",1)
	PlayerProgress.record_story_beat(CheckoutTutorial.BEAT_ID,1)
	for resident in VillageLifeFlow.SETTINGS.residents:
		PlayerProgress.record_story_beat(ResidentRequestFlow.PREFIX+str(resident["request"])+":done",1)
		PlayerProgress.story_beat_days[VillageLifeFlow.PREFIX+"friendship:"+str(resident["id"])] = 1
	check(PreservationLessonFlow.accept("preserve_spring_scent"),"existing lesson accepted after real gates")
	panel.refresh()
	await snap("before")
	await click(row("spring_bud").get_child(1))
	check(GameState.get_item_count("spring_bud") == 2 and int(GameState.preservation_state.fridge.get("spring_bud",0)) == 1,"real put button transfers exactly one")
	check(text_of(panel.rows).contains("오늘 넣었어요"),"deposit shows wait until tomorrow")
	await click(row("spring_bud").get_child(2))
	check(PreservationLessonFlow.ready_path("preserve_spring_scent").is_empty(),"same-day withdrawal cannot complete lesson")
	check(not PlayerProgress.story_beat_days.has(PreservationLessonFlow.key("preserve_spring_scent","stored:fridge")),"same-day empty clears overnight candidate")
	await click(row("spring_bud").get_child(1))
	await snap("stored")
	GameState.advance_calendar_day()
	await get_tree().create_timer(1.1).timeout
	check(GameState.get_item_count("spring_bud") == 0 and GameState.get_item_count("wilted_greens") == 2,"warm buds transform at season boundary")
	check(int(GameState.preservation_state.fridge.get("spring_bud",0)) == 1,"cold buds survive boundary")
	check(text_of(panel.rows).contains("하룻밤 보관했어요"),"visible window automatically refreshes overnight lesson")
	check(row("spring_bud").get_child(0).text.contains("소지 0 / 보관 1"),"visible window automatically refreshes quantities")
	await click(row("spring_bud").get_child(2))
	check(PreservationLessonFlow.ready_path("preserve_spring_scent").get("id","") == "cold","real next-day withdrawal produces actual practice")
	var giver := str(VillageLifeFlow.resident("sora").get("name",""))
	check(text_of(panel.rows).contains(giver+"에게 직접 전달"),"ready specimen points to existing giver")
	check(not panel.message.text.contains("꺼낸 얼음"),"movement message matches actual plant")
	await snap("ready")
	var money := GameState.money
	var stock := GameState.inventory.duplicate(true)
	var progress := PlayerProgress.story_beat_days.duplicate(true)
	panel.refresh()
	panel.refresh()
	check(GameState.money == money and GameState.inventory == stock and PlayerProgress.story_beat_days == progress,"browsing neither pays nor consumes nor finishes lesson")
	check(not PreservationLessonFlow.completed("preserve_spring_scent"),"reading guide gives no automatic reward")
	var save := GameState.create_save_data()
	check(GameState.apply_save_data(save),"in-memory full save reload")
	check(PreservationGuide.known("spring_bud"),"discovery persists through existing save")
	check(PreservationGuide.item_note("fridge","spring_bud").contains(giver+"에게 직접 전달"),"actual practice hint persists after reload")
	var bread_before := FoodShelfLife.days_left("bread",FoodShelfLife.state().inventory.bread[0])
	check(PreservationService.deposit("fridge","bread",1) == 1,"partly aged food deposited")
	var cold_before := FoodShelfLife.days_left("bread",FoodShelfLife.state().fridge.bread[0])
	check(cold_before == bread_before,"deposit does not reset food age")
	panel.refresh()
	check(PreservationGuide.item_note("fridge","bread").contains("출고 뒤 상온 기준 %d일" % cold_before),"cold age labelled as ambient after withdrawal")
	GameState.advance_calendar_day()
	await get_tree().create_timer(1.1).timeout
	check(PreservationService.withdraw("fridge","bread",1) == 1,"partly aged food withdrawal")
	var minimum := 999
	for batch in FoodShelfLife.state().inventory.bread: minimum = mini(minimum,FoodShelfLife.days_left("bread",batch))
	check(minimum <= bread_before,"withdrawal never refreshes oldest food")
	GameState.add_item("berry_juice",1)
	panel.refresh()
	check(PreservationGuide.item_note("fridge","berry_juice").contains("냉동할 수 없는"),"juice gives actual freezing restriction")
	check(not PreservationService.unit("freezer").accepts.has("berry_juice"),"freezing restriction matches service")
	check(PreservationGuide.unit_description(PreservationService.unit("freezer")).contains("멈춥니다"),"freezer rate described from current settings")
	check(PreservationGuide.unit_description(PreservationService.unit("fridge")).contains("새로 채우지"),"storage cannot renew expiry")
	check(PreservationGuide.dry_hint("spring_bud").contains(ItemData.get_item_name("dried_spring_bud")) and PreservationGuide.dry_hint("spring_bud").contains("화덕"),"existing learned drying method names actual output and facility")
	FishingRecords.caught("fish_stream_minnow")
	panel.refresh()
	check(row("fish_stream_minnow") != null and row("fish_stream_minnow").get_child(1).disabled,"previous catch visible without owned fish")
	check(row("fish_stone_crucian") == null,"other unseen fish stay hidden")
	await get_tree().create_timer(1.1).timeout
	var row_instance := row("bread").get_instance_id()
	PlayerProgress.record_story_beat("guide_test_unrelated_daily_greeting",GameState.total_day)
	await get_tree().create_timer(1.1).timeout
	check(row("bread").get_instance_id() == row_instance,"unrelated conversation does not rebuild storage buttons")
	await get_tree().create_timer(1.1).timeout
	panel.contents_scroll.ensure_control_visible(panel.rows.get_child(row("bread").get_index()+1))
	await frames()
	await snap("food")
	var freezer = BuildObjectData.get_build_scene("freezer_unit").instantiate()
	freezer.position = Vector2(250,0)
	freezer.set_meta("build_id","freezer_unit")
	world.get_node("Objects").add_child(freezer)
	panel.hide()
	await frames()
	player.global_position = freezer.global_position + Vector2(0,20)
	check(player.try_interact_with_preservation_unit(),"real freezer interaction")
	await frames()
	check(panel.visible and panel.unit_filter == "freezer","physical freezer selects only its own unit")
	check(row("berry_juice") == null,"unfreezable juice absent from freezer")
	GameState.add_item("winter_frost",2)
	panel.refresh()
	await click(row("winter_frost").get_child(1))
	check(int(GameState.preservation_state.freezer.get("winter_frost",0)) == 1,"real freezer button stores ice")
	check(PreservationGuide.item_note("freezer","winter_frost").contains("다음 아침"),"ice always warns next morning")
	GameState.preservation_state.freezer["fish_stone_crucian"] = 1
	check(not FishingRecords.has("caught:fish_stone_crucian"),"legacy stored fish has no catch record")
	panel.refresh()
	check(row("fish_stone_crucian") != null and not row("fish_stone_crucian").get_child(2).disabled,"stored legacy fish is never hidden")
	GameState.advance_calendar_day()
	await get_tree().create_timer(1.1).timeout
	check(GameState.get_item_count("winter_frost") == 0 and int(GameState.preservation_state.freezer.get("winter_frost",0)) == 1,"warm ice melts while stored ice persists")
	check(row("winter_frost").get_child(0).text.contains("소지 0 / 보관 1"),"open freezer refreshes real ice quantity")
	await snap("freezer")
	for resolution in [Vector2i(1152,648),Vector2i(768,432)]:
		get_tree().root.size = resolution
		await frames()
		panel.hide()
		panel.open()
		await frames()
		check(player.get_viewport().get_visible_rect().encloses(Rect2(Vector2(panel.position),Vector2(panel.size))),"dialogue fits logical viewport "+str(resolution))
		var button := panel.get_ok_button().get_global_rect()
		check(button.position.y >= 0 and button.end.y <= panel.size.y,"return button remains inside "+str(resolution))
		for child in panel.rows.get_children():
			if child is HBoxContainer: check(child.size.x <= panel.contents_scroll.size.x,"item controls fit "+str(resolution))
	await snap("small")
	panel.get_ok_button().pressed.emit()
	await frames()
	check(not panel.visible,"existing return button closes")
	world.queue_free()
	await frames()
	print("CHECK_PRESERVATION_GUIDE checks=%d failures=%d" % [checks,failures])
	get_tree().quit(0 if failures == 0 else 1)
