class_name InventoryCountSlots
extends RefCounted
## Derived compatibility view only: no storage capacity or save fields change.
## Ordinary stock is already counted and displayed dynamically by the live UI.
static func build(counts: Dictionary, minimum_slots: int, stack_limit: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var ids: Array[String] = []
	for raw_id in counts:
		var id := str(raw_id)
		if ItemData.has_item(id) and int(counts[raw_id]) > 0: ids.append(id)
	ids.sort()
	for id in ids:
		var remaining := int(counts[id])
		while remaining > 0:
			var amount := mini(remaining,maxi(1,stack_limit))
			result.append({"item_id":id,"amount":amount})
			remaining -= amount
	while result.size() < maxi(0,minimum_slots):
		result.append({"item_id":"","amount":0})
	return result
