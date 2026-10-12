class_name NpcSpriteArt
extends RefCounted
## 이름 있는 NPC의 정지 그림. 준비한 추가 방향을 읽고, 누락 시 기존 한 방향으로 표시한다.
const DATA_PATH := "res://data/art/npc_sprite_assets.json"
const PREFIX := "npc:"
static var _assets: Dictionary = {}
static var _loaded := false


static func assets() -> Dictionary:
	if not _loaded:
		_loaded = true
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
		if parsed is Dictionary: _assets = parsed
	return _assets


static func key_for(id: String) -> String:
	if id == "neighbor": id = "neighbor_bread" # 기존 story_npcs.csv 인물 ID
	return PREFIX + id if assets().has(id) else ""


static func identity(actor: Node) -> String:
	if actor is CheckoutGuideCustomer: return key_for("delvin")
	if actor is StoryNpc: return key_for(str(actor.beat.get("npc_id", "")))
	if actor is VillageResident:
		var id: String = str(actor.get_meta("fishing_owner", actor.resident_id))
		if id.begins_with("fishing_visitor:"): id = id.trim_prefix("fishing_visitor:")
		return key_for(id)
	return key_for(str(actor.get_meta("npc_id", "")))


static func load_set(key: String) -> Dictionary:
	if not key.begins_with(PREFIX): return {}
	var id := key.trim_prefix(PREFIX)
	if not assets().has(id): return {}
	var row: Dictionary = assets()[id]
	var directional := NpcDirectionArt.load_set(id,row)
	if not directional.is_empty(): return directional
	var path := str(row.path)
	if not ResourceLoader.exists(path): return {}
	var texture := load(path) as Texture2D
	if texture == null: return {}
	var bounds := texture.get_image().get_used_rect()
	if bounds.size.x <= 0 or bounds.size.y <= 0: return {}
	var feet := Vector2(float(row.feet[0]), float(row.feet[1]))
	var direction := str(row.direction)
	var frame := {"texture": texture, "bounds": bounds, "path": path}
	var result := {"directions": {direction: {"idle": frame, "walk": [],
		"anchor": feet - texture.get_size() * 0.5}}, "static_direction": direction,
		"reference_height": feet.y - float(bounds.position.y)}
	if row.has("display_height"): result["display_height"] = float(row.display_height)
	return result
