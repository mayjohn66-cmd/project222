class_name CommunityRequestFlow
extends RefCounted

const SETTINGS = preload("res://scenes/shop/requests/default_community_requests.tres")
const PREFIX := "community_request:"

static func board_available() -> bool:
	return ResidentRequestFlow.tutorial_finished() and ResidentRequestFlow.done("settle_naru")

static func request(id: String) -> Dictionary:
	for entry in SETTINGS.requests:
		if str(entry["id"]) == id: return RequestTextData.enrich(entry, "community_request")
	return {}

static func done(id: String) -> bool:
	return PlayerProgress.story_beat_days.has(PREFIX + id + ":done")

static func accepted(id: String) -> bool:
	return PlayerProgress.story_beat_days.has(PREFIX + id + ":accepted")

static func locked_reason(entry: Dictionary) -> String:
	if not board_available(): return "첫 주민의 정착을 기다리고 있어요."
	if entry.has("after") and not done(str(entry["after"])): return "앞선 공동 부탁을 완료하면 열려요."
	var resident := VillageLifeFlow.resident(str(entry["resident"]))
	if not VillageLifeFlow.available(resident): return "%s의 정착을 기다리고 있어요." % str(resident.get("name", "주민"))
	var required := int(entry["friendship"])
	if VillageLifeFlow.friendship(str(entry["resident"])) < required:
		return "%s · 안부 나누기 %d/%d일" % [resident["name"], VillageLifeFlow.friendship(str(entry["resident"])), required]
	for id in entry.get("participants",[]):
		var participant := VillageLifeFlow.resident(str(id))
		if not VillageLifeFlow.available(participant): return "%s의 정착을 기다리고 있어요." % participant.get("name","주민")
		var minimum := int(entry.get("participant_friendship",0))
		if VillageLifeFlow.friendship(str(id)) < minimum: return "%s · 안부 나누기 %d/%d일" % [participant["name"],VillageLifeFlow.friendship(str(id)),minimum]
	return ""

static func accept(id: String) -> bool:
	var entry := request(id)
	if entry.is_empty() or done(id) or accepted(id) or not locked_reason(entry).is_empty(): return false
	PlayerProgress.record_story_beat(PREFIX + id + ":accepted", GameState.total_day)
	return true

static func required_items(entry: Dictionary) -> Dictionary:
	var totals: Dictionary = {}
	for requirement in entry.get("requirements", []):
		var item := str(requirement["item"])
		totals[item] = int(totals.get(item, 0)) + int(requirement["amount"])
	return totals

static func can_deliver(id: String) -> bool:
	var entry := request(id)
	if entry.is_empty() or not board_available() or not accepted(id) or done(id): return false
	var totals := required_items(entry)
	if totals.is_empty(): return false
	for item in totals:
		if int(totals[item]) <= 0 or not ItemData.has_item(item) or GameState.get_item_count(item) < int(totals[item]): return false
	return true

static func deliver(id: String) -> Dictionary:
	if not can_deliver(id): return {}
	var entry := request(id)
	var totals := required_items(entry)
	for item in totals: GameState.remove_item(item, int(totals[item]))
	PlayerProgress.record_story_beat(PREFIX + id + ":done", GameState.total_day)
	var reputation := maxi(0, int(entry["reputation"]))
	var money := maxi(0, int(entry["money"]))
	PlayerProgress.story_beat_days[ResidentRequestFlow.PREFIX + "reputation:community/" + id] = reputation
	GameState.add_money(money)
	return {"reputation":reputation, "money":money, "completion":str(entry["completion"])}

static func completed_count() -> int:
	var count := 0
	for entry in SETTINGS.requests:
		if done(str(entry["id"])): count += 1
	return count

static func unlocked_paths() -> Array[String]:
	var paths: Array[String] = []
	if board_available(): paths.append(SETTINGS.board_path)
	for entry in SETTINGS.requests:
		if done(str(entry["id"])): paths.append(str(entry["landmark"]))
	return paths
