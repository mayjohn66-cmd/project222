class_name PreservationLessonRecords
extends RefCounted

# Inventory and storage depend only on these small records, not village dialogue.
const SETTINGS = preload("res://scenes/shop/requests/default_preservation_lessons.tres")
const PREFIX := "preservation_lesson:"
static func key(id: String, stage: String) -> String: return PREFIX + id + ":" + stage
static func active(id: String) -> bool: return PlayerProgress.story_beat_days.has(key(id,"accepted")) and not PlayerProgress.story_beat_days.has(key(id,"done"))

static func record_found(item: String) -> void:
	for entry in SETTINGS.events:
		var matches := item == str(entry["raw"])
		for path in entry["paths"]:
			if str(path["item"]) == item: matches = true
		if matches: PlayerProgress.record_story_beat(key(str(entry["id"]),"found"),GameState.total_day)

static func record_deposit(unit: String, item: String, amount: int) -> void:
	if amount <= 0: return
	for entry in SETTINGS.events:
		var id := str(entry["id"])
		if str(entry["raw"]) != item or not active(id): continue
		var candidate := key(id,"stored:" + unit)
		if not PlayerProgress.story_beat_days.has(candidate): PlayerProgress.record_story_beat(candidate,GameState.total_day)

static func record_withdraw(unit: String, item: String, amount: int) -> void:
	if amount <= 0: return
	for entry in SETTINGS.events:
		var id := str(entry["id"])
		if str(entry["raw"]) != item or not active(id): continue
		var candidate := key(id,"stored:" + unit)
		if not PlayerProgress.story_beat_days.has(candidate): continue
		if GameState.total_day > int(PlayerProgress.story_beat_days[candidate]): PlayerProgress.record_story_beat(key(id,"practiced:cold"),GameState.total_day)
		if int(GameState.preservation_state.get(unit,{}).get(item,0)) <= 0: PlayerProgress.story_beat_days.erase(candidate)

static func record_output(item: String, amount: int) -> void:
	if amount <= 0: return
	for entry in SETTINGS.events:
		var id := str(entry["id"])
		if not active(id): continue
		for path in entry["paths"]:
			if str(path["id"]) == "dry" and str(path["item"]) == item: PlayerProgress.record_story_beat(key(id,"practiced:dry"),GameState.total_day)
