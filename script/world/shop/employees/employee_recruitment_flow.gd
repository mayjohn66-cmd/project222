class_name EmployeeRecruitmentFlow
extends RefCounted
const SETTINGS = preload("res://scenes/shop/employees/default_employee_story.tres")
const VERSION := "employee_recruitment:v1"
const PREFIX := "employee_recruitment:met:"
static func enabled() -> bool: return SETTINGS.recruitment_enabled
static func met(id: String) -> bool:
	return not enabled() or PlayerProgress.story_beat_days.has(PREFIX + id)
static func meet(id: String) -> void:
	if not PlayerProgress.story_beat_days.has(PREFIX + id):
		PlayerProgress.record_story_beat(PREFIX + id, GameState.total_day)
static func training_available(id: String) -> bool:
	return not enabled() or EmployeeStoryFlow.available(id, "first_shift") or PlayerProgress.story_beat_days.has("employee_recruitment:legacy_access:" + id)
static func initialize(workers: Array[Node]) -> void:
	if not enabled() or PlayerProgress.story_beat_days.has(VERSION): return
	# Old hired, trained, previously hired/read candidates remain accessible.
	for worker in workers:
		var id := str(worker.get("employee_id"))
		var state := GameState.get_employee_state(id)
		var experienced := bool(worker.get("is_hired")) or int(GameState.get_employee_salary_record(id).get("last_accrual_day", 0)) > 0
		for level in state.get("training_levels", {}).values(): experienced = experienced or int(level) > 0
		var known := experienced or PlayerProgress.story_beat_days.has(EmployeeStoryFlow.PREFIX + id + ":hire_count") or EmployeeStoryFlow.read(id + "_intro")
		if known: meet(id)
		if experienced and not training_available(id): PlayerProgress.record_story_beat("employee_recruitment:legacy_access:" + id, GameState.total_day)
	PlayerProgress.record_story_beat(VERSION, GameState.total_day)
static func next_applicant() -> String:
	if not enabled() or not OpeningJourneyFlow.core_finished(): return ""
	var previous_day := -1
	for id in EmployeeData.get_all_employee_ids():
		if met(id):
			previous_day = maxi(previous_day, int(PlayerProgress.story_beat_days.get(PREFIX + id, -1)))
			continue
		if previous_day >= 0 and GameState.total_day < previous_day + SETTINGS.applicant_day_gap: return ""
		return id
	return ""
static func has_hired(workers: Array[Node]) -> bool:
	for worker in workers:
		if bool(worker.get("is_hired")): return true
	return false
static func guide(workers: Array[Node]) -> String:
	for worker in workers:
		if not bool(worker.get("is_hired")): continue
		if worker.get_work_periods().is_empty(): return "함께 일할 시간대를 근무표에서 골라 주세요. 휴무여도 급여는 누적됩니다."
		if not training_available(str(worker.get("employee_id"))): return "가게를 열고 직원의 첫 출근을 지켜보세요. 함께 일한 뒤 교육을 알아볼 수 있습니다."
	if has_hired(workers): return "함께 일한 직원은 교육 탭에서 능력을 키울 수 있습니다. 아침 6시 오픈 준비 중에 살펴보세요."
	for worker in workers:
		if met(str(worker.get("employee_id"))): return "소개를 들은 지원자의 조건을 살펴보세요. 고용은 아침 6시 오픈 준비 중에 결정할 수 있습니다."
	return "가게 앞에 찾아온 지원자와 [E]로 이야기하세요. 소개를 들은 사람의 고용 조건을 여기서 살펴볼 수 있습니다."
