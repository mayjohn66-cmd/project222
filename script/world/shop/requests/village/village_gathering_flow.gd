class_name VillageGatheringFlow
extends RefCounted
const SETTINGS = preload("res://scenes/shop/requests/default_village_gathering.tres")
const COMPLETED := "village_gathering:well_evening:done"
static func pending() -> bool:
	return ResidentRequestFlow.tutorial_finished() and CommunityRequestFlow.done(SETTINGS.preparation) and not completed()
static func completed() -> bool: return PlayerProgress.story_beat_days.has(COMPLETED)
static func active(hour: int) -> bool: return pending() and hour >= SETTINGS.start_hour and hour < SETTINGS.end_hour
static func title() -> String: return RequestTextData.text("service_text","well_evening_intro","title","우물 곁 저녁 모임")
static func site(world: Node) -> Node2D:
	var result := VillageSettlement.find_site(world,SETTINGS.site_path)
	return result if result != null and result.visible else null
static func all_present(world: Node) -> bool:
	var target := site(world)
	var life = world.get_node_or_null("VillageLifeDirector")
	if target == null or life == null: return false
	for id in SETTINGS.participants:
		var npc = life.residents.get(id)
		if not is_instance_valid(npc) or not npc.visible or npc.global_position.distance_to(target.global_position) > SETTINGS.arrival_distance: return false
	return true
static func lines() -> Array[String]:
	var result: Array[String] = []
	for moment in SETTINGS.moments:
		var speaker := str(moment["speaker"])
		var prefix := "" if speaker.is_empty() else str(VillageLifeFlow.resident(speaker)["name"]) + ": "
		for line in RequestTextData.lines("service_text",str(moment["id"])): result.append(prefix + line)
	return result
static func finish() -> bool:
	if not pending(): return false
	PlayerProgress.record_story_beat(COMPLETED,GameState.total_day)
	return true
static func information(hour: int = -1) -> String:
	if completed(): return "함께 쉬어 간 날: %d일차\n%s" % [PlayerProgress.story_beat_days[COMPLETED],RequestTextData.text("service_text","well_evening_end","summary")]
	if pending(): return "저녁 %02d~%02d시 · 우물 옆 벤치에서 [E]\n%s" % [SETTINGS.start_hour,SETTINGS.end_hour,"이웃들이 모이면 참여할 수 있어요." if hour < 0 or active(hour) else "다음 저녁에도 참여할 수 있어요. 기한은 없습니다."]
	return "게시판에서 저녁 모임 준비를 마치면 참여할 수 있어요."
