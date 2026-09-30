class_name NpcInterventionSelector
extends RefCounted


# 선물이 있는 도움 장면과 선물이 없는 힌트 장면을 같은 조건으로 고른다.
# CSV 순서가 기존 장면의 우선순위다.
static func find_available(tree: SceneTree) -> Dictionary:
	for beat in StoryData.get_beats():
		if is_available(beat, tree):
			return beat

	return {}


static func is_available(beat: Dictionary, tree: SceneTree) -> bool:
	var beat_id: String = str(beat.get("beat_id", ""))
	var npc_id: String = str(beat.get("npc_id", ""))
	var lines: Variant = beat.get("lines", [])
	var conditions: Variant = beat.get("conditions", [])
	var gifts: Variant = beat.get("gifts", [])

	if beat_id.is_empty() or npc_id.is_empty():
		return false

	if StoryData.get_npc(npc_id).is_empty():
		return false

	if not lines is Array or lines.is_empty():
		return false

	var has_dialogue: bool = false
	for line in lines:
		if not str(line).strip_edges().is_empty():
			has_dialogue = true
			break

	if not has_dialogue:
		return false

	if not conditions is Array or not gifts is Array:
		return false

	if not PlayerProgress.can_play_story_beat(
		beat_id,
		int(beat.get("repeat_days", 0)),
		GameState.total_day
	):
		return false

	return StoryConditions.are_met(conditions, tree)


static func kind_of(beat: Dictionary) -> String:
	var gifts: Variant = beat.get("gifts", [])
	return "help" if gifts is Array and not gifts.is_empty() else "hint"
