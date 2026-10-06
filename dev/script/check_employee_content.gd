extends Node
const Tools = preload("res://dev/gemini/request_text_tools.gd")
var checks := 0
var failures := 0
var host
var controller: EmployeeContentController

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func frames() -> void:
	for i in range(8): await get_tree().process_frame

func snap(name: String) -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty(): return
	await frames()
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(args[0] + "-" + name + ".png")

func close_book(menu: Control) -> void:
	menu.close_menu()
	for i in range(120):
		await get_tree().process_frame
		if not menu.visible: break

func drain() -> void:
	for i in range(30):
		if not controller.dialogue.open: return
		controller.dialogue._advance()
	check(false, "employee conversation ends")

func _ready() -> void: call_deferred("run")

func run() -> void:
	GameState.initialize_new_game()
	PlayerProgress.reset()
	var world = load("res://scenes/shop/main.tscn").instantiate()
	world.get_node("TutorialDirector").enabled = false
	add_child(world)
	await frames()
	OpeningJourneyFlow.initialize(world)
	# 직원 관리는 첫 영업·원정 안내를 마친 상태에서 검사한다.
	for step in TutorialDirector.SETTINGS.steps:
		if not step.get("optional", false): PlayerProgress.record_story_beat("tutorial_step:" + str(step["id"]) + ":done", 1)
	var manager = world.get_node("DayManager")
	manager.hour_timer.stop()
	manager.current_hour = 6
	manager.shop_open = false
	manager.customer_spawner.set_process(false)
	var menu = world.find_child("ManagementMenu", true, false)
	check(menu != null, "actual management book exists")
	menu.open_menu(ManagementMenu.MenuTab.EMPLOYEE)
	if DisplayServer.get_name() != "headless": await get_tree().create_timer(1.0, true, false, true).timeout
	host = menu.employee_content
	host._select_employee_tab(host.EmployeeTab.EMPLOYMENT)
	controller = host.employee_content
	var workers := get_tree().get_nodes_in_group("worker")
	var worker = workers[2]
	var id: String = worker.employee_id
	for candidate in workers:
		candidate.set_physics_process(false)
		check(not candidate.is_hired and not EmployeeStoryFlow.profile(candidate.employee_id).is_empty(), "new game keeps existing candidate un-hired with content")
	GameState.money = 400
	host.refresh_view()
	controller.open_story(id)
	await snap("introduction")
	controller.dialogue.close()
	check(not EmployeeStoryFlow.read(id + "_intro"), "partial introduction marks nothing")
	controller.open_story(id)
	drain()
	check(EmployeeStoryFlow.read(id + "_intro") and not worker.is_hired and GameState.money == 400, "complete introduction records story without hiring or charging")
	var button: Button
	for candidate_button in host.employee_list.get_child(2).find_children("*", "Button", true, false):
		if candidate_button.text.begins_with("고용 ·"): button = candidate_button
	check(button != null, "real candidate hire button exists")
	button.pressed.emit()
	await snap("hire")
	check(controller.hire_dialog.visible and not worker.is_hired and GameState.money == 400, "actual button opens review without charging")
	check(controller.hire_dialog.dialog_text.contains("28일 기준 급여 1400 G") and controller.hire_dialog.dialog_text.contains("휴무여도"), "hire review explains cycle wage and paid days without shifts")
	controller.hire_dialog.canceled.emit()
	controller.hire_dialog.hide()
	check(controller.pending_hire == null and not worker.is_hired and GameState.money == 400, "cancel hire changes no employment or cash")
	controller.request_hire(worker)
	manager.shop_open = true
	controller.hire_dialog.confirmed.emit()
	controller.hire_dialog.hide()
	check(not worker.is_hired and GameState.money == 400, "confirmation rechecks changed opening state")
	manager.shop_open = false
	controller.request_hire(worker)
	GameState.money = 0
	controller.hire_dialog.confirmed.emit()
	controller.hire_dialog.hide()
	check(not worker.is_hired and GameState.money == 0, "confirmation rechecks funds")
	GameState.money = 400
	controller.request_hire(worker)
	controller.hire_dialog.confirmed.emit()
	controller.hire_dialog.hide()
	check(worker.is_hired and worker.work_periods.is_empty() and GameState.money == 300 and EmployeeStoryFlow.available(id, "hired"), "confirm hires once with existing cost and empty schedule")
	controller.request_hire(worker)
	check(not controller.hire_dialog.visible and GameState.money == 300, "duplicate hire cannot charge")
	controller.open_story(id)
	drain()
	check(EmployeeStoryFlow.read(id + "_hired") and not EmployeeStoryFlow.available(id, "first_shift"), "first contract read does not pretend employee attended")
	GameState.accrue_employee_salary_for_current_day()
	GameState.accrue_employee_salary_for_current_day()
	check(GameState.get_employee_accrued_salary(id) == 50, "existing wage accrues once even with empty schedule")
	host._train_employee(worker, "checkout")
	check(worker.get_training_level("checkout") == 1 and GameState.money == 200 and EmployeeStoryFlow.available(id, "trained"), "successful real education unlocks story at existing cost")
	GameState.money = 0
	host._train_employee(worker, "restock")
	check(worker.get_training_level("restock") == 0, "failed education grants no level")
	GameState.money = 200
	var periods: Array[String] = ["evening", "night"]
	check(worker.set_work_periods(periods), "actual existing contiguous shift accepted")
	var invalid: Array[String] = ["morning", "evening"]
	check(not worker.set_work_periods(invalid) and worker.work_periods == periods, "nonadjacent shifts still rejected")
	host._request_dismiss(worker)
	await snap("dismiss")
	check(host.dismiss_dialog.visible and host.dismiss_dialog.dialog_text.contains("누적 급여 50 G는 지워지지") and host.dismiss_dialog.dialog_text.contains("교육 단계는 유지"), "real dismissal review explains retained wage and training")
	host.dismiss_dialog.canceled.emit()
	host.dismiss_dialog.hide()
	check(worker.is_hired and worker.work_periods == periods and not EmployeeStoryFlow.available(id, "dismissed"), "cancel dismissal preserves state and story")
	host._request_dismiss(worker)
	host.dismiss_dialog.confirmed.emit()
	host.dismiss_dialog.hide()
	check(not worker.is_hired and worker.work_periods.is_empty() and worker.get_training_level("checkout") == 1 and GameState.get_employee_accrued_salary(id) == 50 and GameState.money == 200, "confirmed dismissal clears shifts and preserves education and wages without refund")
	check(EmployeeStoryFlow.available(id, "dismissed"), "actual dismissal unlocks farewell")
	check(not worker.dismiss_employee(), "duplicate dismissal rejected")
	GameState.total_day += 1
	GameState.accrue_employee_salary_for_current_day()
	check(GameState.get_employee_accrued_salary(id) == 50, "not hired adds no new paid day")
	controller.request_hire(worker)
	controller.hire_dialog.confirmed.emit()
	controller.hire_dialog.hide()
	check(worker.is_hired and GameState.money == 100 and worker.get_training_level("checkout") == 1 and EmployeeStoryFlow.available(id, "rehired"), "rehire charges same cost and retains education with reunion story")
	var saved := GameState.create_save_data().duplicate(true)
	check(GameState.apply_save_data(saved) and EmployeeStoryFlow.read(id + "_intro") and EmployeeStoryFlow.available(id, "rehired") and GameState.get_employee_accrued_salary(id) == 50, "full save reload preserves stories, employment, education and wage")
	GameState.close_employee_salary_period()
	check(GameState.get_unpaid_employee_salary() == 50 and GameState.pay_unpaid_employee_salary() == 50 and GameState.money == 50, "retained wages are paid through existing period settlement")
	controller.open_story(id)
	check(controller.dialogue.open, "pending work story can resume")
	await close_book(menu)
	check(not controller.dialogue.open and not controller.hire_dialog.visible and not get_tree().paused, "closing management clears content modals and resumes gameplay")
	menu.open_menu(ManagementMenu.MenuTab.EMPLOYEE)
	host._select_employee_tab(host.EmployeeTab.EMPLOYMENT)
	host._request_dismiss(worker)
	await close_book(menu)
	check(not host.dismiss_dialog.visible and host.pending_dismiss_worker == null and worker.is_hired, "closing book cancels pending dismissal without firing")
	# 기존 출근 경로를 실제로 실행해 첫 근무를 관찰한다.
	check(worker.set_work_periods(periods), "rehire schedule is explicitly assigned again")
	manager.current_hour = 18
	manager.shop_open = true
	worker._on_shop_opened()
	for i in range(1800):
		await get_tree().physics_frame
		if worker.on_duty and worker.visible: break
	controller.elapsed = 1.0
	controller._process(0.01)
	check(worker.on_duty and worker.visible and EmployeeStoryFlow.available(id, "first_shift"), "actual arrival unlocks first shift story")
	var known := Tools.load_sources()
	var csv := RequestTextData.read_file(RequestTextData.CSV_PATH)
	for moment in EmployeeStoryFlow.SETTINGS.moments:
		check(known["service_text"].has(moment["id"]) and csv.has("service_text:" + str(moment["id"])), "Gemini source and runtime text exist: " + str(moment["id"]))
	check(not known["service_text"].has("worker_001"), "mechanical candidate profiles are not prose rows")
	GameState.initialize_new_game()
	check(not EmployeeStoryFlow.available(id, "hired") and not EmployeeStoryFlow.read(id + "_intro"), "new game clears employment stories")
	print("CHECK_EMPLOYEE_CONTENT checks=", checks, " failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)
