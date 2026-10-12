class_name ActorPoseArt
extends RefCounted
## 실제로 제작된 의상/자세만 읽는다. 좌식은 서 있는 그림의 기준 높이를 공유한다.
const DATA_PATH := "res://data/art/actor_pose_assets.json"
const PREFIX := "pose:"
static var _assets: Dictionary = {}
static var _loaded := false

static func assets() -> Dictionary:
	if not _loaded:
		_loaded = true
		var data = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
		if data is Dictionary: _assets = data
	return _assets

static func key_for(actor: Node, look_key: String) -> String:
	var id := ""
	if bool(actor.get_meta("sitting", false)):
		if look_key == "player": id = "player_" + PlayerProgress.player_gender
		else: id = NpcSpriteArt.identity(actor).trim_prefix(NpcSpriteArt.PREFIX)
		var kind := str(actor.get_meta("sit_kind", "seat"))
		var direction := str(actor.get_meta("seat_direction", ""))
		if direction.is_empty():
			var face: Vector2 = actor.get_meta("face_dir", Vector2(0,1))
			var projected := ActorSpriteFrames.direction_for(rad_to_deg(atan2(face.x,face.y)),45.0)
			direction = "south-west" if kind == "floor" else projected
			if direction == "south": direction = "south-west"
			elif direction == "north": direction = "north-west"
			elif direction == "west": direction = "south-west"
			elif direction == "east": direction = "south-east"
		id += ":" + kind + ":" + direction
	elif look_key == "commuter" and actor.has_meta("look_key"): id = "commuter"
	elif actor is VillageResident and actor.resident_id == "village_blacksmith": id = "blacksmith"
	return PREFIX+id if assets().has(id) else ""

static func load_set(key: String) -> Dictionary:
	if not key.begins_with(PREFIX): return {}
	var row: Dictionary = assets().get(key.trim_prefix(PREFIX), {})
	if row.is_empty() or not ResourceLoader.exists(str(row.path)): return {}
	if str(row.get("pose","")) == "standing":
		var directional := NpcDirectionArt.load_set(key.trim_prefix(PREFIX),row)
		if not directional.is_empty(): return directional
	var texture := load(str(row.path)) as Texture2D
	if texture == null: return {}
	var bounds := texture.get_image().get_used_rect()
	if bounds.size.x <= 0 or bounds.size.y <= 0: return {}
	var feet := Vector2(float(row.feet[0]), float(row.feet[1]))
	var direction := str(row.direction)
	var frame := {"texture":texture,"bounds":bounds,"path":str(row.path)}
	return {"directions":{direction:{"idle":frame,"walk":[],"anchor":feet-texture.get_size()*0.5}},
		"static_direction":direction,"reference_height":float(row.reference_height),
		"display_height":float(row.display_height)}
