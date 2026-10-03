class_name LanternWayfarerFlow
extends RefCounted

const SETTINGS = preload("res://scenes/shop/requests/default_lantern_wayfarer.tres")
const PREFIX := "village_event:lantern_wayfarer:"
const JOURNAL_ID := "event:lantern_wayfarer"

static func unlocked() -> bool:
	return ResidentRequestFlow.tutorial_finished() and CommunityRequestFlow.done(SETTINGS.prerequisite)

static func accepted() -> bool: return PlayerProgress.story_beat_days.has(PREFIX + "accepted")
static func helped() -> bool: return PlayerProgress.story_beat_days.has(PREFIX + "helped")
static func completed() -> bool: return PlayerProgress.story_beat_days.has(PREFIX + "done")
static func title() -> String: return RequestTextData.text("service_text", "lantern_wayfarer", "title", "등불 아래의 길손")

static func evening(hour: int) -> bool:
	if hour < 0 or hour > 23: return false
	if SETTINGS.start_hour < SETTINGS.end_hour: return hour >= SETTINGS.start_hour and hour < SETTINGS.end_hour
	return hour >= SETTINGS.start_hour or hour < SETTINGS.end_hour

static func return_ready() -> bool:
	return unlocked() and helped() and not completed() and GameState.total_day >= int(PlayerProgress.story_beat_days[PREFIX + "helped"]) + maxi(1, SETTINGS.return_days)

static func phase(hour: int) -> String:
	if not unlocked(): return "locked"
	if completed(): return "done"
	if helped(): return "return" if return_ready() else "waiting_return"
	if accepted(): return "supplies"
	return "introduction" if evening(hour) else "waiting_evening"

static func accept(hour: int) -> bool:
	if phase(hour) != "introduction": return false
	PlayerProgress.record_story_beat(PREFIX + "accepted", GameState.total_day)
	return true

static func choice(id: String) -> Dictionary:
	for entry in SETTINGS.choices:
		if str(entry["id"]) == id: return entry
	return {}

static func chosen() -> String:
	for entry in SETTINGS.choices:
		if PlayerProgress.story_beat_days.has(PREFIX + "choice:" + str(entry["id"])): return str(entry["id"])
	return ""

static func can_help(id: String) -> bool:
	var entry := choice(id)
	if not unlocked() or not accepted() or helped() or completed() or entry.is_empty(): return false
	return int(entry["amount"]) > 0 and ItemData.has_item(str(entry["item"])) and GameState.get_item_count(str(entry["item"])) >= int(entry["amount"])

static func help(id: String) -> bool:
	if not can_help(id): return false
	var entry := choice(id)
	GameState.remove_item(str(entry["item"]), int(entry["amount"]))
	PlayerProgress.record_story_beat(PREFIX + "choice:" + id, GameState.total_day)
	PlayerProgress.record_story_beat(PREFIX + "helped", GameState.total_day)
	return true

static func reward_description() -> String:
	var parts: Array[String] = []
	for gift in SETTINGS.gifts:
		parts.append("%s ×%d" % [ItemData.get_item_name(str(gift["item"])), int(gift["amount"])])
	parts.append("평판 +%d" % maxi(0, SETTINGS.reputation))
	return " · ".join(parts)

static func finish() -> bool:
	if not return_ready() or chosen().is_empty(): return false
	# Validate every gift before recording completion or granting any of them.
	for gift in SETTINGS.gifts:
		if not ItemData.has_item(str(gift["item"])) or int(gift["amount"]) <= 0: return false
	PlayerProgress.record_story_beat(PREFIX + "done", GameState.total_day)
	PlayerProgress.story_beat_days[ResidentRequestFlow.PREFIX + "reputation:event/lantern_wayfarer"] = maxi(0, SETTINGS.reputation)
	for gift in SETTINGS.gifts: GameState.add_item(str(gift["item"]), int(gift["amount"]))
	return true

static func site(world: Node) -> StaticBody2D:
	if not unlocked(): return null
	for path in [SETTINGS.site_path, SETTINGS.fallback_path]:
		var target := VillageSettlement.find_site(world, path)
		if target != null and target.visible: return target
	return null

static func information(hour: int = -1) -> String:
	if not unlocked(): return "길목에 작은 등불을 설치하면 저녁에 길손이 찾아옵니다."
	if completed():
		return "다시 만난 날: %d일차\n%s" % [PlayerProgress.story_beat_days[PREFIX + "done"], RequestTextData.text("service_text", "lantern_wayfarer", "completion")]
	if helped():
		var item := str(choice(chosen()).get("item", ""))
		return "%s를 나눈 날: %d일차\n%s" % [ItemData.get_item_name(item), PlayerProgress.story_beat_days[PREFIX + "helped"], "길손이 돌아왔어요. 등불 근처에서 다시 이야기하세요. [E]" if return_ready() else "다음 날 길손이 돌아옵니다. 기한 없이 기다려도 괜찮아요."]
	if accepted(): return "물 또는 빵 중 한 가지를 창고에 준비해 길손에게 건네세요. [E]\n기한은 없습니다. 진열대와 원정 가방 물품은 사용하지 않아요."
	return "저녁·심야 %02d~%02d시 · 등불 근처에서 길손과 이야기하세요. [E]\n%s" % [SETTINGS.start_hour, SETTINGS.end_hour, "지금 만나러 갈 수 있어요." if evening(hour) else "다음 저녁에도 만날 수 있어요. 기한은 없습니다."]
