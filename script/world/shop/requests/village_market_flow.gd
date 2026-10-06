class_name VillageMarketFlow
extends RefCounted

const SETTINGS = preload("res://scenes/shop/requests/default_village_market.tres")
const PREFIX := "village_market:first_market:"
const JOURNAL_ID := "event:first_market"

static func title() -> String: return RequestTextData.text("service_text", "first_market_intro", "title", "작은 노점의 첫 장터")
static func accepted() -> bool: return PlayerProgress.story_beat_days.has(PREFIX + "accepted")
static func prepared() -> bool: return PlayerProgress.story_beat_days.has(PREFIX + "prepared")
static func completed() -> bool: return PlayerProgress.story_beat_days.has(PREFIX + "done")
static func locked_reason() -> String:
	if not ResidentRequestFlow.tutorial_finished(): return "첫 거래와 원정 재료 판매를 먼저 마쳐 주세요."
	if not VillageStoryFlow.completed(): return "이세르의 마을 이야기를 마치면 첫 장터를 준비할 수 있어요."
	for id in SETTINGS.participants:
		if not VillageLifeFlow.available(VillageLifeFlow.resident(id)): return "이웃들의 정착을 기다리고 있어요."
	return ""
static func accept() -> bool:
	if accepted() or completed() or not locked_reason().is_empty(): return false
	PlayerProgress.record_story_beat(PREFIX + "accepted", GameState.total_day)
	return true
static func required_items() -> Dictionary:
	var result: Dictionary = {}
	for entry in SETTINGS.requirements:
		var id := str(entry["item"])
		result[id] = int(result.get(id, 0)) + int(entry["amount"])
	return result
static func can_prepare() -> bool:
	if not accepted() or prepared() or completed() or not locked_reason().is_empty(): return false
	var totals := required_items()
	if totals.is_empty(): return false
	for id in totals:
		if int(totals[id]) <= 0 or not ItemData.has_item(id) or GameState.get_item_count(id) < int(totals[id]): return false
	return true
static func prepare() -> bool:
	if not can_prepare(): return false
	var totals := required_items()
	for id in totals: GameState.remove_item(id, int(totals[id]))
	PlayerProgress.record_story_beat(PREFIX + "prepared", GameState.total_day)
	return true
static func earliest_day() -> int:
	return int(PlayerProgress.story_beat_days.get(PREFIX + "prepared", GameState.total_day)) + maxi(1, SETTINGS.days_after)
static func active(hour: int) -> bool:
	return prepared() and not completed() and locked_reason().is_empty() and GameState.total_day >= earliest_day() and hour >= SETTINGS.start_hour and hour < SETTINGS.end_hour
static func site(world: Node) -> StaticBody2D:
	var node := VillageSettlement.find_site(world, SETTINGS.site_path)
	return node if node != null and node.visible else null
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
static func reward_description() -> String:
	var result: Array[String] = []
	for gift in SETTINGS.gifts: result.append("%s ×%d" % [ItemData.get_item_name(str(gift["item"])), int(gift["amount"])])
	result.append("%d G · 평판 +%d" % [maxi(0, SETTINGS.money), maxi(0, SETTINGS.reputation)])
	return " · ".join(result)
static func finish(hour: int, world: Node) -> bool:
	if not active(hour) or not all_present(world): return false
	for gift in SETTINGS.gifts:
		if not ItemData.has_item(str(gift["item"])) or int(gift["amount"]) <= 0: return false
	PlayerProgress.record_story_beat(PREFIX + "done", GameState.total_day)
	PlayerProgress.story_beat_days[ResidentRequestFlow.PREFIX + "reputation:event/first_market"] = maxi(0, SETTINGS.reputation)
	for gift in SETTINGS.gifts: GameState.add_item(str(gift["item"]), int(gift["amount"]))
	GameState.add_money(maxi(0, SETTINGS.money))
	return true
static func information() -> String:
	if completed(): return "첫 장터를 연 날: %d일차\n%s" % [PlayerProgress.story_beat_days[PREFIX + "done"], RequestTextData.text("service_text", "first_market_end", "completion")]
	var reason := locked_reason()
	if not reason.is_empty(): return reason
	if not accepted(): return "타블렌에게 첫 장터 이야기를 들어 보세요. [E]"
	if not prepared():
		var text := "타블렌에게 준비 물품 전달하기 [E] · 창고 기준\n"
		var totals := required_items()
		for id in totals: text += "%s %d/%d  " % [ItemData.get_item_name(id), mini(GameState.get_item_count(id), int(totals[id])), int(totals[id])]
		if RequestPaymentText.is_gift({"payment_kind":SETTINGS.payment_kind}):
			text += "\n" + RequestPaymentText.notice({"payment_kind":SETTINGS.payment_kind}) + "\n장터를 마친 답례: " + reward_description()
		return text + "\n기한 없이 준비할 수 있습니다."
	return "%d일차부터 매일 %02d~%02d시 · 노점에서 [E]\n이웃들이 도착하면 참여합니다. 시간을 놓쳐도 다시 열립니다.\n답례: %s" % [earliest_day(), SETTINGS.start_hour, SETTINGS.end_hour, reward_description()]
