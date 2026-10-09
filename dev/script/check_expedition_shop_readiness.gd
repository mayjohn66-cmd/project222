extends Node
var checks := 0
var failures := 0
var world
func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(text)
func frames() -> void:
	for i in range(12): await get_tree().process_frame
func click(button: Button) -> void:
	for pressed in [true,false]:
		var event := InputEventMouseButton.new()
		event.position = button.get_global_rect().get_center()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		get_viewport().push_input(event,true)
	await frames()
func key(code: Key) -> void:
	for pressed in [true,false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.pressed = pressed
		get_viewport().push_input(event,true)
	await frames()
func context(hour: int, open: bool, minute: int = 0) -> void:
	GameState.set_meta("shop_return_context",{"hour":hour,"minute":minute,"was_open":open,"expedition_seconds":0.0})
func employment(id: String, hired: bool, periods: Array[String]) -> void:
	check(GameState.set_employee_state(id,hired,periods),"valid employee state "+id)
	for worker in get_tree().get_nodes_in_group("worker"):
		if worker.employee_id == id:
			worker.is_hired = hired
			worker.work_periods.assign(periods)
func text_of(guide) -> String:
	var lines: Array[String] = []
	for node in guide.list.get_children():
		if node is Label: lines.append(node.text)
	return "\n".join(lines)
func snap(label: String) -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty() or DisplayServer.get_name() == "headless": return
	await get_tree().create_timer(0.4).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(args[0]+"-"+label+".png")
func _ready() -> void: call_deferred("run")
func run() -> void:
	GameState.initialize_new_game()
	PlayerProgress.reset()
	if GameState.has_meta("shop_return_context"): GameState.remove_meta("shop_return_context")
	var summary := ExpeditionShopReadinessData.snapshot()
	check(not summary["valid"] and summary["status"] == "unknown","missing departure context does not pretend shop is closed")
	GameState.set_meta("shop_return_context",{"hour":99,"was_open":true})
	check(not ExpeditionShopReadinessData.snapshot()["valid"],"invalid hour falls back safely")
	GameState.set_meta("shop_return_context",{"hour":6})
	check(not ExpeditionShopReadinessData.snapshot()["valid"],"legacy missing open status stays unknown")
	context(9,true,30)
	GameState.set_meta("shop_return_context",JSON.parse_string(JSON.stringify(GameState.get_meta("shop_return_context"))))
	check(ExpeditionShopReadinessData.snapshot()["valid"] and ExpeditionShopReadinessData.snapshot()["minute"] == 30,"JSON checkpoint float hours remain readable")
	GameState.set_meta("shop_return_context",{"hour":9.5,"was_open":true})
	check(not ExpeditionShopReadinessData.snapshot()["valid"],"invalid fractional hour is never treated as departure time")
	context(6,false)
	var before := GameState.employee_states.duplicate(true)
	check(ExpeditionShopReadinessData.snapshot()["status"] == "closed" and GameState.employee_states == before,"legacy empty employee states read defaults without writing")
	world = load("res://scenes/shop/main.tscn").instantiate()
	world.get_node("TutorialDirector").enabled = false
	add_child(world)
	await frames()
	world.process_mode = Node.PROCESS_MODE_DISABLED
	for child in world.find_children("*","",true,false): child.process_mode = Node.PROCESS_MODE_DISABLED
	world.hide()
	for id in EmployeeData.get_all_employee_ids(): employment(id,false,[])
	context(6,true)
	check(ExpeditionShopReadinessData.snapshot()["status"] == "unstaffed","initial shop has no staffed hours")
	context(18,true)
	var missed := ShopOfflineSimulator.simulate(get_tree(),world.get_node("Actors/Player"),18,1.0)
	check(int(missed["unstaffed_missed"]) > 0 and int(missed["sales"]) == 0,"actual offline simulation confirms unstaffed customer loss")
	employment("worker_001",true,["morning","day"])
	employment("worker_002",false,["evening","night"])
	context(9,true,30)
	summary = ExpeditionShopReadinessData.snapshot()
	check(summary["status"] == "partial" and summary["hired"].size() == 1,"unhired schedules never count as coverage")
	check(summary["bands"].size() == 4 and summary["bands"][0]["start"] == 9 and summary["bands"][0]["minute"] == 30 and summary["bands"][-1]["end"] == 30,"partial first period and next morning boundary are preserved")
	employment("worker_002",true,["evening","night"])
	check(ExpeditionShopReadinessData.snapshot()["status"] == "covered","two complementary schedules cover full remaining day")
	employment("worker_001",true,["night","morning"])
	employment("worker_002",true,["morning","day"])
	for hour in range(24):
		context(hour,true)
		summary = ExpeditionShopReadinessData.snapshot()
		var band: Dictionary = summary["bands"][0]
		check(not band["names"].is_empty() == ShopOfflineSimulator._has_staff_at_hour(get_tree(),hour),"current coverage matches actual offline worker rule hour="+str(hour))
		for later in summary["bands"]:
			check(not later["names"].is_empty() == ShopOfflineSimulator._has_staff_at_hour(get_tree(),posmod(int(later["start"]),24)),"remaining coverage matches real worker rule")
	context(1,true)
	summary = ExpeditionShopReadinessData.snapshot()
	check(summary["bands"].size() == 1 and summary["bands"][0]["end"] == 6,"early morning stops at current day settlement, not following day")
	context(6,false)
	check(ExpeditionShopReadinessData.snapshot()["status"] == "closed","closed departure never implies staffed sales")
	employment("worker_001",true,[])
	employment("worker_002",false,[])
	context(6,true)
	check(ExpeditionShopReadinessData.snapshot()["status"] == "unstaffed" and ExpeditionShopReadinessData.snapshot()["hired"].size() == 1,"hired employee with rest day has no assigned coverage")
	var saved := GameState.create_save_data()
	check(GameState.apply_save_data(saved) and ExpeditionShopReadinessData.snapshot()["status"] == "unstaffed","existing saves preserve actual employment and schedule")
	var valid_employee: Dictionary = GameState.employee_states["worker_001"].duplicate(true)
	GameState.employee_states["worker_001"] = {"is_hired":true,"work_periods":["invalid"]}
	check(ExpeditionShopReadinessData.snapshot()["status"] == "unknown_roster","invalid roster cannot claim coverage")
	GameState.employee_states["worker_001"] = valid_employee
	# 실제 전환처럼 매장 씬을 제거한 뒤 준비 화면을 검증한다.
	world.queue_free()
	await frames()
	var expedition = load("res://scenes/expedition/expedition.tscn").instantiate()
	add_child(expedition)
	await frames()
	var prep = expedition.prep_panel
	var guide: ExpeditionShopReadinessGuide = prep.get_node("ShopReadinessGuide")
	var gear: ExpeditionLoadoutGuide = prep.get_node("LoadoutGuide")
	check(not guide.entry.is_visible_in_tree(),"shop guide hidden on walking road")
	guide.display()
	check(not guide.overlay.visible,"hidden prep never opens shop guide")
	prep.show_departure_choice()
	prep.show()
	check(not guide.entry.is_visible_in_tree(),"destination selection does not show future details")
	prep.map_content.region_buttons["forest"].pressed.emit()
	await frames()
	check(guide.entry.is_visible_in_tree() and not guide.entry.get_global_rect().intersects(gear.entry.get_global_rect()) and not guide.entry.get_global_rect().intersects(prep.start_button.get_global_rect()),"two guide buttons and departure do not overlap")
	var state_before := GameState.create_save_data()
	var context_before: Dictionary = GameState.get_meta("shop_return_context").duplicate(true)
	await click(guide.entry)
	check(guide.overlay.visible and guide.current["status"] == "unstaffed","actual click opens correct shop content")
	check(text_of(guide).contains("정비 시간") and text_of(guide).contains("계산을 할 수 없어") and not text_of(guide).contains("worker_003") and not text_of(guide).contains("직원 3"),"empty shop teaches absence without listing future candidates")
	await snap("unstaffed")
	await click(prep.start_button)
	await key(KEY_E)
	await key(KEY_R)
	await key(KEY_F5)
	check(expedition.current_expedition_phase == expedition.ExpeditionPhase.PREP and guide.overlay.visible,"guide blocks background departure and shortcuts")
	var state_after := GameState.create_save_data()
	check(state_after == state_before and GameState.get_meta("shop_return_context") == context_before,"readiness view never simulates sales, moves time, saves, hires or changes departure")
	await key(KEY_TAB)
	check(get_viewport().gui_get_focus_owner() == guide.close_button,"focus stays in shop guide")
	await key(KEY_ESCAPE)
	check(not guide.overlay.visible and prep.visible and get_viewport().gui_get_focus_owner() == guide.entry,"Esc returns focus to shop guide entry")
	await click(gear.entry)
	check(gear.overlay.visible and text_of(gear).contains("처음 들 무기") and not guide.overlay.visible,"existing gear guide remains independent")
	await key(KEY_ESCAPE)
	context(9,true,30)
	employment("worker_001",true,["morning","day"])
	await click(guide.entry)
	check(guide.current["status"] == "partial" and text_of(guide).contains("09:30") and text_of(guide).contains("근무자 없음"),"partial schedule shows actual time and gaps")
	await snap("partial")
	employment("worker_002",true,["evening","night"])
	await get_tree().create_timer(0.3).timeout
	check(guide.current["status"] == "covered" and not text_of(guide).contains("근무자 없음"),"open guide refreshes changed schedule")
	await snap("covered")
	guide.scroll.scroll_vertical = 120
	await frames()
	var old_scroll := guide.scroll.scroll_vertical
	guide.refresh()
	check(guide.scroll.scroll_vertical == old_scroll,"unchanged guide preserves scroll")
	context(9,false,30)
	guide.refresh()
	check(guide.current["status"] == "closed","closed state refreshes independently of coverage")
	check(text_of(guide).contains("손님은 받지 않습니다"),"closed guide avoids claiming sales even with staffed hours")
	for resolution in [Vector2i(1152,648),Vector2i(768,432),Vector2i(593,523)]:
		get_window().size = resolution
		await frames()
		guide.fit()
		await frames()
		check(get_viewport().get_visible_rect().encloses(guide.root.get_global_rect()) and guide.root.get_global_rect().encloses(guide.close_button.get_global_rect()),"shop panel and fixed close fit "+str(resolution))
		await snap(str(resolution.x))
	await key(KEY_TAB)
	await key(KEY_ENTER)
	check(not guide.overlay.visible,"Enter on close returns to bag")
	guide.display()
	prep.select_tab(prep.PrepTab.MAP)
	check(not guide.overlay.visible,"map hides inherited independent layer")
	prep.map_content.region_buttons["forest"].pressed.emit()
	await frames()
	guide.display()
	prep.hide()
	check(not guide.overlay.visible,"closing preparation hides guide")
	prep.show()
	if GameState.has_meta("shop_return_context"): GameState.remove_meta("shop_return_context")
	guide.display()
	check(guide.current["status"] == "unknown" and not text_of(guide).contains("닫고 나옴"),"old context missing shows fallback in real UI")
	var overlay = guide.overlay
	expedition.queue_free()
	await frames()
	check(not is_instance_valid(guide) and not is_instance_valid(overlay),"scene exit frees shop guide layer")
	print("CHECK_EXPEDITION_SHOP_READINESS checks=",checks," failures=",failures)
	get_tree().quit(0 if failures == 0 else 1)
