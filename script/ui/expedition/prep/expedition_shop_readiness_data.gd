class_name ExpeditionShopReadinessData
extends RefCounted
## 출발 때 저장된 영업 상태와 기존 직원 근무표를 조회한다. 판매 계산은 실행하지 않는다.
static func snapshot() -> Dictionary:
	var result := {"valid":false, "roster_valid":true, "status":"unknown", "bands":[], "hired":[]}
	var raw: Variant = GameState.get_meta("shop_return_context",{})
	if not raw is Dictionary: return result
	var context: Dictionary = raw
	var raw_hour: Variant = context.get("hour")
	if not (raw_hour is int or raw_hour is float) or not context.get("was_open") is bool: return result
	# JSON 체크포인트에서 시간은 정수 값의 float로 복원될 수 있다.
	if raw_hour is float and (not is_finite(raw_hour) or raw_hour != floor(raw_hour)): return result
	var hour := int(raw_hour)
	if hour < 0 or hour > 23: return result
	result["valid"] = true
	result["hour"] = hour
	var raw_minute: Variant = context.get("minute",0)
	result["minute"] = 30 if (raw_minute is int or raw_minute is float) and raw_minute == 30 else 0
	result["was_open"] = bool(context["was_open"])
	for id in EmployeeData.get_all_employee_ids():
		var profile := EmployeeData.get_employee(id)
		var saved := GameState.get_employee_state(id)
		if saved.is_empty():
			saved = {"is_hired":bool(profile.get("initially_hired",false)),"work_periods":profile.get("default_work_periods",[])}
		if not GameState.is_employee_state_valid(saved):
			result["roster_valid"] = false
			continue
		if saved["is_hired"]:
			result["hired"].append({"id":id,"name":str(profile.get("display_name",id)),"periods":saved["work_periods"].duplicate()})
	var until := posmod(GameConfig.DAY_START_HOUR-hour,24)
	if until == 0: until = 24
	var cursor := hour
	var limit := hour+until
	var gaps := 0
	while cursor < limit:
		var period := EmployeeData.get_period_at_hour(posmod(cursor,24))
		var stop := cursor+1
		while stop < limit and EmployeeData.get_period_at_hour(posmod(stop,24)) == period: stop += 1
		var names: Array[String] = []
		for employee in result["hired"]:
			if employee["periods"].has(period): names.append(str(employee["name"]))
		if names.is_empty(): gaps += 1
		result["bands"].append({"period":period,"start":cursor,"minute":result["minute"] if cursor == hour else 0,"end":stop,"names":names})
		cursor = stop
	if not result["was_open"]: result["status"] = "closed"
	elif not result["roster_valid"]: result["status"] = "unknown_roster"
	elif gaps == result["bands"].size(): result["status"] = "unstaffed"
	elif gaps > 0: result["status"] = "partial"
	else: result["status"] = "covered"
	return result

static func time_text(hour: int, minute: int = 0, end: bool = false) -> String:
	return "%02d:%02d" % [24 if end and hour > 0 and posmod(hour,24) == 0 else posmod(hour,24),minute]

static func guidance(data: Dictionary) -> String:
	match str(data["status"]):
		"closed": return "가게를 닫고 나왔습니다. 원정 중에는 손님을 받지 않고, 실제 원정에 쓴 만큼 가게 시간이 흐릅니다. 직원 없이도 재료를 구하러 갈 수 있습니다."
		"unstaffed": return "영업하며 나왔지만 다음 정산 전까지 맡아 줄 근무자가 없습니다. 원정 중 플레이어는 계산을 할 수 없어 그 시간의 손님을 놓칩니다. 가게로 돌아가 닫고 떠나거나, 이미 고용한 직원의 근무표를 준비할 수 있습니다."
		"partial": return "영업하며 나왔습니다. 아래 근무표에 비는 시간대가 있습니다. 그 시간까지 원정에 머무르면 계산할 사람이 없어 손님을 놓칩니다. 담당이 있는 시간대에는 실제 진열 재고로 판매를 처리합니다."
		"covered": return "영업하며 나왔고, 다음 정산 전까지 근무표에 담당이 있습니다. 실제 진열 재고가 있어야 판매할 수 있으며 모든 상품이 팔린다는 뜻은 아닙니다."
		"unknown_roster": return "출발 기록은 있지만 일부 직원 근무 기록을 확인할 수 없습니다. 가게로 돌아가 직원 상태와 근무표를 확인해 주세요."
	return "출발 전 가게 기록을 확인할 수 없습니다. 가게로 돌아가 문 상태와 직원 근무표를 확인해 주세요."
