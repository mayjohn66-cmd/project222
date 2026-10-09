extends "res://dev/script/check_employee_recruitment.gd"
## Real controls and attendance. Tutorial completion, clock and education funds
## are fixtures; no attendance, movement or clock-out flags are injected.
var menu: ManagementMenu
var host
func settle_book() -> void:
	await get_tree().create_timer(1.7,true,false,true).timeout
	await frames()
func close_book() -> void:
	menu.close_menu()
	await settle_book()
	check(not menu.visible and not get_tree().paused,"closing book resumes world")
func click(button: Button) -> void:
	check(is_instance_valid(button),"actual book button exists")
	if not is_instance_valid(button): return
	var parent := button.get_parent()
	while parent != null and not parent is ScrollContainer: parent = parent.get_parent()
	if parent is ScrollContainer: parent.ensure_control_visible(button)
	await frames()
	var position := button.get_global_rect().get_center()
	if menu.has_meta("book_stage") and is_instance_valid(menu.get_meta("book_stage")):
		position += menu.get_meta("book_stage")._offset
	for pressed in [true,false]:
		var event := InputEventMouseButton.new()
		event.position = position
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		get_viewport().push_input(event,true)
	await frames()
func card_button(prefix: String) -> Button:
	for button in host.employee_list.find_children("*","Button",true,false):
		if button.text.begins_with(prefix): return button
	return null
func open_employment() -> void:
	menu.open_menu(ManagementMenu.MenuTab.EMPLOYEE)
	host._select_employee_tab(host.EmployeeTab.EMPLOYMENT)
	await settle_book()
