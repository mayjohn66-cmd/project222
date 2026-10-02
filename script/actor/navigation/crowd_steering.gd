class_name CrowdSteering
extends RefCounted
## 여러 사람이 좁은 길에서 겹치지 않게 걷는 규칙(연속 이동 + 분리). 계산은 바닥 평면(칸 단위)에서 한다.
##   - 앞에서 가로막은 사람이 있으면 멈추거나 느려진다(줄 서기).
##   - 옆이나 뒤에서 너무 가까운 사람은 서로 밀어낸다.
## 화면 좌표(마름모) ↔ 바닥 좌표 변환은 screen_to_ground / ground_to_screen. 화면 y 는 2:1 로 눌려 있어서
## 화면 거리를 그대로 쓰면 앞뒤 간격이 실제보다 가깝게 보이기 때문이다.

const TILE: Vector2 = Vector2(96.0, 48.0)

# 이 거리(칸)보다 가까운 사람을 의식하고, STOP 안으로는 더 다가가지 않는다. 겹침 판정은 이보다 작은 값(0.45)으로 잰다.
const KEEP_DISTANCE: float = 0.6
const STOP_DISTANCE: float = 0.5
const AHEAD_DOT: float = 0.35
const PUSH_GAIN: float = 3.0

# 부드러운 분리: 걷는 동안 앞사람 때문에 줄어드는 속도의 하한(0이면 완전히 멈춤). 이 값만큼은 계속 걸어서 서로 겹쳐 지나간다.
const SOFT_MIN_SLOW: float = 0.45


static func screen_to_ground(p: Vector2, tile: Vector2 = TILE) -> Vector2:
	var a: float = p.x / (tile.x * 0.5)
	var b: float = p.y / (tile.y * 0.5)
	return Vector2((a + b) * 0.5, (b - a) * 0.5)


static func ground_to_screen(g: Vector2, tile: Vector2 = TILE) -> Vector2:
	return Vector2((g.x - g.y) * tile.x * 0.5, (g.x + g.y) * tile.y * 0.5)


# heading: 가려는 방향(바닥 평면, 길이 1). offsets: 다른 사람까지의 바닥 벡터(칸).
# 반환: {"slow": 0~1 (앞사람 때문에 줄이는 비율), "push": 바닥 벡터(칸/초, 옆사람을 피하는 밀림)}
static func compute(heading: Vector2, offsets: Array, soft: bool = false) -> Dictionary:
	var slow: float = 1.0
	var push := Vector2.ZERO

	for offset in offsets:
		var d: float = offset.length()

		if d >= KEEP_DISTANCE or d < 0.0001:
			continue

		var direction: Vector2 = offset / d
		var ahead: float = direction.dot(heading)

		if ahead > AHEAD_DOT:
			slow = minf(slow, clampf((d - STOP_DISTANCE) / (KEEP_DISTANCE - STOP_DISTANCE), 0.0, 1.0))
		else:
			push -= direction * (KEEP_DISTANCE - d) * PUSH_GAIN

	# 부드럽게: 완전히 멈추지 않고 하한 속도로 계속 걸어, 걷는 손님끼리는 막히지 않고 겹쳐 지나간다.
	if soft:
		slow = maxf(slow, SOFT_MIN_SLOW)

	return {"slow": slow, "push": push}
