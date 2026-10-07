class_name OpeningTerrain
extends RefCounted
## 새 게임 초반(첫 원정을 다녀와 가져온 재료를 첫 판매할 때까지)의 "낯선 땅".
## 가게가 갑자기 놓인 곳이라 포장도로·울타리·마을 소품이 없고, 가게 부지와 원정 출발지까지 이어지는 좁은 풀밭 길만 있다.
## 길은 가게 문 앞에서 시작해 흙길이 점점 흐려지며 원정 출발지로 어렴풋이 이어진다.
## 원정 직후 곧바로 마을 지형으로 바뀌면 튜토리얼 도중에 풍경이 달라져 어색하므로, 원정 뒤 재료 판매 단계(`OpeningJourneyFlow.RAW_SALE`)까지 마친 다음에야 `wild()`가 false가 되어 평소 마을 지형으로 돌아간다.

const END_STEP := "tutorial_step:raw_sale:done"   # 같은 단계를 안내까지 마쳤다는 기록(이야기 검사·이전 저장 호환)
const END_BEAT := OpeningJourneyFlow.RAW_SALE   # 이 기록이 생기면 낯선 땅이 끝난다(핵심 튜토리얼의 마지막 판매)
const GRASS_MARGIN := 3          # 길 양옆으로 남기는 풀밭 폭(칸)
const DEPARTURE_MARGIN := 3      # 원정 출발지(5×5) 둘레 여유(칸)
const SOLID_TRAIL_CELLS := 4     # 문 앞에서 흙이 끊기지 않는 칸 수
const TRAIL_START_CHANCE := 88   # 그 뒤 흙이 보이는 확률(%) 시작값
const TRAIL_FADE_PER_CELL := 2   # 한 칸 갈 때마다 줄어드는 확률
const TRAIL_MIN_CHANCE := 30
const TRAIL_RUN := 3             # 흙이 끊기는 단위(칸)


# 지금이 낯선 땅 단계인지. 기존 저장·첫 재료 판매를 마친 게임은 항상 false.
static func wild() -> bool:
	if PlayerProgress.story_beat_days.has(OpeningJourneyFlow.VERSION):
		return not (PlayerProgress.story_beat_days.has(END_BEAT) or PlayerProgress.story_beat_days.has(END_STEP))

	# 도입부가 기록되기 직전의 새 게임(OpeningJourneyFlow.initialize 와 같은 조건)
	if GameState.total_day != 1 or GameState.has_store_layout() or GameState.has_player_state():
		return false

	for key in PlayerProgress.story_beat_days:
		if str(key).begins_with("tutorial_step:"):
			return false

	return true


# 가게 안 칸 사각형(칸 좌표). 월드의 Floor 에서 읽고, 없으면 기본 크기.
static func store_rect_of(exterior: Node) -> Rect2i:
	var world: Node = exterior.get_parent()
	var floor_node: Node = world.get_node_or_null("Floor") if world != null else null
	return floor_node.get_store_rect() if floor_node != null and floor_node.has_method("get_store_rect") else Rect2i(0, 0, 10, 8)


# 가게 문 바로 바깥 칸. 실제로 설치된 출입문(없으면 기본 위치 서쪽 벽 가운데쯤)을 따라가므로 문을 옮기면 길도 따라간다.
# 문이 선 벽 방향: 0 위쪽(y 작은 쪽) / 1 오른쪽(x 큰 쪽) / 2 아래쪽(y 큰 쪽) / 3 왼쪽(x 작은 쪽).
static func door_outside_cell(exterior: Node) -> Vector2i:
	var lot: Rect2i = exterior.get_exterior_rect()
	var fallback := Vector2i(lot.position.x + 1, lot.position.y + 6)   # 기본: 서쪽 벽 (0,4) 바깥
	var world: Node = exterior.get_parent()
	var objects: Node = world.get_node_or_null("Objects") if world != null else null

	if objects == null:
		return fallback

	var store_rect: Rect2i = store_rect_of(exterior)

	for object in objects.get_children():
		if object.is_queued_for_deletion() or bool(object.get_meta("is_build_preview", false)):
			continue

		if str(object.get_meta("build_id", "")) != "door":
			continue

		var anchor: Vector2i = object.get_meta("anchor", Vector2i(-1, -1))

		if anchor == Vector2i(-1, -1):
			continue

		match posmod(int(object.get_meta("rotation_index", 3)), 4):
			0:
				return Vector2i(anchor.x, store_rect.position.y - 1)
			1:
				return Vector2i(store_rect.end.x, anchor.y)
			2:
				return Vector2i(anchor.x, store_rect.end.y)
			_:
				return Vector2i(store_rect.position.x - 1, anchor.y)

	return fallback


