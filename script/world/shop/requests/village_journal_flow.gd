class_name VillageJournalFlow
extends RefCounted

static func available() -> bool:
	return ResidentRequestFlow.tutorial_finished()

static func entries() -> Array[Dictionary]:
	var result: Array[Dictionary] = [{"id":"next_request", "title":"다음 주민 부탁"}]
	for resident in VillageLifeFlow.SETTINGS.residents:
		result.append({"id":"resident:" + str(resident["id"]), "title":str(resident["name"])})
	for landmark in ResidentStoryFlow.SETTINGS.landmarks:
		result.append({"id":"place:" + str(landmark["request"]), "title":ResidentStoryFlow.landmark_for_request(str(landmark["request"]))})
	for request in CommunityRequestFlow.SETTINGS.requests:
		var id := str(request["id"])
		result.append({"id":"community:" + id, "title":RequestTextData.text("community_request",id,"title","마을 부탁")})
	for request in PersonalRequestFlow.entries(): result.append({"id":"personal:" + str(request["id"]),"title":str(request["title"])})
	for visitor in VillageVisitorFlow.SETTINGS.visitors:
		var type_id := str(visitor["type"])
		result.append({"id":"visitor:" + type_id,"title":VillageVisitorFlow.name_for(type_id)})
	result.append({"id":"gathering:well_evening","title":VillageGatheringFlow.title()})
	result.append({"id":LanternWayfarerFlow.JOURNAL_ID,"title":LanternWayfarerFlow.title()})
	result.append({"id":VillageStoryFlow.JOURNAL_ID,"title":VillageStoryFlow.title()})
	result.append({"id":VillageMarketFlow.JOURNAL_ID,"title":VillageMarketFlow.title()})
	result.append({"id":VillageRestFlow.JOURNAL_ID,"title":"쉼터에서 처음 함께 쉬기"})
	result.append({"id":VillageGoodwillFlow.JOURNAL_ID,"title":VillageGoodwillFlow.title()})
	for event in SeasonalVillageFlow.events():
		result.append({"id":SeasonalVillageFlow.JOURNAL_PREFIX + str(event["id"]), "title":SeasonalVillageFlow.title(str(event["id"]))})
	for event in ResidentMemoryFlow.SETTINGS.events:
		result.append({"id":ResidentMemoryFlow.JOURNAL_PREFIX + str(event["id"]), "title":ResidentMemoryFlow.title(str(event["id"]))})
	return result

static func information(id: String) -> String:
	if id.begins_with(ResidentMemoryFlow.JOURNAL_PREFIX): return ResidentMemoryFlow.information(id.trim_prefix(ResidentMemoryFlow.JOURNAL_PREFIX))
	if id.begins_with(SeasonalVillageFlow.JOURNAL_PREFIX): return SeasonalVillageFlow.information(id.trim_prefix(SeasonalVillageFlow.JOURNAL_PREFIX))
	if id == VillageGoodwillFlow.JOURNAL_ID: return VillageGoodwillFlow.information()
	if id == VillageRestFlow.JOURNAL_ID: return VillageRestFlow.information()
	if id == VillageMarketFlow.JOURNAL_ID: return VillageMarketFlow.information()
	if id == VillageStoryFlow.JOURNAL_ID: return VillageStoryFlow.information()
	if id == LanternWayfarerFlow.JOURNAL_ID: return LanternWayfarerFlow.information()
	if id.begins_with("visitor:"): return VillageVisitorFlow.information(id.trim_prefix("visitor:"))
	if id == "gathering:well_evening": return VillageGatheringFlow.information()
	if id.begins_with("personal:"):
		var entry := PersonalRequestFlow.request(id.trim_prefix("personal:"))
		if entry.is_empty(): return ""
		var status := "함께 완료한 부탁" if PersonalRequestFlow.done(str(entry["id"])) else ("물품 준비 중" if PersonalRequestFlow.accepted(str(entry["id"])) else "게시판에서 부탁 듣기")
		return status + "\n" + PersonalRequestFlow.information(entry)
	if id == "next_request":
		var introduction := ResidentStoryFlow.pending_introduction()
		if not introduction.is_empty(): return "가게를 방문한 %s와 먼저 인사하세요." % introduction["npc"]
		var request := ResidentRequestFlow.current()
		if request.is_empty(): return "지금까지의 주민 부탁을 마쳤습니다. 이웃과 안부를 나누고 마을 게시판을 살펴보세요."
		var status := "물품 전달 가능" if ResidentRequestFlow.can_deliver(request) else ("물품 준비 중" if ResidentRequestFlow.accepted(str(request["id"])) else "주민에게 부탁 듣기")
		return "%s · %s\n%s %d/%d · 창고 기준" % [request["title"],status,ItemData.get_item_name(str(request["item"])),GameState.get_item_count(str(request["item"])),request["amount"]]
	if id.begins_with("resident:"):
		var resident_id := id.trim_prefix("resident:")
		var resident := VillageLifeFlow.resident(resident_id)
		if not VillageLifeFlow.available(resident): return "아직 정착하지 않았습니다. 가게를 찾는 손님과 인연을 이어 가세요."
		return "%s · 함께 인사한 날 %d일\n%s" % [VillageLifeFlow.friendship_name(resident_id),VillageLifeFlow.friendship(resident_id),"오늘 안부를 나눴습니다." if VillageLifeFlow.greeted_today(resident_id) else "오늘은 아직 안부를 나누지 않았습니다."]
	if id.begins_with("place:"):
		var request_id := id.trim_prefix("place:")
		if not ResidentRequestFlow.done(request_id): return "이웃의 정착 부탁을 마치면 함께 만들 수 있습니다."
		return "함께 만든 날: %d일차\n지금 마을에서 이용할 수 있습니다." % int(PlayerProgress.story_beat_days[ResidentRequestFlow.PREFIX + request_id + ":done"])
	if id.begins_with("community:"):
		var request_id := id.trim_prefix("community:")
		var request := CommunityRequestFlow.request(request_id)
		if request.is_empty(): return ""
		if CommunityRequestFlow.done(request_id): return "%s · 함께 만든 날 %d일차" % [request["landmark_name"],PlayerProgress.story_beat_days[CommunityRequestFlow.PREFIX + request_id + ":done"]]
		var reason := CommunityRequestFlow.locked_reason(request)
		var status := reason if not reason.is_empty() else ("물품 전달 가능" if CommunityRequestFlow.can_deliver(request_id) else ("물품 준비 중" if CommunityRequestFlow.accepted(request_id) else "게시판에서 부탁 듣기"))
		return "%s\n%s" % [request["summary"],status]
	return ""

