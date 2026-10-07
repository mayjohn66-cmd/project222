extends Node
## 프롤로그 가게 집기 배치: 기본 배치가 매장 안에 있고, 청소 더미·점원/손님 자리·길이 배치에서 올바르게 정해지는지,
## 저장 형식을 다시 읽어도 같은지, 배치를 바꾸면 파생값이 따라 바뀌는지 확인한다(파일은 만들지 않는다).
var checks := 0
var failures := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("FAIL: " + message)

func _ready() -> void:
	call_deferred("run")

func overlaps(route: Array) -> bool:
	var blocked := OpeningStorePaths.blocked_cells()
	for point in route:
		if blocked.has(point): return true
	return false

func run() -> void:
	var defaults := OpeningStoreLayout.default_props()
	check(defaults.size() == 14, "기본 배치는 집기 14개")
	var inside := true
	for prop in defaults:
		var cells: Rect2i = OpeningStoreLayout.cells_of(prop)
		if not OpeningStoreLayout.STORE_CELLS.encloses(cells) or not OpeningStoreLayout.KINDS.has(prop["model"]): inside = false
	check(inside, "기본 집기는 모두 매장 안의 알려진 종류")
	# 저장 형식 왕복(파일 대신 사용자 폴더 임시 파일)
	var path := "user://opening_layout_check.json"
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify({"version": 1, "props": OpeningStoreLayout._to_json(defaults)}))
	file.close()
	var restored: Array = OpeningStoreLayout._read(path)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	check(restored == defaults, "저장 형식을 다시 읽으면 같은 배치")
	check(OpeningStoreLayout._read("user://does_not_exist.json").is_empty(), "없는 파일은 빈 배치(기본값으로 대체)")
	# 청소 더미: 6곳, 모든 집기가 한 번씩, 철광석 합계 4
	OpeningStoreLayout.set_props(defaults)
	OpeningCleanup.reset()
	var piles := OpeningCleanup.piles()
	var seen: Dictionary = {}
	var ore := 0
	for pile in piles:
		for index in pile["props"]: seen[index] = seen.get(index, 0) + 1
		ore += int((pile["loot"] as Dictionary).get("iron_ore", 0))
	check(piles.size() == 6 and seen.size() == defaults.size() and not seen.values().has(2), "청소 더미 6곳이 집기를 한 번씩 맡는다")
	check(ore == OpeningCleanup.ORE_TOTAL, "철광석 합계가 정해진 개수")
	# 길과 자리
	var counter := OpeningStorePaths.counter_cells()
	check(counter["cashier"] == Vector2i(6, 5) and counter["customer"] == Vector2i(6, 7), "계산대 뒤·앞 칸이 단말기(POS) 앞뒤의 점원·손님 자리")
	# 앉을 자리: 기본 배치엔 탁자가 없고, 탁자(남쪽 창 앞, 길이 방향이 남북)를 놓으면 북쪽 의자에 남쪽을 보고 앉는다
	check(OpeningStorePaths.seat_cells().is_empty(), "탁자가 없으면 앉을 자리도 없다")
	var with_table: Array = defaults.duplicate(true)
	with_table.append(OpeningStoreLayout.make("table", Vector2i(1, 7), 1))
	OpeningStoreLayout.set_props(with_table)
	var seat := OpeningStorePaths.seat_cells()
	check(not seat.is_empty() and seat["face"] == Vector2(0.0, 1.0) and Vector2(seat["seat"]).y < 7.0 and seat["approach"] == Vector2i(1, 6), "탁자 북쪽 의자에 창(남쪽)을 보고 앉고 그 앞 칸에서 들어선다")
	OpeningStoreLayout.set_props(defaults)
	var route := OpeningStorePaths.route(OpeningStorePaths.OUTSIDE_START, counter["customer"])
	check(route.size() >= 2 and route[0] == OpeningStorePaths.OUTSIDE_START and route[-1] == counter["customer"], "문 밖에서 계산 자리까지 길이 있다")
	var full: Array = OpeningStorePaths.route(OpeningStorePaths.OUTSIDE_START, counter["customer"])
	var cells_on_route: Array = []
	var astar_ok := true
	for i in range(full.size() - 1):
		var a: Vector2i = full[i]
		var b: Vector2i = full[i + 1]
		var step := Vector2i(signi(b.x - a.x), signi(b.y - a.y))
		var at := a
		while at != b:
			at += step
			if OpeningStorePaths.blocked_cells().has(at): astar_ok = false
	check(astar_ok, "길은 집기가 놓인 칸을 지나지 않는다")
	check(not OpeningStorePaths.blocked_cells().has(OpeningStorePaths.browse_cell()) and OpeningStoreLayout.STORE_CELLS.has_point(OpeningStorePaths.browse_cell()), "둘러볼 자리는 빈 칸")
	# 배치를 바꾸면 파생값이 따라간다: 계산대를 문 쪽 벽으로 옮기고 돌림
	var moved: Array = []
	for prop in defaults:
		moved.append((prop as Dictionary).duplicate(true))
	moved[13] = OpeningStoreLayout.make("counter", Vector2i(0, 6), 1)
	OpeningStoreLayout.set_props(moved)
	OpeningCleanup.reset()
	var moved_counter := OpeningStorePaths.counter_cells()
	check(moved_counter["cashier"] != counter["cashier"] and not OpeningStorePaths.blocked_cells().has(moved_counter["customer"]), "계산대를 옮기면 점원·손님 자리도 따라간다")
	check(OpeningCleanup.piles().size() == 6, "집기 수가 같으면 청소 더미 수도 같다")
	# 집기가 아주 적을 때도 철광석이 모자라지 않는다
	OpeningStoreLayout.set_props([OpeningStoreLayout.make("counter", Vector2i(5, 5), 0), OpeningStoreLayout.make("gondola", Vector2i(2, 2), 0)])
	OpeningCleanup.reset()
	var few_ore := 0
	for pile in OpeningCleanup.piles(): few_ore += int((pile["loot"] as Dictionary).get("iron_ore", 0))
	check(OpeningCleanup.piles().size() == 2 and few_ore == OpeningCleanup.ORE_TOTAL, "집기가 둘뿐이어도 철광석 합계 유지")
	OpeningStoreLayout.set_props([])
	OpeningStoreLayout.reload()
	OpeningCleanup.reset()
	print("CHECK_OPENING_LAYOUT checks=%d failures=%d" % [checks, failures])
	get_tree().quit(1 if failures > 0 else 0)
