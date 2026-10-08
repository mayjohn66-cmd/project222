extends Node
var checks := 0
var failures := 0
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(message)
func frames() -> void:
	for i in range(8): await get_tree().process_frame
func drain(dialogue: StoryDialoguePanel) -> void:
	for i in range(100):
		if not dialogue.open: return
		dialogue._advance()
	check(false,"introduction ends")
func snapshot(label: String) -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty() or DisplayServer.get_name() == "headless": return
	await get_tree().create_timer(2.0,true,false,true).timeout
	await frames()
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(args[0] + "-" + label + ".png")
func _ready() -> void: call_deferred("run")
func run() -> void:
	GameState.initialize_new_game()
	PlayerProgress.reset()
	var world = load("res://scenes/shop/main.tscn").instantiate()
	world.get_node("TutorialDirector").enabled = false
	add_child(world)
	await frames()
	OpeningJourneyFlow.initialize(world)
	var director = world.get_node("EmployeeRecruitmentDirector")
	var manager = world.get_node("DayManager")
	manager.hour_timer.stop()
	manager.current_hour = 6
	manager.shop_open = false
	manager.customer_spawner.set_process(false)
	var player = world.get_node("Actors/Player")
	var host = manager.management_menu.employee_content
	var controller = host.employee_content
	var workers := get_tree().get_nodes_in_group("worker")
	check(workers.size() == 3,"existing three workers retained")
	check(EmployeeRecruitmentFlow.next_applicant().is_empty(),"no applicant during core tutorial")
	director.refresh_visit()
	check(not is_instance_valid(director.applicant),"no physical visitor before tutorial completion")
	host.refresh_view()
	check(host.employee_list.get_child_count() == 0 and not host.schedule_button.visible and not host.training_button.visible and not host.info_button.visible,"empty early employee page hides advanced tabs and un-met candidates")
	for worker in workers:
		check(not worker.hire_employee(),"direct hire also rejects un-met candidate")
	for step in TutorialDirector.SETTINGS.steps:
		if not step.get("optional",false): PlayerProgress.record_story_beat("tutorial_step:" + str(step["id"]) + ":done",GameState.total_day)
	check(EmployeeRecruitmentFlow.next_applicant() == "worker_001","first existing employee follows core tutorial")
	await get_tree().physics_frame
	director.refresh_visit()
	check(is_instance_valid(director.applicant),"actual applicant spawned on clear road")
	if not is_instance_valid(director.applicant): get_tree().quit(1); return
	check(director.applicant.is_in_group("story_npc") and not director.applicant.is_in_group("worker") and not director.applicant.is_in_group("customer"),"applicant does not participate in wages or sales")
	check(director.applicant.get_meta("look_key") == "worker" and director.applicant.sprite.sprite_frames != null,"existing appearance rendered in 2D and 3D")
	check(director.applicant.global_position.distance_to(director.applicant.destination) >= EmployeeRecruitmentFlow.SETTINGS.applicant_walk_distance,"arrival starts away from conversation point")
	check(not director.applicant.route.is_empty(),"actual connected walking route exists")
	var start: Vector2 = director.applicant.global_position
	player.global_position = start + Vector2(350,0)
	for i in range(100): await get_tree().physics_frame
	check(director.applicant.global_position.distance_to(start) > 10,"actual applicant walks toward store")
	check(not director.try_interact(),"cannot talk from far away")
	player.global_position = director.applicant.global_position + Vector2(25,0)
	check(not director.interaction_hint().is_empty(),"nearby E hint names applicant")
	check(world.get_node("WorldInteractions").try_interact(),"real shared E interaction opens applicant introduction")
	check(director.dialogue.open and manager.hour_timer.paused and not player.is_physics_processing() and world.get_node("WorldInteractions").blocked(),"conversation pauses time and blocks movement and other interactions")
	await snapshot("applicant")
	director.dialogue.close()
	check(not EmployeeRecruitmentFlow.met("worker_001") and not EmployeeStoryFlow.read("worker_001_intro") and not manager.hour_timer.paused and player.is_physics_processing(),"later leaves meeting unfinished and resumes exactly")
	check(director.try_interact(),"introduction may be retried without penalty")
	drain(director.dialogue)
	check(EmployeeRecruitmentFlow.met("worker_001") and EmployeeStoryFlow.read("worker_001_intro"),"completed real introduction records both meeting and story")
	check(not workers[0].is_hired and GameState.money == 0,"meeting neither hires nor charges")
	host.refresh_view()
	check(host.employee_list.get_child_count() == 1,"only met applicant appears")
	check(EmployeeRecruitmentFlow.next_applicant().is_empty(),"second applicant does not appear on same day")
	manager.management_menu.open_menu(ManagementMenu.MenuTab.EMPLOYEE)
	host._select_employee_tab(host.EmployeeTab.EMPLOYMENT)
	await frames()
	check(host.employee_scroll.size.y >= 250, "candidate page keeps usable scrolling height")
	for button in host.employee_list.find_children("*","Button",true,false):
		if button.text.begins_with("고용 ·"):
			check(host.employee_scroll.get_global_rect().encloses(button.get_global_rect()), "first candidate hire button fully visible without scrolling")
	await snapshot("candidate")
	controller.request_hire(workers[0])
	check(controller.hire_dialog.visible,"real candidate can review existing terms")
	controller.hire_dialog.canceled.emit()
	controller.hire_dialog.hide()
	check(not workers[0].is_hired,"declining contract leaves optional progression unchanged")
	controller.request_hire(workers[0])
	controller.hire_dialog.confirmed.emit()
	controller.hire_dialog.hide()
	check(workers[0].is_hired and workers[0].work_periods.is_empty() and GameState.money == 0,"existing free hire with empty schedule retained")
	host.refresh_view()
	check(host.schedule_button.visible and host.info_button.visible and not host.training_button.visible,"first contract exposes schedule and wage information but hides education")
	check(not workers[0].train_stat("checkout"),"training API cannot bypass actual first attendance")
	host._select_employee_tab(host.EmployeeTab.TRAINING)
	check(host.current_employee_tab == host.EmployeeTab.EMPLOYMENT,"direct hidden-tab selection falls back safely")
	await frames()
	check(host.employee_scroll.size.y >= 220, "hired page keeps usable scrolling height")
	await snapshot("hired")
	manager.management_menu.close_menu()
	for i in range(120):
		await get_tree().process_frame
		if not manager.management_menu.visible: break
	var periods: Array[String] = ["morning"]
	check(workers[0].set_work_periods(periods),"player explicitly chooses first shift")
	check(not EmployeeRecruitmentFlow.training_available("worker_001"),"schedule assignment does not pretend attendance")
	manager.shop_open = true
	workers[0]._on_shop_opened()
	for i in range(1800):
		await get_tree().physics_frame
		if workers[0].on_duty and workers[0].visible: break
	controller.elapsed = 1
	controller._process(0.01)
	check(workers[0].on_duty and workers[0].visible and EmployeeRecruitmentFlow.training_available("worker_001"),"actual existing commute unlocks first-shift education")
	host.refresh_view()
	check(host.training_button.visible,"education becomes visible after actual attendance")
	GameState.advance_calendar_day()
	manager.shop_open = false
	check(EmployeeRecruitmentFlow.next_applicant() == "worker_002","next candidate waits until following day independent of hiring")
	await frames()
	director.refresh_visit()
	check(is_instance_valid(director.applicant) and director.applicant.employee_id == "worker_002","second actual visitor replaces greeted applicant")
	player.global_position = director.applicant.global_position + Vector2(25,0)
	check(director.try_interact(),"second actual visitor can be greeted")
	drain(director.dialogue)
	check(EmployeeRecruitmentFlow.met("worker_002") and not workers[1].is_hired,"second applicant may remain un-hired")
	check(EmployeeRecruitmentFlow.next_applicant().is_empty(),"third visitor again waits a day")
	GameState.advance_calendar_day()
	check(EmployeeRecruitmentFlow.next_applicant() == "worker_003","third applicant follows even without hiring second")
	var saved := GameState.create_save_data().duplicate(true)
	check(GameState.apply_save_data(saved) and EmployeeRecruitmentFlow.met("worker_002") and EmployeeRecruitmentFlow.training_available("worker_001") and not EmployeeRecruitmentFlow.met("worker_003"),"save/reload preserves gradual meetings and actual attendance")
	check(EmployeeRecruitmentFlow.next_applicant() == "worker_003", "calendar and next-applicant eligibility survive real save reload")
	# Migration preserves old hired, dismissed/educated and wage records without granting money.
	PlayerProgress.story_beat_days.erase(EmployeeRecruitmentFlow.VERSION)
	for id in EmployeeData.get_all_employee_ids(): PlayerProgress.story_beat_days.erase(EmployeeRecruitmentFlow.PREFIX + id)
	var levels := {"checkout":1,"restock":0,"movement":0,"service":0}
	GameState.set_employee_state("worker_002",false,[])
	GameState.employee_states["worker_002"]["training_levels"] = levels
	GameState.money = 600
	GameState.accrue_employee_salary_for_current_day()
	var wage := GameState.get_employee_accrued_salary("worker_001")
	EmployeeRecruitmentFlow.initialize(workers)
	check(EmployeeRecruitmentFlow.met("worker_001") and EmployeeRecruitmentFlow.met("worker_002") and not EmployeeRecruitmentFlow.met("worker_003"),"legacy hired and previously educated accessible; untouched candidates stay hidden")
	check(EmployeeRecruitmentFlow.training_available("worker_002") and workers[1].get_training_level("checkout") == 1 and GameState.money == 600 and GameState.get_employee_accrued_salary("worker_001") == wage,"migration retains training, money, wages and education access")
	check(not EmployeeStoryFlow.available("worker_002", "first_shift"), "legacy education access does not invent first-attendance story")
	var keys := PlayerProgress.story_beat_days.duplicate()
	EmployeeRecruitmentFlow.initialize(workers)
	check(keys == PlayerProgress.story_beat_days,"migration is idempotent")
	GameState.initialize_new_game()
	check(not EmployeeRecruitmentFlow.met("worker_001") and not EmployeeRecruitmentFlow.training_available("worker_001"),"new game clears applicant and first-shift progress")
	print("CHECK_EMPLOYEE_RECRUITMENT checks=",checks," failures=",failures)
	get_tree().quit(0 if failures == 0 else 1)
