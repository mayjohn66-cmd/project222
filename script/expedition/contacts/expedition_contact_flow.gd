class_name ExpeditionContactFlow
extends RefCounted

const SETTINGS = preload("res://scenes/expedition/contacts/default_expedition_contacts.tres")
const PREFIX := "expedition_contact:"
const JOURNAL_PREFIX := "contact:"

static func event(id: String) -> Dictionary:
	for entry in SETTINGS.events:
		if str(entry["id"]) == id: return entry
	return {}

static func key(id: String, stage: String) -> String: return PREFIX + id + ":" + stage
static func has(id: String, stage: String) -> bool: return PlayerProgress.story_beat_days.has(key(id,stage))
static func day(id: String, stage: String) -> int: return int(PlayerProgress.story_beat_days.get(key(id,stage),-1))
static func title(id: String) -> String: return RequestTextData.text("service_text",id + "_meet","title",id)

static func encounter(region: String, result: String, room_type: String) -> Dictionary:
	if not CommunityRequestFlow.board_available() or room_type != ExpeditionMap.NODE_UNKNOWN or not SETTINGS.safe_results.has(result): return {}
	for entry in SETTINGS.events:
		if str(entry["region"]) == region and not has(str(entry["id"]),"met"): return entry
	return {}

static func meet(id: String) -> bool:
	if event(id).is_empty() or has(id,"met") or not CommunityRequestFlow.board_available(): return false
	PlayerProgress.record_story_beat(key(id,"met"),GameState.total_day)
	return true

static func ready(id: String) -> bool:
	var entry := event(id)
	if entry.is_empty() or not has(id,"met") or has(id,"done"): return false
	var totals := CommunityRequestFlow.required_items(entry)
	if totals.is_empty(): return false
	for item in totals:
		if not ItemData.has_item(item) or int(totals[item]) <= 0 or GameState.get_item_count(item) < int(totals[item]): return false
	return true

static func phase(id: String) -> String:
	var entry := event(id)
	if entry.is_empty() or not CommunityRequestFlow.board_available(): return "locked"
	if has(id,"after"): return "complete"
	if has(id,"bought"):
		return "after" if GameState.total_day >= day(id,"bought") + int(entry["days_after"]) else "rest"
	if has(id,"done"):
		return "visit" if GameState.total_day >= day(id,"done") + int(entry["days_after"]) else "rest"
	if not has(id,"met"): return "unseen"
	if GameState.total_day < day(id,"met") + int(entry["days_after"]): return "rest"
	return "finish" if ready(id) else "wait"

static func complete_action(id: String, stage: String) -> bool:
	if phase(id) != stage: return false
	if stage == "after":
		PlayerProgress.record_story_beat(key(id,"after"),GameState.total_day)
		return true
	if stage != "finish" or not ready(id): return false
	var entry := event(id)
	for gift in entry["gifts"]:
		if not ItemData.has_item(str(gift["item"])) or int(gift["amount"]) <= 0: return false
	var totals := CommunityRequestFlow.required_items(entry)
	for item in totals: GameState.remove_item(item,int(totals[item]))
	PlayerProgress.record_story_beat(key(id,"done"),GameState.total_day)
	PlayerProgress.story_beat_days[ResidentRequestFlow.PREFIX + "reputation:contact/" + id] = maxi(0,int(entry["reputation"]))
	for gift in entry["gifts"]: GameState.add_item(str(gift["item"]),int(gift["amount"]))
	return true

static func record_sale(customer: Node, item: String, amount: int) -> bool:
	var id := str(customer.get_meta("expedition_contact_id",""))
	var entry := event(id)
	if entry.is_empty() or not customer.purchase_completed or phase(id) != "visit": return false
	if customer.get_customer_type_id() != str(entry["type"]) or item != str(entry["purchase_item"]) or amount < int(entry["purchase_amount"]): return false
	PlayerProgress.record_story_beat(key(id,"bought"),GameState.total_day)
	return true

static func requirements(id: String) -> String:
	var parts: Array[String] = []
	var totals := CommunityRequestFlow.required_items(event(id))
	for item in totals: parts.append("%s %d/%d · 창고" % [ItemData.get_item_name(item),GameState.get_item_count(item),totals[item]])
	return "\n".join(parts)

static func reward(id: String) -> String:
	var entry := event(id)
	var parts: Array[String] = []
	for gift in entry.get("gifts",[]): parts.append("%s ×%d" % [ItemData.get_item_name(str(gift["item"])),gift["amount"]])
	return " · ".join(parts) + " · 평판 +%d (최초 1회)" % int(entry.get("reputation",0))

static func information(id: String) -> String:
	var entry := event(id)
	if entry.is_empty(): return ""
	var state := phase(id)
	var name := CustomerTypeData.get_display_name(str(entry["type"]))
	if state == "locked": return "첫 거래와 원재료 판매를 마치고 첫 주민을 정착시키면 이야기를 만날 수 있어요."
	if state == "unseen": return "%s 원정의 물음표 방에서 %s를 만날 수 있어요.\n전투가 없는 빈 방이나 휴식 방에서 가까이 가서 [E]. 지나쳐도 다음 원정에서 다시 만날 수 있어요." % [ExpeditionMapData.get_region_data(str(entry["region"])).get("name",entry["region"]),name]
	if state == "rest": return "만남을 기억하고 있어요. 다음 날 이후 이야기가 이어집니다."
	if state in ["wait","finish"]: return "%s가 마을 게시판 근처에서 기다립니다.\n같은 사람에게 직접 [E]\n%s\n답례: %s" % [name,requirements(id),reward(id)]
	if state == "visit": return "%s가 가게에 들를 준비를 합니다.\n%s ×%d를 진열하고 가게를 열어 주세요. 실제 결제가 필요합니다." % [name,ItemData.get_item_name(str(entry["purchase_item"])),entry["purchase_amount"]]
	if state == "after": return "원정에서 만난 사람이 가게에서 물품을 샀어요. 다음 이야기를 게시판 근처에서 [E]로 들어 주세요. 추가 답례는 없습니다."
	return RequestTextData.text("service_text",id + "_after","completion") + "\n가게를 찾은 날: %d일차" % day(id,"bought")
