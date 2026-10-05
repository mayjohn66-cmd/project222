class_name PowerRepairFlow
extends RefCounted
const SETTINGS = preload("res://scenes/shop/power/default_power_repair.tres")
const PREFIX := "shop_power:"
const JOURNAL_ID := "shop_power"

static func opted_in() -> bool: return PlayerProgress.story_beat_days.has(PREFIX + "broken")
static func marked(step: String) -> bool: return PlayerProgress.story_beat_days.has(PREFIX + step)
static func powered() -> bool: return not opted_in() or marked("restored")
static func introduced() -> bool: return marked("introduced")
static func title() -> String: return RequestTextData.text("service_text", "power_stone_intro", "title", "꺼진 계산대에 다시 불이")
static func action(resident_id: String) -> Dictionary:
	if not opted_in() or powered() or introduced() or resident_id != "naru": return {}
	if not VillageLifeFlow.available(VillageLifeFlow.resident("naru")): return {}
	return {"flow":"power_repair", "id":"power_stone_intro", "stage":"introduction", "resident":"naru"}
static func complete_action(entry: Dictionary) -> bool:
	if entry.is_empty() or entry != action(str(entry.get("resident", ""))): return false
	PlayerProgress.record_story_beat(PREFIX + "introduced", GameState.total_day)
	return true
static func phase() -> String:
	if not opted_in(): return "legacy"
	if powered(): return "memory"
	if not introduced(): return "undiscovered"
	if not marked("inspected"): return "inspection"
	if not marked("ordered"): return "supplies"
	return "finish" if GameState.total_day >= ready_day() else "working"
static func ready_day() -> int:
	return int(PlayerProgress.story_beat_days.get(PREFIX + "ordered", GameState.total_day)) + SETTINGS.work_days
static func inspect() -> bool:
	if phase() != "inspection": return false
	PlayerProgress.record_story_beat(PREFIX + "inspected", GameState.total_day)
	return true
static func blocked_reason() -> String:
	if phase() != "supplies": return "먼저 기술자에게 점검을 받으세요."
	if SETTINGS.fee <= 0 or SETTINGS.work_days < 1: return "개조 조건을 확인할 수 없습니다."
	for requirement in SETTINGS.requirements:
		var item := str(requirement.get("item", ""))
		var amount := int(requirement.get("amount", 0))
		if not ItemData.has_item(item) or amount <= 0: return "필요 재료를 확인할 수 없습니다."
		if GameState.get_item_count(item) < amount: return "필요 재료를 일반 창고에 준비하세요."
	if not GameState.can_afford(SETTINGS.fee): return "개조비가 부족합니다. 수기로 장사하며 준비할 수 있습니다."
	return ""
static func order() -> bool:
	if not blocked_reason().is_empty(): return false
	if not GameState.spend_money(SETTINGS.fee): return false
	for requirement in SETTINGS.requirements: GameState.remove_item(str(requirement["item"]), int(requirement["amount"]))
	PlayerProgress.record_story_beat(PREFIX + "ordered", GameState.total_day)
	return true
static func finish() -> bool:
	if phase() != "finish": return false
	PlayerProgress.record_story_beat(PREFIX + "restored", GameState.total_day)
	return true
static func information() -> String:
	match phase():
		"legacy": return "기존 저장의 계산대는 현재 상태를 유지합니다."
		"memory": return "마석 발전기를 연결한 계산대입니다. 현지 기술자에게 맡겨 되찾은 첫 기계입니다."
		"undiscovered": return "계산대 전원이 꺼졌습니다. 지금은 장부로 거래합니다. 첫 거래와 원정을 마치고 정착한 타블렌과 이야기하세요."
		"inspection": return "타블렌에게 마석 이야기를 들었습니다. 노점 근처 순회 기술자에게 점검을 받으세요. [E]"
		"working", "finish": return "%d일차부터 기술자에게 작업 마무리를 들을 수 있습니다. [E]\n기다리는 동안 장부로 계속 영업할 수 있습니다." % ready_day()
	var text := "마석은 기술자가 조달합니다. 개조비에 포함됩니다.\n"
	for requirement in SETTINGS.requirements:
		text += "%s · 일반 창고 %d/%d\n" % [ItemData.get_item_name(str(requirement["item"])), GameState.get_item_count(str(requirement["item"])), requirement["amount"]]
	return text + "개조비 %dG · 소지금 %dG\n맡긴 날부터 게임 날짜 %d일 뒤 완료 대화.\n재료는 원정의 광산에서 준비할 수 있습니다." % [SETTINGS.fee, GameState.get_money(), SETTINGS.work_days]
