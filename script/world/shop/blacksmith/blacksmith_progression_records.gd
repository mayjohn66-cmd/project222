class_name BlacksmithProgressionRecords
extends RefCounted
const PREFIX := "blacksmith_progress:"
static func has(key: String) -> bool: return PlayerProgress.story_beat_days.has(PREFIX + key)
static func mark(key: String) -> void: PlayerProgress.record_story_beat(PREFIX + key, GameState.total_day)
static func value(key: String) -> int: return int(PlayerProgress.story_beat_days.get(PREFIX + key, 0))
static func new_game() -> void: mark("version")
static func legacy() -> bool: return not has("version")
static func returns() -> int: return value("returns")
static func enhanced() -> void:
	if has("first_enhanced"): return
	mark("first_enhanced")
	PlayerProgress.story_beat_days[PREFIX + "enhanced_return"] = returns()
static func deposited(context: Dictionary, item: Dictionary) -> void:
	if not context.get("explored", false): return
	if item.get("item_id", "") == "iron_ore" and item.get("blacksmith_ore_origin", false) and int(item.get("amount", 0)) > 0:
		mark("ore_returned")
static func returned(context: Dictionary) -> void:
	if not context.get("explored", false): return
	var receipt := "return_day:" + str(GameState.total_day)
	if has(receipt): return
	mark(receipt)
	PlayerProgress.story_beat_days[PREFIX + "returns"] = returns() + 1
