class_name BlacksmithProgressionFlow
extends RefCounted
const ENABLED := true
const JOURNAL_ID := "blacksmith:journal"
const SETTINGS = preload("res://scenes/shop/blacksmith/default_blacksmith_progression.tres")
static func legacy_rights() -> bool:
	if not ENABLED or not BlacksmithProgressionRecords.legacy(): return false
	if BlacksmithProgressionRecords.has("legacy_access"): return true
	var granted := CommunityRequestFlow.done("open_smithy")
	var enhanced := false
	for item in GameState.get_owned_equipment_instances() + GameState.get_saved_expedition_bag():
		if int(item.get("enhancement_level", 0)) > 0:
			granted = true
			enhanced = true
	if granted:
		BlacksmithProgressionRecords.mark("legacy_access")
		if enhanced: BlacksmithProgressionRecords.enhanced()
	return granted
static func service_available() -> bool:
	return ENABLED and (legacy_rights() or (CommunityRequestFlow.done("open_smithy") and BlacksmithProgressionRecords.has("service_intro")))
static func introduction_ready() -> bool:
	if not ENABLED or BlacksmithProgressionRecords.has("heard") or legacy_rights(): return false
	if not ResidentRequestFlow.tutorial_finished() or not ResidentRequestFlow.done("settle_naru") or not ResidentRequestFlow.done("traveler_water"): return false
	return BlacksmithProgressionRecords.has("ore_returned") or (BlacksmithProgressionRecords.legacy() and GameState.get_item_count("iron_ore") > 0)
static func npc_available() -> bool:
	return ENABLED and (legacy_rights() or BlacksmithProgressionRecords.has("heard"))
static func stage() -> String:
	if service_available(): return "smith_return_greeting"
	if not BlacksmithProgressionRecords.has("met"): return "smith_first_meeting"
	return "smith_workshop_ready" if CommunityRequestFlow.done("open_smithy") else "smith_workshop_wait"
static func afterglow_ready() -> bool:
	return BlacksmithProgressionRecords.has("first_enhanced") and not BlacksmithProgressionRecords.has("afterglow") and BlacksmithProgressionRecords.returns() > BlacksmithProgressionRecords.value("enhanced_return")
static func lines(id: String) -> Array[String]:
	return RequestTextData.lines("service_text",id)
static func complete(id: String) -> void:
	match id:
		"smith_heard_naru":
			if introduction_ready(): BlacksmithProgressionRecords.mark("heard")
		"smith_first_meeting":
			if npc_available() and not BlacksmithEquipmentAdapter.entries().is_empty(): BlacksmithProgressionRecords.mark("met")
		"smith_workshop_ready":
			if CommunityRequestFlow.done("open_smithy"): BlacksmithProgressionRecords.mark("service_intro")
		"smith_after_first_return":
			if afterglow_ready(): BlacksmithProgressionRecords.mark("afterglow")
static func next_step() -> String:
	if not ENABLED or not ResidentRequestFlow.done("traveler_water"): return ""
	if introduction_ready(): return "타블렌에게 안부를 나눈 뒤 광석을 다루는 사람의 소식을 들어 보세요."
	if not npc_available(): return "광산에서 철광석을 챙겨 돌아오면 타블렌과 이야기해 보세요."
	if not BlacksmithProgressionRecords.has("met") and not legacy_rights(): return "마을 바깥 길의 대장장이에게 장비를 보여 주세요. 장비를 건네거나 재료를 쓰지는 않습니다."
	if not CommunityRequestFlow.done("open_smithy") and not legacy_rights():
		var reason := CommunityRequestFlow.locked_reason(CommunityRequestFlow.request("open_smithy"))
		return "코르빈과 이웃의 작업장을 준비하세요. 마을 부탁 게시판의 대장간 부탁을 이어 갑니다.\n" + reason
	if not service_available(): return "대장간 앞의 대장장이에게 새 작업장 이야기를 들어 보세요."
	return "대장장이에게 [E]로 안부·장비 제작·강화를 선택하세요. 강화는 재료를 확인한 뒤 결정하며, 원정 준비에서는 장비를 조회합니다." + ("\n원정에서 돌아온 안부가 기다립니다." if afterglow_ready() else "")
static func destination(world: Node) -> Node2D:
	if introduction_ready(): return VillageJournalFlow.destination(world, "resident:naru")
	if npc_available():
		if BlacksmithProgressionRecords.has("met") and not CommunityRequestFlow.done("open_smithy") and not legacy_rights(): return VillageSettlement.find_site(world, CommunityRequestFlow.SETTINGS.board_path)
		var director := world.get_node_or_null("BlacksmithDirector")
		if director != null and is_instance_valid(director.npc) and director.npc.visible: return director.npc
	return null
