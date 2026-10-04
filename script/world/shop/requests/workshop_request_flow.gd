class_name WorkshopRequestFlow
extends RefCounted

const SETTINGS = preload("res://scenes/shop/requests/default_workshop_requests.tres")

static func locked_reason(entry: Dictionary) -> String:
	var after := str(entry.get("after_craft", ""))
	if after.is_empty(): return ""
	if CraftingPathFlow.stage(after).is_empty(): return "앞선 제품 이야기의 설정을 찾을 수 없습니다."
	if not CraftingPathFlow.done(after):
		return "이웃과 제품 만들기 '%s'의 시제품을 나눈 뒤 부탁이 이어져요." % CraftingPathFlow.title(after)
	var day := int(PlayerProgress.story_beat_days[CraftingPathFlow.key(after,"done")])
	var wait_days := maxi(0,int(entry.get("days_after",1)))
	if GameState.total_day < day + wait_days:
		return "시제품을 나눈 뒤 %d일 후부터 부탁을 들을 수 있어요." % wait_days
	return ""
