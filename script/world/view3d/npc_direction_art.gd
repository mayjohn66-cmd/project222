class_name NpcDirectionArt
extends RefCounted
## 실제 준비한 방향별 정지 그림만 읽는다. 걷기 프레임은 만들어 채우지 않는다.
const DATA_PATH := "res://data/art/npc_direction_assets.json"
static var _assets: Dictionary = {}
static var _loaded := false


static func assets() -> Dictionary:
	if not _loaded:
		_loaded = true
		if FileAccess.file_exists(DATA_PATH):
			var parsed = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
			if parsed is Dictionary: _assets = parsed
	return _assets


static func load_set(identity: String, base_row: Dictionary) -> Dictionary:
	var row: Dictionary = assets().get(identity,{})
	if row.is_empty(): return {}
	var directions: Dictionary = {}
	for direction in ActorSpriteFrames.DIRECTIONS:
		var pose: Dictionary = row.get("directions",{}).get(direction,{})
		var path := str(pose.get("path",""))
		if path.is_empty() or not ResourceLoader.exists(path): return {}
		var texture := load(path) as Texture2D
		if texture == null: return {}
		var bounds := texture.get_image().get_used_rect()
		if bounds.size.x <= 0 or bounds.size.y <= 0: return {}
		var feet := Vector2(float(pose.feet[0]),float(pose.feet[1]))
		directions[direction] = {"idle":{"texture":texture,"bounds":bounds,"path":path},
			"walk":[],"anchor":feet-texture.get_size()*0.5}
	var result := {"directions":directions,"reference_height":float(row.reference_height),"directional_idle":true}
	if base_row.has("display_height"): result["display_height"] = float(base_row.display_height)
	return result
