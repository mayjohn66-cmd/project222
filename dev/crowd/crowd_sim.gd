extends RefCounted
## 손님 무리 이동 시뮬레이션(화면·엔진 물리 없이 숫자만). 좁은 통로에서 여러 명이 겹치는지 재고, 이동 방식을 비교한다.
## 단위: 1 = 칸 하나. 시간 간격 DT 초.
##
## 이동 모델:
##   CURRENT  현재 customer.gd 방식: 칸 중심 → 칸 중심으로 가고 도착하면 중심에 붙인다. 다른 손님은 보지 않는다.
##   RESERVE  다음 칸에 아무도 없을 때만 들어가고, 있으면 기다린다(칸 예약).
##   FLOW     칸 중심에 붙이지 않고 연속으로 이동. 앞 사람과 최소 거리를 지키고, 옆 사람은 밀어낸다(분리).
## 겹침 판정: 두 사람의 중심 거리가 OVERLAP_DISTANCE 미만이면 그림이 포개져 보인다고 센다.

enum Model { CURRENT, RESERVE, FLOW }

const DT: float = 1.0 / 30.0
const SPEED: float = 1.5
const OVERLAP_DISTANCE: float = 0.45
const KEEP_DISTANCE: float = 0.6
const STOP_DISTANCE: float = 0.5  # 이 거리 안으로는 더 다가가지 않는다(겹침 판정 거리보다 크게)
const MAX_SECONDS: float = 90.0
const STUCK_SECONDS: float = 6.0


class Agent:
	var id: int = 0
	var pos: Vector2 = Vector2.ZERO
	var path: Array[Vector2i] = []
	var index: int = 0
	var spawn_time: float = 0.0
	var started: bool = false
	var done: bool = false
	var stuck_for: float = 0.0
	var speed: float = 1.5  # 사람마다 걷는 빠르기가 다르다
	var dwell: float = 0.0  # 도착 칸에서 머무는 시간(진열대 앞에서 물건 고르기 등)
	var waiting_until: float = -1.0


var walls: Dictionary = {}  # Vector2i -> true (벽 칸)
var agents: Array[Agent] = []
var model: int = Model.CURRENT
var occupied: Dictionary = {}  # RESERVE: 칸 -> agent id
var time: float = 0.0

# 결과
var overlap_ticks: int = 0
var max_overlapping_pairs: int = 0
var finished: int = 0
var stuck_agents: int = 0
var last_finish_time: float = 0.0


# map: 문자열 줄들. '#' 벽, '.' 길. 시작·끝은 호출하는 쪽이 정한다.
func load_map(rows: Array) -> void:
	walls.clear()

	for y in range(rows.size()):
		for x in range(rows[y].length()):
			if rows[y][x] == "#":
				walls[Vector2i(x, y)] = true


func is_free(c: Vector2i) -> bool:
	return not walls.has(c)


