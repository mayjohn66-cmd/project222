class_name RequestNotebookData
extends RefCounted
## 수락/완료 기록을 읽어 수첩을 재구성한다. 조회 자체는 진행을 바꾸지 않는다.
static func entries() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	var residents: Array[Dictionary] = ResidentRequestFlow.SETTINGS.requests.duplicate(true)
	residents.append_array(ResidentStoryFlow.SETTINGS.settlement_requests)
	for raw in residents:
		var id := str(raw["id"])
		var entry := RequestTextData.enrich(raw, "resident_request")
		_request(rows, "request:" + id, entry, ResidentRequestFlow.accepted(id), ResidentRequestFlow.done(id), ResidentRequestFlow.PREFIX + id)
	for entry in CommunityRequestFlow.SETTINGS.requests:
		var id := str(entry["id"])
		_request(rows, "community:" + id, CommunityRequestFlow.request(id), CommunityRequestFlow.accepted(id), CommunityRequestFlow.done(id), CommunityRequestFlow.PREFIX + id)
	for entry in PersonalRequestFlow.entries():
		var id := str(entry["id"])
		_request(rows, "personal:" + id, entry, PersonalRequestFlow.accepted(id), PersonalRequestFlow.done(id), PersonalRequestFlow.PREFIX + id)
	for entry in VillageJournalFlow.entries():
		var id := str(entry["id"])
		if id == "next_request" or id.begins_with("personal:") or id.begins_with("community:"): continue
		var flags := _recorded(id)
		if flags.is_empty(): continue
		rows.append({"id": id, "title": entry["title"], "category": flags[0], "status": flags[1], "source": {}})
	return rows

static func _request(rows: Array[Dictionary], id: String, entry: Dictionary, accepted: bool, done: bool, key: String) -> void:
	if not accepted and not done: return
	rows.append({"id": id, "title": entry["title"], "source": entry, "category": "done" if done else "active", "status": "완료" if done else "진행 중", "key": key})

static func _recorded(id: String) -> Array:
	if id.begins_with("resident:"):
		if VillageLifeFlow.available(VillageLifeFlow.resident(id.trim_prefix("resident:"))): return ["neighbors", "이웃"]
		return []
	if id.begins_with("place:"):
		return ["memories", "함께 만든 곳"] if ResidentRequestFlow.done(id.trim_prefix("place:")) else []
	if id.begins_with("visitor:"):
		return ["memories", "만난 손님"] if PlayerProgress.story_beat_days.has(ResidentRequestFlow.PREFIX + "visited:" + id.trim_prefix("visitor:")) else []
	if id.begins_with(VillageExpansionFlow.JOURNAL_PREFIX): return _flags(VillageExpansionFlow.accepted(id.trim_prefix(VillageExpansionFlow.JOURNAL_PREFIX)), VillageExpansionFlow.done(id.trim_prefix(VillageExpansionFlow.JOURNAL_PREFIX)) and not VillageExpansionFlow.accepted(id.trim_prefix(VillageExpansionFlow.JOURNAL_PREFIX)))
	if id.begins_with(ActFourFlow.JOURNAL_PREFIX): return _flags(ActFourFlow.accepted(id.trim_prefix(ActFourFlow.JOURNAL_PREFIX)), ActFourFlow.done(id.trim_prefix(ActFourFlow.JOURNAL_PREFIX)) and not ActFourFlow.accepted(id.trim_prefix(ActFourFlow.JOURNAL_PREFIX)))
	if id.begins_with(CraftingPathFlow.JOURNAL_PREFIX): return _flags(CraftingPathFlow.accepted(id.trim_prefix(CraftingPathFlow.JOURNAL_PREFIX)), CraftingPathFlow.done(id.trim_prefix(CraftingPathFlow.JOURNAL_PREFIX)))
	if id.begins_with(PreservationLessonFlow.JOURNAL_PREFIX): return _flags(PreservationLessonFlow.accepted(id.trim_prefix(PreservationLessonFlow.JOURNAL_PREFIX)), PreservationLessonFlow.completed(id.trim_prefix(PreservationLessonFlow.JOURNAL_PREFIX)))
	if id.begins_with(ResidentMemoryFlow.JOURNAL_PREFIX): return _flags(ResidentMemoryFlow.accepted(id.trim_prefix(ResidentMemoryFlow.JOURNAL_PREFIX)), ResidentMemoryFlow.completed(id.trim_prefix(ResidentMemoryFlow.JOURNAL_PREFIX)))
	if id.begins_with(SeasonalVillageFlow.JOURNAL_PREFIX): return _flags(SeasonalVillageFlow.accepted(id.trim_prefix(SeasonalVillageFlow.JOURNAL_PREFIX)), SeasonalVillageFlow.completed(id.trim_prefix(SeasonalVillageFlow.JOURNAL_PREFIX)))
	if id.begins_with(RegularCustomerFlow.JOURNAL_PREFIX): return _flags(RegularCustomerRecords.has(id.trim_prefix(RegularCustomerFlow.JOURNAL_PREFIX), "intro"), RegularCustomerRecords.has(id.trim_prefix(RegularCustomerFlow.JOURNAL_PREFIX), "after"))
	if id.begins_with(ExpeditionContactFlow.JOURNAL_PREFIX): return _flags(ExpeditionContactFlow.has(id.trim_prefix(ExpeditionContactFlow.JOURNAL_PREFIX), "intro"), ExpeditionContactFlow.has(id.trim_prefix(ExpeditionContactFlow.JOURNAL_PREFIX), "after"))
	if id.begins_with(WeatherLifeFlow.JOURNAL_PREFIX): return _flags(WeatherLifeFlow.has(id.trim_prefix(WeatherLifeFlow.JOURNAL_PREFIX), "intro"), WeatherLifeFlow.has(id.trim_prefix(WeatherLifeFlow.JOURNAL_PREFIX), "after"))
	if id == VillageStoryFlow.JOURNAL_ID: return _flags(VillageStoryFlow.accepted(), VillageStoryFlow.completed())
	if id == VillageGoodwillFlow.JOURNAL_ID: return _flags(VillageGoodwillFlow.accepted(), VillageGoodwillFlow.completed())
	if id == VillageMarketFlow.JOURNAL_ID: return _flags(VillageMarketFlow.accepted(), VillageMarketFlow.completed())
	if id == LanternWayfarerFlow.JOURNAL_ID: return _flags(LanternWayfarerFlow.accepted(), LanternWayfarerFlow.completed())
	if id == VillageRestFlow.JOURNAL_ID: return _flags(VillageRestFlow.prepared(), VillageRestFlow.completed())
	if id == "gathering:well_evening": return ["memories", "함께한 모임"] if VillageGatheringFlow.completed() else []
	if id == "fishing:journal": return ["memories", "낚시 기록"]
	if id == PowerRepairFlow.JOURNAL_ID: return _flags(PowerRepairFlow.introduced(), PowerRepairFlow.marked("restored"))
	if id == BlacksmithProgressionFlow.JOURNAL_ID: return ["memories", "만난 기술자"] if BlacksmithProgressionRecords.has("heard") else []
	return []

