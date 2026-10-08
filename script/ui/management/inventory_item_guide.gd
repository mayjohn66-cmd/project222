class_name InventoryItemGuide
extends RefCounted

## 가진 물품을 실제 진열·보관·배운 가공 흐름에 연결한다.
const ENABLED := true

static func world(from: Node) -> Node:
	var node := from
	while node != null:
		if node.scene_file_path == "res://scenes/shop/main.tscn": return node
		node = node.get_parent()
	return null

static func learned_outputs(item: String) -> Array[String]:
	var outputs: Array[String] = []
	if not ShopSpaceProgression.production_introduced(): return outputs
	for recipe in ProductRecipeData.get_learned_recipes():
		for ingredient in recipe["ingredients"]:
			if str(ingredient["item_id"]) != item: continue
			var output := str(recipe["result_item_id"])
			if output not in outputs: outputs.append(output)
			break
	return outputs

static func learned_result(item: String) -> bool:
	if not ShopSpaceProgression.production_introduced(): return false
	for recipe in ProductRecipeData.get_learned_recipes():
		if str(recipe["result_item_id"]) == item: return true
	return false

static func acquire(item: String) -> String:
	if not ENABLED or not ItemData.has_item(item): return ""
	var kind := ItemData.get_item_type(item)
	if FishingData.fish(item): return "획득 경로 · 물가에서 낚시"
	if kind == ItemData.ITEM_TYPE_MATERIAL:
		return "획득 경로 · 배운 제조법으로 가공" if learned_result(item) else "획득 경로 · 채집·원정 등"
	if kind == ItemData.ITEM_TYPE_STORE_PRODUCT:
		if not ShopSpaceProgression.production_introduced(): return "제작 안내를 들은 뒤 제조법을 확인하세요."
		return "제작 상태 · 배운 제조법에서 확인 가능" if learned_result(item) else "제작 상태 · 지금 배운 제조법 없음"
	return ""

static func note(from: Node, item: String) -> String:
	if not ENABLED or not ItemData.has_item(item): return ""
	var lines: Array[String] = []
	var shop := world(from)
	var carried := GameState.get_item_count(item)
	if ItemData.is_sellable(item) and ItemData.is_shelf_allowed(item):
		if ItemData.get_item_type(item) == ItemData.ITEM_TYPE_MATERIAL:
			lines.append("가공하지 않고도 진열해 팔 수 있는 재료입니다.")
		else:
			lines.append("진열대에 놓아야 손님이 고를 수 있습니다.")
		var displayed := StoreEventPreparation.displayed(shop,item) if shop != null else 0
		if displayed > 0: lines.append("진열 %d개 · 손님이 집어 계산하면 판매됩니다." % displayed)
		if carried > 0: lines.append("소지 %d개 · 진열대에서 [E]로 보충하세요." % carried)
		if shop != null:
			var stored := ProductPreparationData.shelf_count(shop,item)
			if stored > 0: lines.append("창고 선반 %d개 · 현장에서 꺼내야 사용할 수 있어요." % stored)
		var cold := ProductPreparationData.preservation_note(item)
		if not cold.is_empty(): lines.append(cold)
	elif not ItemData.is_sellable(item):
		lines.append("이 물품은 가게에서 판매하는 상품이 아닙니다.")
	elif not ItemData.is_shelf_allowed(item):
		lines.append("이 물품은 진열대에 놓을 수 없습니다.")
	var material := PreservationGuide.material(item)
	if not material.is_empty():
		lines.append(PreservationGuide.ambient_hint(item))
	if FoodShelfLife.tracked(item):
		var unit := "냉장" if not bool(FoodShelfLife.rules()[item]["freezable"]) else "냉장·냉동"
		lines.append("기한이 있는 물품 · %s 보관과 진열량을 함께 살펴보세요." % unit)
	var outputs := learned_outputs(item)
	if not outputs.is_empty():
		var names: Array[String] = []
		for id in outputs.slice(0,2): names.append(ItemData.get_item_name(id))
		lines.append("배운 가공에 사용 · %s%s" % ["·".join(names)," 외" if outputs.size() > 2 else ""])
	var notes: Dictionary = ProductPreparationContext.notes()
	if notes.has(item):
		lines.append("지금 연결된 이야기 · " + " / ".join(notes[item].slice(0,2)))
	return "[지금 할 수 있는 일]\n" + "\n".join(lines) if not lines.is_empty() else ""
