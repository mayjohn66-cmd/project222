class_name ResidentMemoryFlow
extends RefCounted

const SETTINGS = preload("res://scenes/shop/requests/default_resident_memories.tres")
const PREFIX := "resident_memory:"
const JOURNAL_PREFIX := "memory:"

static func event(id: String) -> Dictionary:
	for entry in SETTINGS.events:
		if str(entry["id"]) == id: return entry
	return {}
static func key(id: String, stage: String) -> String: return PREFIX + id + ":" + stage
static func accepted(id: String) -> bool: return PlayerProgress.story_beat_days.has(key(id, "accepted"))
static func completed(id: String) -> bool: return PlayerProgress.story_beat_days.has(key(id, "done"))
static func title(id: String) -> String: return RequestTextData.text("service_text", id + "_intro", "title", "이웃의 작은 기억")
static func choice(id: String, scene_id: String) -> Dictionary:
	for entry in event(id).get("choices", []):
		if str(entry["id"]) == scene_id: return entry
	return {}
static func chosen(id: String) -> String:
	for entry in event(id).get("choices", []):
		if PlayerProgress.story_beat_days.has(key(id, "choice:" + str(entry["id"]))): return str(entry["id"])
	return ""

static func locked_reason(entry: Dictionary) -> String:
	if entry.is_empty(): return "이야기를 찾을 수 없습니다."
	if not CommunityRequestFlow.board_available(): return "안내를 마치고 첫 이웃의 정착을 도와 주세요."
	var resident := VillageLifeFlow.resident(str(entry["giver"]))
	if not VillageLifeFlow.available(resident): return "%s의 정착을 기다리고 있어요." % resident.get("name", "주민")
	if accepted(str(entry["id"])): return ""
	var prerequisite := SeasonalLifeRequestFlow.locked_reason(entry)
	if not prerequisite.is_empty(): return prerequisite
	if VillageLifeFlow.friendship(str(entry["giver"])) < int(entry["friendship"]):
		return "%s와 안부를 조금 더 나눠 주세요. 함께 인사한 날 %d/%d일" % [resident["name"], VillageLifeFlow.friendship(str(entry["giver"])), int(entry["friendship"])]
	var first_day := -1
	for id in entry["after_any_seasonal"]:
		if SeasonalVillageFlow.completed(str(id)):
			var day := int(PlayerProgress.story_beat_days[SeasonalVillageFlow.key(str(id), "done")])
			first_day = day if first_day < 0 else mini(first_day, day)
	if first_day < 0: return "관련 계절 생활 재료 부탁 중 하나를 마치면 이야기가 이어져요."
	if GameState.total_day < first_day + maxi(0, int(entry["days_after_seasonal"])): return "계절 준비를 도운 뒤 조금 더 시간이 지나면 이야기가 이어져요."
	return ""

static func accept(id: String) -> bool:
	if accepted(id) or completed(id) or not locked_reason(event(id)).is_empty(): return false
	PlayerProgress.record_story_beat(key(id, "accepted"), GameState.total_day)
	return true
static func select(id: String, scene_id: String) -> bool:
	if not accepted(id) or completed(id) or not chosen(id).is_empty() or choice(id, scene_id).is_empty() or not locked_reason(event(id)).is_empty(): return false
	PlayerProgress.record_story_beat(key(id, "choice:" + scene_id), GameState.total_day)
	return true
static func finish(id: String) -> bool:
	var entry := event(id)
	if not accepted(id) or completed(id) or chosen(id).is_empty() or not locked_reason(entry).is_empty(): return false
	for gift in entry["gifts"]:
		if not ItemData.has_item(str(gift["item"])) or int(gift["amount"]) <= 0: return false
	PlayerProgress.record_story_beat(key(id, "done"), GameState.total_day)
	PlayerProgress.story_beat_days[ResidentRequestFlow.PREFIX + "reputation:memory/" + id] = maxi(0, int(entry["reputation"]))
	for gift in entry["gifts"]: GameState.add_item(str(gift["item"]), int(gift["amount"]))
	return true
static func reward_description(id: String) -> String:
	var parts: Array[String] = []
	for gift in event(id).get("gifts", []): parts.append("%s ×%d" % [ItemData.get_item_name(str(gift["item"])), int(gift["amount"])])
	parts.append("평판 +%d" % maxi(0, int(event(id).get("reputation", 0))))
	return " · ".join(parts)
static func action(resident: String) -> Dictionary:
	for entry in SETTINGS.events:
		var id := str(entry["id"])
		if resident != entry["giver"] or not locked_reason(entry).is_empty(): continue
		var stage := "memory" if completed(id) else ("introduction" if not accepted(id) else ("choose" if chosen(id).is_empty() else "finish"))
		var scene_id := chosen(id) if stage in ["memory", "finish"] else id + ("_intro" if stage == "introduction" else "_choose")
		return {"flow":"resident_memory", "event":id, "resident":resident, "stage":stage, "id":scene_id, "field":"completion" if stage == "memory" else "lines"}
	return {}
static func complete_action(entry: Dictionary) -> bool:
	if entry.is_empty() or entry != action(str(entry.get("resident", ""))): return false
	match str(entry["stage"]):
		"introduction": return accept(str(entry["event"]))
		"choose": return true
		"finish": return finish(str(entry["event"]))
	return false
static func information(id: String) -> String:
	if event(id).is_empty(): return ""
	if completed(id): return "이야기를 나눈 날: %d일차\n선택한 기억: %s\n%s" % [PlayerProgress.story_beat_days[key(id, "done")], RequestTextData.text("service_text", chosen(id), "title"), RequestTextData.text("service_text", chosen(id), "completion")]
	var reason := locked_reason(event(id))
	if not reason.is_empty(): return reason
	var name := str(VillageLifeFlow.resident(str(event(id)["giver"]))["name"])
	if not chosen(id).is_empty(): return "선택한 기억: %s\n%s에게 이야기를 마저 듣기 [E]" % [RequestTextData.text("service_text", chosen(id), "title"), name]
	return "%s와 이야기하고 마음에 남길 답을 골라 보세요. [E]\n물품 준비나 기한 없이 진행합니다. 답례는 어느 답을 골라도 같아요." % name
