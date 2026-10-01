class_name ResidentRequestFlow
extends RefCounted

const SETTINGS = preload("res://scenes/shop/requests/default_resident_requests.tres")
const PREFIX := "resident_request:"

static func tutorial_finished() -> bool:
	for step in TutorialDirector.SETTINGS.steps:
		if not PlayerProgress.story_beat_days.has("tutorial_step:" + str(step["id"]) + ":done"):
			return false
	return true

static func current() -> Dictionary:
	if not tutorial_finished(): return {}
	var base_request: Dictionary = {}
	for request in SETTINGS.requests:
		if not done(str(request["id"])):
			base_request = request
			break
	# 이미 받은 부탁은 새 손님 등장 때문에 숨기지 않는다.
	if not base_request.is_empty() and accepted(str(base_request["id"])): return base_request
	var settlement := ResidentStoryFlow.current_request()
	return settlement if not settlement.is_empty() else base_request

static func total_completed_count() -> int:
	var count := completed_count()
	for request in ResidentStoryFlow.SETTINGS.settlement_requests:
		if done(str(request["id"])): count += 1
	return count

static func total_request_count() -> int:
	return SETTINGS.requests.size() + ResidentStoryFlow.SETTINGS.settlement_requests.size()

static func done(id: String) -> bool:
	return PlayerProgress.story_beat_days.has(PREFIX + id + ":done")

static func accepted(id: String) -> bool:
	return PlayerProgress.story_beat_days.has(PREFIX + id + ":accepted")

static func accept(request: Dictionary) -> bool:
	if request.is_empty() or current().get("id") != request.get("id") or accepted(str(request["id"])):
		return false
	PlayerProgress.record_story_beat(PREFIX + str(request["id"]) + ":accepted", GameState.total_day)
	return true

static func completed_count() -> int:
	var count := 0
	for request in SETTINGS.requests:
		if done(str(request["id"])): count += 1
	return count

static func reputation() -> int:
	var value := 0
	for key in PlayerProgress.story_beat_days:
		if str(key).begins_with(PREFIX + "reputation:"):
			value += maxi(0, int(PlayerProgress.story_beat_days[key]))
	return value

static func customer_available(type_id: String) -> bool:
	for milestone in SETTINGS.customer_milestones:
		if str(milestone["type"]) == type_id:
			return completed_count() >= int(milestone["completed"])
	return true

static func pending_introduction() -> String:
	for milestone in SETTINGS.customer_milestones:
		var type_id := str(milestone["type"])
		if customer_available(type_id) and not PlayerProgress.story_beat_days.has(PREFIX + "visited:" + type_id):
			return type_id
	return ""

static func record_visit(type_id: String) -> void:
	if type_id == pending_introduction():
		PlayerProgress.record_story_beat(PREFIX + "visited:" + type_id, GameState.total_day)

static func can_deliver(request: Dictionary) -> bool:
	return not request.is_empty() and accepted(str(request["id"])) and not done(str(request["id"])) \
		and GameState.get_item_count(str(request["item"])) >= int(request["amount"])

static func deliver(request: Dictionary) -> Dictionary:
	# 중복 보상이나 이전 부탁의 데이터로 다른 부탁을 완료하는 것을 막는다.
	if request.is_empty() or current().get("id") != request.get("id") or not can_deliver(request): return {}
	var item_id := str(request["item"])
	var amount := int(request["amount"])
	if amount <= 0 or not ItemData.has_item(item_id): return {}
	var before := completed_count()
	if GameState.remove_item(item_id, amount) != amount: return {}
	var id := str(request["id"])
	PlayerProgress.record_story_beat(PREFIX + id + ":done", GameState.total_day)
	# 진행 기록의 정수 저장 기능으로 평판을 보존한다. 날짜 키와 별도 이름을 사용한다.
	PlayerProgress.story_beat_days[PREFIX + "reputation:" + id] = maxi(0, int(request["reputation"]))
	GameState.add_money(maxi(0, int(request["money"])))
	var unlocked: Array[String] = []
	for milestone in SETTINGS.customer_milestones:
		if before < int(milestone["completed"]) and completed_count() >= int(milestone["completed"]):
			unlocked.append(str(milestone["type"]))
	return {"money":int(request["money"]), "reputation":int(request["reputation"]), "unlocked":unlocked}
