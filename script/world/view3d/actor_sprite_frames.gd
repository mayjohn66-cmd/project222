class_name ActorSpriteFrames
extends RefCounted
## 제공 PNG를 그대로 읽고 캔버스 여백을 제거한다. 발 기준점과 배율은 걷기 중 고정한다.

const ROOT := "res://art/actors/"
const DIRECTIONS := ["south", "south-east", "east", "north-east", "north", "north-west", "west", "south-west"]
const KEYS := ["worker_001", "worker_002", "worker_003", "normal", "traveler", "adventurer", "miner", "herbalist", "child", "collector", "marsh_local"]
const FRAME_COUNT := 8
static var _cache: Dictionary = {}


static func load_set(key: String) -> Dictionary:
	if _cache.has(key):
		return _cache[key]
	if key not in KEYS:
		return {}
	var directions: Dictionary = {}
	var reference_height := 0.0
	for direction in DIRECTIONS:
		var idle := _frame(ROOT + key + "/rotations/" + direction.replace("-", "_") + ".png")
		if idle.is_empty():
			return _missing(key)
		var anchor: Vector2 = _feet(idle.texture.get_image(), idle.bounds) - idle.texture.get_size() * 0.5
		var frames: Array[Dictionary] = []
		var poses: Array[Dictionary] = [idle]
		for index in FRAME_COUNT:
			var frame := _frame(ROOT + key + "/animations/walk/" + direction + "/frame_%03d.png" % index)
			if frame.is_empty():
				return _missing(key)
			frames.append(frame)
			poses.append(frame)
		for pose in poses:
			# Idle is 64px; walk canvases are 84/88/92px with centered padding.
			var top: float = float(pose.bounds.position.y) - pose.texture.get_height() * 0.5
			reference_height = maxf(reference_height, anchor.y - top)
		directions[direction] = {"idle": idle, "walk": frames, "anchor": anchor}
	var result := {"directions": directions, "reference_height": reference_height}
	_cache[key] = result
	return result


static func _frame(path: String) -> Dictionary:
	if not ResourceLoader.exists(path):
		return {}
	var texture := load(path) as Texture2D
	if texture == null:
		return {}
	var bounds := texture.get_image().get_used_rect()
	if bounds.size.x == 0 or bounds.size.y == 0:
		return {}
	return {"texture": texture, "bounds": bounds, "path": path}


static func _feet(image: Image, bounds: Rect2i) -> Vector2:
	var left := image.get_width()
	var right := -1
	for y in range(maxi(bounds.position.y, bounds.end.y - 3), bounds.end.y):
		for x in range(bounds.position.x, bounds.end.x):
			if image.get_pixel(x, y).a >= 0.5:
				left = mini(left, x)
				right = maxi(right, x)
	var center := (float(left + right) + 1.0) * 0.5 if right >= left else float(bounds.get_center().x)
	return Vector2(center, bounds.end.y)


static func _missing(key: String) -> Dictionary:
	push_warning("[ActorSpriteFrames] 불완전한 그림 묶음, 기존 3D 인물 사용: " + key)
	_cache[key] = {}
	return {}


## Facing yaw is world X/Z; artwork directions are screen compass directions.
static func direction_for(facing_yaw: float, camera_yaw: float) -> String:
	var index := posmod(int(floor((facing_yaw - camera_yaw + 22.5) / 45.0)), DIRECTIONS.size())
	return DIRECTIONS[index]
