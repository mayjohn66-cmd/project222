extends Node
## IsoSortGroup 검사: 실제 IsoBox 도형(바닥 발자국)과 움직이는 물체로 앞뒤 순서가 맞게 바뀌는지 확인한다.

var failures: int = 0


func _ready() -> void:
	call_deferred("_run")


func _check(ok: bool, text: String) -> void:
	if ok:
		print("PASS: ", text)
	else:
		failures += 1
		print("FAIL: ", text)


func _iso(x: float, y: float) -> Vector2:
	return Vector2((x - y) * 48.0, (x + y) * 24.0)


func _index(group: Node, node: Node) -> int:
	return node.get_index()


func _run() -> void:
	var group := IsoSortGroup.new()
	group.auto_refresh = false
	add_child(group)

	# 긴 벽: 칸 (0..6, 0..1), 높이 96.
	var wall := IsoBox.new()
	wall.footprint_size = Vector2(6, 1)
	wall.height = 96.0
	wall.position = _iso(0, 0)
	group.add_child(wall)

	var actor := Node2D.new()
	actor.set_meta("iso_actor", Vector3(0.4, 0.4, 56.0))
	group.add_child(actor)

	var label := Node2D.new()  # 상자가 없는 자식은 제자리
	group.add_child(label)

	# 벽 앞(y 큼)
	actor.position = _iso(2.0, 1.6)
	group.refresh()
	_check(_index(group, wall) < _index(group, actor), "벽 앞의 캐릭터는 벽보다 나중에 그려짐")

	# 벽 뒤(y 작음)
	actor.position = _iso(2.0, -1.6)
	group.refresh()
	_check(_index(group, actor) < _index(group, wall), "벽 뒤의 캐릭터는 벽보다 먼저 그려짐")

	# 벽 옆(x 작음: 벽의 시작 x=-0.5 보다 왼쪽) 캐릭터는 뒤.
	actor.position = _iso(-1.5, 0.0)
	group.refresh()
	_check(_index(group, actor) < _index(group, wall), "벽 끝 바깥(x 작음)의 캐릭터는 벽보다 먼저 그려짐")

	# 다시 앞으로 보내면 순서가 되돌아온다(자동 재정렬).
	actor.position = _iso(3.0, 2.0)
	group.refresh()
	_check(_index(group, wall) < _index(group, actor), "다시 벽 앞으로 오면 순서가 바뀜")

	# 상자가 없는 자식은 자식 수가 같고 사라지지 않는다.
	_check(group.get_child_count() == 3 and label.get_parent() == group, "상자가 없는 자식은 그대로 있음")

	# 같은 위치로 다시 불러도 아무것도 하지 않는다(서명 같음).
	_check(group.refresh().is_empty(), "바뀐 게 없으면 다시 정렬하지 않음")

	# IsoBox 가 상자로 바뀌는 값: 6x1 벽 -> x -0.5..5.5, y -0.5..0.5, z 0..96
	var b: Dictionary = IsoSortGroup.box_of(wall)
	_check(is_equal_approx(b["min"].x, -0.5) and is_equal_approx(b["max"].x, 5.5) and is_equal_approx(b["min"].y, -0.5) and is_equal_approx(b["max"].y, 0.5) and is_equal_approx(b["max"].z, 96.0), "IsoBox 발자국 → 상자 값")

	# IsoObject(두 부품): 합친 상자
	var obj := IsoObject.new()
	obj.object_size = Vector2(2, 1)
	var part_a := IsoBox.new()
	part_a.footprint_size = Vector2(1, 1)
	part_a.object_size = Vector2(2, 1)
	part_a.cell_offset = Vector2(0, 0)
	part_a.height = 30.0
	var part_b := IsoBox.new()
	part_b.footprint_size = Vector2(1, 1)
	part_b.object_size = Vector2(2, 1)
	part_b.cell_offset = Vector2(1, 0)
	part_b.height = 70.0
	obj.add_child(part_a)
	obj.add_child(part_b)
	obj.position = _iso(10, 10)
	group.add_child(obj)
	var ob: Dictionary = IsoSortGroup.box_of(obj)
	_check(not ob.is_empty() and is_equal_approx(ob["max"].z, 70.0) and ob["max"].x - ob["min"].x > 1.5, "IsoObject 는 부품을 합친 큰 상자")

	print("CHECK_ISO_SORT_GROUP failures=", failures)
	get_tree().quit(1 if failures > 0 else 0)
