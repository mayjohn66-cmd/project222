class_name ExpeditionFoodBatches
extends RefCounted
## Food batches travel with their stock. Saved bags/checkpoints can be mirrors.
const ENABLED := true
const LIVE_GROUP := "expedition_food_owner"

static func valid_entry(entry: Dictionary, day: int) -> bool:
	var item := str(entry.get("item_id",""))
	if not FoodShelfLife.tracked(item):
		return not entry.has("food_batches") or (entry["food_batches"] is Array and entry["food_batches"].is_empty())
	if not entry.get("amount") is int or int(entry["amount"]) <= 0: return false
	# No batches is an older save or a newly acquired item, never a bad batch.
	return not entry.has("food_batches") or FoodShelfLife.valid_batches(entry["food_batches"],int(entry["amount"]),day)

static func valid_entries(entries: Variant, day: int) -> bool:
	if not ENABLED: return true
	if not entries is Array: return false
	for entry in entries:
		if not entry is Dictionary or not valid_entry(entry,day): return false
	return true

static func adopt(entry: Dictionary) -> void:
	if ENABLED and FoodShelfLife.tracked(str(entry.get("item_id",""))) and not entry.has("food_batches"):
		entry["food_batches"] = FoodShelfLife.fresh(int(entry["amount"]))

static func extra(item: String, amount: int, metadata: Dictionary) -> Dictionary:
	var entry := metadata.duplicate(true)
	entry["item_id"] = item
	entry["amount"] = amount
	if ENABLED:
		if not valid_entry(entry,GameState.total_day): return {"success":false}
		adopt(entry)
	return {"success":true,"data":entry}

static func batches(entry: Dictionary) -> Array:
	return entry.get("food_batches",[]).duplicate(true) if ENABLED else []

static func loot(entry: Dictionary) -> Dictionary:
	var result := entry.duplicate(true)
	for key in ["uid","cell","rotated"]: result.erase(key)
	adopt(result)
	return result

static func settle_entries(entries: Array, report: bool = true) -> bool:
	if not ENABLED or not valid_entries(entries,GameState.total_day): return false
	var changed := false
	for i in range(entries.size()-1,-1,-1):
		var entry: Dictionary = entries[i]
		var item := str(entry.get("item_id",""))
		if not FoodShelfLife.tracked(item): continue
		var previous := entry.duplicate(true)
		adopt(entry)
		var lots: Array = entry["food_batches"]
		FoodShelfLife._age(item,lots,FoodShelfLife.SETTINGS.ambient_age,report)
		entry["amount"] = FoodShelfLife.quantity(lots)
		if int(entry["amount"]) == 0: entries.remove_at(i)
		changed = changed or previous != entry
	return changed

static func settle_bag(bag: ExpeditionBag) -> void:
	if ENABLED and bag != null: settle_entries(bag.placements)

static func settle_owned_stock() -> void:
	if not ENABLED: return
	var tree := GameState.get_tree()
	var owner: Node = null
	if tree != null:
		for candidate in tree.get_nodes_in_group(LIVE_GROUP):
			if not candidate.is_queued_for_deletion() and candidate.get("expedition_bag") != null:
				owner = candidate
				break
	var checkpoint: Dictionary = GameState.expedition_checkpoint
	var historical: Variant = checkpoint.get("bag_placements",[])
	if owner != null:
		var changed := settle_entries(owner.expedition_bag.placements)
		var loot_changed := settle_entries(owner.temporary_loot)
		# While a room is open its pending drops own the stock; after exit they
		# are a stale copy of the already exposed temporary loot, not more stock.
		if owner.expedition_room_controller.is_active():
			settle_entries(owner.expedition_room_controller.pending_loot)
		if changed: owner.call_deferred("refresh_bag_ui")
		if loot_changed: owner.call_deferred("refresh_loot_ui")
		settle_entries(GameState.saved_expedition_bag,false)
		if historical is Array: settle_entries(historical,false)
	elif GameState.has_expedition_checkpoint() and checkpoint.has("bag_placements") and historical is Array:
		settle_entries(historical)
		settle_entries(GameState.saved_expedition_bag,false)
	else:
		settle_entries(GameState.saved_expedition_bag)
		if historical is Array: settle_entries(historical,false)

static func valid_save(data: Dictionary) -> bool:
	if not ENABLED: return true
	var day := int(data.get("total_day",data.get("current_day",1)))
	if not valid_entries(data.get("saved_expedition_bag",[]),day): return false
	var checkpoint: Variant = data.get("expedition_checkpoint",{})
	return not checkpoint is Dictionary or valid_entries(checkpoint.get("bag_placements",[]),day)
