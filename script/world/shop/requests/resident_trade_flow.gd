class_name ResidentTradeFlow
extends RefCounted
const SETTINGS = preload("res://scenes/shop/requests/default_resident_trade.tres")
const PREFIX := "resident_trade:"

static func available() -> bool:
	return VillageLifeFlow.available(VillageLifeFlow.resident("naru")) and VillageLifeFlow.friendship("naru") >= 1

static func offer(id: String) -> Dictionary:
	for entry in SETTINGS.offers:
		if str(entry["id"]) == id: return entry
	return {}

static func used(id: String) -> int:
	if PlayerProgress.story_beat_days.get(PREFIX + id + ":day", -1) != GameState.total_day: return 0
	return maxi(0, int(PlayerProgress.story_beat_days.get(PREFIX + id + ":count", 0)))

static func remaining(id: String) -> int:
	var entry := offer(id)
	return maxi(0, int(entry.get("daily_limit", 0)) - used(id))

static func blocked_reason(id: String) -> String:
	var entry := offer(id)
	if entry.is_empty(): return "교환 품목을 찾지 못했어요."
	if not available(): return "나루가 정착한 뒤 먼저 안부를 나눠 주세요."
	if VillageLifeFlow.friendship("naru") < int(entry["friendship"]):
		return "나루와 안부 나누기 %d/%d일" % [VillageLifeFlow.friendship("naru"), entry["friendship"]]
	if int(entry["give_amount"]) <= 0 or int(entry["receive_amount"]) <= 0 or int(entry["daily_limit"]) <= 0 \
		or not ItemData.has_item(str(entry["give"])) or not ItemData.has_item(str(entry["receive"])): return "이 교환은 준비 중입니다."
	if remaining(id) <= 0: return "오늘 준비한 수량이 끝났어요. 다음 날 다시 만나요."
	if GameState.get_item_count(str(entry["give"])) < int(entry["give_amount"]): return "교환할 재료가 창고에 부족해요."
	return ""

static func exchange(id: String) -> Dictionary:
	if not blocked_reason(id).is_empty(): return {}
	var entry := offer(id)
	var count := used(id)
	var amount := int(entry["give_amount"])
	if GameState.remove_item(str(entry["give"]), amount) != amount: return {}
	PlayerProgress.record_story_beat(PREFIX + id + ":day", GameState.total_day)
	PlayerProgress.story_beat_days[PREFIX + id + ":count"] = count + 1
	GameState.add_item(str(entry["receive"]), int(entry["receive_amount"]))
	return {"item":str(entry["receive"]), "amount":int(entry["receive_amount"])}
