class_name RegisterRestockGuide
extends RefCounted
## A sold-out assignment needs a location and a next action, not extra stock.
const ENABLED := true

static func note(world: Node, product: Dictionary) -> String:
	if not ENABLED or world == null or int(product.get("stock", 0)) > 0: return ""
	var item := str(product.get("item_id", ""))
	if not ItemData.has_item(item): return ""
	var lines: Array[String] = []
	var carried := GameState.get_item_count(item)
	if carried > 0: lines.append(UiText.f("register.restock.carried", [carried]))
	var stored := ProductPreparationData.shelf_count(world, item)
	if stored > 0: lines.append(UiText.f("register.restock.warehouse", [stored]))
	for id in ["fridge", "freezer"]:
		if not PreservationService.installed(id): continue
		var amount := int(GameState.preservation_state.get(id, {}).get(item, 0))
		if amount > 0:
			lines.append(UiText.f("register.restock.fridge", [amount]) if id == "fridge" else UiText.f("register.restock.freezer", [amount]))
	if lines.is_empty():
		lines.append(UiText.t("register.restock.empty"))
		# Show only an existing acquisition path or an already learned recipe.
		if FishingData.fish(item) or ItemData.get_item_type(item) == ItemData.ITEM_TYPE_MATERIAL or InventoryItemGuide.learned_result(item):
			var acquire := InventoryItemGuide.acquire(item)
			if not acquire.is_empty(): lines.append(acquire)
	return UiText.t("register.restock.heading") + "\n" + "\n".join(lines)
