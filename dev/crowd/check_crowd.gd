extends Node
## 좁은 통로 무리 이동 시험: 현재 방식(칸 중심 고정, 서로 안 봄)이 얼마나 겹치는지 재고, 다른 방식과 비교한다.

const Sim = preload("res://dev/crowd/crowd_sim.gd")

var failures: int = 0


func _ready() -> void:
	call_deferred("_run")


func _check(ok: bool, text: String) -> void:
	if ok:
		print("PASS: ", text)
	else:
		failures += 1
		print("FAIL: ", text)


func _scenario(name: String, rows: Array, from: Vector2i, to: Vector2i, count: int, gap: float, dwell: float = 3.0) -> Dictionary:
	var out: Dictionary = {}

	for m in [Sim.Model.CURRENT, Sim.Model.RESERVE, Sim.Model.FLOW]:
		var s := Sim.new()
		s.load_map(rows)
		var rng := RandomNumberGenerator.new()
		rng.seed = 11  # 세 모델이 같은 사람들을 걷게 한다

		for i in range(count):
			s.add_agent(from, to, float(i) * gap, rng.randf_range(1.0, 1.9), dwell)

		s.run(m)
		out[m] = s
		print("  [%s] %s: %s" % [name, ["현재", "칸예약", "연속+분리"][m], s.summary()])

	return out


func _run() -> void:
	# 1) 칸 하나 폭의 긴 통로, 손님 15명이 0.6초 간격으로 입장, 걷는 빠르기는 사람마다 다르고 도착해서 3초 머문다.
	var straight: Array = ["##############", "#............#", "##############"]
	print("시나리오 1: 한 칸 폭 직선 통로(길이 12), 15명")
	var s1: Dictionary = _scenario("직선", straight, Vector2i(1, 1), Vector2i(12, 1), 15, 0.6)
	_check(s1[Sim.Model.CURRENT].overlap_ticks > 100, "현재 방식은 좁은 통로에서 오래 겹침(겹친 틱 100 초과)")
	_check(s1[Sim.Model.RESERVE].overlap_ticks == 0 and s1[Sim.Model.RESERVE].finished == 15, "칸 예약은 겹침 0, 모두 도착")
	_check(s1[Sim.Model.FLOW].overlap_ticks * 10 < s1[Sim.Model.CURRENT].overlap_ticks and s1[Sim.Model.FLOW].finished == 15, "연속+분리는 겹침이 현재의 10분의 1 미만, 모두 도착")

	# 2) 지그재그 미로(칸 하나 폭), 12명.
	var maze: Array = [
		"################",
		"#S.............#",
		"############.###",
		"#............###",
		"#.##############",
		"#.............E#",
		"################",
	]
	print("시나리오 2: 미로형 통로, 12명")
	var s2: Dictionary = _scenario("미로", maze, Vector2i(1, 1), Vector2i(14, 5), 12, 0.5)
	_check(s2[Sim.Model.CURRENT].overlap_ticks > 50, "현재 방식은 미로에서도 겹침이 큼")
	_check(s2[Sim.Model.RESERVE].overlap_ticks == 0, "칸 예약은 미로에서 겹침 0")
	_check(s2[Sim.Model.FLOW].overlap_ticks < s2[Sim.Model.CURRENT].overlap_ticks, "연속+분리는 미로에서 현재보다 겹침이 적음")

	# 3) 양방향: 한 칸 폭에서 마주 오기(막힘 위험), 두 칸 폭에서 마주 오기.
	print("시나리오 3: 한 칸 폭 통로에서 양쪽에서 마주 오기(5명씩) — 막힘 확인")
	var narrow: Array = ["##############", "#............#", "##############"]

	for m in [Sim.Model.CURRENT, Sim.Model.RESERVE, Sim.Model.FLOW]:
		var s := Sim.new()
		s.load_map(narrow)

		for i in range(5):
			s.add_agent(Vector2i(1, 1), Vector2i(12, 1), float(i) * 0.8, 1.5, 0.0)
			s.add_agent(Vector2i(12, 1), Vector2i(1, 1), float(i) * 0.8, 1.5, 0.0)

		s.run(m)
		print("  [마주] %s: %s" % [["현재", "칸예약", "연속+분리"][m], s.summary()])

		if m != Sim.Model.CURRENT:
			_check(s.stuck_agents > 0, "%s: 한 칸 폭에서 마주 오면 막힘이 생긴다(설계로 풀어야 하는 문제)" % ["칸예약", "연속+분리"][m - 1])

	# 4) 조향 규칙 단위 검사(실제 게임이 쓰는 CrowdSteering)
	var ahead: Dictionary = CrowdSteering.compute(Vector2(1, 0), [Vector2(0.52, 0.0)])
	_check(ahead["slow"] < 0.3 and ahead["push"] == Vector2.ZERO, "바로 앞 가까운 사람이 있으면 거의 멈춤")
	var far: Dictionary = CrowdSteering.compute(Vector2(1, 0), [Vector2(1.2, 0.0)])
	_check(far["slow"] == 1.0 and far["push"] == Vector2.ZERO, "멀리 있는 사람은 신경 쓰지 않음")
	var beside: Dictionary = CrowdSteering.compute(Vector2(1, 0), [Vector2(0.0, 0.3)])
	_check(beside["slow"] == 1.0 and beside["push"].y < 0.0, "옆의 가까운 사람에게서 멀어지는 쪽으로 밀림")
	var round_trip: Vector2 = CrowdSteering.screen_to_ground(CrowdSteering.ground_to_screen(Vector2(2.5, -1.0)))
	_check(round_trip.is_equal_approx(Vector2(2.5, -1.0)), "바닥↔화면 좌표 변환이 서로 되돌려짐")

	print("CHECK_CROWD failures=", failures)
	get_tree().quit(1 if failures > 0 else 0)
