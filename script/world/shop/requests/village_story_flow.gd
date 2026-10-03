class_name VillageStoryFlow
extends RefCounted

const SETTINGS = preload("res://scenes/shop/requests/default_village_story.tres")
const PREFIX := "village_story:sora_village_story:"
const JOURNAL_ID := "story:sora_village_story"

static func title() -> String:
	return RequestTextData.text("service_text", "sora_village_story", "title", "이세르의 마을 이야기")

static func accepted() -> bool: return PlayerProgress.story_beat_days.has(PREFIX + "accepted")
static func heard(id: String) -> bool: return PlayerProgress.story_beat_days.has(PREFIX + "heard:" + id)
static func completed() -> bool: return PlayerProgress.story_beat_days.has(PREFIX + "done")

static func locked_reason() -> String:
	if not ResidentRequestFlow.tutorial_finished(): return "델빈의 안내를 마치고 주민들과 인연을 이어 가세요."
	var residents: Array[String] = SETTINGS.participants.duplicate()
	residents.append(SETTINGS.giver)
	for id in residents:
		var resident := VillageLifeFlow.resident(id)
		if not VillageLifeFlow.available(resident): return "%s의 정착을 기다리고 있어요." % resident.get("name", "주민")
	if not PersonalRequestFlow.done(SETTINGS.after_request): return "이세르의 우물 곁 기록 부탁을 먼저 마쳐 주세요."
	if SETTINGS.after_gathering and not VillageGatheringFlow.completed(): return "우물 곁 저녁 모임에 참여한 뒤 이야기를 남길 수 있어요."
	if not PlayerProgress.story_beat_days.has(SETTINGS.after_event): return "등불 아래의 길손과 다시 만난 뒤 이야기가 이어져요."
	return ""

static func accept() -> bool:
	if accepted() or completed() or not locked_reason().is_empty(): return false
	PlayerProgress.record_story_beat(PREFIX + "accepted", GameState.total_day)
	return true

static func listen(id: String) -> bool:
	if not accepted() or completed() or heard(id) or id not in SETTINGS.participants or not locked_reason().is_empty(): return false
	PlayerProgress.record_story_beat(PREFIX + "heard:" + id, GameState.total_day)
	return true

static func ready() -> bool:
	if not accepted() or completed() or not locked_reason().is_empty(): return false
	for id in SETTINGS.participants:
		if not heard(id): return false
	return true

static func choice(id: String) -> Dictionary:
	for entry in SETTINGS.choices:
		if str(entry["id"]) == id: return entry
	return {}

static func chosen() -> String:
	for entry in SETTINGS.choices:
		var id := str(entry["id"])
		if PlayerProgress.story_beat_days.has(PREFIX + "choice:" + id): return id
	return ""

static func select(id: String) -> bool:
	if not ready() or not chosen().is_empty() or choice(id).is_empty(): return false
	PlayerProgress.record_story_beat(PREFIX + "choice:" + id, GameState.total_day)
	return true

static func finish() -> bool:
	if not ready() or chosen().is_empty(): return false
	for gift in SETTINGS.gifts:
		if not ItemData.has_item(str(gift["item"])) or int(gift["amount"]) <= 0: return false
	PlayerProgress.record_story_beat(PREFIX + "done", GameState.total_day)
	PlayerProgress.story_beat_days[ResidentRequestFlow.PREFIX + "reputation:story/sora_village_story"] = maxi(0, SETTINGS.reputation)
	for gift in SETTINGS.gifts: GameState.add_item(str(gift["item"]), int(gift["amount"]))
	return true

static func reward_description() -> String:
	var parts: Array[String] = []
	for gift in SETTINGS.gifts:
		parts.append("%s ×%d" % [ItemData.get_item_name(str(gift["item"])), int(gift["amount"])])
	parts.append("평판 +%d" % maxi(0, SETTINGS.reputation))
	return " · ".join(parts)

static func action(resident_id: String) -> Dictionary:
	if not locked_reason().is_empty(): return {}
	if resident_id == SETTINGS.giver:
		if completed(): return {"stage":"memory", "id":"village_story_" + chosen(), "field":"completion"}
		if not accepted(): return {"stage":"introduction", "id":"sora_village_story"}
		if not chosen().is_empty(): return {"stage":"finish", "id":"village_story_" + chosen()}
		return {"stage":"choose" if ready() else "reminder", "id":"village_story_choose" if ready() else "village_story_reminder"}
	if accepted() and not completed() and resident_id in SETTINGS.participants and not heard(resident_id):
		return {"stage":"listen", "id":"village_story_" + resident_id, "resident":resident_id}
	return {}

static func next_resident() -> String:
	if completed() or not locked_reason().is_empty(): return ""
	if not accepted() or ready(): return SETTINGS.giver
	for id in SETTINGS.participants:
		if not heard(id): return id
	return SETTINGS.giver

static func information() -> String:
	if completed():
		var id := "village_story_" + chosen()
		return "이야기를 남긴 날: %d일차\n선택한 기억: %s\n%s" % [PlayerProgress.story_beat_days[PREFIX + "done"], RequestTextData.text("service_text", id, "title"), RequestTextData.text("service_text", id, "completion")]
	var reason := locked_reason()
	if not reason.is_empty(): return reason
	if not accepted(): return "이세르에게 말을 걸어 마을 이야기를 함께 남겨 보세요. [E]\n물품 준비나 기한 없이 진행합니다."
	if not chosen().is_empty(): return "선택한 기억: %s\n이세르에게 돌아가 기록을 마쳐 주세요. [E]" % RequestTextData.text("service_text", "village_story_" + chosen(), "title")
	var status: Array[String] = []
	for id in SETTINGS.participants:
		status.append("%s · %s" % [VillageLifeFlow.resident(id)["name"], "이야기를 들었어요" if heard(id) else "이야기 듣기 [E]"])
	status.append("이세르에게 돌아가 남길 기억을 고르세요. [E]" if ready() else "주민 대화를 끝까지 들으면 수첩에 기록됩니다.")
	return "\n".join(status)
