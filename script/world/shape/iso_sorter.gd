class_name IsoSorter
extends RefCounted
## 아이소메트릭 그림 순서(뒤 → 앞) 계산. 물체마다 "한 점의 y값"으로 앞뒤를 정하면 큰 물체(긴 벽)와
## 작은 물체(캐릭터)가 어긋나므로, 물체를 상자로 보고 상자끼리의 위치 관계로 순서를 정한다.
##
## 방식(참고: 도트처럼 보이는 3D 렌더 기법의 "정렬"):
##   1. 화면에서 겹치는 상자 쌍만 본다.
##   2. 쌍마다 앞뒤를 정한다. 우리 상자는 격자에 맞는 직육면체이므로 분리축 검사가 단순하다:
##      A.max.x <= B.min.x 이면 A가 뒤, A.max.y <= B.min.y 이면 A가 뒤, A.max.z <= B.min.z 이면 A가 뒤(위에 있는 것이 앞).
##   3. 뒤→앞 그래프를 위상 정렬한다. 세 물체가 서로 앞서는 순환이 있으면, 화면 겹침 넓이가 가장 작은 관계를 끊는다.
##
## 좌표: x, y 는 칸(소수 가능) — +x는 화면 오른쪽 아래, +y는 왼쪽 아래. z 는 바닥에서의 높이(픽셀).
## 입력 항목: {"id": 아무 값, "min": Vector3, "max": Vector3}. 결과: {"order": [id...](뒤→앞), "cuts": [{"back","front","area"}...]}

const TILE: Vector2 = Vector2(96.0, 48.0)
const EPS: float = 0.0001


# 항목 목록을 그리는 순서(뒤→앞)로 정렬한다.
static func sort_items(items: Array, tile: Vector2 = TILE) -> Dictionary:
	var ids: Array = []
	var edges: Array = []

	for item in items:
		ids.append(item["id"])

	for i in range(items.size()):
		for j in range(i + 1, items.size()):
			var area: float = overlap_area(items[i], items[j], tile)

			if area <= EPS:
				continue

			var verdict: int = compare(items[i], items[j])

			if verdict < 0:
				edges.append({"back": items[i]["id"], "front": items[j]["id"], "area": area})
			elif verdict > 0:
				edges.append({"back": items[j]["id"], "front": items[i]["id"], "area": area})

	var tie: Dictionary = {}

	for item in items:
		tie[item["id"]] = center_depth(item)

	return order_from_edges(ids, edges, tie)


# -1 = a 가 뒤(b 가 앞), 1 = a 가 앞, 0 = 판단 불가(서로 안 겹치거나 모호).
static func compare(a: Dictionary, b: Dictionary) -> int:
	var a_behind: bool = _behind(a, b)
	var b_behind: bool = _behind(b, a)

	if a_behind and not b_behind:
		return -1

	if b_behind and not a_behind:
		return 1

	# 둘 다 분리되어 있거나(모호) 서로 파고든 경우: 중심 깊이로 정한다.
	var da: float = center_depth(a)
	var db: float = center_depth(b)

	if absf(da - db) <= EPS:
		return 0

	return -1 if da < db else 1


static func _behind(a: Dictionary, b: Dictionary) -> bool:
	return (
		a["max"].x <= b["min"].x + EPS
		or a["max"].y <= b["min"].y + EPS
		or a["max"].z <= b["min"].z + EPS
	)


# 깊이(클수록 앞): 칸 좌표 x+y 의 중심에 높이를 조금 반영한다.
static func center_depth(item: Dictionary) -> float:
	var mn: Vector3 = item["min"]
	var mx: Vector3 = item["max"]
	return (mn.x + mx.x + mn.y + mx.y) * 0.5 + (mn.z + mx.z) * 0.0005


