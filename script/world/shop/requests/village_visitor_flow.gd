class_name VillageVisitorFlow
extends RefCounted
const SETTINGS = preload("res://scenes/shop/requests/default_village_visitors.tres")

static func rule(type_id: String) -> Dictionary:
	for entry in SETTINGS.visitors:
		if str(entry["type"]) == type_id: return entry
	return {}

static func available(type_id: String) -> bool:
	var entry := rule(type_id)
	if entry.is_empty(): return true
	if not ResidentRequestFlow.tutorial_finished(): return false
	# Read saved completion keys without loading each quest flow through the customer picker.
	var prefix := "community_request:" if str(entry["kind"]) == "community" else "personal_request:"
	return PlayerProgress.story_beat_days.has(prefix + str(entry["request"]) + ":done")

static func pending_visit() -> String:
	for entry in SETTINGS.visitors:
		var type_id := str(entry["type"])
		if available(type_id) and not PlayerProgress.story_beat_days.has(ResidentRequestFlow.PREFIX + "visited:" + type_id): return type_id
	return ""

static func available_types() -> Array[String]:
	var result: Array[String] = []
	for entry in SETTINGS.visitors:
		if available(str(entry["type"])): result.append(str(entry["type"]))
	return result

static func name_for(type_id: String) -> String:
	return CustomerTypeData.get_display_name(type_id)

static func information(type_id: String) -> String:
	var entry := rule(type_id)
	if entry.is_empty(): return ""
	if not available(type_id): return "방문 조건: " + str(entry["condition"])
	var key := ResidentRequestFlow.PREFIX + "visited:" + type_id
	if PlayerProgress.story_beat_days.has(key): return "첫 방문: %d일차\n가게를 열어 두면 다시 만날 수 있어요." % PlayerProgress.story_beat_days[key]
	return "방문 준비 완료 · 가게를 열어 두면 새 손님이 찾아와요."