# 문 앞에서 원정 출발지까지 가는 칸 길: ㄱ자(세로 먼저, 안 되면 가로 먼저)로 가게 부지를 가로지르지 않으면 그대로,
# 둘 다 가게를 지나면(문이 남쪽·동쪽 벽일 때 등) 가게를 돌아가는 최단 길(AStar).
static func trail_path(start: Vector2i, goal: Vector2i, store_rect: Rect2i) -> Array[Vector2i]:
	for vertical_first in [true, false]:
		var corner := Vector2i(start.x, goal.y) if vertical_first else Vector2i(goal.x, start.y)
		var path: Array[Vector2i] = []
		var at := start
		path.append(at)

		for target in [corner, goal]:
			while at != target:
				if at.x != target.x:
					at.x += signi(target.x - at.x)
				else:
					at.y += signi(target.y - at.y)

				path.append(at)

		var crosses := false

		for cell in path:
			if store_rect.has_point(cell):
				crosses = true
				break

		if not crosses:
			return path

	var margin := Rect2i(minf(start.x, goal.x) - 6, minf(start.y, goal.y) - 6, absi(goal.x - start.x) + 13, absi(goal.y - start.y) + 13)
	margin = margin.merge(store_rect.grow(3))
	var astar := AStarGrid2D.new()
	astar.region = margin
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	astar.update()

	for y in range(store_rect.position.y, store_rect.end.y):
		for x in range(store_rect.position.x, store_rect.end.x):
			if margin.has_point(Vector2i(x, y)):
				astar.set_point_solid(Vector2i(x, y), true)

	var result: Array[Vector2i] = []

	for cell in astar.get_id_path(start, goal):
		result.append(cell)

	return result if not result.is_empty() else [start, goal]


# 칸 → "grass" | "dirt". 문 앞에서 시작해 원정 출발지까지의 길.
static func layout(exterior: Node) -> Dictionary:
	var result: Dictionary = {}
	var lot: Rect2i = exterior.get_exterior_rect()
	var departure: Vector2i = exterior.get_expedition_departure_cell()
	var door_out: Vector2i = door_outside_cell(exterior)
	var store_rect: Rect2i = store_rect_of(exterior)
	var path: Array[Vector2i] = trail_path(door_out, departure, store_rect)

	# 부지 전체와 출발지 둘레는 풀밭
	for y in range(lot.position.y, lot.end.y):
		for x in range(lot.position.x, lot.end.x):
			result[Vector2i(x, y)] = "grass"

	for y in range(departure.y - 2 - DEPARTURE_MARGIN, departure.y + 3 + DEPARTURE_MARGIN):
		for x in range(departure.x - 2 - DEPARTURE_MARGIN, departure.x + 3 + DEPARTURE_MARGIN):
			result[Vector2i(x, y)] = "grass"

	for cell in path:
		for dy in range(-GRASS_MARGIN, GRASS_MARGIN + 1):
			for dx in range(-GRASS_MARGIN, GRASS_MARGIN + 1):
				var near := cell + Vector2i(dx, dy)

				if not result.has(near):
					result[near] = "grass"

	# 흙길: 문 앞은 또렷하고 멀어질수록 3칸 덩어리로 끊겨 흐려진다(같은 길이면 항상 같은 모양). 폭은 2칸.
	for i in range(path.size()):
		var chance: int = 100 if i < SOLID_TRAIL_CELLS else maxi(TRAIL_MIN_CHANCE, TRAIL_START_CHANCE - (i - SOLID_TRAIL_CELLS) * TRAIL_FADE_PER_CELL)
		var arrived: bool = i >= path.size() - 3   # 출발지에 닿는 마지막 몇 칸은 또렷하게(도착을 알아보게)

		if arrived or absi(hash(i / TRAIL_RUN)) % 100 < chance:
			var cell: Vector2i = path[i]
			var next_cell: Vector2i = path[mini(i + 1, path.size() - 1)]
			var moving_vertical: bool = next_cell.x == cell.x and next_cell != cell
			result[cell] = "dirt"
			result[cell + (Vector2i(1, 0) if moving_vertical else Vector2i(0, 1))] = "dirt"

	return result