static func _flags(accepted: bool, done: bool) -> Array:
	if done: return ["done", "완료"]
	return ["active", "진행 중"] if accepted else []

static func detail(row: Dictionary) -> Dictionary:
	var id := str(row["id"])
	var entry: Dictionary = row["source"]
	if entry.is_empty(): return {"text": VillageJournalFlow.information(id), "progress": -1.0, "reward": "", "context": row["status"]}
	var complete: bool = row["category"] == "done"
	var text := str(row["status"])
	var key := str(row["key"])
	var day := int(PlayerProgress.story_beat_days.get(key + (":done" if complete else ":accepted"), 0))
	if day > 0: text += " · %d일차" % day
	var npc := str(entry.get("npc", ""))
	if npc.is_empty() and entry.has("resident"): npc = str(VillageLifeFlow.resident(str(entry["resident"])).get("name", ""))
	if not npc.is_empty(): text += "\n" + npc
	var summary := str(entry.get("summary", ""))
	if complete: summary = "\n".join(PackedStringArray(entry.get("completion", []))) if entry.get("completion") is Array else str(entry.get("completion", ""))
	var context := text
	text = ""
	var normalized := RequestProposalData.resident(entry) if id.begins_with("request:") else entry
	var totals := CommunityRequestFlow.required_items(normalized)
	var total := 0
	var have := 0
	text += "전달한 물품" if complete else "소지한 물품"
	for item in totals:
		var needed := int(totals[item])
		var owned := needed if complete else mini(GameState.get_item_count(item), needed)
		total += needed
		have += owned
		text += "\n%s %d / %d" % [ItemData.get_item_name(item), owned, needed]
	var reward := "답례: %d G · 평판 +%d" % [int(entry.get("money", 0)), int(entry.get("reputation", 0))]
	if not complete and total > 0 and have == total: text += "\n\n전달할 준비가 되었습니다."
	if not summary.is_empty(): text += "\n\n" + summary
	return {"text": text, "progress": 100.0 * have / total if total > 0 else -1.0, "reward": reward, "context": context}

static func destination(world: Node, id: String) -> Node2D:
	if not id.begins_with("request:"): return VillageJournalFlow.destination(world, id)
	var request_id := id.trim_prefix("request:")
	var current := ResidentRequestFlow.current()
	if str(current.get("id", "")) == request_id:
		var director := world.get_node_or_null("ResidentRequestDirector")
		if director != null and is_instance_valid(director.npc) and director.npc.visible: return director.npc
	for entry in VillageLifeFlow.entries():
		if str(entry.get("request", "")) == request_id: return VillageJournalFlow.destination(world, "resident:" + str(entry["id"]))
	return null
