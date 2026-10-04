class_name RegularCustomerRecords
extends RefCounted

# Small purchase records; no dependency on the dialogue director or customer script.
const SETTINGS = preload("res://scenes/shop/requests/default_regular_customers.tres")
const PREFIX := "regular_customer:"
static func key(id: String, stage: String) -> String: return PREFIX + id + ":" + stage
static func has(id: String, stage: String) -> bool: return PlayerProgress.story_beat_days.has(key(id,stage))
static func day(id: String, stage: String) -> int: return int(PlayerProgress.story_beat_days.get(key(id,stage),-1))
static func event(id: String) -> Dictionary:
	for entry in SETTINGS.events:
		if str(entry["id"]) == id: return entry
	return {}
static func record_sale(customer: Node, item: String, amount: int) -> bool:
	var id := str(customer.get_meta("regular_story_id",""))
	var entry := event(id)
	if entry.is_empty() or item != str(entry["purchase_item"]) or amount <= 0: return false
	if customer.get_customer_type_id() != str(entry["type"]): return false
	var stage := str(customer.get_meta("regular_story_purchase",""))
	if stage == "first" and not has(id,"first"):
		PlayerProgress.record_story_beat(key(id,"first"),GameState.total_day)
		return true
	if stage == "repeat" and has(id,"intro") and not has(id,"repeat") \
			and GameState.total_day >= day(id,"intro") + int(entry["days_after"]) \
			and amount >= int(entry["repeat_amount"]):
		PlayerProgress.record_story_beat(key(id,"repeat"),GameState.total_day)
		return true
	return false
