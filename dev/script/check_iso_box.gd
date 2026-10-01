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


func _run() -> void:
	for size in [Vector2i(1, 1), Vector2i(2, 1), Vector2i(3, 2)]:
		for rot in 4:
			var box := IsoBox.new()
			box.footprint_size = size
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

	print("CHECK_ISO_BOX failures=", failures)
	get_tree().quit(1 if failures > 0 else 0)
