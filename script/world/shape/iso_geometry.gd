class_name IsoGeometry
extends RefCounted
## 아이소메트릭(2:1 마름모) 도형 계산 모음. 그림이 아니라 도형이 먼저이고,
## 화면에 그리는 면과 충돌 영역이 모두 같은 발자국(footprint)에서 나온다.
##
## 좌표 규칙은 `FurnitureFootprint`와 같다: 기준 칸 (0,0)의 중심이 원점이고,
## 발자국은 +x, +y 방향으로 size 칸만큼 뻗는다.
## 바닥 꼭짓점 순서 = [위(N), 오른쪽(E), 아래(S), 왼쪽(W)].

const TILE: Vector2 = Vector2(96.0, 48.0)

const N: int = 0
const E: int = 1
const S: int = 2
const W: int = 3


# 바닥 마름모. 충돌 영역도 이 값을 그대로 쓴다.
static func ground(size: Vector2i, rotation: int = 0, depth: float = 1.0, tile: Vector2 = TILE) -> PackedVector2Array:
	return FurnitureFootprint.polygon(size, depth, rotation, tile)


# 점들을 위로 height 픽셀 들어 올린다.
static func lift(points: PackedVector2Array, height: float) -> PackedVector2Array:
	var result := PackedVector2Array()

	for p in points:
		result.append(p + Vector2(0.0, -height))

	return result


# 윗면(위N, 오른쪽E, 아래S, 왼쪽W 순서).
static func top_face(corners: PackedVector2Array, height: float) -> PackedVector2Array:
	return lift(corners, height)


# 왼쪽 앞면(W-S 변). 점 순서 = 왼쪽 위, 오른쪽 위, 오른쪽 아래, 왼쪽 아래.
static func left_face(corners: PackedVector2Array, height: float) -> PackedVector2Array:
	return PackedVector2Array([
		corners[W] + Vector2(0.0, -height),
		corners[S] + Vector2(0.0, -height),
		corners[S],
		corners[W],
	])


# 오른쪽 앞면(S-E 변). 점 순서 = 왼쪽 위, 오른쪽 위, 오른쪽 아래, 왼쪽 아래.
static func right_face(corners: PackedVector2Array, height: float) -> PackedVector2Array:
	return PackedVector2Array([
		corners[S] + Vector2(0.0, -height),
		corners[E] + Vector2(0.0, -height),
		corners[E],
		corners[S],
	])


# 타일 한 변에 서는 면(문, 창문 같은 패치). 점 순서 = 왼쪽 위, 오른쪽 위, 오른쪽 아래, 왼쪽 아래.
# descending = true 이면 `\`(오른쪽이 낮음), false 이면 `/`(왼쪽이 낮음).
# 가로 width에 2:1 기울기를 맞춘 세로 이동량을 쓰고, 바닥 중앙의 높이는 base_y.
static func edge_plane(width: float, height: float, base_y: float, descending: bool) -> PackedVector2Array:
	var half_w: float = width * 0.5
	var drop: float = width * 0.5
	var left_bottom: float = base_y - drop * 0.5
	var right_bottom: float = base_y + drop * 0.5

	if not descending:
		var swap: float = left_bottom
		left_bottom = right_bottom
		right_bottom = swap

	return PackedVector2Array([
		Vector2(-half_w, left_bottom - height),
		Vector2(half_w, right_bottom - height),
		Vector2(half_w, right_bottom),
		Vector2(-half_w, left_bottom),
	])


# 면의 가로 화면 길이(타일 반복 계산용).
static func screen_width(quad: PackedVector2Array) -> float:
	return absf(quad[1].x - quad[0].x)


static func screen_height(quad: PackedVector2Array) -> float:
	return absf(quad[3].y - quad[0].y)
