class_name VillageGoodwillFlow
extends RefCounted

const SETTINGS = preload("res://scenes/shop/requests/default_village_goodwill.tres")
const PREFIX := "village_goodwill:shop_neighbors:"
const JOURNAL_ID := "event:shop_neighbors"

static func title() -> String:
	return RequestTextData.text("service_text", "goodwill_intro", "title", "가게 앞에 남기는 안부")
static func accepted() -> bool: return PlayerProgress.story_beat_days.has(PREFIX + "accepted")
static func heard(id: String) -> bool: return PlayerProgress.story_beat_days.has(PREFIX + "heard:" + id)
static func completed() -> bool: return PlayerProgress.story_beat_days.has(PREFIX + "done")

static func locked_reason() -> String:
	if not ResidentRequestFlow.tutorial_finished(): return "첫 거래와 원정 재료 판매를 마치고 이웃들과 인연을 이어 가세요."
	for id in SETTINGS.participants:
		var resident := VillageLifeFlow.resident(id)
		if not VillageLifeFlow.available(resident): return "%s의 정착을 기다리고 있어요." % resident.get("name", "주민")
	if not VillageRestFlow.completed(): return "길목 쉼터의 첫 모임을 끝까지 함께해 주세요."
	var last_day := int(PlayerProgress.story_beat_days[VillageRestFlow.PREFIX + "done"])
	for id in SETTINGS.after_requests:
		if not PersonalRequestFlow.done(id): return "%s 부탁을 먼저 마쳐 주세요." % RequestTextData.text("personal_request", id, "title", id)
		if not MarketAfterglowFlow.heard(id): return "%s 전달 뒤 주민에게 후일담을 끝까지 들어 주세요. [E]" % RequestTextData.text("personal_request", id, "title", id)
		last_day = maxi(last_day, int(PlayerProgress.story_beat_days[PersonalRequestFlow.PREFIX + id + ":done"]))
		last_day = maxi(last_day, int(PlayerProgress.story_beat_days[MarketAfterglowFlow.PREFIX + id + ":heard"]))
	if GameState.total_day < last_day + maxi(0, SETTINGS.days_after): return "이웃들의 생활 후일담을 들은 다음 날부터 이야기가 이어져요."
	return ""

static func accept() -> bool:
	if accepted() or completed() or not locked_reason().is_empty(): return false
	PlayerProgress.record_story_beat(PREFIX + "accepted", GameState.total_day)
	return true
static func listen(id: String) -> bool:
	if not accepted() or completed() or heard(id) or id not in SETTINGS.participants or not locked_reason().is_empty(): return false
	PlayerProgress.record_story_beat(PREFIX + "heard:" + id, GameState.total_day)
	return true
static func ready() -> bool:
	if not accepted() or completed() or not locked_reason().is_empty(): return false
	for id in SETTINGS.participants:
		if not heard(id): return false
	return true
static func finish() -> bool:
	if not ready(): return false
	for gift in SETTINGS.gifts:
		if not ItemData.has_item(str(gift.get("item", ""))) or int(gift.get("amount", 0)) <= 0: return false
	PlayerProgress.record_story_beat(PREFIX + "done", GameState.total_day)
	PlayerProgress.story_beat_days[ResidentRequestFlow.PREFIX + "reputation:event/shop_neighbors"] = maxi(0, SETTINGS.reputation)
	for gift in SETTINGS.gifts: GameState.add_item(str(gift["item"]), int(gift["amount"]))
	return true
static func reward_description() -> String:
	var parts: Array[String] = []
	for gift in SETTINGS.gifts: parts.append("%s ×%d" % [ItemData.get_item_name(str(gift["item"])), int(gift["amount"])])
	parts.append("평판 +%d" % maxi(0, SETTINGS.reputation))
	return " · ".join(parts)

static func action(resident_id: String) -> Dictionary:
	if completed() or not locked_reason().is_empty(): return {}
	var stage := ""
	var id := ""
	if not accepted():
		if resident_id != SETTINGS.giver: return {}
		stage = "introduction"
		id = "goodwill_intro"
	elif resident_id in SETTINGS.participants and not heard(resident_id):
		stage = "listen"
		id = "goodwill_" + resident_id
	elif resident_id == SETTINGS.giver:
		stage = "finish" if ready() else "reminder"
		id = "goodwill_finish" if ready() else "goodwill_wait"
	else: return {}
	return {"stage":stage, "id":id, "resident":resident_id, "flow":"goodwill"}

static func complete_action(entry: Dictionary) -> bool:
	if entry.is_empty() or entry != action(str(entry.get("resident", ""))): return false
	match str(entry["stage"]):
		"introduction": return accept()
		"listen": return listen(str(entry["resident"]))
		"finish": return finish()
	return false
static func next_resident() -> String:
	if completed() or not locked_reason().is_empty(): return ""
	if not accepted() or ready(): return SETTINGS.giver
	for id in SETTINGS.participants:
		if not heard(id): return id
	return ""
static func information() -> String:
	if completed():
		var memories: Array[String] = ["안부를 나눈 날: %d일차" % PlayerProgress.story_beat_days[PREFIX + "done"]]
		for id in SETTINGS.participants:
			memories.append("%s: %s" % [VillageLifeFlow.resident(id)["name"], RequestTextData.text("service_text", "goodwill_" + id, "completion")])
		memories.append(RequestTextData.text("service_text", "goodwill_finish", "completion"))
		return "\n".join(memories)
	var reason := locked_reason()
	if not reason.is_empty(): return reason
	if not accepted(): return "이세르에게 말을 걸어 이웃들이 남긴 안부 이야기를 시작하세요. [E]\n물품 전달이나 기한 없이 진행합니다."
	var status: Array[String] = []
	for id in SETTINGS.participants: status.append("%s · %s" % [VillageLifeFlow.resident(id)["name"], "안부를 들었어요" if heard(id) else "안부 이야기 듣기 [E]"])
	status.append("이세르에게 돌아가 이웃의 선물 받기 [E]" if ready() else "순서와 시간대에 관계없이 주민 대화를 끝까지 들어 주세요.")
	return "\n".join(status)
