class_name FishingService
extends RefCounted
static func has_rod() -> bool:
	return GameState.get_item_count("fishing_rod_wood") > 0 or GameState.get_item_count("fishing_rod_reinforced") > 0
static func capacity(item: String, amount: int = 1, removed: Dictionary = {}) -> bool:
	var stock := GameState.get_inventory_data()
	stock[item] = int(stock.get(item, 0)) + amount
	var slots := 0
	for id in stock:
		var count := maxi(0, int(stock[id]) - int(removed.get(id, 0)))
		slots += ceili(float(count) / GameState.PLAYER_INVENTORY_STACK_LIMIT)
	return slots <= GameState.PLAYER_INVENTORY_SLOT_COUNT
static func consume(requirements: Array, choices: Dictionary = {}) -> bool:
	var totals := selected(requirements, choices)
	if totals.is_empty() and not requirements.is_empty(): return false
	for id in totals:
		if GameState.get_item_count(str(id)) < int(totals[id]): return false
	# No yield between preflight and commit: expiry queries settle before removal.
	for id in totals: GameState.remove_item(str(id), int(totals[id]))
	return true
static func selected(requirements: Array, choices: Dictionary) -> Dictionary:
	var result := {}
	for i in requirements:
		var id := str(i.get("item_id", ""))
		if i.has("group_id"):
			var group := str(i["group_id"])
			id = str(choices.get(group, ""))
			if not FishingData.group(group).has(id): return {}
		if not ItemData.has_item(id) or int(i["amount"]) <= 0: return {}
		result[id] = int(result.get(id, 0)) + int(i["amount"])
	return result
static func make_rod(id: String, hour: float, weather: String) -> bool:
	var tool := FishingData.entry(id)
	if tool.is_empty() or id not in ["fishing_rod_wood", "fishing_rod_reinforced"]: return false
	if not FishingContent.conditions(tool, hour, weather) or FishingRecords.has("tool:" + id): return false
	if id == "fishing_rod_wood" and not FishingRecords.accepted("fishing_rod"): return false
	var required := selected(tool["materials"], {})
	if not capacity(id, 1, required) or not consume(tool["materials"]): return false
	GameState.add_item(id, 1)
	GameState.rebuild_inventory_slots_from_counts()
	FishingRecords.mark("tool:" + id)
	return true
static func pool(location: String, season: String, period: String, weather: String) -> Array:
	var result := []
	for f in FishingData.entries("fish"):
		if not f["locations"].has(location) or not f["seasons"].has(season): continue
		if not FishingRecords.has("catch") and f["rarity"] != "common": continue
		if str(f["time"]) not in ["all", period] or str(f["weather"]) not in ["all", weather]: continue
		result.append(f)
	return result
static func roll(location: String, hour: float, weather: String, rng: RandomNumberGenerator) -> String:
	var options := pool(location, CalendarData.get_season_id(GameState.total_day), EmployeeData.get_period_at_hour(int(hour)), weather)
	var total := 0.0
	for f in options: total += float(f["catch_weight"])
	if total <= 0: return ""
	var cursor := rng.randf() * total
	for f in options:
		cursor -= float(f["catch_weight"])
		if cursor <= 0: return str(f["id"])
	return str(options.back()["id"])
static func receive(item: String) -> bool:
	if not FishingData.fish(item) or not capacity(item): return false
	GameState.add_item(item, 1)
	GameState.rebuild_inventory_slots_from_counts()
	FishingRecords.caught(item)
	return true
