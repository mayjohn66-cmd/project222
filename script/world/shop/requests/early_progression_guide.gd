class_name EarlyProgressionGuide
extends RefCounted
## The pause between early requests is a visit/greeting/purchase, not completion.
const ENABLED := true

static func waiting_text() -> String:
	if not ENABLED or not ResidentMerchantSupply.ENABLED or not ResidentRequestFlow.tutorial_finished(): return ""
	if ResidentRequestFlow.done("traveler_water") or not ResidentRequestFlow.done("neighbor_bread") or not ResidentRequestFlow.done("gatherer_herbs"): return ""
	if not ResidentStoryFlow.introduction_read("peddler"):
		if PlayerProgress.story_beat_days.has(ResidentRequestFlow.PREFIX + "visited:peddler"):
			return "타블렌이 가게를 다시 찾았습니다. 가까이에서 인사를 나누세요. [E]"
		return "엘미의 부탁을 마쳤습니다. 타블렌을 다시 만나 채집 도구를 구할 길을 마련해 보세요.\n가게를 열어 방문을 기다리세요. 팔 물품을 진열하고 손님을 맞이하세요."
	if not ResidentRequestFlow.done("settle_naru"):
		return "타블렌에게 말을 걸어 노점 자리를 마련하는 부탁을 들어 보세요. [E]"
	if VillageLifeFlow.friendship("naru") < 1:
		return "노점 자리를 마련했습니다. 타블렌에게 먼저 안부를 나누세요. [E]\n안부 뒤 노점에서 도구와 재료를 살펴볼 수 있습니다."
	if ResidentMerchantSupply.owns_effect("collect_water"):
		return tool_instruction("collect_water")
	var price := ExpeditionShopData.get_price("gathering_bottle")
	var missing := maxi(0,price-GameState.get_money())
	var text := "타블렌의 노점 [E]에서 채집용 물병을 살펴보세요.\n물병 %d G · 소지금 %d G" % [price,GameState.get_money()]
	if missing > 0:
		text += " · %d G 부족\n부탁에 필요한 물품은 남겨 두고, 남는 판매 가능 재료를 진열해 판매하세요." % missing
	else:
		text += "\n구매한 도구는 원정 준비의 보유 장비에서 가방에 넣습니다."
	return text + "\n도구를 준비하면 라슈의 물 부탁이 이어집니다."

static func tool_instruction(effect: String) -> String:
	var item := ""
	for id in ExpeditionShopData.get_items_by_category(ExpeditionShopData.CATEGORY_TOOL):
		if ExpeditionEquipmentData.get_effect_id(id) == effect:
			item = id
			break
	if item.is_empty(): return ""
	var name := ItemData.get_item_name(item)
	if ENABLED:
		for entry in GameState.get_saved_expedition_bag():
			var id := str(entry.get("item_id",""))
			if ExpeditionEquipmentData.has_equipment(id) and ExpeditionEquipmentData.get_equipment_type(id) == ExpeditionEquipmentData.TYPE_TOOL and ExpeditionEquipmentData.get_effect_id(id) == effect:
				return "필수 도구 · %s: 원정 가방에 준비되어 있습니다. 출발할 때 그대로 챙기세요." % ItemData.get_item_name(id)
		for entry in GameState.get_owned_equipment_instances():
			var id := str(entry.get("item_id",""))
			if ExpeditionEquipmentData.has_equipment(id) and ExpeditionEquipmentData.get_equipment_type(id) == ExpeditionEquipmentData.TYPE_TOOL and ExpeditionEquipmentData.get_effect_id(id) == effect:
				return "필수 도구 · %s: 이미 보유하고 있습니다. 원정 준비의 보유 장비에서 가방에 넣으세요. 다시 살 필요는 없습니다." % ItemData.get_item_name(id)
	return "필수 도구 · %s: 타블렌의 노점 [E]에서 구매하고 원정 가방에 넣으세요." % name

static func destination(world: Node) -> Node2D:
	if world == null or waiting_text().is_empty(): return null
	if not ResidentStoryFlow.introduction_read("peddler"):
		var objects := world.get_node_or_null("Objects")
		if objects != null:
			for object in objects.get_children():
				if object.is_in_group("door") and _available_target(object): return object
	elif ResidentRequestFlow.done("settle_naru"):
		if VillageLifeFlow.friendship("naru") < 1:
			var life := world.get_node_or_null("VillageLifeDirector")
			if life != null:
				var resident = life.residents.get("naru")
				if _available_target(resident): return resident
		else:
			var stall := VillageSettlement.find_site(world,ResidentTradeFlow.SETTINGS.site)
			if _available_target(stall): return stall
	return null

# The 3D mirror hides 2D village containers. Individual target visibility
# still expresses whether a site is unlocked/present in the game world.
static func _available_target(node: Variant) -> bool:
	return is_instance_valid(node) and node is Node2D and node.is_inside_tree() and node.visible and not node.is_queued_for_deletion() and not node.get_meta("is_build_preview",false)
