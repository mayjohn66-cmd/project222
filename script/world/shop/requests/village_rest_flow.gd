class_name VillageRestFlow
extends RefCounted

const SETTINGS = preload("res://scenes/shop/requests/default_village_rest.tres")
const PREFIX := "village_rest:trail_corner:"
const JOURNAL_ID := "event:trail_rest_corner"

static func title() -> String: return RequestTextData.text("community_request", SETTINGS.preparation, "title", "길목에 놓는 작은 쉼터")
static func completed() -> bool: return PlayerProgress.story_beat_days.has(PREFIX + "done")
static func locked_reason() -> String:
	if not ResidentRequestFlow.tutorial_finished(): return "첫 거래와 원정 재료 판매를 먼저 마쳐 주세요."
	if not VillageMarketFlow.completed(): return "첫 장터를 마친 뒤 이웃들과 이야기를 이어 가세요."
	var last_day := int(PlayerProgress.story_beat_days[VillageMarketFlow.PREFIX + "done"])
	for id in SETTINGS.afterglow_requests:
		if not MarketAfterglowFlow.heard(id): return "%s 전달 뒤 주민의 후일담을 먼저 들어 주세요. [E]" % RequestTextData.text("personal_request", id, "title", id)
		last_day = maxi(last_day, int(PlayerProgress.story_beat_days[MarketAfterglowFlow.PREFIX + id + ":heard"]))
	if GameState.total_day < last_day + maxi(1, SETTINGS.days_after): return "이웃들의 후일담을 들은 다음 날부터 쉼터를 준비할 수 있어요."
	return ""
static func prepared() -> bool: return CommunityRequestFlow.done(SETTINGS.preparation)
static func earliest_day() -> int:
	return int(PlayerProgress.story_beat_days.get(CommunityRequestFlow.PREFIX + SETTINGS.preparation + ":done", GameState.total_day)) + maxi(1, SETTINGS.opening_days_after)
static func active(hour: int) -> bool:
	return not completed() and prepared() and locked_reason().is_empty() and GameState.total_day >= earliest_day() and hour >= SETTINGS.start_hour and hour < SETTINGS.end_hour
static func site(world: Node) -> StaticBody2D:
	var target := VillageSettlement.find_site(world, SETTINGS.site_path)
	return target if target != null and target.visible else null
static func all_present(world: Node) -> bool:
	var target := site(world)
	var life = world.get_node_or_null("VillageLifeDirector")
	if target == null or life == null: return false
	for id in SETTINGS.participants:
		var npc = life.residents.get(id)
		if not is_instance_valid(npc) or not npc.visible or npc.is_queued_for_deletion() or npc.global_position.distance_to(target.global_position) > SETTINGS.arrival_distance: return false
	return true
static func lines() -> Array[String]:
	var result: Array[String] = []
	for moment in SETTINGS.moments:
		if not moment.has("speaker"): continue
		for line in RequestTextData.lines("service_text", str(moment["id"])):
			result.append(str(VillageLifeFlow.resident(str(moment["speaker"]))["name"]) + ": " + line)
	return result
static func finish(hour: int, world: Node) -> bool:
	if not active(hour) or not all_present(world): return false
	PlayerProgress.record_story_beat(PREFIX + "done", GameState.total_day)
	PlayerProgress.story_beat_days[ResidentRequestFlow.PREFIX + "reputation:event/trail_rest_corner"] = maxi(0, SETTINGS.opening_reputation)
	return true
static func rest(world: Node) -> bool:
	if not completed() or site(world) == null: return false
	if int(PlayerProgress.story_beat_days.get(PREFIX + "rested", -1)) == GameState.total_day: return false
	PlayerProgress.record_story_beat(PREFIX + "rested", GameState.total_day)
	return true
static func information() -> String:
	if completed():
		var result := "처음 함께 쉰 날: %d일차\n%s\n벤치에서 다시 쉬어 가기 [E] · 반복 답례 없음" % [PlayerProgress.story_beat_days[PREFIX + "done"], RequestTextData.text("service_text", "trail_rest_end", "completion")]
		if PlayerProgress.story_beat_days.has(PREFIX + "rested"): result += "\n최근 들른 날: %d일차" % PlayerProgress.story_beat_days[PREFIX + "rested"]
		return result
	var reason := locked_reason()
	if not reason.is_empty(): return reason
	if not prepared(): return "마을 게시판에서 쉼터 부탁을 맡고 재료를 준비해 주세요. [E]"
	return "%d일차부터 매일 %02d~%02d시 · 길목 벤치에서 [E]\n이웃들이 도착하면 처음 함께 쉬어요. 놓쳐도 다음 오후에 참여할 수 있습니다." % [earliest_day(), SETTINGS.start_hour, SETTINGS.end_hour]
