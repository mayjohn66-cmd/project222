extends Node
## 집터 슬롯 검사: 데이터 일관성(간격·금지 구역), 배정 순서, 다음 날 완성, 저장·옛 저장 호환.
var checks := 0
var failures := 0


func check(ok: bool, label: String) -> void:
	checks += 1
	if ok:
		print("PASS: ", label)
	else:
		failures += 1
		print("FAIL: ", label)


func _ready() -> void:
	call_deferred("run")


func run() -> void:
	VillageHouseSlotsData.reload_data()
	var slots: Array[Dictionary] = VillageHouseSlotsData.slots
	check(slots.size() >= 8, "집터가 8곳 이상 있다 (%d)" % slots.size())
	# 가까운 고리부터 정렬
	var rings_ok := true
	for i in range(1, slots.size()):
		if int(slots[i]["ring"]) < int(slots[i - 1]["ring"]):
			rings_ok = false
	check(rings_ok, "집터는 안쪽 고리부터 정렬된다")
	var ids := {}
	for slot in slots:
		ids[slot["id"]] = true
	check(ids.size() == slots.size(), "집터 id 중복 없음")
	# 간격
	var spacing_ok := true
	for i in range(slots.size()):
		for j in range(i + 1, slots.size()):
			var d: Vector2i = (slots[i]["cell"] as Vector2i) - (slots[j]["cell"] as Vector2i)
			if maxi(absi(d.x), absi(d.y)) < 4:
				spacing_ok = false
	check(spacing_ok, "집터끼리 4칸 이상 떨어져 있다")
	# 금지 구역: 가장 크게 확장한 편의점 부지(+여유), 원정 출발 지점 반경 4칸, 손님 길(보도 줄)
	var max_size: Vector2i = StoreExpansionData.STORE_SIZES[StoreExpansionData.STORE_SIZES.keys().max()]
	var lot := Rect2i(Vector2i(-2, -2), Vector2i(max_size.x + 2 + 1 + 1 + 2, max_size.y + 2 + 1 + 1 + 2)).grow(1)
	var depart := Vector2i(13, -14)
	var zones_ok := true
	var corridors_ok := true
	for slot in slots:
		var cell: Vector2i = slot["cell"]
		if lot.has_point(cell):
			zones_ok = false
		if maxi(absi(cell.x - depart.x), absi(cell.y - depart.y)) < 4:
			zones_ok = false
		# 왼쪽 손님 길: 처음~최대 확장 때의 아래쪽 보도 줄(y=9, 17)에서 3칸 안은 비운다
		for sidewalk_y in [9, 17]:
			if cell.x < -2 and absi(cell.y - sidewalk_y) < 3:
				corridors_ok = false
		# 위쪽 손님 길: 오른쪽 보도 줄(x=11, 19)에서 3칸 안은 비운다
		for sidewalk_x in [11, 19]:
			if cell.y < -2 and absi(cell.x - sidewalk_x) < 3:
				corridors_ok = false
	check(zones_ok, "집터가 편의점 부지·원정 출발 지점을 침범하지 않는다")
	check(corridors_ok, "집터가 손님 출입 길을 막지 않는다")

	# 실제 월드: 주민이 서 있을 수 있어야 한다(집터 곁에 걷는 땅이 있고 막히지 않는다)
	var world = load("res://scenes/shop/main.tscn").instantiate()
	add_child(world)
	world.get_node("TutorialDirector").enabled = false
	for i in range(4):
		await get_tree().process_frame
	var terrain: Node2D = world.get_node("StoreExterior")
	var life = world.get_node("VillageLifeDirector")
	var standable := true
	for slot in slots:
		var body := StaticBody2D.new()
		world.add_child(body)
		body.global_position = terrain.to_global(terrain.grid_to_local(slot["cell"]))
		if life._approach_position(body) == Vector2.INF:
			standable = false
			print("  서 있을 곳 없음: ", slot["id"], slot["cell"])
		body.queue_free()
	check(standable, "모든 집터 곁에 주민이 설 자리가 있다")
	world.queue_free()
	await get_tree().process_frame

	# 배정
	var original: Dictionary = GameState.create_save_data()
	GameState.village_homes.clear()
	GameState.total_day = 5
	var first := VillageHousing.assign("doyun")
	check(first == slots[0]["id"], "첫 주민은 가장 가까운 집터")
	check(VillageHousing.assign("doyun") == first, "같은 주민은 같은 집터")
	var second := VillageHousing.assign("somebody")
	check(second == slots[1]["id"] and second != first, "다음 주민은 다음 집터")
	check(not VillageHousing.built("doyun"), "정착한 날에는 집이 아직 없다")
	GameState.total_day = 6
	check(VillageHousing.built("doyun"), "다음 날부터 집이 있다")
	check(VillageHousing.cell_of("doyun") == slots[0]["cell"], "집 위치는 집터 칸")
	# 집터가 모자라면 빈 문자열
	for n in range(slots.size() + 2):
		VillageHousing.assign("r%d" % n)
	check(VillageHousing.assign("overflow").is_empty(), "집터가 모자라면 배정하지 않는다")
	# 저장·불러오기
	var saved: Dictionary = GameState.create_save_data()
	GameState.village_homes.clear()
	GameState.apply_save_data(saved)
	check(VillageHousing.slot_of("doyun") == first and VillageHousing.slot_of("somebody") == second, "저장 후 불러와도 집터가 같다")
	# 옛 저장(필드 없음)
	var old_save: Dictionary = saved.duplicate(true)
	old_save.erase("village_homes")
	GameState.apply_save_data(old_save)
	check(GameState.village_homes.is_empty() and VillageHousing.adopt_legacy, "옛 저장은 빈 배정으로 열리고 채택 표시가 켜진다")
	check(not VillageHousing.assign("doyun").is_empty() and VillageHousing.built("doyun"), "옛 저장의 정착 주민은 바로 지어진 집을 받는다")
	VillageHousing.adopt_legacy = false
	# 복원
	GameState.apply_save_data(original)
	print("CHECK_VILLAGE_HOUSING checks=%d failures=%d" % [checks, failures])
	get_tree().quit(1 if failures > 0 else 0)
