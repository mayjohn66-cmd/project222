class_name ExpeditionPlayerAttackArt
extends RefCounted
## Basic sword motion only; equipment stats and hit timing stay in the model.
const PLAYBACK := [1, 2, 3, 0] # Existing immediate hit: strike is the first pose.
const PHASE_ENDS := [0.16, 0.40, 0.75, 1.0]
static var _cache: Dictionary = {}


static func frames(player_key: String, direction: String) -> Array[Dictionary]:
	var key := player_key+"/"+direction
	if _cache.has(key): return _cache[key]
	var result: Array[Dictionary] = []
	if player_key not in ["player_male", "player_female"] or direction not in ActorSpriteFrames.DIRECTIONS:
		return result
	for index in range(4):
		var path := "res://art/actors/%s/animations/attack/%s/frame_%03d.png" % [player_key, direction, index]
		if not ResourceLoader.exists(path): return []
		var texture := load(path) as Texture2D
		if texture == null: return []
		result.append({"texture":texture, "bounds":texture.get_image().get_used_rect(), "path":path})
	_cache[key] = result
	return result


static func pose(player_key: String, direction: String, progress: float) -> Dictionary:
	var available := frames(player_key,direction)
	if available.is_empty(): return {}
	var index := 3
	for i in range(PHASE_ENDS.size()):
		if progress < PHASE_ENDS[i]:
			index = i
			break
	return available[PLAYBACK[index]]
