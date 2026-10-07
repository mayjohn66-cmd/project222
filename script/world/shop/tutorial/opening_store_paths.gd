class_name OpeningStorePaths
extends RefCounted
## 프롤로그 연출의 걸을 곳과 길을 집기 배치(`OpeningStoreLayout`)에서 자동으로 구한다. 배치를 바꿔도 손님·점원이 집기를 뚫고 걷지 않는다.
##   점원 자리·계산 자리: 계산대(`counter`)의 뒤쪽·앞쪽 칸. 계산대가 없으면 매장 가운데.
##   둘러볼 자리: 첫 진열대(`gondola`) 앞 칸. 없으면 매장 가운데.
##   길: 칸 격자 위 최단 경로(4방향). 집기가 놓인 칸과 문 외의 벽 바깥 칸은 막혀 있다.
## 칸 좌표: 문 (0,4), 매장 (0..9, 0..7), 문 밖은 x < 0.

const DOOR_CELL := Vector2i(0, 4)
const OUTSIDE_START := Vector2i(-3, 4)
const REGION := Rect2i(-4, -1, 15, 10)    # 길을 찾는 범위(문 밖 거리 포함)


static func blocked_cells(open_floor: bool = false) -> Dictionary:
	var blocked: Dictionary = {}

	for prop in ([] if open_floor else OpeningStoreLayout.props()):
		if str(prop["model"]) == "table":
			continue  # 의자가 낮아 지나다닐 수 있게 둔다

		var rect: Rect2i = OpeningStoreLayout.cells_of(prop)

		for y in range(rect.position.y, rect.end.y):
			for x in range(rect.position.x, rect.end.x):
				blocked[Vector2i(x, y)] = true

	# 서쪽 벽 바깥 줄: 문 자리만 열려 있다(벽을 뚫고 들어오지 못하게)
	for y in range(REGION.position.y, REGION.end.y):
		if y != DOOR_CELL.y:
			blocked[Vector2i(-1, y)] = true

	return blocked


# 계산대 뒤(점원)·앞(손님) 칸. 계산대가 여럿이면 첫 번째.
static func counter_cells() -> Dictionary:
	for prop in OpeningStoreLayout.props():
		if str(prop["model"]) != "counter":
			continue

		var rect: Rect2i = OpeningStoreLayout.cells_of(prop)
		var center := Vector2i(rect.position.x + rect.size.x / 2, rect.position.y + rect.size.y / 2)
		var front := _front_dir(int(prop["rot"]))
		var blocked: Dictionary = blocked_cells()
		# 단말기(POS)는 계산대 길이 방향 0.6 지점(모델 `_counter`): 점원·손님은 그 앞뒤에 선다
		var along_x: bool = posmod(int(prop["rot"]), 2) == 0
		var pos_u: float = 0.6
		var anchor: Vector2i = prop["anchor"]
		var rot: int = posmod(int(prop["rot"]), 4)
		var pos_cell: Vector2i = center

		if along_x:
			var x: float = (float(anchor.x) - 0.5 + pos_u) if rot == 0 else (float(anchor.x + rect.size.x) - 0.5 - pos_u)
			pos_cell = Vector2i(roundi(x), center.y)
		else:
			var y: float = (float(anchor.y) - 0.5 + pos_u) if rot == 1 else (float(anchor.y + rect.size.y) - 0.5 - pos_u)
			pos_cell = Vector2i(center.x, roundi(y))

		var behind: Vector2i = _nearest_free(pos_cell - front, blocked)
		var customer: Vector2i = _nearest_free(pos_cell + front, blocked)
		return {"cashier": behind, "customer": customer}

	var middle := _nearest_free(Vector2i(5, 4), blocked_cells())
	return {"cashier": middle, "customer": middle}


