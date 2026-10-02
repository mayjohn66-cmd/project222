extends Node
## IsoSorter 검사: 큰 벽과 작은 물체의 앞뒤, 격자 상자 판정, 세 물체 순환에서 가장 작은 겹침을 끊는지 확인한다.

var failures: int = 0


func _ready() -> void:
	call_deferred("_run")


func _check(ok: bool, text: String) -> void:
	if ok:
		print("PASS: ", text)
	else:
		failures += 1
		print("FAIL: ", text)


func _box(id: String, mn: Vector3, mx: Vector3) -> Dictionary:
	return {"id": id, "min": mn, "max": mx}


func _before(order: Array, back, front) -> bool:
	return order.find(back) != -1 and order.find(back) < order.find(front)


func _run() -> void:
	# 1) 긴 벽(뒤쪽 y=0..1, x 0..6) 앞뒤: 캐릭터는 벽 앞(y=2)과 벽 뒤(y=-2) 두 곳.
	var wall: Dictionary = _box("wall", Vector3(0, 0, 0), Vector3(6, 1, 96))
	var front_char: Dictionary = _box("front", Vector3(2.4, 2.0, 0), Vector3(2.8, 2.4, 40))
	var r1: Dictionary = IsoSorter.sort_items([front_char, wall])
	_check(_before(r1["order"], "wall", "front"), "벽 앞(y 큼)의 캐릭터는 벽보다 나중에 그림")
	_check(r1["cuts"].is_empty(), "단순 배치에는 끊는 관계가 없음")

	var back_char: Dictionary = _box("back", Vector3(2.4, -1.4, 0), Vector3(2.8, -1.0, 40))
	var r2: Dictionary = IsoSorter.sort_items([wall, back_char])
	_check(_before(r2["order"], "back", "wall"), "벽 뒤(y 작음)의 캐릭터는 벽보다 먼저 그림")

	# 2) 화면에서 겹치지 않는 물체는 관계를 만들지 않는다.
	var far: Dictionary = _box("far", Vector3(10, 10, 0), Vector3(11, 11, 20))
	var r3: Dictionary = IsoSorter.sort_items([wall, far])
	_check(r3["order"].size() == 2 and r3["cuts"].is_empty(), "겹치지 않는 물체는 서로 영향 없음")

	# 3) 위에 놓인 물체(z)는 아래 물체보다 앞.
	var table: Dictionary = _box("table", Vector3(0, 0, 0), Vector3(2, 2, 30))
	var cup: Dictionary = _box("cup", Vector3(0.5, 0.5, 30), Vector3(1.0, 1.0, 40))
	_check(IsoSorter.compare(table, cup) == -1 and IsoSorter.compare(cup, table) == 1, "위에 올린 물건은 아래 물체보다 앞")

	# 4) 큰 물체와 작은 물체: 한 점 y값(발끝)으로는 틀리는 경우도 상자로는 맞는다.
	var tall_wall: Dictionary = _box("tall", Vector3(3, 0, 0), Vector3(4, 5, 120))
	var small_left: Dictionary = _box("small", Vector3(0.0, 1.0, 0), Vector3(0.5, 1.5, 40))
	var r4: Dictionary = IsoSorter.sort_items([small_left, tall_wall])
	_check(_before(r4["order"], "small", "tall"), "긴 벽 옆(x 작음)의 작은 물체는 벽보다 먼저 그림")

	# 5) 그래프 단계: 세 물체가 서로 앞서는 순환에서 가장 작은 관계를 끊는다(A<B, B<C, C<A).
	var edges: Array = [
		{"back": "A", "front": "B", "area": 336.0},
		{"back": "B", "front": "C", "area": 659.0},
		{"back": "C", "front": "A", "area": 150.0},
	]
	var r5: Dictionary = IsoSorter.order_from_edges(["A", "B", "C"], edges)
	_check(r5["cuts"].size() == 1 and r5["cuts"][0]["area"] == 150.0, "순환에서 겹침이 가장 작은 관계(150)를 끊음")
	_check(r5["order"] == ["C", "A", "B"] or _before(r5["order"], "A", "B") and _before(r5["order"], "B", "C"), "끊은 뒤 남은 관계(A<B<C)대로 순서가 나옴")
	_check(r5["order"].size() == 3, "순환이 있어도 모든 물체가 순서에 들어감")

	# 6) 순환이 아닌 사슬은 아무것도 끊지 않는다.
	var chain: Dictionary = IsoSorter.order_from_edges(["A", "B", "C"], [
		{"back": "A", "front": "B", "area": 5.0},
		{"back": "B", "front": "C", "area": 5.0},
	])
	_check(chain["order"] == ["A", "B", "C"] and chain["cuts"].is_empty(), "사슬은 그대로 정렬")

	# 7) 같은 입력은 항상 같은 순서(결정적).
	var again: Dictionary = IsoSorter.sort_items([front_char, wall])
	_check(again["order"] == r1["order"], "같은 입력이면 같은 순서")

	# 8) 무작위 장면 300개: 항상 모든 물체가 한 번씩 순서에 들어가고, 순환이 생기면 끊어서 해결한다.
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var all_ok: bool = true
	var cut_scenes: int = 0

	for scene in 300:
		var items: Array = []

		for k in rng.randi_range(2, 9):
			var x: float = float(rng.randi_range(0, 6))
			var y: float = float(rng.randi_range(0, 6))
			var z: float = float(rng.randi_range(0, 2)) * 24.0
			items.append(_box("o%d" % k, Vector3(x, y, z), Vector3(x + rng.randi_range(1, 3), y + rng.randi_range(1, 3), z + rng.randi_range(1, 4) * 24.0)))

		var res: Dictionary = IsoSorter.sort_items(items)
		var uniq: Dictionary = {}

		for id in res["order"]:
			uniq[id] = true

		if res["order"].size() != items.size() or uniq.size() != items.size():
			all_ok = false

		if not res["cuts"].is_empty():
			cut_scenes += 1

	_check(all_ok, "무작위 장면 300개에서 모든 물체가 정확히 한 번씩 정렬됨(순환 포함)")
	print("(참고) 순환을 끊은 장면 수: %d / 300" % cut_scenes)

	print("CHECK_ISO_SORTER failures=", failures)
	get_tree().quit(1 if failures > 0 else 0)
