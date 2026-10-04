class_name PreservationLessonFlow
extends RefCounted

const SETTINGS = PreservationLessonRecords.SETTINGS
const PREFIX := PreservationLessonRecords.PREFIX
const JOURNAL_PREFIX := "preservation:"

static func event(id: String) -> Dictionary:
	for entry in SETTINGS.events:
		if str(entry["id"]) == id: return entry
	return {}
static func key(id: String, stage: String) -> String: return PREFIX + id + ":" + stage
static func accepted(id: String) -> bool: return PlayerProgress.story_beat_days.has(key(id,"accepted"))
static func completed(id: String) -> bool: return PlayerProgress.story_beat_days.has(key(id,"done"))
static func title(id: String) -> String: return RequestTextData.text("service_text", id + "_intro", "title", "계절을 남기는 방법")

static func discovered(entry: Dictionary) -> bool:
	if PlayerProgress.story_beat_days.has(key(str(entry["id"]),"found")): return true
	# Old saves have no encounter marker: existing stock is a valid discovery.
	for path in entry["paths"]:
		if GameState.get_item_count(str(path["item"])) > 0: return true
	for unit in PreservationService.SETTINGS.units:
		if int(GameState.preservation_state.get(str(unit["id"]),{}).get(str(entry["raw"]),0)) > 0: return true
	return false

static func locked_reason(entry: Dictionary) -> String:
	if entry.is_empty(): return "보관 이야기를 찾을 수 없습니다."
	if not CommunityRequestFlow.board_available(): return "첫 거래와 원정 재료 판매를 마친 뒤 이어집니다."
	var resident := VillageLifeFlow.resident(str(entry["giver"]))
	if not VillageLifeFlow.available(resident): return "%s의 정착을 기다리고 있어요." % resident.get("name","이웃")
	if accepted(str(entry["id"])) or completed(str(entry["id"])): return ""
	if not discovered(entry): return "%s을 만나면 보존 이야기를 들을 수 있어요." % ItemData.get_item_name(str(entry["raw"]))
	if VillageLifeFlow.friendship(str(entry["giver"])) < int(entry["friendship"]): return "이웃과 오늘의 안부를 나눠 보세요. [E]"
	return ""

static func accept(id: String) -> bool:
	if accepted(id) or completed(id) or not locked_reason(event(id)).is_empty(): return false
	PlayerProgress.record_story_beat(key(id,"accepted"),GameState.total_day)
	return true

static func ready_path(id: String) -> Dictionary:
	var entry := event(id)
	if entry.is_empty() or not accepted(id) or completed(id) or not locked_reason(entry).is_empty(): return {}
	for path in entry["paths"]:
		if PlayerProgress.story_beat_days.has(key(id,"practiced:" + str(path["id"]))) and GameState.get_item_count(str(path["item"])) >= int(path["amount"]): return path
	return {}

static func finish(id: String, path_id: String) -> bool:
	var path := ready_path(id)
	if path.is_empty() or str(path["id"]) != path_id: return false
	var entry := event(id)
	for gift in entry["gifts"]:
		if not ItemData.has_item(str(gift["item"])) or int(gift["amount"]) <= 0: return false
	if GameState.remove_item(str(path["item"]),int(path["amount"])) != int(path["amount"]): return false
	PlayerProgress.record_story_beat(key(id,"done"),GameState.total_day)
	PlayerProgress.record_story_beat(key(id,"done_path:" + path_id),GameState.total_day)
	PlayerProgress.story_beat_days[ResidentRequestFlow.PREFIX + "reputation:preservation/" + id] = maxi(0,int(entry["reputation"]))
	for gift in entry["gifts"]: GameState.add_item(str(gift["item"]),int(gift["amount"]))
	return true

static func action(resident: String) -> Dictionary:
	for entry in SETTINGS.events:
		var id := str(entry["id"])
		if entry["giver"] != resident or completed(id) or not locked_reason(entry).is_empty(): continue
		var path := ready_path(id)
		var stage := "introduction" if not accepted(id) else ("reminder" if path.is_empty() else "finish")
		var scene := id + ("_intro" if stage == "introduction" else ("_wait" if path.is_empty() else "_" + str(path["id"])))
		return {"flow":"preservation", "event":id,"resident":resident,"stage":stage,"id":scene,"path":str(path.get("id",""))}
	return {}

static func complete_action(action_entry: Dictionary) -> bool:
	if action_entry.is_empty() or action_entry != action(str(action_entry.get("resident",""))): return false
	match str(action_entry["stage"]):
		"introduction": return accept(str(action_entry["event"]))
		"finish": return finish(str(action_entry["event"]),str(action_entry["path"]))
	return false

static func reward_description(id: String) -> String:
	var parts: Array[String] = []
	for gift in event(id).get("gifts",[]): parts.append("%s ×%d" % [ItemData.get_item_name(str(gift["item"])),int(gift["amount"])])
	parts.append("평판 +%d" % int(event(id).get("reputation",0)))
	return " · ".join(parts)

static func information(id: String) -> String:
	var entry := event(id)
	if entry.is_empty(): return ""
	if completed(id):
		for path in entry["paths"]:
			if PlayerProgress.story_beat_days.has(key(id,"done_path:" + str(path["id"]))): return "함께한 날: %d일차\n%s" % [PlayerProgress.story_beat_days[key(id,"done")],RequestTextData.text("service_text",id + "_" + str(path["id"]),"completion")]
	var reason := locked_reason(entry)
	if not reason.is_empty(): return reason
	var name := str(VillageLifeFlow.resident(str(entry["giver"]))["name"])
	if not accepted(id):
		var methods := "냉동함에 넣고 다음 날 이후 꺼내기" if str(entry["raw"]) == "winter_frost" else "냉장·냉동함에서 하룻밤 보관하거나 베이킹 작업대에서 말려 수령하기"
		return "%s에게 제안 듣기 [E] · 소개를 끝까지 읽으면 시작합니다.\n%s\n관리 메뉴 → 진열 인벤토리 → 냉장·냉동 보관.\n준비한 시료를 창고에서 주민에게 직접 전달합니다. 기한은 없어요." % [name,methods]
	var parts: Array[String] = ["소개 뒤 보관하거나 가공한 시료를 %s에게 직접 전달 [E]" % name]
	for path in entry["paths"]:
		var practiced := PlayerProgress.story_beat_days.has(key(id,"practiced:" + str(path["id"])))
		parts.append("%s · %s · %s %d/%d (창고)" % ["하룻밤 보관 후 꺼내기" if path["id"] == "cold" else "베이킹 작업대에서 말려 수령", "체험 완료" if practiced else "체험 준비",ItemData.get_item_name(str(path["item"])),GameState.get_item_count(str(path["item"])),int(path["amount"])])
	parts.append("관리 메뉴 → 진열 인벤토리 → 냉장·냉동 보관. 얼음은 냉동함만 가능하며 꺼낸 날 전달하세요.")
	if entry["paths"].size() > 1: parts.append("두 방법 중 하나만 준비하면 됩니다. 기한은 없어요.")
	parts.append("답례: " + reward_description(id))
	return "\n".join(parts)
