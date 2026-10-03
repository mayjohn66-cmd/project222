class_name ResidentStoryFlow
extends RefCounted

const SETTINGS = preload("res://scenes/shop/requests/default_resident_story.tres")
const PREFIX := "resident_story:"

static func introduction_read(type_id: String) -> bool:
	return PlayerProgress.story_beat_days.has(PREFIX + "met:" + type_id)

static func pending_introduction() -> Dictionary:
	if not ResidentRequestFlow.tutorial_finished(): return {}
	for introduction in SETTINGS.introductions:
		var type_id := str(introduction["type"])
		if PlayerProgress.story_beat_days.has(ResidentRequestFlow.PREFIX + "visited:" + type_id) \
				and not introduction_read(type_id):
			return RequestTextData.enrich(introduction, "resident_introduction")
	return {}

static func meet(type_id: String) -> bool:
	if pending_introduction().get("type", "") != type_id: return false
	PlayerProgress.record_story_beat(PREFIX + "met:" + type_id, GameState.total_day)
	return true

static func current_request() -> Dictionary:
	if not ResidentRequestFlow.tutorial_finished(): return {}
	for request in SETTINGS.settlement_requests:
		if ResidentRequestFlow.done(str(request["id"])): continue
		if not introduction_read(str(request["requires_intro"])): continue
		if request.has("after") and not ResidentRequestFlow.done(str(request["after"])): continue
		return RequestTextData.enrich(request, "resident_request")
	return {}

static func stage() -> int:
	var count := 0
	for landmark in SETTINGS.landmarks:
		if ResidentRequestFlow.done(str(landmark["request"])): count += 1
	return count

static func place_name() -> String:
	return ["황무지의 작은 가게", "쉬어 가는 길목", "첫 이웃이 사는 곳", "함께 만든 작은 마을"][mini(stage(),3)]

static func landmark_for_request(id: String) -> String:
	for landmark in SETTINGS.landmarks:
		if str(landmark["request"]) == id: return RequestTextData.text("service_text", "landmark_" + id, "title", id)
	return ""
