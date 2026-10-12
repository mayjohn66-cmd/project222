class_name SeasonalLifeRequestFlow
extends RefCounted

const SETTINGS = preload("res://scenes/shop/requests/default_seasonal_life_requests.tres")

static func season_available(entry: Dictionary, started: bool) -> bool:
	return CalendarData.get_season_id(GameState.total_day) == str(entry["season"]) or (started and bool(entry.get("continue_outside_season", false)))

static func locked_reason(entry: Dictionary) -> String:
	var request_id := str(entry.get("after_request", ""))
	if request_id.is_empty(): return ""
	if not PersonalRequestFlow.done(request_id):
		return "먼저 '%s' 개인 부탁을 마쳐 주세요." % RequestTextData.text("personal_request", request_id, "title", request_id)
	var last_day := int(PlayerProgress.story_beat_days[PersonalRequestFlow.PREFIX + request_id + ":done"])
	if bool(entry.get("after_request_heard", true)):
		if not MarketAfterglowFlow.heard(request_id): return "앞선 부탁을 전한 뒤 주민의 후일담을 끝까지 들어 주세요. [E]"
		last_day = maxi(last_day, int(PlayerProgress.story_beat_days[MarketAfterglowFlow.PREFIX + request_id + ":heard"]))
	if GameState.total_day < last_day + maxi(0, int(entry.get("days_after_request", 1))):
		return "앞선 후일담을 들은 뒤 조금 더 시간이 지나면 새 계절 이야기가 이어져요."
	var giver := str(entry["giver"])
	if VillageLifeFlow.friendship(giver) < int(entry.get("friendship", 3)):
		return "%s와 안부를 조금 더 나눠 주세요. 함께 인사한 날 %d/%d일" % [VillageLifeFlow.resident(giver).get("name", "주민"), VillageLifeFlow.friendship(giver), int(entry.get("friendship", 3))]
	return ""
