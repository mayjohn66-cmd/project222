class_name VillageLifeFlow
extends RefCounted

const SETTINGS = preload("res://scenes/shop/requests/default_village_life.tres")
const PREFIX := "village_life:"

static func entries() -> Array[Dictionary]:
	var result: Array[Dictionary] = SETTINGS.residents.duplicate(true)
	result.append_array(VillageExpansionFlow.SETTINGS.residents)
	return result

static func resident(id: String) -> Dictionary:
	for entry in entries():
		if str(entry["id"]) == id: return RequestTextData.enrich(entry, "resident_greeting")
	return {}

static func available(entry: Dictionary) -> bool:
	if entry.has("expansion_event"): return ResidentRequestFlow.tutorial_finished() and VillageExpansionFlow.done(str(entry["expansion_event"]))
	return not entry.is_empty() and ResidentRequestFlow.tutorial_finished() and ResidentRequestFlow.done(str(entry["request"]))

static func greeted_today(id: String) -> bool:
	return PlayerProgress.story_beat_days.get(PREFIX + "greeted:" + id, -1) == GameState.total_day

static func friendship(id: String) -> int:
	return maxi(0, int(PlayerProgress.story_beat_days.get(PREFIX + "friendship:" + id, 0)))

static func friendship_name(id: String) -> String:
	var title := "새 이웃"
	for index in range(SETTINGS.friendship_thresholds.size()):
		if friendship(id) >= SETTINGS.friendship_thresholds[index]: title = SETTINGS.friendship_names[index]
	return title

static func greet(id: String) -> Dictionary:
	var entry := resident(id)
	if not available(entry): return {}
	var first := not greeted_today(id)
	var reward := ""
	if first:
		PlayerProgress.record_story_beat(PREFIX + "greeted:" + id, GameState.total_day)
		PlayerProgress.story_beat_days[PREFIX + "friendship:" + id] = friendship(id) + 1
		var item := str(entry["gift"])
		var amount := maxi(0, int(entry["amount"]))
		if amount > 0 and ItemData.has_item(item):
			GameState.add_item(item, amount)
			reward = "%s ×%d" % [ItemData.get_item_name(item), amount]
	return {"first":first, "gift":reward, "friendship":friendship_name(id)}

static func well_used_today() -> bool:
	return PlayerProgress.story_beat_days.get(PREFIX + "well", -1) == GameState.total_day

static func draw_water() -> bool:
	if not ResidentRequestFlow.tutorial_finished() or not ResidentRequestFlow.done("settle_sora") or well_used_today(): return false
	if SETTINGS.well_amount <= 0 or not ItemData.has_item(SETTINGS.well_item): return false
	PlayerProgress.record_story_beat(PREFIX + "well", GameState.total_day)
	GameState.add_item(SETTINGS.well_item, SETTINGS.well_amount)
	return true