func find_path(from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	var prev: Dictionary = {from: from}
	var queue: Array[Vector2i] = [from]
	var head: int = 0

	while head < queue.size():
		var cur: Vector2i = queue[head]
		head += 1

		if cur == to:
			break

		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = cur + d

			if not prev.has(n) and is_free(n) and n.x >= 0 and n.y >= 0 and n.x < 64 and n.y < 64:
				prev[n] = cur
				queue.append(n)

	var out: Array[Vector2i] = []

	if not prev.has(to):
		return out

	var c: Vector2i = to

	while c != from:
		out.push_front(c)
		c = prev[c]

	out.push_front(from)
	return out


func add_agent(from: Vector2i, to: Vector2i, spawn_time: float, speed: float = SPEED, dwell: float = 0.0) -> void:
	var a := Agent.new()
	a.id = agents.size()
	a.path = find_path(from, to)
	a.spawn_time = spawn_time
	a.pos = Vector2(from) + Vector2(0.5, 0.5)
	a.speed = speed
	a.dwell = dwell
	agents.append(a)


func cell_center(c: Vector2i) -> Vector2:
	return Vector2(c) + Vector2(0.5, 0.5)


func run(which: int) -> void:
	model = which
	time = 0.0

	while time < MAX_SECONDS and finished + stuck_agents < agents.size():
		_step()
		_measure()
		time += DT


func _step() -> void:
	for a in agents:
		if a.done or time < a.spawn_time or a.path.size() < 2:
			continue

		if a.waiting_until >= 0.0:
			if time >= a.waiting_until:
				_complete(a)

			continue

		if not a.started:
			if model == Model.RESERVE and occupied.has(a.path[0]):
				continue  # 시작 칸이 차 있으면 들어가지 못함(입구 대기)

			a.started = true
			a.pos = cell_center(a.path[0])
			a.index = 1

			if model == Model.RESERVE:
				occupied[a.path[0]] = a.id

		match model:
			Model.CURRENT:
				_step_current(a)
			Model.RESERVE:
				_step_reserve(a)
			Model.FLOW:
				_step_flow(a)


# 도착: 머무는 시간이 있으면 그 자리에서 기다렸다가 끝낸다.
func _reach_end(a: Agent) -> void:
	if a.dwell > 0.0:
		a.waiting_until = time + a.dwell
	else:
		_complete(a)


func _complete(a: Agent) -> void:
	a.done = true
	finished += 1
	last_finish_time = time

	if model == Model.RESERVE:
		occupied.erase(a.path[a.path.size() - 1])


func _step_current(a: Agent) -> void:
	var target: Vector2 = cell_center(a.path[a.index])
	var dist: float = a.pos.distance_to(target)

	if dist <= maxf(SPEED * DT, 0.04):
		a.pos = target  # 도착하면 칸 중심에 붙인다
		a.index += 1

		if a.index >= a.path.size():
			_reach_end(a)

		return

	a.pos += a.pos.direction_to(target) * a.speed * DT


func _step_reserve(a: Agent) -> void:
	var cur_cell: Vector2i = a.path[a.index - 1]
	var next_cell: Vector2i = a.path[a.index]
	var target: Vector2 = cell_center(next_cell)

	# 다음 칸이 비어 있어야 출발한다. 이미 가는 중이면(예약해 둔 상태) 계속 간다.
	if a.pos.distance_to(cell_center(cur_cell)) < 0.001 and occupied.get(next_cell, a.id) != a.id:
		a.stuck_for += DT

		if a.stuck_for > STUCK_SECONDS:
			a.done = true
			stuck_agents += 1
			occupied.erase(cur_cell)

		return

	a.stuck_for = 0.0
	occupied[next_cell] = a.id
	var dist: float = a.pos.distance_to(target)

	if dist <= maxf(SPEED * DT, 0.04):
		a.pos = target
		occupied.erase(cur_cell)
		a.index += 1

		if a.index >= a.path.size():
			_reach_end(a)

		return

	a.pos += a.pos.direction_to(target) * a.speed * DT


func _step_flow(a: Agent) -> void:
	var target: Vector2 = cell_center(a.path[a.index])
	var to_target: Vector2 = target - a.pos

	if to_target.length() <= 0.15:
		a.index += 1

		if a.index >= a.path.size():
			_reach_end(a)

		return

	var heading: Vector2 = to_target.normalized()
	var vel: Vector2 = heading * a.speed
	var slow: float = 1.0

	for other in agents:
		if other == a or other.done or not other.started:
			continue

		var offset: Vector2 = other.pos - a.pos
		var d: float = offset.length()

		if d >= KEEP_DISTANCE or d < 0.0001:
			continue

		# 앞에 있는 사람이면 멈추고(줄 서기), 옆이면 서로 밀어낸다.
		var ahead: float = offset.normalized().dot(heading)

		if ahead > 0.35:
			slow = minf(slow, clampf((d - STOP_DISTANCE) / (KEEP_DISTANCE - STOP_DISTANCE), 0.0, 1.0))
		else:
			vel -= offset.normalized() * (KEEP_DISTANCE - d) * 3.0

	var next_pos: Vector2 = a.pos + vel * slow * DT

	# 벽 칸으로는 들어가지 못한다(축마다 따로 막아 벽을 따라 미끄러진다).
	var try_x := Vector2(next_pos.x, a.pos.y)
	var try_y := Vector2(a.pos.x, next_pos.y)

	if is_free(Vector2i(floori(try_x.x), floori(try_x.y))):
		a.pos.x = try_x.x

	if is_free(Vector2i(floori(try_y.x), floori(try_y.y))):
		a.pos.y = try_y.y

	if slow <= 0.01:
		a.stuck_for += DT

		if a.stuck_for > STUCK_SECONDS:
			a.done = true
			stuck_agents += 1
	else:
		a.stuck_for = 0.0


func _measure() -> void:
	var pairs: int = 0
	var live: Array[Agent] = []

	for a in agents:
		if a.started and not a.done:
			live.append(a)

	for i in range(live.size()):
		for j in range(i + 1, live.size()):
			if live[i].pos.distance_to(live[j].pos) < OVERLAP_DISTANCE:
				pairs += 1

	if pairs > 0:
		overlap_ticks += 1

	max_overlapping_pairs = maxi(max_overlapping_pairs, pairs)


func summary() -> String:
	return "겹친 순간 %d틱(최대 %d쌍 동시), 도착 %d/%d, 정체 포기 %d, 마지막 도착 %.1f초" % [overlap_ticks, max_overlapping_pairs, finished, agents.size(), stuck_agents, last_finish_time]
