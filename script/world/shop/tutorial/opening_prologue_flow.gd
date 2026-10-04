class_name OpeningPrologueFlow
extends RefCounted
const SETTINGS = preload("res://scenes/shop/tutorial/default_opening_prologue.tres")
const PREFIX := "opening_prologue:"

static func completed(id: String) -> bool:
	return PlayerProgress.story_beat_days.has(PREFIX + id)
static func current() -> Dictionary:
	# Only genuine new-game bootstrap opts in; existing saves keep their place.
	if not PlayerProgress.story_beat_days.has(OpeningJourneyFlow.PROLOGUE): return {}
	for key in PlayerProgress.story_beat_days:
		if str(key).begins_with("tutorial_step:") or str(key) == CheckoutTutorial.BEAT_ID: return {}
	for moment in SETTINGS.moments:
		if not completed(str(moment["id"])): return moment
	return {}
static func pending() -> bool: return not current().is_empty()
static func complete(id: String) -> bool:
	if current().get("id","") != id: return false
	PlayerProgress.record_story_beat(PREFIX + id,GameState.total_day)
	return true