# 화면에서 상자가 차지하는 사각형(윤곽 상자).
static func screen_rect(item: Dictionary, tile: Vector2 = TILE) -> Rect2:
	var mn: Vector3 = item["min"]
	var mx: Vector3 = item["max"]
	var hw: float = tile.x * 0.5
	var hh: float = tile.y * 0.5
	var left: float = (mn.x - mx.y) * hw
	var right: float = (mx.x - mn.y) * hw
	var top: float = (mn.x + mn.y) * hh - mx.z
	var bottom: float = (mx.x + mx.y) * hh - mn.z
	return Rect2(left, top, right - left, bottom - top)


static func overlap_area(a: Dictionary, b: Dictionary, tile: Vector2 = TILE) -> float:
	var r: Rect2 = screen_rect(a, tile).intersection(screen_rect(b, tile))
	return maxf(r.size.x, 0.0) * maxf(r.size.y, 0.0) if r.has_area() else 0.0


# 그래프만으로 순서를 만든다. edges: [{"back","front","area"}]. tie: {id: 깊이} (동률일 때 뒤쪽 먼저).
# 순환이 있으면 그 순환에서 area 가 가장 작은 관계를 끊고 계속한다. 끊은 관계는 cuts 로 돌려준다.
static func order_from_edges(ids: Array, edges: Array, tie: Dictionary = {}) -> Dictionary:
	var live: Array = edges.duplicate()
	var cuts: Array = []

	while true:
		var cycle: Array = _find_cycle(ids, live)

		if cycle.is_empty():
			break

		var weakest: Dictionary = cycle[0]

		for e in cycle:
			if float(e["area"]) < float(weakest["area"]):
				weakest = e

		live.erase(weakest)
		cuts.append(weakest)

	# 순환이 없으니 위상 정렬(Kahn). 동률은 tie 값이 작은(뒤쪽) 것을 먼저.
	var indegree: Dictionary = {}
	var out_edges: Dictionary = {}

	for id in ids:
		indegree[id] = 0
		out_edges[id] = []

	for e in live:
		indegree[e["front"]] += 1
		out_edges[e["back"]].append(e["front"])

	var ready: Array = []

	for id in ids:
		if indegree[id] == 0:
			ready.append(id)

	var order: Array = []

	while not ready.is_empty():
		var pick: int = 0

		for k in range(1, ready.size()):
			if float(tie.get(ready[k], 0.0)) < float(tie.get(ready[pick], 0.0)):
				pick = k

		var id = ready[pick]
		ready.remove_at(pick)
		order.append(id)

		for nxt in out_edges[id]:
			indegree[nxt] -= 1

			if indegree[nxt] == 0:
				ready.append(nxt)

	return {"order": order, "cuts": cuts}


# 순환 하나를 찾아 그 관계(edge)들을 돌려준다. 없으면 빈 배열.
static func _find_cycle(ids: Array, edges: Array) -> Array:
	var adjacent: Dictionary = {}

	for id in ids:
		adjacent[id] = []

	for e in edges:
		adjacent[e["back"]].append(e)

	var state: Dictionary = {}  # 1 = 탐색 중, 2 = 끝
	var path_edges: Array = []

	for start in ids:
		if state.has(start):
			continue

		var found: Array = _dfs(start, adjacent, state, path_edges)

		if not found.is_empty():
			return found

	return []


static func _dfs(node, adjacent: Dictionary, state: Dictionary, path_edges: Array) -> Array:
	state[node] = 1

	for e in adjacent[node]:
		var nxt = e["front"]
		path_edges.append(e)

		if state.get(nxt, 0) == 1:
			var cycle: Array = []
			var started: bool = false

			for pe in path_edges:
				if pe["back"] == nxt:
					started = true

				if started:
					cycle.append(pe)

			return cycle

		if state.get(nxt, 0) == 0:
			var inner: Array = _dfs(nxt, adjacent, state, path_edges)

			if not inner.is_empty():
				return inner

		path_edges.pop_back()

	state[node] = 2
	return []
