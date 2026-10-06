class_name EmployeeStoryFlow
extends RefCounted
const SETTINGS = preload("res://scenes/shop/employees/default_employee_story.tres")
const PREFIX := "employee_story:"

static func profile(id: String) -> Dictionary:
	for entry in SETTINGS.profiles:
		if str(entry["employee_id"]) == id: return entry
	return {}

static func available(id: String, event: String) -> bool:
	return event == "intro" or PlayerProgress.story_beat_days.has(PREFIX + id + ":" + event)

static func observe_existing(id: String) -> void:
	# 기존 고용을 새 채용으로 기록하거나 급여/교육을 초기화하지 않는다.
	if not PlayerProgress.story_beat_days.has(PREFIX + id + ":hire_count"):
		PlayerProgress.story_beat_days[PREFIX + id + ":hire_count"] = 1

static func record(id: String, event: String) -> void:
	if profile(id).is_empty(): return
	if event == "hired":
		var count := int(PlayerProgress.story_beat_days.get(PREFIX + id + ":hire_count", 0))
		PlayerProgress.story_beat_days[PREFIX + id + ":hire_count"] = count + 1
		if count > 0: event = "rehired"
	PlayerProgress.record_story_beat(PREFIX + id + ":" + event, GameState.total_day)

static func unread(id: String) -> Dictionary:
	for entry in SETTINGS.moments:
		if str(entry["employee_id"]) == id and available(id, str(entry["event"])) and not read(str(entry["id"])):
			return entry
	return {}

static func read(id: String) -> bool:
	return PlayerProgress.story_beat_days.has(PREFIX + "read:" + id)

static func finish(id: String) -> bool:
	for entry in SETTINGS.moments:
		if str(entry["id"]) == id and available(str(entry["employee_id"]), str(entry["event"])) and not read(id):
			PlayerProgress.record_story_beat(PREFIX + "read:" + id, GameState.total_day)
			return true
	return false

static func memory(id: String) -> String:
	var result := ""
	for entry in SETTINGS.moments:
		var key := str(entry["id"])
		if str(entry["employee_id"]) == id and read(key):
			result += "%s · %s\n" % [RequestTextData.text("service_text", key, "title"), RequestTextData.text("service_text", key, "completion")]
	return result if not result.is_empty() else "아직 함께 읽은 이야기가 없습니다."

static func terms(worker: Node, dismiss: bool = false) -> String:
	var id := str(worker.get("employee_id"))
	var salary := EmployeeData.get_monthly_salary(id)
	var cost := int(worker.get_hire_cost())
	if dismiss:
		return "%s과 함께 일하는 것을 마칠까요?\n근무표는 비워지고 교육 단계는 유지됩니다.\n이번 기간 누적 급여 %d G는 지워지지 않습니다.\n누적 급여는 기존 계절 말 정산에 포함됩니다.\n다시 고용할 때 %d G가 필요합니다." % [worker.get_employee_display_name(), GameState.get_employee_accrued_salary(id), cost]
	return "%s과 함께 일할까요?\n고용 비용 %d G · %d일 기준 급여 %d G\n선호 시간: %s\n고용 뒤 근무표를 직접 지정합니다(이어진 최대 2타임).\n휴무여도 고용 중인 날은 급여가 누적됩니다.\n소지금 %d G · 전체 미지급 급여 %d G" % [worker.get_employee_display_name(), cost, CalendarData.DAYS_PER_SEASON, salary, EmployeeData.get_period_name(str(worker.get("preferred_period"))), GameState.money, GameState.get_unpaid_employee_salary()]

static func hire_reason(worker: Node) -> String:
	if not is_instance_valid(worker) or worker.is_queued_for_deletion(): return "직원을 찾을 수 없습니다."
	if bool(worker.get("is_hired")): return "이미 고용된 직원입니다."
	if not worker.can_change_employment(): return "오전 6시 오픈 준비 중에 고용할 수 있습니다."
	if not GameState.can_afford(int(worker.get_hire_cost())): return "고용 비용이 부족합니다."
	return ""
