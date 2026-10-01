extends Node
## IsoBox / IsoGeometry 검사: 충돌 영역 = 바닥 발자국, 면 좌표, 문 면 계산이 옛 값과 같은지 확인한다.

var failures: int = 0


func _ready() -> void:
	call_deferred("_run")


func _check(ok: bool, text: String) -> void:
	if ok:
		print("PASS: ", text)
	else:
		failures += 1
		print("FAIL: ", text)


func _same(a: PackedVector2Array, b: PackedVector2Array) -> bool:
	if a.size() != b.size():
		return false

	for i in a.size():
		if not a[i].is_equal_approx(b[i]):
			return false

	return true


func _run() -> void:
	for size in [Vector2i(1, 1), Vector2i(2, 1), Vector2i(3, 2)]:
		for rot in 4:
			var box := IsoBox.new()
			box.footprint_size = Vector2(size)
			box.rotation_index = rot
			add_child(box)
			var expected := FurnitureFootprint.polygon(size, 1.0, rot, IsoGeometry.TILE)
			_check(box.get_collision_polygon() == expected, "충돌 영역 = 발자국 %s 회전 %d" % [size, rot])
			_check(box.get_collision_polygon().size() == 4, "충돌 꼭짓점 4개 %s %d" % [size, rot])
			box.queue_free()

	# 1x1: 마름모 꼭짓점이 타일 크기와 같다.
	var g := IsoGeometry.ground(Vector2i.ONE)
	_check(is_equal_approx(g[IsoGeometry.E].x - g[IsoGeometry.W].x, 96.0), "1x1 가로 96")
	_check(is_equal_approx(g[IsoGeometry.S].y - g[IsoGeometry.N].y, 48.0), "1x1 세로 48")

	# 면: 바닥 변과 들어 올린 변이 높이만큼 위에 있다.
	var lf := IsoGeometry.left_face(g, 60.0)
	_check(lf[2] == g[IsoGeometry.S] and lf[3] == g[IsoGeometry.W], "왼쪽 면 바닥 = W-S 변")
	_check(is_equal_approx(lf[0].y, g[IsoGeometry.W].y - 60.0), "왼쪽 면 높이 60")
	var rf := IsoGeometry.right_face(g, 60.0)
	_check(rf[3] == g[IsoGeometry.S] and rf[2] == g[IsoGeometry.E], "오른쪽 면 바닥 = S-E 변")
	var tf := IsoGeometry.top_face(g, 60.0)
	_check(is_equal_approx(tf[IsoGeometry.S].y, g[IsoGeometry.S].y - 60.0), "윗면 높이 60")

	# 문 면: 2:1 기울기, 짝수는 `\`, 홀수는 `/`.
	var down := IsoGeometry.edge_plane(52.0, 110.0, 12.0, true)
	_check(down[1].y > down[0].y and is_equal_approx(down[1].y - down[0].y, 26.0), "문 면 `\\` 기울기 26px")
	_check(is_equal_approx(down[3].y, 12.0 - 13.0) and is_equal_approx(down[2].y, 12.0 + 13.0), "문 면 바닥 중앙 = base_y")
	var up := IsoGeometry.edge_plane(52.0, 110.0, 12.0, false)
	_check(up[1].y < up[0].y, "문 면 `/` 기울기")

	# 옛 door_visual 계산과 같은 결과인지(회귀).
	var old_left_bottom: float = 12.0 - 52.0 * 0.5 * 0.5
	_check(is_equal_approx(down[3].y, old_left_bottom), "문 면 옛 계산과 동일")

	# 조합 오브젝트: ㄱ자 가로등(기둥 + 공중에 뜬 팔).
	var lamp := IsoObject.new()
	lamp.object_size = Vector2(1, 1)
	var post := IsoBox.new()
	post.cell_offset = Vector2(0.35, 0.35)
	post.footprint_size = Vector2(0.3, 0.3)
	post.height = 100.0
	var arm := IsoBox.new()
	arm.cell_offset = Vector2(0.35, 0.35)
	arm.footprint_size = Vector2(0.9, 0.3)
	arm.height = 10.0
	arm.elevation = 100.0
	arm.blocking = false
	lamp.add_child(post)
	lamp.add_child(arm)
	add_child(lamp)
	_check(lamp.get_parts().size() == 2, "조합 오브젝트 부품 2개")
	_check(lamp.get_blocking_polygons().size() == 1, "막는 부품은 기둥 하나뿐(팔은 공중)")
	_check(_same(post.get_collision_polygon(), IsoGeometry.rect_ground(Vector2(0.35, 0.35), Vector2(0.3, 0.3))), "기둥 충돌 = 0.3칸 사각형")
	_check(arm.get_collision_polygon().size() == 4 and arm._collision.disabled, "팔 충돌은 꺼짐")
	# 팔은 기둥 위(elevation)에 그려진다.
	var base := IsoGeometry.lift(arm.get_ground_polygon(), arm.elevation)
	_check(is_equal_approx(base[IsoGeometry.S].y, arm.get_ground_polygon()[IsoGeometry.S].y - 100.0), "팔 높이 100")

	# 회전: 2x1 오브젝트의 한쪽 끝 부품이 회전 1에서 반대 축 끝으로 간다.
	var r0 := IsoGeometry.transform_rect(Vector2(0, 0), Vector2(1, 1), Vector2(2, 1), 0)
	_check(r0[0] == Vector2(0, 0) and r0[1] == Vector2(1, 1), "회전 0 그대로")
	var r1 := IsoGeometry.transform_rect(Vector2(0, 0), Vector2(1, 1), Vector2(2, 1), 1)
	_check(r1[1] == Vector2(1, 1), "회전 1 부품 크기 유지")
	_check(is_equal_approx(r1[0].y, 0.0) and is_equal_approx(r1[0].x, 0.0), "회전 1 2x1 → 1x2, 첫 부품은 (0,0)")
	var r1b := IsoGeometry.transform_rect(Vector2(1, 0), Vector2(1, 1), Vector2(2, 1), 1)
	_check(is_equal_approx(r1b[0].y, 1.0) and is_equal_approx(r1b[0].x, 0.0), "회전 1 둘째 부품은 (0,1)")
	_check(IsoGeometry.rotated_object_size(Vector2(2, 1), 1) == Vector2(1, 2), "회전한 전체 크기 1x2")

	print("CHECK_ISO_BOX failures=", failures)
	get_tree().quit(1 if failures > 0 else 0)
