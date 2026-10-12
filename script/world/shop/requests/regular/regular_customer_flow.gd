class_name RegularCustomerFlow
extends RefCounted
const RECORDS = preload("res://script/world/shop/requests/regular/regular_customer_records.gd")
const SETTINGS = RECORDS.SETTINGS
const JOURNAL_PREFIX := "regular:"
static func title(id: String) -> String: return RequestTextData.text("service_text",id + "_intro","title",id)
static func ready(id: String) -> bool:
	var entry := RECORDS.event(id)
	if entry.is_empty() or not RECORDS.has(id,"accepted") or RECORDS.has(id,"done"): return false
	var totals := CommunityRequestFlow.required_items(entry)
	if totals.is_empty(): return false
	for item in totals:
		if not ItemData.has_item(item) or int(totals[item]) <= 0 or GameState.get_item_count(item) < int(totals[item]): return false
	return true
static func phase(id: String) -> String:
	var entry := RECORDS.event(id)
	if entry.is_empty() or not ResidentRequestFlow.tutorial_finished() or not VillageVisitorFlow.available(str(entry["type"])): return "locked"
	if RECORDS.has(id,"after"): return "complete"
	if RECORDS.has(id,"done"):
		return "after" if GameState.total_day >= RECORDS.day(id,"done") + int(entry["days_after"]) else "rest"
	if not RECORDS.has(id,"first"): return "first_purchase"
	if GameState.total_day < RECORDS.day(id,"first") + int(entry["days_after"]): return "rest"
	if not RECORDS.has(id,"intro"): return "intro"
	if not RECORDS.has(id,"repeat"):
		return "repeat_purchase" if GameState.total_day >= RECORDS.day(id,"intro") + int(entry["days_after"]) else "rest"
	if GameState.total_day < RECORDS.day(id,"repeat") + int(entry["days_after"]): return "rest"
	if not RECORDS.has(id,"accepted"): return "request"
	return "finish" if ready(id) else "wait"
static func complete_action(id: String, stage: String) -> bool:
	if phase(id) != stage: return false
	if stage in ["intro","request","after"]:
		PlayerProgress.record_story_beat(RECORDS.key(id,"accepted" if stage == "request" else stage),GameState.total_day)
		return true
	if stage != "finish" or not ready(id): return false
	var entry := RECORDS.event(id)
	for gift in entry["gifts"]:
		if not ItemData.has_item(str(gift["item"])) or int(gift["amount"]) <= 0: return false
	for item in CommunityRequestFlow.required_items(entry):
		GameState.remove_item(item,int(CommunityRequestFlow.required_items(entry)[item]))
	PlayerProgress.record_story_beat(RECORDS.key(id,"done"),GameState.total_day)
	PlayerProgress.story_beat_days[ResidentRequestFlow.PREFIX + "reputation:regular/" + id] = maxi(0,int(entry["reputation"]))
	for gift in entry["gifts"]: GameState.add_item(str(gift["item"]),int(gift["amount"]))
	return true
static func requirements(id: String) -> String:
	var text := ""
	for item in CommunityRequestFlow.required_items(RECORDS.event(id)):
		text += "%s %d/%d · 창고\n" % [ItemData.get_item_name(item),GameState.get_item_count(item),CommunityRequestFlow.required_items(RECORDS.event(id))[item]]
	return text.strip_edges()
static func reward(id: String) -> String:
	var entry := RECORDS.event(id)
	var parts: Array[String] = []
	for gift in entry.get("gifts",[]): parts.append("%s ×%d" % [ItemData.get_item_name(str(gift["item"])),gift["amount"]])
	return " · ".join(parts) + " · 평판 +%d (최초 1회)" % int(entry.get("reputation",0))
static func information(id: String) -> String:
	var entry := RECORDS.event(id)
	if entry.is_empty(): return ""
	var state := phase(id)
	var name := CustomerTypeData.get_display_name(str(entry["type"]))
	if state == "locked": return "첫 거래와 원재료 판매를 마치고 이 손님의 기존 방문 조건을 열어 주세요.\n" + VillageVisitorFlow.information(str(entry["type"]))
	if state == "first_purchase": return "%s의 첫 구매를 기다립니다.\n%s를 진열하면 실제로 구매할 때 인연이 시작됩니다." % [name,ItemData.get_item_name(str(entry["purchase_item"]))]
	if state == "repeat_purchase": return "%s가 동료 몫을 사러 다시 찾아올 준비를 합니다.\n%s ×%d를 진열하고 가게를 열어 주세요. 실제 결제가 필요합니다." % [name,ItemData.get_item_name(str(entry["purchase_item"])),entry["repeat_amount"]]
	if state == "rest": return "오늘의 만남을 기억하고 있습니다. 다음 날 이후 이야기가 이어집니다."
	if state in ["intro","request"]: return "%s가 마을 게시판 근처에서 기다립니다. 가까이 가서 [E]로 이야기를 들으세요." % name
	if state in ["wait","finish"]: return "준비한 뒤 같은 손님에게 직접 [E]\n" + requirements(id) + "\n답례: " + reward(id)
	var memory := RequestTextData.text("service_text",id + "_finish","completion")
	if state == "after": return memory + "\n다시 만난 손님의 이야기를 마을 게시판 근처에서 들어 주세요. 추가 답례는 없습니다."
	return RequestTextData.text("service_text",id + "_after","completion") + "\n함께한 날: %d일차" % RECORDS.day(id,"done")
