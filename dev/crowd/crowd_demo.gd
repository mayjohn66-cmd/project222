extends Node2D
## 무리 이동 시뮬레이션을 눈으로 보는 데모(게임 없이). 통로를 지나가는 손님을 점으로 그린다.
##   1 / 2 / 3 키: 이동 방식 전환(1 = 현재, 2 = 칸 예약, 3 = 연속 이동 + 분리). 바뀌면 처음부터 다시 시작한다.
##   M 키: 통로 모양 전환(직선 ↔ 미로)
##   빨간 원 = 지금 다른 손님과 겹친 손님. 위쪽 글자에 겹친 쌍 수와 도착 인원이 나온다.
## 실행: Godot 에서 dev/crowd/crowd_demo.tscn 을 열고 F6.

const Sim = preload("res://dev/crowd/crowd_sim.gd")
const CELL: float = 44.0
const STRAIGHT: Array = ["##############", "#............#", "##############"]
const MAZE: Array = [
	"################",
	"#S.............#",
	"############.###",
	"#............###",
	"#.##############",
	"#.............E#",
	"################",
]

var sim
var model: int = Sim.Model.CURRENT
var use_maze: bool = false
var label: Label
var accumulated: float = 0.0


func _ready() -> void:
	position = Vector2(60, 110)
	var layer := CanvasLayer.new()
	add_child(layer)
	label = Label.new()
	label.position = Vector2(16, 10)
	label.add_theme_font_size_override("font_size", 20)
	layer.add_child(label)
	_restart()


func _restart() -> void:
	sim = Sim.new()
	var rows: Array = MAZE if use_maze else STRAIGHT
	sim.load_map(rows)
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var start: Vector2i = Vector2i(1, 1)
	var goal: Vector2i = Vector2i(14, 5) if use_maze else Vector2i(12, 1)

	for i in range(15):
		sim.add_agent(start, goal, float(i) * 0.6, rng.randf_range(1.0, 1.9), 3.0)

	sim.model = model
	sim.time = 0.0
	sim.overlap_ticks = 0
	queue_redraw()


func _process(delta: float) -> void:
	accumulated += delta

	while accumulated >= Sim.DT:
		accumulated -= Sim.DT

		if sim.time < Sim.MAX_SECONDS and sim.finished + sim.stuck_agents < sim.agents.size():
			sim._step()
			sim._measure()
			sim.time += Sim.DT

	label.text = "1 현재 / 2 칸 예약 / 3 연속+분리 / M 미로\\n방식: %s   통로: %s   시간 %.1f초\\n%s" % [["현재(칸 중심 고정)", "칸 예약", "연속 이동 + 분리"][model], "미로" if use_maze else "직선", sim.time, sim.summary()]
	queue_redraw()


func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return

	match event.keycode:
		KEY_1:
			model = Sim.Model.CURRENT
		KEY_2:
			model = Sim.Model.RESERVE
		KEY_3:
			model = Sim.Model.FLOW
		KEY_M:
			use_maze = not use_maze
		_:
			return

	_restart()


func _draw() -> void:
	for cell in sim.walls.keys():
		draw_rect(Rect2(Vector2(cell) * CELL, Vector2(CELL, CELL)), Color(0.25, 0.27, 0.33))

	var rows: Array = MAZE if use_maze else STRAIGHT

	for y in range(rows.size()):
		for x in range(rows[y].length()):
			if not sim.walls.has(Vector2i(x, y)):
				draw_rect(Rect2(Vector2(x, y) * CELL, Vector2(CELL, CELL)), Color(0.13, 0.15, 0.18))
				draw_rect(Rect2(Vector2(x, y) * CELL, Vector2(CELL, CELL)), Color(0.2, 0.22, 0.27), false)

	var live: Array = []

	for a in sim.agents:
		if a.started and not a.done:
			live.append(a)

	for a in live:
		var overlapped: bool = false

		for b in live:
			if b != a and a.pos.distance_to(b.pos) < Sim.OVERLAP_DISTANCE:
				overlapped = true
				break

		var center: Vector2 = a.pos * CELL
		draw_circle(center, 8.0, Color(0.95, 0.85, 0.4) if not a.waiting_until >= 0.0 else Color(0.5, 0.8, 1.0))

		if overlapped:
			draw_arc(center, 13.0, 0.0, TAU, 20, Color(1.0, 0.25, 0.25), 2.0)
