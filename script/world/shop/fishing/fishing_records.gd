class_name FishingRecords
extends RefCounted
# Only integer records, compatible with the existing optional story save map.
const PREFIX := "fishing:"
static func has(key: String) -> bool:
	return PlayerProgress.story_beat_days.has(PREFIX + key)
static func mark(key: String) -> void:
	PlayerProgress.record_story_beat(PREFIX + key, GameState.total_day)
static func done(id: String) -> bool: return has(id + ":done")
static func accepted(id: String) -> bool: return has(id + ":accepted")
static func caught(item: String) -> void:
	if not FishingData.fish(item): return
	mark("caught:" + item)
	mark("catch")
static func sold(item: String, amount: int) -> void:
	if amount <= 0: return
	if FishingData.fish(item): mark("sale")
	for e in FishingData.entries("store_events"):
		var id := str(e["id"])
		var store = load("res://script/data/shop/events/store_event_data.gd")
		if e["products"].has(item) and store.is_event_active(id, GameState.total_day) \
			and store.is_discovered_for_occurrence(id, GameState.total_day):
			mark("receipt:" + id + ":" + str(CalendarData.get_year(GameState.total_day)))
static func stored(item: String, amount: int) -> void:
	if amount > 0 and FishingData.fish(item) and accepted("fishing_keep"):
		mark("kept")
static func collected(item: String, amount: int) -> void:
	if amount <= 0: return
	for g in FishingData.entries("goods"):
		if str(g["id"]) == item:
			mark("collected:" + item)
			if item == "fish_dried" and accepted("fishing_keep"): mark("kept")
static func discovered(seasonal_only: bool = false) -> int:
	var count := 0
	for f in FishingData.entries("fish"):
		if has("caught:" + str(f["id"])) and (not seasonal_only or f["seasons"].size() == 1): count += 1
	return count
static func recipe_available(id: String) -> bool:
	var info := FishingData.variant(id)
	return info.is_empty() or PlayerProgress.is_recipe_learned(str(info["base"]))

static func market_item_available(item: String) -> bool:
	if not item.begins_with("fish_"): return true
	if FishingData.fish(item): return has("caught:" + item)
	for recipe in FishingData.entries("recipes"):
		if str(recipe["result_item_id"]) == item: return PlayerProgress.is_recipe_learned(str(recipe["id"]))
	return true
