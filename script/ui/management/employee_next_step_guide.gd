class_name EmployeeNextStepGuide
extends RefCounted
# Reads the current visit, assigned shifts and retained wages. No hiring or story completion.
const ENABLED := true

static func world_for(host: Node) -> Node:
	var world := host
	while world != null and world.get_node_or_null("DayManager") == null: world = world.get_parent()
	return world

static func manager_for(host: Node) -> Node:
	var world := world_for(host)
	return world.get_node("DayManager") if world != null else null

static func valid_workers(workers: Array[Node]) -> Array[Node]:
	return workers.filter(func(worker): return is_instance_valid(worker) and not worker.is_queued_for_deletion())

static func period_text(period: String) -> String:
	var hours: Array[int] = []
	for hour in range(24):
		if EmployeeData.get_period_at_hour(hour) == period: hours.append(hour)
	if hours.is_empty(): return EmployeeData.get_period_name(period)
	return "%s %02d~%02d시" % [EmployeeData.get_period_name(period),hours[0],hours[-1] + 1]

static func schedule_text(worker: Node) -> String:
	var parts: Array[String] = []
	for period in worker.get_work_periods(): parts.append(period_text(str(period)))
	return "휴무" if parts.is_empty() else " · ".join(parts)

static func has_accrued_salary(workers: Array[Node]) -> bool:
	for worker in valid_workers(workers):
		if GameState.get_employee_accrued_salary(str(worker.get("employee_id"))) > 0: return true
	return false

static func preparation(manager: Node) -> String:
	if manager == null: return "변경은 아침 %d시, 문을 열기 전 정비 시간에 합니다." % GameConfig.DAY_START_HOUR
	if manager.summary_open or manager.closing_shop: return "하루 정산과 직원 퇴근을 마친 뒤 변경할 수 있습니다."
	if manager.current_hour != GameConfig.DAY_START_HOUR or manager.shop_open:
		return "지금은 조회만 할 수 있습니다. 변경은 아침 %d시, 문을 열기 전에 합니다." % GameConfig.DAY_START_HOUR
	return "지금은 문을 열기 전 정비 시간입니다."

static func employment(host: Node, workers: Array[Node]) -> String:
	var world := world_for(host)
	var manager := manager_for(host)
	var hired := valid_workers(workers).filter(func(worker): return bool(worker.get("is_hired")))
	# An empty shift is more urgent than another employee's optional education.
	for worker in hired:
		if worker.get_work_periods().is_empty():
			return "%s은 휴무로 되어 있습니다. 근무표에서 시간대를 고르고 ‘근무표 적용’을 누르세요.\n휴무여도 급여는 누적됩니다." % worker.get_employee_display_name() + ("\n" + preparation(manager) if manager != null and (manager.current_hour != GameConfig.DAY_START_HOUR or manager.shop_open) else "")
	for worker in hired:
		if not EmployeeRecruitmentFlow.training_available(str(worker.get("employee_id"))): return first_shift(worker,manager)
	if not hired.is_empty():
		return "함께 일한 직원은 교육 탭에서 능력을 키울 수 있습니다.\n" + preparation(manager)
	for worker in valid_workers(workers):
		if EmployeeRecruitmentFlow.met(str(worker.get("employee_id"))):
			return "소개를 들은 지원자의 고용 조건을 살펴보세요.\n" + preparation(manager)
	if EmployeeRecruitmentFlow.enabled() and not OpeningJourneyFlow.core_finished():
		return "먼저 현재 가게 안내를 따라 직접 계산과 첫 원정을 익혀 보세요.\n첫 영업과 원정 재료 판매를 마치면 함께 일할 지원자가 찾아옵니다."
	if world != null:
		var director = world.get_node_or_null("EmployeeRecruitmentDirector")
		if director != null and is_instance_valid(director.applicant) and not director.applicant.is_queued_for_deletion():
			return "가게 앞의 %s 지원자와 [E]로 인사를 나눠 보세요.\n책을 닫으면 지원자의 이동과 대화를 이어갈 수 있습니다." % EmployeeData.get_employee(director.applicant.employee_id)["display_name"]
	return "아직 소개를 들은 지원자가 없습니다. 책을 닫고 가게를 돌보며 방문을 기다려 보세요."

static func first_shift(worker: Node, manager: Node) -> String:
	var roster := "%s · %s" % [worker.get_employee_display_name(),schedule_text(worker)]
	if worker.get_work_periods().is_empty():
		return roster + "\n시간대를 비우면 출근하지 않습니다. 휴무여도 고용한 날의 급여는 누적됩니다."
	if manager == null or not manager.shop_open:
		return roster + "\n가게를 연 뒤 맡긴 시간대에 출근합니다. 책을 닫고 가게 문을 열어 주세요."
	if not worker.is_hour_in_shift(manager.current_hour):
		return roster + "\n지금은 이 직원의 근무 시간이 아닙니다. 책을 닫고 맡긴 시간대까지 가게를 운영해 보세요."
	if bool(worker.get("commute_animation_running")):
		return roster + "\n직원이 출근 중입니다. 책을 닫고 가게 안으로 들어오는 모습을 지켜보세요."
	if EmployeeRecruitmentFlow.training_available(str(worker.get("employee_id"))):
		return roster + "\n책을 닫고 맡긴 시간대의 근무를 이어가세요."
	return roster + "\n직원이 실제 출근한 뒤 교육이 열립니다. 책을 닫고 첫 근무를 지켜보세요."

static func tab_message(host, workers: Array[Node]) -> String:
	var world := world_for(host)
	var manager := manager_for(host)
	match host.current_employee_tab:
		host.EmployeeTab.EMPLOYMENT: return employment(host,workers)
		host.EmployeeTab.SCHEDULE:
			return "이어진 시간대를 최대 2개 고른 뒤 ‘근무표 적용’을 누르세요. 모두 해제하면 휴무입니다.\n" + preparation(manager)
		host.EmployeeTab.TRAINING:
			return "처음 출근한 직원의 능력을 교육합니다. 비용과 다음 효과를 살펴보세요.\n" + preparation(manager)
		host.EmployeeTab.INFO:
			return "근무·능력과 이번 급여 기간의 누적 급여를 확인합니다. 해고해도 이미 쌓인 급여는 남습니다.\n이전 기간 미지급 급여: %d G" % GameState.get_unpaid_employee_salary()
	return ""
