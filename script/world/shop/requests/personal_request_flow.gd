class_name PersonalRequestFlow
extends RefCounted

const SETTINGS = preload("res://scenes/shop/requests/default_personal_requests.tres")
const PREFIX := "personal_request:"

static func entries() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var all_requests: Array[Dictionary] = SETTINGS.requests.duplicate(true)
	all_requests.append_array(MarketAfterglowFlow.SETTINGS.requests)
	all_requests.append_array(MarketAfterglowFlow.FOLLOWUPS.requests)
	all_requests.append_array(StoreEventFollowupFlow.SETTINGS.requests)
	all_requests.append_array(SeasonStockpileFlow.SETTINGS.requests)
	all_requests.append_array(WorkshopRequestFlow.SETTINGS.requests)
	for data in all_requests:
		var entry: Dictionary = data.duplicate(true)
		for field in ["title","summary","completion"]:
			entry[field] = RequestTextData.text("personal_request",str(entry["id"]),field,str(entry.get(field,"")))
		result.append(entry)
	return result

static func request(id: String) -> Dictionary:
	for entry in entries():
		if entry["id"] == id: return entry
	return {}

static func done(id: String) -> bool: return PlayerProgress.story_beat_days.has(PREFIX + id + ":done")
static func accepted(id: String) -> bool: return PlayerProgress.story_beat_days.has(PREFIX + id + ":accepted")

static func locked_reason(entry: Dictionary) -> String:
	var resident := VillageLifeFlow.resident(str(entry["resident"]))
	if not CommunityRequestFlow.board_available() or not VillageLifeFlow.available(resident): return "주민의 정착을 기다리고 있어요."
	var friendship := VillageLifeFlow.friendship(str(entry["resident"]))
	if friendship < int(entry["friendship"]): return "%s · 안부 나누기 %d/%d일" % [resident["name"],friendship,entry["friendship"]]
	var after := str(entry.get("after", ""))
	var last_day := -1
	if not after.is_empty():
		if not done(after): return "앞선 개인 부탁 '%s'을 마치면 이야기가 이어져요." % RequestTextData.text("personal_request",after,"title",after)
		last_day = int(PlayerProgress.story_beat_days[PREFIX + after + ":done"])
	if bool(entry.get("after_gathering", false)):
		if not VillageGatheringFlow.completed(): return "우물 곁 첫 저녁 모임을 마치면 이야기가 이어져요."
		last_day = maxi(last_day,int(PlayerProgress.story_beat_days[VillageGatheringFlow.COMPLETED]))
	if bool(entry.get("after_market", false)):
		if not VillageMarketFlow.completed(): return "작은 노점의 첫 장터를 함께 마치면 부탁이 이어져요."
		last_day = maxi(last_day, int(PlayerProgress.story_beat_days[VillageMarketFlow.PREFIX + "done"]))
	if bool(entry.get("after_rest", false)):
		if not VillageRestFlow.completed(): return "길목 쉼터의 첫 모임을 끝까지 함께하면 부탁이 이어져요."
		last_day = maxi(last_day, int(PlayerProgress.story_beat_days[VillageRestFlow.PREFIX + "done"]))
	if bool(entry.get("after_heard", false)):
		if not MarketAfterglowFlow.heard(after): return "앞선 부탁을 전한 뒤 주민에게 후일담을 끝까지 들어 주세요."
		last_day = maxi(last_day, int(PlayerProgress.story_beat_days[MarketAfterglowFlow.PREFIX + after + ":heard"]))
	var wait_days := maxi(0,int(entry.get("days_after",0)))
	if last_day >= 0 and GameState.total_day < last_day + wait_days:
		return "앞선 이야기를 마친 뒤 %d일 후부터 부탁을 들을 수 있어요." % wait_days
	var workshop_reason := WorkshopRequestFlow.locked_reason(entry)
	if not workshop_reason.is_empty(): return workshop_reason
	var recipe_id := str(entry.get("recipe", ""))
	if not recipe_id.is_empty() and not RecipeUnlockData.is_recipe_available(recipe_id):
		return "%s 레시피를 배우면 준비할 수 있어요. 원정에서 두루마리를 찾아 사용해 주세요." % ItemData.get_item_name(recipe_id)
	# 맡은 부탁은 이후 계절·행사 설정이나 영업 기록의 변경으로 취소하지 않는다.
	if not accepted(str(entry["id"])) and not done(str(entry["id"])):
		var stockpile_reason := SeasonStockpileFlow.locked_reason(entry, false)
		if not stockpile_reason.is_empty(): return stockpile_reason
		var event_reason := StoreEventFollowupFlow.locked_reason(entry)
		if not event_reason.is_empty(): return event_reason
	return ""

static func accept(id: String) -> bool:
	var entry := request(id)
	if entry.is_empty() or accepted(id) or done(id) or not locked_reason(entry).is_empty(): return false
	PlayerProgress.record_story_beat(PREFIX + id + ":accepted",GameState.total_day)
	return true

static func can_deliver(id: String) -> bool:
	var entry := request(id)
	if entry.is_empty() or not accepted(id) or done(id) or not locked_reason(entry).is_empty(): return false
	var totals := CommunityRequestFlow.required_items(entry)
	if totals.is_empty(): return false
	for item in totals:
		if int(totals[item]) <= 0 or not ItemData.has_item(item) or GameState.get_item_count(item) < int(totals[item]): return false
	return true

static func deliver(id: String) -> Dictionary:
	if not can_deliver(id): return {}
	var entry := request(id)
	var totals := CommunityRequestFlow.required_items(entry)
	for item in totals: GameState.remove_item(item,int(totals[item]))
	PlayerProgress.record_story_beat(PREFIX + id + ":done",GameState.total_day)
	PlayerProgress.story_beat_days[ResidentRequestFlow.PREFIX + "reputation:personal/" + id] = maxi(0,int(entry["reputation"]))
	GameState.add_money(maxi(0,int(entry["money"])))
	return entry

static func information(entry: Dictionary) -> String:
	var id := str(entry["id"])
	if done(id):
		var result := "%s\n함께 완료한 날: %d일차" % [entry["completion"],int(PlayerProgress.story_beat_days[PREFIX + id + ":done"])]
		var afterglow := MarketAfterglowFlow.information(id)
		return result + ("\n" + afterglow if not afterglow.is_empty() else "")
	var text := str(entry["summary"]) + "\n"
	var totals := CommunityRequestFlow.required_items(entry)
	for item in totals:
		text += "%s %d/%d · 창고\n" % [ItemData.get_item_name(item),GameState.get_item_count(item),totals[item]]
	if str(entry.get("payment_kind", "")) == "gift":
		text += "나눔 부탁 · 물품 대금은 별도로 받지 않습니다.\n답례: 평판 +%d · %d G" % [entry["reputation"],entry["money"]]
	else:
		text += "보상: 평판 +%d · %d G" % [entry["reputation"],entry["money"]]
	var reason := locked_reason(entry)
	if not reason.is_empty(): text += "\n" + reason
	return text
