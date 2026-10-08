class_name ExpeditionGatheringToolGuide
extends RefCounted

static func required_tool(table: String) -> String:
	var rule: Dictionary = ExpeditionGatheringData.get_rule(table)
	if not bool(rule.get("tool_required", false)): return ""
	var effect := str(rule.get("tool_effect_id", ""))
	for item in ExpeditionShopData.get_items_by_category(ExpeditionShopData.CATEGORY_TOOL):
		if ExpeditionEquipmentData.get_effect_id(item) == effect:
			return "필수 도구 · %s: 원정 준비의 [원정 상점] → 도구에서 구매하고 가방에 넣으세요." % ItemData.get_item_name(item)
	return "이 채집물에는 도구가 필요합니다. 출발 전에 가방을 확인하세요."
