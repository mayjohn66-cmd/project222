class_name SeasonalVillageFlow
extends RefCounted
const SETTINGS = preload("res://scenes/shop/requests/default_seasonal_village.tres")
const PREFIX := "seasonal_village:"
const JOURNAL_PREFIX := "seasonal:"
const SEASON_NAMES := {"spring":"봄", "summer":"여름", "autumn":"가을", "winter":"겨울"}

static func events() -> Array[Dictionary]:
	var result: Array[Dictionary] = SETTINGS.events.duplicate(true)
	result.append_array(SeasonalLifeRequestFlow.SETTINGS.events)
	return result

static func event(id: String) -> Dictionary:
	for entry in events():
		if str(entry["id"]) == id: return entry
	return {}
static func key(id: String, stage: String) -> String: return PREFIX + id + ":" + stage
static func accepted(id: String) -> bool: return PlayerProgress.story_beat_days.has(key(id, "accepted"))
static func completed(id: String) -> bool: return PlayerProgress.story_beat_days.has(key(id, "done"))
static func heard(id: String, resident: String) -> bool: return PlayerProgress.story_beat_days.has(key(id, "heard:" + resident))
static func observed(id: String) -> bool: return PlayerProgress.story_beat_days.has(key(id, "observed"))
static func title(id: String) -> String: return RequestTextData.text("service_text", id + "_intro", "title", id)
static func locked_reason(entry: Dictionary) -> String:
	if entry.is_empty(): return ""
	if not CommunityRequestFlow.board_available(): return "안내를 마치고 첫 이웃의 정착을 도와 주세요."
	var prerequisite := SeasonalLifeRequestFlow.locked_reason(entry)
	if not prerequisite.is_empty(): return prerequisite
	if not SeasonalLifeRequestFlow.season_available(entry, accepted(str(entry["id"]))):
		if bool(entry.get("continue_outside_season", false)): return "%s에 제안을 들을 수 있어요. 맡은 뒤에는 계절이 바뀌어도 준비할 수 있습니다." % SEASON_NAMES[entry["season"]]
		return "%s에 이어갈 수 있어요. 진행 기록은 다음 %s에도 유지됩니다." % [SEASON_NAMES[entry["season"]], SEASON_NAMES[entry["season"]]]
	var after := str(entry.get("after", ""))
	if not after.is_empty() and not CommunityRequestFlow.done(after): return "먼저 %s 공동 부탁을 마쳐 주세요." % RequestTextData.text("community_request", after, "title", after)
	var residents: Array = entry.get("participants", []).duplicate()
	residents.append(str(entry["giver"]))
	for id in residents:
		var resident := VillageLifeFlow.resident(str(id))
		if not VillageLifeFlow.available(resident): return "%s의 정착을 기다리고 있어요." % resident.get("name", "주민")
	return ""
static func accept(id: String) -> bool:
	var entry := event(id)
	if entry.is_empty() or accepted(id) or completed(id) or not locked_reason(entry).is_empty(): return false
	PlayerProgress.record_story_beat(key(id, "accepted"), GameState.total_day)
	return true
static func site(world: Node, id: String) -> StaticBody2D:
	var target := VillageSettlement.find_site(world, str(event(id).get("site", "")))
	return target if target != null and target.visible else null
static func can_observe(id: String, world: Node, hour: int) -> bool:
	var entry := event(id)
	return not entry.is_empty() and entry["mode"] == "observe" and accepted(id) and not completed(id) and not observed(id) and locked_reason(entry).is_empty() and site(world, id) != null and hour >= int(entry["start_hour"]) and hour < int(entry["end_hour"])
static func observe(id: String, world: Node, hour: int) -> bool:
	if not can_observe(id, world, hour): return false
	var player := world.get_node_or_null("Actors/Player") as Node2D
	if player == null or player.global_position.distance_to(site(world, id).global_position) > SETTINGS.interaction_distance: return false
	PlayerProgress.record_story_beat(key(id, "observed"), GameState.total_day)
	return true
static func listen(id: String, resident: String) -> bool:
	var entry := event(id)
	if entry.is_empty() or entry["mode"] != "neighbors" or resident not in entry["participants"] or not accepted(id) or completed(id) or heard(id, resident) or not locked_reason(entry).is_empty(): return false
	PlayerProgress.record_story_beat(key(id, "heard:" + resident), GameState.total_day)
	return true
