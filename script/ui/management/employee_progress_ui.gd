class_name EmployeeProgressUI
extends RefCounted
static func refresh(host) -> void:
	if not EmployeeRecruitmentFlow.enabled():
		for button in host.employee_tab_buttons.values(): button.show()
		return
	var workers: Array[Node] = host.get_tree().get_nodes_in_group("worker")
	var hired := EmployeeRecruitmentFlow.has_hired(workers)
	var training := false
	for worker in workers:
		if bool(worker.get("is_hired")) and EmployeeRecruitmentFlow.training_available(str(worker.get("employee_id"))): training = true
	host.schedule_button.visible = hired
	host.info_button.visible = hired or GameState.get_unpaid_employee_salary() > 0 or (EmployeeNextStepGuide.ENABLED and EmployeeNextStepGuide.has_accrued_salary(workers))
	host.training_button.visible = training
	if not host.employee_tab_buttons[host.current_employee_tab].visible:
		host.current_employee_tab = host.EmployeeTab.EMPLOYMENT
static func show_worker(host, worker: Node) -> bool:
	if not EmployeeRecruitmentFlow.enabled(): return true
	var hired := bool(worker.get("is_hired"))
	var id := str(worker.get("employee_id"))
	if not hired and not EmployeeRecruitmentFlow.met(id): return false
	if host.current_employee_tab == host.EmployeeTab.TRAINING: return hired and EmployeeRecruitmentFlow.training_available(id)
	if host.current_employee_tab == host.EmployeeTab.INFO: return hired or PlayerProgress.story_beat_days.has(EmployeeStoryFlow.PREFIX + id + ":hire_count") or (EmployeeNextStepGuide.ENABLED and GameState.get_employee_accrued_salary(id) > 0)
	if host.current_employee_tab == host.EmployeeTab.SCHEDULE: return hired
	return true