func run() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	check(OS.get_user_data_dir().contains("foodbag_checks"),"isolated employee test project")
	if not OS.get_user_data_dir().contains("foodbag_checks"): get_tree().quit(1); return
	GameState.initialize_new_game()
	PlayerProgress.reset()
	var world = load("res://scenes/shop/main.tscn").instantiate()
	world.get_node("TutorialDirector").enabled = false
	add_child(world)
	await frames()
	OpeningJourneyFlow.initialize(world)
	var manager = world.get_node("DayManager")
	manager.hour_timer.stop()
	manager.current_hour = GameConfig.DAY_START_HOUR
	manager.shop_open = false
	manager.customer_spawner.set_process(false)
	var director = world.get_node("EmployeeRecruitmentDirector")
	director.set_process(false)
	menu = manager.management_menu
	host = menu.employee_content
	var controller: EmployeeContentController = host.employee_content
	var worker = get_tree().get_nodes_in_group("worker")[0]
	var id: String = worker.employee_id
	await open_employment()
	check(host.message_label.text.contains("직접 계산"),"tutorial page refers to current store practice")
	check(not host.message_label.text.contains("가게 앞의") and host.employee_list.get_child_count() == 0,"no invented applicant before tutorial")
	check(not host.schedule_button.visible and not host.training_button.visible and not host.info_button.visible,"advanced internal tabs wait for prerequisites")
	await snapshot("tutorial")
	await close_book()
	for step in TutorialDirector.SETTINGS.steps:
		if not step.get("optional",false): PlayerProgress.record_story_beat("tutorial_step:"+str(step["id"])+":done",GameState.total_day)
	var rebuilt: Array[Dictionary] = [
		{"build_id":"door","anchor":Vector2i(0,4),"rotation_index":3},
		{"build_id":"register","anchor":Vector2i(4,3),"rotation_index":0},
		{"build_id":"shelf_1x1","anchor":Vector2i(2,2),"rotation_index":0},
		{"build_id":"shelf_1x1","anchor":Vector2i(2,5),"rotation_index":0}]
	world.get_node("BuildManager")._restore_current_area_layout(rebuilt)
	await frames()
	await open_employment()
	check(host.message_label.text.contains("방문을 기다려") and not host.message_label.text.contains("가게 앞의"),"eligible unspawned visitor is described as waiting")
	await close_book()
	director.refresh_visit()
	check(is_instance_valid(director.applicant),"actual first applicant arrives")
	if not is_instance_valid(director.applicant): get_tree().quit(1); return
	await open_employment()
	check(host.message_label.text.contains(worker.get_employee_display_name()) and host.message_label.text.contains("[E]") and host.message_label.text.contains("책을 닫"),"present visitor has named reachable next action")
	await close_book()
	world.get_node("Actors/Player").global_position = director.applicant.global_position + Vector2(25,0)
	check(world.get_node("WorldInteractions").try_interact(),"real shared interaction opens introduction")
	drain(director.dialogue)
	check(EmployeeRecruitmentFlow.met(id) and not worker.is_hired,"introduction only unlocks candidate")
	await open_employment()
	await click(card_button("고용 ·"))
	check(controller.hire_dialog.visible and not worker.is_hired,"actual hire opens confirmation")
	controller.hire_dialog.confirmed.emit()
	controller.hire_dialog.hide()
	host.refresh_view()
	check(worker.is_hired and worker.work_periods.is_empty() and not host.training_button.visible,"hire creates no automatic shift or education")
	check(host.message_label.text.contains("근무표 적용") and host.message_label.text.contains("휴무여도"),"empty shift explains apply and wages")
	await click(host.schedule_button)
	var evenings: CheckBox
	var nights: CheckBox
	var labels: Array[String] = []
	for box in host.employee_list.find_children("*","CheckBox",true,false):
		labels.append(box.text)
		if box.text.begins_with("저녁"): evenings = box
		if box.text.begins_with("심야"): nights = box
	check(labels.has("아침 06~12시") and labels.has("낮 12~18시") and labels.has("저녁 18~24시") and labels.has("심야 00~06시"),"real schedule controls show actual hour ranges")
	await click(evenings)
	await click(nights)
	check(worker.work_periods.is_empty(),"selection alone does not apply shift")
	await click(card_button("근무표 적용"))
	check(worker.work_periods == ["evening","night"],"apply stores adjacent cross-midnight shift")
	check(host.message_label.text.contains("18~24시") and host.message_label.text.contains("00~06시") and host.message_label.text.contains("가게 문"),"applied shift explains when and how to begin")
	check(host.employee_scroll.size.y >= 220,"schedule explanation leaves usable scrolling height")
	await snapshot("schedule")
	var saved := GameState.create_save_data().duplicate(true)
	check(GameState.apply_save_data(saved) and not EmployeeRecruitmentFlow.training_available(id),"scheduled save reload does not invent attendance")
	await close_book()
	manager.current_hour = 12
	manager.open_shop()
	manager.hour_timer.stop()
	manager.customer_spawner.set_process(false)
	manager.customer_spawner.spawn_timer.stop()
	check(manager.shop_open and not worker.on_duty and not worker.visible,"real opening outside shift keeps employee absent")
	await open_employment()
	check(host.message_label.text.contains("근무 시간이 아닙니다") and host.message_label.text.contains("책을 닫"),"midday guide waits for actual evening shift")
	await click(host.schedule_button)
	check(host.message_label.text.contains("조회만") and host.message_label.text.contains("아침 6시"),"read-only schedule explains next editable time")
	var morning: Array[String] = ["morning"]
	check(card_button("근무표 적용").disabled and not worker.set_work_periods(morning),"real guards reject shift change while open")
	await snapshot("read-only")
	await close_book()
	manager.current_hour = 18
	world.get_node("Actors/Player").global_position += Vector2(250,-100)
	for i in range(120):
		await get_tree().physics_frame
		if worker.commute_animation_running: break
	check(worker.commute_animation_running and not worker.on_duty,"evening attendance starts commute before work")
	await open_employment()
	check(host.message_label.text.contains("출근 중") and not host.training_button.visible,"paused arrival directs closing book and keeps education locked")
	await close_book()
	for i in range(1800):
		await get_tree().physics_frame
		if worker.on_duty and worker.visible: break
	controller.elapsed = 1.0
	controller._process(0.01)
	check(worker.on_duty and worker.visible and EmployeeRecruitmentFlow.training_available(id),"real arrival enables first-work education")
	await open_employment()
	await click(host.training_button)
	check(host.message_label.text.contains("조회만") and card_button("교육 ·").disabled and not worker.train_stat("checkout"),"education waits for closed-store preparation")
	await close_book()
	# Clock fixture only; employee must actually leave through the real door.
	manager.current_hour = GameConfig.DAY_START_HOUR
	manager.close_shop_for_day_end_and_settle()
	for i in range(2400):
		await get_tree().physics_frame
		if manager.summary_open: break
	check(manager.summary_open and not worker.visible and not worker.on_duty and worker.state == worker.WorkerState.OFF_DUTY,"real day-end waits for actual employee clock-out")
	if not manager.summary_open: get_tree().paused = false; get_tree().quit(1); return
	manager.confirm_next_day()
	manager.hour_timer.stop()
	check(GameState.total_day == 2 and worker.can_edit_work_schedule(),"next morning allows management after genuine clock-out")
	# Budget fixture isolates existing education cost; no gameplay reward added.
	GameState.money = 500
	await open_employment()
	await click(host.training_button)
	var educate := card_button("교육 ·")
	var cost: int = int(educate.text.get_slice("·",1).strip_edges().trim_suffix("G"))
	await click(educate)
	check(worker.get_training_level("checkout") == 1 and GameState.money == 500 - cost,"actual next-morning education charges existing cost once")
	await snapshot("education")
	GameState.accrue_employee_salary_for_current_day()
	var accrued: int = GameState.get_employee_accrued_salary(id)
	check(accrued > 0 and GameState.get_unpaid_employee_salary() == 0,"current wages exist before prior-period debt")
	await click(host.employment_button)
	await click(card_button("해고"))
	check(host.dismiss_dialog.visible,"actual dismissal opens review")
	host.dismiss_dialog.confirmed.emit()
	host.dismiss_dialog.hide()
	check(not worker.is_hired and worker.work_periods.is_empty() and worker.get_training_level("checkout") == 1,"dismissal clears shift and retains education")
	check(GameState.get_employee_accrued_salary(id) == accrued and host.info_button.visible and not host.schedule_button.visible,"last dismissed employee keeps wage access before settlement")
	await click(host.info_button)
	var text := ""
	for label in host.employee_list.find_children("*","Label",true,false): text += label.text + "\n"
	check(text.contains("현재 누적 급여: %dG" % accrued) and text.contains("28일 기준 급여") and host.employee_list.get_child_count() == 1,"dismissed wage card remains readable")
	host.employee_scroll.scroll_vertical = int(host.employee_scroll.get_v_scroll_bar().max_value)
	await frames()
	var wage_label: Label
	for label in host.employee_list.find_children("*","Label",true,false):
		if label.text.contains("현재 누적 급여:"): wage_label = label
	check(wage_label != null and wage_label.get_global_rect().end.y <= host.employee_scroll.get_global_rect().end.y + 2,"actual scrolling exposes retained wage amount")
	await snapshot("dismissed-salary")
	var money: int = GameState.money
	var wages := GameState.create_save_data().duplicate(true)
	host.refresh_view()
	host.refresh_view()
	check(GameState.money == money and GameState.get_employee_accrued_salary(id) == accrued,"browsing wage page neither pays nor accrues salary")
	check(GameState.apply_save_data(wages),"dismissed wages round-trip full save")
	host.refresh_view()
	check(host.info_button.visible and host.employee_list.get_child_count() == 1,"reload keeps current-period dismissed wages visible")
	await click(host.employment_button)
	await click(card_button("고용 ·"))
	controller.hire_dialog.confirmed.emit()
	controller.hire_dialog.hide()
	check(worker.is_hired and worker.work_periods.is_empty() and worker.get_training_level("checkout") == 1,"rehire retains education and needs fresh shift")
	await click(host.schedule_button)
	await click(card_button("근무표 적용"))
	check(host.message_label.text.contains("출근하지 않습니다") and host.message_label.text.contains("휴무여도"),"empty applied shift explains absence and paid days")
	get_tree().paused = false
	print("CHECK_EMPLOYEE_NEXT_STEPS checks=",checks," failures=",failures)
	get_tree().quit(0 if failures == 0 else 1)