static func ready(id: String) -> bool:
	var entry := event(id)
	if entry.is_empty() or not accepted(id) or completed(id) or not locked_reason(entry).is_empty(): return false
	match str(entry["mode"]):
		"observe": return observed(id)
		"neighbors":
			for resident in entry["participants"]:
				if not heard(id, str(resident)): return false
			return true
		"delivery":
			var totals := CommunityRequestFlow.required_items(entry)
			if totals.is_empty(): return false
			for item in totals:
				if int(totals[item]) <= 0 or not ItemData.has_item(item) or GameState.get_item_count(item) < int(totals[item]): return false
			return true
	return false
static func finish(id: String) -> bool:
	if not ready(id): return false
	var entry := event(id)
	for gift in entry["gifts"]:
		if not ItemData.has_item(str(gift["item"])) or int(gift["amount"]) <= 0: return false
	var totals := CommunityRequestFlow.required_items(entry)
	for item in totals: GameState.remove_item(item, int(totals[item]))
	PlayerProgress.record_story_beat(key(id, "done"), GameState.total_day)
	PlayerProgress.story_beat_days[ResidentRequestFlow.PREFIX + "reputation:seasonal/" + id] = maxi(0, int(entry["reputation"]))
	for gift in entry["gifts"]: GameState.add_item(str(gift["item"]), int(gift["amount"]))
	return true
static func reward_description(id: String) -> String:
	var entry := event(id)
	var parts: Array[String] = []
	for gift in entry.get("gifts", []): parts.append("%s ×%d" % [ItemData.get_item_name(str(gift["item"])), int(gift["amount"])])
	parts.append("평판 +%d" % int(entry.get("reputation", 0)))
	return " · ".join(parts)
static func requirements_description(id: String) -> String:
	var parts: Array[String] = []
	var totals := CommunityRequestFlow.required_items(event(id))
	for item in totals: parts.append("%s %d/%d · 창고" % [ItemData.get_item_name(item), GameState.get_item_count(item), int(totals[item])])
	return " · ".join(parts)
static func action(resident: String) -> Dictionary:
	var all_events := events()
	# 계절이 바뀌어도 맡은 부탁의 안내를 새 계절 제안으로 덮지 않는다.
	for started in [true, false]:
		for entry in all_events:
			var id := str(entry["id"])
			if accepted(id) != started or completed(id) or not locked_reason(entry).is_empty(): continue
			var stage := ""
			var scene := ""
			if not started:
				if resident != entry["giver"]: continue
				stage = "introduction"
				scene = id + "_intro"
			elif entry["mode"] == "neighbors" and resident in entry["participants"] and not heard(id, resident):
				stage = "listen"
				scene = id + "_" + resident
			elif resident == entry["giver"]:
				stage = "finish" if ready(id) else "reminder"
				scene = id + ("_finish" if ready(id) else "_wait")
			else: continue
			return {"flow":"seasonal", "event":id, "resident":resident, "stage":stage, "id":scene}
	return {}
static func complete_action(entry: Dictionary) -> bool:
	if entry.is_empty() or entry != action(str(entry.get("resident", ""))): return false
	var id := str(entry["event"])
	match str(entry["stage"]):
		"introduction": return accept(id)
		"listen": return listen(id, str(entry["resident"]))
		"finish": return finish(id)
	return false
static func next_resident(id: String) -> String:
	var entry := event(id)
	if entry.is_empty() or completed(id) or not locked_reason(entry).is_empty(): return ""
	if accepted(id) and entry["mode"] == "neighbors":
		for resident in entry["participants"]:
			if not heard(id, str(resident)): return str(resident)
	return str(entry["giver"])
static func information(id: String) -> String:
	var entry := event(id)
	if entry.is_empty(): return ""
	if completed(id): return "함께한 날: %d일차\n%s" % [PlayerProgress.story_beat_days[key(id, "done")], RequestTextData.text("service_text", id + "_finish", "completion")]
	var reason := locked_reason(entry)
	if not reason.is_empty(): return reason
	if not accepted(id): return "%s에게 제안 듣기 [E]" % VillageLifeFlow.resident(str(entry["giver"]))["name"]
	if ready(id): return "%s에게 돌아가 마무리 [E]\n답례: %s" % [VillageLifeFlow.resident(str(entry["giver"]))["name"], reward_description(id)]
	match str(entry["mode"]):
		"observe": return "%s에서 살펴보기 [E] · %02d~%02d시" % [entry["site_name"], entry["start_hour"], entry["end_hour"]]
		"delivery": return requirements_description(id) + "\n창고에 준비하고 %s에게 직접 전달 [E]" % VillageLifeFlow.resident(str(entry["giver"]))["name"]
		"neighbors":
			var parts: Array[String] = []
			for resident in entry["participants"]: parts.append("%s · %s" % [VillageLifeFlow.resident(str(resident))["name"], "들었어요" if heard(id, str(resident)) else "이야기 듣기 [E]"])
			return "\n".join(parts)
	return ""