# 앉을 자리(첫 취식 탁자의 의자): {seat: 의자 위치(칸 좌표 실수), approach: 의자 쪽으로 들어서는 칸, face: 바라보는 쪽 칸 방향}.
# 의자는 탁자 길이 방향 양끝(모델 `_table`)에 있고, 탁자 뒤(창 쪽)를 보고 앉는 의자를 고른다. 탁자가 없으면 빈 딕셔너리.
static func seat_cells() -> Dictionary:
	for prop in OpeningStoreLayout.props():
		if str(prop["model"]) != "table":
			continue

		var rect: Rect2 = OpeningStoreLayout.rect_of(prop)
		var center: Vector2 = rect.get_center()
		var along_x: bool = posmod(int(prop["rot"]), 2) == 0
		var axis: Vector2 = Vector2(1.0, 0.0) if along_x else Vector2(0.0, 1.0)
		var seat_a: Vector2 = center - axis * 0.4
		var seat_b: Vector2 = center + axis * 0.4
		# 창이 있는 가까운 벽(서쪽 x=-0.5 / 남쪽 y=7.5)을 바라보는 쪽 의자에 앉는다. 벽과 나란한 축이면 서쪽·남쪽을 더 보는 쪽
		var wall_dir: Vector2 = Vector2(-1.0, 0.0) if center.x + 0.5 <= 7.5 - center.y else Vector2(0.0, 1.0)
		var seat: Vector2 = seat_a if (seat_b - seat_a).normalized().dot(wall_dir) > 0.0 else seat_b
		var face: Vector2 = (center - seat).normalized()  # 의자에서 탁자 쪽(= 벽 쪽)을 본다
		return {"seat": seat, "approach": Vector2i((seat - face * 0.9).round()), "face": face}

	return {}


static func browse_cell() -> Vector2i:
	# 가장 긴 진열대(같으면 먼저 놓은 것) 앞 칸
	var best: Dictionary = {}
	var best_length: int = 0

	for prop in OpeningStoreLayout.props():
		if str(prop["model"]) != "gondola":
			continue

		var size: Vector2i = prop["size"]
		var length: int = maxi(size.x, size.y)

		if length > best_length:
			best = prop
			best_length = length

	if best.is_empty():
		return _nearest_free(Vector2i(5, 4), blocked_cells())

	var rect: Rect2i = OpeningStoreLayout.cells_of(best)
	var center := Vector2i(rect.position.x + rect.size.x / 2, rect.position.y + rect.size.y / 2)
	return _nearest_free(center + _front_dir(int(best["rot"])), blocked_cells())


static func center_cell() -> Vector2i:
	return _nearest_free(Vector2i(5, 4), blocked_cells())


# from → to 칸 길(양끝 포함, 일직선 가운데 칸은 줄인다). 길이 없으면 곧장 가는 두 점.
# open_floor: 집기가 부서지고 없는 뒤(깨어난 뒤)에는 집기 칸을 막지 않는다.
static func route(from_cell: Vector2i, to_cell: Vector2i, open_floor: bool = false) -> Array:
	var astar := AStarGrid2D.new()
	astar.region = REGION
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	astar.update()

	for cell in blocked_cells(open_floor):
		if REGION.has_point(cell):
			astar.set_point_solid(cell, true)

	if not REGION.has_point(from_cell) or not REGION.has_point(to_cell):
		return [from_cell, to_cell]

	astar.set_point_solid(from_cell, false)
	astar.set_point_solid(to_cell, false)
	var raw: Array = astar.get_id_path(from_cell, to_cell)

	if raw.is_empty():
		return [from_cell, to_cell]

	var path: Array = []

	for i in range(raw.size()):
		if i > 0 and i < raw.size() - 1:
			var a: Vector2i = raw[i - 1]
			var b: Vector2i = raw[i]
			var c: Vector2i = raw[i + 1]

			if (b - a) == (c - b):
				continue  # 일직선이면 가운데 칸은 생략

		path.append(raw[i])

	return path


static func STORE_RECT() -> Rect2i:
	return OpeningStoreLayout.STORE_CELLS


# 회전별 앞면 방향(칸): 0 → +y, 1 → +x, 2 → -y, 3 → -x
static func _front_dir(rot: int) -> Vector2i:
	match posmod(rot, 4):
		0:
			return Vector2i(0, 1)
		1:
			return Vector2i(1, 0)
		2:
			return Vector2i(0, -1)
		_:
			return Vector2i(-1, 0)


# cell 이 막혀 있으면 가장 가까운 빈 칸(매장 안)
static func _nearest_free(cell: Vector2i, blocked: Dictionary) -> Vector2i:
	if STORE_RECT().has_point(cell) and not blocked.has(cell):
		return cell

	var best: Vector2i = cell
	var best_distance: float = INF

	for y in range(STORE_RECT().position.y, STORE_RECT().end.y):
		for x in range(STORE_RECT().position.x, STORE_RECT().end.x):
			var c := Vector2i(x, y)

			if blocked.has(c):
				continue

			var d: float = Vector2(c).distance_to(Vector2(cell))

			if d < best_distance:
				best_distance = d
				best = c

	return best