static func destination(world: Node, id: String) -> Node2D:
	if not available(): return null
	if id.begins_with(ResidentMemoryFlow.JOURNAL_PREFIX):
		var memory := ResidentMemoryFlow.event(id.trim_prefix(ResidentMemoryFlow.JOURNAL_PREFIX))
		if memory.is_empty() or not ResidentMemoryFlow.locked_reason(memory).is_empty(): return null
		return destination(world, "resident:" + str(memory["giver"]))
	if id.begins_with(SeasonalVillageFlow.JOURNAL_PREFIX):
		var event_id := id.trim_prefix(SeasonalVillageFlow.JOURNAL_PREFIX)
		var event := SeasonalVillageFlow.event(event_id)
		if event.is_empty() or SeasonalVillageFlow.completed(event_id) or not SeasonalVillageFlow.locked_reason(event).is_empty(): return null
		if SeasonalVillageFlow.accepted(event_id) and event["mode"] == "observe" and not SeasonalVillageFlow.observed(event_id): return SeasonalVillageFlow.site(world, event_id)
		return destination(world, "resident:" + SeasonalVillageFlow.next_resident(event_id))
	if id == VillageGoodwillFlow.JOURNAL_ID:
		var resident_id := VillageGoodwillFlow.next_resident()
		return destination(world, "resident:" + resident_id) if not resident_id.is_empty() else null
	if id == VillageRestFlow.JOURNAL_ID:
		if VillageRestFlow.prepared(): return VillageRestFlow.site(world)
		return destination(world, "community:" + VillageRestFlow.SETTINGS.preparation)
	if id == VillageMarketFlow.JOURNAL_ID:
		if not VillageMarketFlow.locked_reason().is_empty(): return null
		return VillageMarketFlow.site(world) if VillageMarketFlow.prepared() else destination(world, "resident:" + VillageMarketFlow.SETTINGS.giver)
	if id == VillageStoryFlow.JOURNAL_ID:
		var resident_id := VillageStoryFlow.SETTINGS.giver if VillageStoryFlow.completed() else VillageStoryFlow.next_resident()
		return destination(world, "resident:" + resident_id) if not resident_id.is_empty() else null
	if id == LanternWayfarerFlow.JOURNAL_ID:
		var wayfarer = world.get_node_or_null("LanternWayfarerDirector")
		if wayfarer != null and is_instance_valid(wayfarer.npc) and wayfarer.npc.visible and not wayfarer.npc.is_queued_for_deletion(): return wayfarer.npc
		return LanternWayfarerFlow.site(world) if not LanternWayfarerFlow.completed() else null
	if id == "gathering:well_evening":
		if VillageGatheringFlow.pending() or VillageGatheringFlow.completed(): return VillageGatheringFlow.site(world)
		return destination(world,"community:" + VillageGatheringFlow.SETTINGS.preparation)
	if id.begins_with("personal:"):
		var entry := PersonalRequestFlow.request(id.trim_prefix("personal:"))
		if entry.is_empty() or not PersonalRequestFlow.locked_reason(entry).is_empty(): return null
		if PersonalRequestFlow.done(str(entry["id"])): return destination(world,"resident:" + str(entry["resident"]))
		var board := VillageSettlement.find_site(world,CommunityRequestFlow.SETTINGS.board_path)
		return board if board != null and board.visible else null
	if id == "next_request":
		var director = world.get_node_or_null("ResidentRequestDirector")
		return director.npc if director != null and is_instance_valid(director.npc) and director.npc.visible else null
	if id.begins_with("resident:"):
		var life = world.get_node_or_null("VillageLifeDirector")
		var npc = life.residents.get(id.trim_prefix("resident:")) if life != null else null
		return npc if is_instance_valid(npc) and npc.visible else null
	var path := ""
	if id.begins_with("place:"):
		for landmark in ResidentStoryFlow.SETTINGS.landmarks:
			if str(landmark["request"]) == id.trim_prefix("place:") and ResidentRequestFlow.done(str(landmark["request"])): path = str(landmark["path"])
	elif id.begins_with("community:"):
		var request_id := id.trim_prefix("community:")
		var request := CommunityRequestFlow.request(request_id)
		if request.is_empty(): return null
		if CommunityRequestFlow.done(request_id):
			var landmark := CommunityRequestFlow.landmark_site(world, request)
			return landmark if landmark != null and landmark.visible else null
		elif CommunityRequestFlow.locked_reason(request).is_empty(): path = CommunityRequestFlow.SETTINGS.board_path
	if path.is_empty(): return null
	var site := VillageSettlement.find_site(world,path)
	return site if site != null and site.visible else null
