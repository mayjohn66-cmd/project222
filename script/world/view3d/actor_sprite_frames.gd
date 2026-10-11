class_name ActorSpriteFrames
extends RefCounted
## 제공 PNG를 그대로 읽고 캔버스 여백을 제거한다. 발 기준점과 배율은 걷기 중 고정한다.

const ROOT := "res://art/actors/"
const DIRECTIONS := ["south", "south-east", "east", "north-east", "north", "north-west", "west", "south-west"]
const KEYS := ["worker_001", "worker_002", "worker_003", "normal", "traveler", "adventurer", "miner", "herbalist", "child", "collector", "marsh_local", "player_male", "player_female"]
const FRAME_COUNT := 8
static var _cache: Dictionary = {}


static func load_set(key: String) -> Dictionary:
	if _cache.has(key):
		return _cache[key]
	if key.begins_with(ActorPoseArt.PREFIX):
		var pose_set := ActorPoseArt.load_set(key)
		_cache[key] = pose_set
		return pose_set
	if key.begins_with(NpcSpriteArt.PREFIX):
		var static_set := NpcSpriteArt.load_set(key)
		_cache[key] = static_set
		return static_set
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


## 땅에 닿는 기준점. 세로는 발 맨 아래, 가로는 **몸의 가운데 축**(머리 구간과 몸통 구간 불투명 픽셀 평균의 중간)이다.
## 예전에는 가로도 맨 아래 세 줄(발)의 가운데였는데, 비스듬한 방향에서는 몸이 발 중심에서 최대 7픽셀씩 어긋나
## 8방향을 돌려 볼 때 캐릭터 축이 좌우로 흔들려 보였다(2026-10-09). 모자·가방처럼 머리가 몸통에서 기운 그림도 한쪽으로 쏠리지 않게
## 머리와 몸통의 가운데를 쓴다.
static func _feet(image: Image, bounds: Rect2i) -> Vector2:
	var h := bounds.size.y
	var head_axis := _axis_x(image, bounds, bounds.position.y, bounds.position.y + int(float(h) * 0.30))
	var torso_axis := _axis_x(image, bounds, bounds.position.y + int(float(h) * 0.30), bounds.position.y + int(float(h) * 0.65))
	var axis: float = (head_axis + torso_axis) * 0.5 if head_axis >= 0.0 and torso_axis >= 0.0 else float(bounds.get_center().x)
	return Vector2(axis, bounds.end.y)


# 세로 구간 [top, bottom) 의 불투명 픽셀 가로 평균. 없으면 -1.
static func _axis_x(image: Image, bounds: Rect2i, top: int, bottom: int) -> float:
	var sum := 0.0
	var count := 0
	for y in range(top, bottom):
		for x in range(bounds.position.x, bounds.end.x):
			if image.get_pixel(x, y).a >= 0.5:
				sum += float(x) + 0.5
				count += 1
	return sum / float(count) if count > 0 else -1.0


static func _missing(key: String) -> Dictionary:
	push_warning("[ActorSpriteFrames] 불완전한 그림 묶음, 기존 3D 인물 사용: " + key)
	_cache[key] = {}
	return {}


const CAMERA_PITCH_DEG := 30.0 # 매장 카메라가 내려다보는 각도(StoreView3D.PITCH_DEG 와 같다)


## 그림 방향은 화면의 8방위(남=아래, 동=오른쪽 …)다. 월드 방향각을 그대로 45도씩 나누면 등각 시점에서
## 화면에 보이는 각도와 어긋나(남·북 그림이 약 80도, 동·서 그림이 약 23도를 차지) 360도로 돌릴 때 그림이 엇나간다(2026-10-09).
## 그래서 걷는 방향을 화면에 투영한 각도(땅 방향은 sin(피치)만큼 눌린다)로 고른다.
## facing_yaw: 월드 X/Z 평면의 방향각(atan2(x, z)), camera_yaw: 카메라가 바라보는 쪽 각도(도).
static func direction_for(facing_yaw: float, camera_yaw: float) -> String:
	var heading := Vector2(sin(deg_to_rad(facing_yaw)), cos(deg_to_rad(facing_yaw)))
	var toward_camera := Vector2(sin(deg_to_rad(camera_yaw)), cos(deg_to_rad(camera_yaw)))
	var screen_right := Vector2(toward_camera.y, -toward_camera.x)
	var screen_x := heading.dot(screen_right)
	var screen_y := heading.dot(toward_camera) * sin(deg_to_rad(CAMERA_PITCH_DEG))
	var screen_angle := rad_to_deg(atan2(screen_y, screen_x)) # 0=오른쪽, 90=아래(카메라 쪽)
	var index := posmod(int(floor((90.0 - screen_angle + 22.5) / 45.0)), DIRECTIONS.size())
	return DIRECTIONS[index]
