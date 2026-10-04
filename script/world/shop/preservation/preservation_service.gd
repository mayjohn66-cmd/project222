class_name PreservationService
extends RefCounted

const SETTINGS = preload("res://scenes/shop/preservation/default_preservation.tres")

static func initial_state(day: int) -> Dictionary:
	return {"last_day":day,"installed":[],"fridge":{},"freezer":{},"notices":[]}

static func unit(id: String) -> Dictionary:
	for entry in SETTINGS.units:
		if entry["id"] == id: return entry
	return {}

static func installed(id: String) -> bool:
	return GameState.preservation_state.get("installed", []).has(id)

static func count(id: String) -> int:
	var total := 0
	for amount in GameState.preservation_state.get(id, {}).values(): total += int(amount)
	return total

static func install(id: String) -> bool:
	var entry := unit(id)
	if entry.is_empty() or installed(id) or not GameState.spend_money(int(entry["cost"])): return false
	GameState.preservation_state["installed"].append(id)
	return true

static func deposit(id: String, item: String, amount: int = 1) -> int:
	settle()
	var entry := unit(id)
	if entry.is_empty() or not installed(id) or not entry["accepts"].has(item) or amount <= 0: return 0
	var moved := mini(amount, mini(GameState.get_item_count(item), int(entry["capacity"]) - count(id)))
	if moved <= 0: return 0
	var removed := GameState.remove_item(item, moved)
	var contents: Dictionary = GameState.preservation_state[id]
	contents[item] = int(contents.get(item, 0)) + removed
	return removed

static func withdraw(id: String, item: String, amount: int = 1) -> int:
	settle()
	if unit(id).is_empty() or not installed(id) or amount <= 0: return 0
	var contents: Dictionary = GameState.preservation_state[id]
	var moved := mini(amount, int(contents.get(item, 0)))
	if moved <= 0: return 0
	contents[item] = int(contents[item]) - moved
	if contents[item] == 0: contents.erase(item)
	GameState.add_item(item, moved)
	return moved

static func valid_state(value: Variant, day: int) -> bool:
	if not value is Dictionary: return false
	if not value.get("last_day") is int or int(value["last_day"]) < 1 or int(value["last_day"]) > day: return false
	if not value.get("installed") is Array or not value.get("notices") is Array: return false
	var ids: Array = value["installed"]
	var seen: Array = []
	for id in ids:
		if not id is String or unit(id).is_empty() or seen.has(id): return false
		seen.append(id)
	for entry in SETTINGS.units:
		var id := str(entry["id"])
		if not value.get(id) is Dictionary: return false
		var total := 0
		for item in value[id]:
			if not entry["accepts"].has(item) or not value[id][item] is int or int(value[id][item]) <= 0: return false
			total += int(value[id][item])
		if total > int(entry["capacity"]) or (total > 0 and not ids.has(id)): return false
	for notice in value["notices"]:
		if not notice is String: return false
	return value["notices"].size() <= 10

# Daily rules deliberately avoid per-item timers: plants change outside their harvest
# season, ice changes at the next dawn. Moving warm stock never refreshes a timer.
# Cold stock is separate ownership, not a flag on all stock with the same item ID.
static func settle() -> void:
	var state: Dictionary = GameState.preservation_state
	if state.is_empty():
		GameState.preservation_state = initial_state(GameState.total_day)
		return
	var previous := int(state["last_day"])
	var today: int = GameState.total_day
	if today <= previous: return
	state["last_day"] = today # Guard against inventory queries during refresh.
	var changes: Dictionary = {}
	for rule in SETTINGS.materials:
		if _crossed_change_day(rule, previous, today): changes[str(rule["item"])] = str(rule["result"])
	if changes.is_empty(): return
	var converted: Dictionary = {}
	for item in changes:
		var amount := int(GameState.inventory.get(item, 0))
		if amount <= 0: continue
		GameState.inventory[item] = 0
		var result := str(changes[item])
		GameState.inventory[result] = int(GameState.inventory.get(result, 0)) + amount
		converted[item] = amount
	var tree := GameState.get_tree()
	# Saved layout is also transformed while the store scene is absent (expedition).
	for entry in GameState.store_layout:
		for key in ["shelf_slots", "storage_slots", "warehouse_slots"]:
			_transform_slots(entry.get(key, []), changes)
	if tree != null:
		for shelf in tree.get_nodes_in_group("shelf"):
			if shelf.is_queued_for_deletion() or bool(shelf.get_meta("is_build_preview", false)): continue
			_merge_counts(converted, _transform_slots(shelf.slots, changes))
			shelf.update_stock_label()
		for storage in tree.get_nodes_in_group("warehouse_storage"):
			if storage.is_queued_for_deletion() or bool(storage.get_meta("is_build_preview", false)): continue
			_merge_counts(converted, _transform_slots(storage.storage_slots, changes))
			storage._rebuild_stored_items()
	for item in converted:
		state["notices"].append("%d일차 · %s %d개 → %s (상온 보관)" % [today, ItemData.get_item_name(item), converted[item], ItemData.get_item_name(changes[item])])
	while state["notices"].size() > 10: state["notices"].pop_front()
	GameState.rebuild_inventory_slots_from_counts()

static func _crossed_change_day(rule: Dictionary, previous: int, today: int) -> bool:
	var season := str(rule["season"])
	if season.is_empty() or today - previous > CalendarData.DAYS_PER_SEASON: return true
	for day in range(previous + 1, today + 1):
		if CalendarData.get_season_id(day) != season: return true
	return false

static func _transform_slots(slots: Array, changes: Dictionary) -> Dictionary:
	var counts: Dictionary = {}
	for slot in slots:
		var item := str(slot.get("item_id", ""))
		var amount := int(slot.get("stock", slot.get("amount", 0)))
		if amount <= 0 or not changes.has(item): continue
		slot["item_id"] = changes[item]
		counts[item] = int(counts.get(item, 0)) + amount
	return counts

static func _merge_counts(target: Dictionary, values: Dictionary) -> void:
	for item in values: target[item] = int(target.get(item, 0)) + int(values[item])
