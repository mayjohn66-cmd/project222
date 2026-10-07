class_name OpeningTerrain
extends RefCounted
## 새 게임 초반(첫 원정을 다녀와 가져온 재료를 첫 판매할 때까지)의 "낯선 땅".
## 가게가 갑자기 놓인 곳이라 포장도로·울타리·마을 소품이 없고, 가게 부지와 원정 출발지까지 이어지는 좁은 풀밭 길만 있다.
## 길은 가게 문 앞에서 시작해 흙길이 점점 흐려지며 원정 출발지로 어렴풋이 이어진다.
## 원정 직후 곧바로 마을 지형으로 바뀌면 튜토리얼 도중에 풍경이 달라져 어색하므로, 원정 뒤 재료 판매 단계(`OpeningJourneyFlow.RAW_SALE`)까지 마친 다음에야 `wild()`가 false가 되어 평소 마을 지형으로 돌아간다.

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
		return not PlayerProgress.story_beat_days.has(END_BEAT)

	# 도입부가 기록되기 직전의 새 게임(OpeningJourneyFlow.initialize 와 같은 조건)
	if GameState.total_day != 1 or GameState.has_store_layout() or GameState.has_player_state():
		return false

	for key in PlayerProgress.story_beat_days:
		if str(key).begins_with("tutorial_step:"):
			return false

	return true


# 칸 → "grass" | "dirt". 문 앞(서쪽 벽)에서 북쪽으로 올라가 원정 출발지까지의 ㄱ자 길.
static func layout(exterior: Node) -> Dictionary:
	var result: Dictionary = {}
	var lot: Rect2i = exterior.get_exterior_rect()
	var departure: Vector2i = exterior.get_expedition_departure_cell()
	# 가게 문은 서쪽 벽 가운데쯤(앵커 0,4)이라 문 바로 바깥 칸에서 길을 시작한다.
	var door_out := Vector2i(lot.position.x + 1, lot.position.y + 6)
	var corner := Vector2i(door_out.x, departure.y)
	var path: Array[Vector2i] = []

	for y in range(door_out.y, corner.y - 1, -1):
		path.append(Vector2i(door_out.x, y))

	for x in range(corner.x + 1, departure.x + 1):
		path.append(Vector2i(x, corner.y))

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
			var vertical: bool = cell.x == door_out.x and cell.y > corner.y
			result[cell] = "dirt"
			result[cell + (Vector2i(1, 0) if vertical else Vector2i(0, 1))] = "dirt"

	return result
