extends Node
## 도입부 문 옮기기: 서쪽 벽(방향 3)에서 문을 위아래로 옮길 수 있고, 초반 풀밭 길이 문을 따라간다.
var checks := 0
var failures := 0
func check(ok: bool, text: String) -> void:
	checks += 1
	if ok: print("PASS: ", text)
	else:
		failures += 1
		push_error(text)
func _ready() -> void: call_deferred("run")
func run() -> void:
	GameState.initialize_new_game()
	var world = load("res://scenes/shop/main.tscn").instantiate()
	add_child(world)
	for i in range(4): await get_tree().process_frame
	var bm = world.get_node("BuildManager")
	var exterior = world.get_node("StoreExterior")
	var floor_node = world.get_node("Floor")
	check(OpeningTerrain.wild(), "새 게임은 낯선 땅 단계")
	var start: Vector2i = OpeningTerrain.door_outside_cell(exterior)
	check(start == Vector2i(-1, 4), "문 바깥 칸은 서쪽 벽 (0,4) 바깥")
	var idx: int = bm.get_catalog_index_from_build_id("door")
	bm.build_selection_state.restore_selection(idx, 3)
	var west := 0
	for y in range(floor_node.rows):
		if bm.can_place(Vector2i(0, y)) or y == 4: west += 1
	check(west >= 2, "서쪽 벽에서도 문을 놓을 수 있다")
	check(bm.can_place(Vector2i(0, 2)) and not bm.can_place(Vector2i(1, 2)), "서쪽 벽 가장자리 칸만 된다")
	# 실제로 옮긴다(빌드 이동 서비스)
	var door: Node2D = null
	for o in world.get_node("Objects").get_children():
		if str(o.get_meta("build_id", "")) == "door": door = o
	check(door != null, "도입부 문이 있다")
	bm.build_selection_state.restore_selection(idx, 3)
	check(bm.build_move_service.begin_move(door, Vector2i(0, 4)), "문 집어 들기")
	var new_anchor := Vector2i(0, 2)
	check(bm.can_place(new_anchor), "빈 서쪽 칸에 놓을 수 있다")
	var w: Vector2 = bm.get_current_furniture_world_position(new_anchor)
	bm.build_move_service.finish_move(new_anchor, w, idx, 3, bm.get_occupied_cells(new_anchor), bm.get_current_reserved_cells(new_anchor))
	bm.clear_build_selection()
	await get_tree().process_frame
	check(OpeningTerrain.door_outside_cell(exterior) == Vector2i(-1, 2), "문을 옮기면 길 시작 칸도 따라간다")
	var layout: Dictionary = OpeningTerrain.layout(exterior)
	check(str(layout.get(Vector2i(-1, 2), "")) == "dirt", "새 문 앞은 흙길")
	# 남쪽·동쪽 벽 문: 길이 가게를 가로지르지 않는다
	for rot_case in [[2, Vector2i(3, 7)], [1, Vector2i(9, 3)]]:
		var rot_value: int = rot_case[0]
		var anchor: Vector2i = rot_case[1]
		for o in world.get_node("Objects").get_children():
			if str(o.get_meta("build_id", "")) == "door": door = o
		var from_anchor: Vector2i = door.get_meta("anchor")
		bm.build_selection_state.restore_selection(idx, int(door.get_meta("rotation_index")))
		bm.build_move_service.begin_move(door, from_anchor)
		bm.build_selection_state.restore_selection(idx, rot_value)
		var ok: bool = bm.can_place(anchor)
		check(ok, "방향 %d 벽에 놓을 수 있다" % rot_value)
		if ok:
			bm.build_move_service.finish_move(anchor, bm.get_current_furniture_world_position(anchor), idx, rot_value, bm.get_occupied_cells(anchor), bm.get_current_reserved_cells(anchor))
		else:
			bm.build_move_service.cancel_move()
		bm.clear_build_selection()
		await get_tree().process_frame
		var out := OpeningTerrain.door_outside_cell(exterior)
		var store_rect: Rect2i = OpeningTerrain.store_rect_of(exterior)
		var path := OpeningTerrain.trail_path(out, exterior.get_expedition_departure_cell(), store_rect)
		var crosses := false
		for cell in path:
			if store_rect.has_point(cell): crosses = true
		check(not store_rect.has_point(out) and not crosses and path[path.size() - 1] == exterior.get_expedition_departure_cell(), "방향 %d 문의 길은 가게를 지나지 않고 출발지에 닿는다" % rot_value)
	print("CHECK_DOOR_MOVE checks=", checks, " failures=", failures)
	get_tree().quit()
