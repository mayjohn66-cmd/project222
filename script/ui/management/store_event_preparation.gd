class_name StoreEventPreparation
extends RefCounted
## 들은 소문의 상품 재고를 확인한다. 판매 예측이나 준비 할당량은 만들지 않는다.
const ENABLED := true

static func items(event: Dictionary) -> Array[String]:
	var result: Array[String] = []
	var id := str(event.get("event_id",""))
	if not ENABLED or not StoreEventData.is_discovered_for_occurrence(id,GameState.total_day): return result
	var current := StoreEventData.get_event_occurrence(id,GameState.total_day)
	if event.get("occurrence_id",current["occurrence_id"]) != current["occurrence_id"]: return result
	if GameState.total_day < int(current["discovery_start_day"]) or GameState.total_day > int(current["end_day"]): return result
	if id.begins_with("fish_store_") and not FishingContent.store_available(id): return result
	var moment := StoreEventStory.moment(id,StoreEventStory.phase(current,GameState.total_day))
	if moment.get("cue_items",[]).is_empty(): moment = StoreEventStory.moment(id,"rumor")
	for raw in moment.get("cue_items",[]):
		var item := str(raw)
		if ItemData.has_item(item) and ItemData.is_sellable(item) and item not in result: result.append(item)
	return result

static func displayed(world: Node, item: String) -> int:
	var amount := 0
	for shelf in world.get_tree().get_nodes_in_group("shelf"):
		if not is_instance_valid(shelf) or shelf.is_queued_for_deletion() or not world.is_ancestor_of(shelf) or shelf.get_meta("is_build_preview",false): continue
		if shelf.has_method("get_item_stock"): amount += shelf.get_item_stock(item)
	return amount

static func recipes(item: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for recipe in ProductRecipeData.get_learned_recipes():
		if str(recipe["result_item_id"]) == item: result.append(recipe)
	return result

static func summary(world: Node, event: Dictionary) -> String:
	var lines: Array[String] = []
	var food := false
	for item in items(event):
		var stock := GameState.get_item_count(item)
		var on_shelf := displayed(world,item)
		lines.append("%s · 진열 %d개 / 소지 %d개" % [ItemData.get_item_name(item),on_shelf,stock])
		var stored := ProductPreparationData.shelf_count(world,item)
		if stored > 0: lines.append("창고 선반 %d개 · 현장에서 꺼내기" % stored)
		var cold := ProductPreparationData.preservation_note(item)
		if not cold.is_empty(): lines.append(cold)
		if on_shelf > 0: lines.append("진열 중 · 판매 뒤에는 재고를 보충해 주세요.")
		elif stock > 0: lines.append("소지 상품을 진열대에 보충해 주세요.")
		else:
			lines.append("보관 중인 상품은 꺼낸 뒤 진열해 주세요." if stored > 0 or not cold.is_empty() else "상품을 마련한 뒤 진열해 주세요.")
			if stored == 0 and cold.is_empty():
				var next := StoreEventNextStepGuide.missing(item)
				if not next.is_empty(): lines.append(next)
		food = food or FoodShelfLife.tracked(item)
	if lines.is_empty(): return ""
	if food: lines.append("식품은 기한을 살피며 조금씩 보충해 주세요.")
	return "[소문을 듣고 살펴본 상품]\n" + "\n".join(lines) + "\n\n보관 상품은 꺼내서 진열해야 팔 수 있어요."
