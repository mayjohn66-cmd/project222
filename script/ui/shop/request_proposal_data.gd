class_name RequestProposalData
extends RefCounted
## 기존 부탁 수치와 원문만 읽는다. 수락·전달·보상은 각 Flow가 처리한다.
static func resident(entry: Dictionary) -> Dictionary:
	var result := entry.duplicate(true)
	result["requirements"] = [{"item": entry["item"], "amount": entry["amount"]}]
	result["summary"] = ""
	return result

static func board(id: String) -> Dictionary:
	if id.begins_with("personal:"):
		var entry := PersonalRequestFlow.request(id.trim_prefix("personal:"))
		if entry.is_empty() or PersonalRequestFlow.accepted(str(entry["id"])) or PersonalRequestFlow.done(str(entry["id"])) or not PersonalRequestFlow.locked_reason(entry).is_empty(): return {}
		return entry
	if id.begins_with(VillageExpansionFlow.JOURNAL_PREFIX):
		var event_id := id.trim_prefix(VillageExpansionFlow.JOURNAL_PREFIX)
		if VillageExpansionFlow.accepted(event_id) or not VillageExpansionFlow.locked_reason(event_id).is_empty(): return {}
		var proposal := VillageExpansionFlow.event(event_id).duplicate(true)
		proposal["title"] = VillageExpansionFlow.title(event_id)
		proposal["summary"] = RequestTextData.text("service_text", str(proposal.get("title_id", event_id)), "summary", "")
		return proposal
	if id.begins_with(ActFourFlow.JOURNAL_PREFIX):
		var event_id := id.trim_prefix(ActFourFlow.JOURNAL_PREFIX)
		if ActFourFlow.accepted(event_id) or not ActFourFlow.locked_reason(event_id).is_empty(): return {}
		var proposal := ActFourFlow.event(event_id).duplicate(true)
		proposal["title"] = ActFourFlow.title(event_id)
		proposal["summary"] = RequestTextData.text("service_text", str(proposal.get("title_id", event_id)), "summary", "")
		return proposal
	var entry := CommunityRequestFlow.request(id)
	if entry.is_empty() or CommunityRequestFlow.accepted(id) or CommunityRequestFlow.done(id) or not CommunityRequestFlow.locked_reason(entry).is_empty(): return {}
	return entry

static func description(entry: Dictionary) -> String:
	var lines := PackedStringArray()
	var npc := str(entry.get("npc", ""))
	if npc.is_empty() and entry.has("resident"):
		npc = str(VillageLifeFlow.resident(str(entry["resident"])).get("name", ""))
	if not npc.is_empty(): lines.append(npc)
	var summary := str(entry.get("summary", ""))
	if not summary.is_empty(): lines.append(summary)
	var required := CommunityRequestFlow.required_items(entry)
	if not required.is_empty():
		lines.append("\n필요한 물품")
		for item in required: lines.append("%s ×%d" % [ItemData.get_item_name(item), required[item]])
	if entry.has("money") or entry.has("reputation"):
		lines.append("\n답례")
		lines.append("%d G · 평판 +%d" % [int(entry.get("money", 0)), int(entry.get("reputation", 0))])
	if entry.has("reward_text"):
		lines.append("\n답례\n" + str(entry["reward_text"]))
	for gift in entry.get("gifts", []):
		lines.append("%s ×%d" % [ItemData.get_item_name(str(gift["item"])), int(gift["amount"])])
	return "\n".join(lines)

static func story(action: Dictionary) -> Dictionary:
	var id := str(action.get("id", ""))
	var proposal := {"title": RequestTextData.text("service_text", id, "title", "이웃의 제안"), "summary": ""}
	var event_id := str(action.get("event", ""))
	match str(action.get("flow", "")):
		"power_repair": proposal["title"] = PowerRepairFlow.title()
		"preservation":
			proposal["title"] = PreservationLessonFlow.title(event_id)
			proposal["reward_text"] = PreservationLessonFlow.reward_description(event_id)
		"crafting_path":
			proposal.merge(CraftingPathFlow.stage(event_id), true)
			proposal["title"] = CraftingPathFlow.title(event_id)
		"seasonal":
			proposal["title"] = SeasonalVillageFlow.title(event_id)
			proposal["requirements"] = SeasonalVillageFlow.event(event_id).get("requirements", [])
			proposal["reward_text"] = SeasonalVillageFlow.reward_description(event_id)
		"resident_memory":
			proposal["title"] = ResidentMemoryFlow.title(event_id)
			proposal["reward_text"] = ResidentMemoryFlow.reward_description(event_id)
		"goodwill":
			proposal["title"] = VillageGoodwillFlow.title()
			proposal["reward_text"] = VillageGoodwillFlow.reward_description()
		_:
			proposal["title"] = VillageStoryFlow.title()
			proposal["reward_text"] = VillageStoryFlow.reward_description()
	return proposal
