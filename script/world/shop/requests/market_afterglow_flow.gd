class_name MarketAfterglowFlow
extends RefCounted

const SETTINGS = preload("res://scenes/shop/requests/default_market_afterglow.tres")
const FOLLOWUPS = preload("res://scenes/shop/requests/default_trail_errands.tres")
const PREFIX := "market_afterglow:"

static func moments() -> Array[Dictionary]:
	var entries: Array[Dictionary] = SETTINGS.moments.duplicate(true)
	entries.append_array(FOLLOWUPS.moments)
	return entries

static func moment(request_id: String) -> Dictionary:
	for entry in moments():
		if str(entry["request"]) == request_id: return entry
	return {}
static func heard(request_id: String) -> bool:
	return PlayerProgress.story_beat_days.has(PREFIX + request_id + ":heard")
static func pending(resident_id: String) -> String:
	if not ResidentRequestFlow.tutorial_finished() or not VillageMarketFlow.completed(): return ""
	for entry in moments():
		var id := str(entry["request"])
		if str(entry["resident"]) == resident_id and PersonalRequestFlow.done(id) and not heard(id): return id
	return ""
static func listen(request_id: String) -> bool:
	var entry := moment(request_id)
	if entry.is_empty() or pending(str(entry["resident"])) != request_id: return false
	PlayerProgress.record_story_beat(PREFIX + request_id + ":heard", GameState.total_day)
	return true
static func lines(request_id: String) -> Array[String]:
	var entry := moment(request_id)
	return [] if entry.is_empty() else RequestTextData.lines("service_text", str(entry["id"]))
static func information(request_id: String) -> String:
	var entry := moment(request_id)
	if entry.is_empty() or not PersonalRequestFlow.done(request_id): return ""
	if not heard(request_id): return "전달 뒤 %s에게 후일담 듣기 [E] · 추가 물품은 필요 없습니다." % VillageLifeFlow.resident(str(entry["resident"]))["name"]
	return "후일담을 들은 날: %d일차\n%s" % [PlayerProgress.story_beat_days[PREFIX + request_id + ":heard"], RequestTextData.text("service_text", str(entry["id"]), "completion")]
