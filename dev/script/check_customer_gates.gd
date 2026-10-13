extends Node
## 손님 게이트 검사: 도로 끝이 화면에 보여도 손님은 화면 밖 지점에서 나타나고 사라진다.
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
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("run")


func run() -> void:
	var world = load("res://scenes/shop/main.tscn").instantiate()
	add_child(world)
	world.get_node("TutorialDirector").enabled = false
	for i in range(4):
		await get_tree().process_frame
	var exterior: Node2D = world.get_node("StoreExterior")
	var rect: Rect2i = exterior.get_exterior_rect()
	var ends: Array[Vector2i] = [
		Vector2i(rect.position.x, exterior._get_bottom_sidewalk_y()),
		Vector2i(exterior._get_right_sidewalk_x(), rect.position.y),
	]
	check(CustomerGates.outward(rect, ends[0]) == Vector2i(-1, 0), "왼쪽 끝은 -x 방향")
	check(CustomerGates.outward(rect, ends[1]) == Vector2i(0, -1), "위쪽 끝은 -y 방향")
	check(CustomerGates.outward(rect, Vector2i(rect.position.x + 5, rect.position.y + 5)) == Vector2i.ZERO, "끝이 아니면 방향 없음")
	var camera: Camera2D = get_viewport().get_camera_2d()
	check(camera != null, "카메라가 있다")
	if camera == null:
		get_tree().quit(1)
		return
	camera.position_smoothing_enabled = false
	for end_cell in ends:
		var end_world: Vector2 = exterior.to_global(exterior.grid_to_local(end_cell))
		# 카메라를 도로 끝에 맞춰 끝이 화면 한가운데 보이게 한다.
		camera.global_position = end_world
		camera.force_update_scroll()
		await get_tree().process_frame
		var view: Rect2 = CustomerGates.visible_world_rect(exterior)
		check(view.has_point(end_world), "도로 끝이 화면 안에 보인다: %s" % [end_cell])
		var gate: Vector2 = CustomerGates.gate_position(exterior, end_cell)
		check(not view.has_point(gate), "게이트는 화면 밖: %s" % [end_cell])
		check(not view.grow(CustomerGates.value("margin_px")).has_point(gate), "게이트는 여유 거리만큼 화면 밖: %s" % [end_cell])
		# 카메라를 멀리 치우면 끝이 이미 화면 밖이므로 게이트가 끝 그대로다.
		camera.global_position = end_world + Vector2(100000, 100000)
		camera.force_update_scroll()
		await get_tree().process_frame
		check(CustomerGates.gate_position(exterior, end_cell) == end_world, "끝이 화면 밖이면 그대로: %s" % [end_cell])
	# 실제 생성: 카메라를 도로 끝에 두고 여러 번 생성해도 처음 위치는 항상 화면 밖
	var layout: Array[Dictionary] = [
		{"build_id": "door", "anchor": Vector2i(0, 4), "rotation_index": 3},
		{"build_id": "register", "anchor": Vector2i(4, 3), "rotation_index": 0},
	]
	world.get_node("BuildManager")._restore_current_area_layout(layout)
	await get_tree().process_frame
	world.get_node("DayManager").open_shop()
	var spawner = world.get_node("DayManager").customer_spawner
	for customer_node in get_tree().get_nodes_in_group("customer"):
		customer_node.queue_free()
	var left_world: Vector2 = exterior.to_global(exterior.grid_to_local(ends[0]))
	camera.global_position = left_world
	camera.force_update_scroll()
	await get_tree().process_frame
	var first_positions: Array[Vector2] = []
	for n in range(6):
		var before: Array = get_tree().get_nodes_in_group("customer")
		spawner.spawn_customer()
		await get_tree().physics_frame
		await get_tree().physics_frame
		for customer_node in get_tree().get_nodes_in_group("customer"):
			if not before.has(customer_node):
				first_positions.append(customer_node.global_position)
	var view_now: Rect2 = CustomerGates.visible_world_rect(exterior)
	check(first_positions.size() > 0, "손님이 실제로 생성됐다(%d명)" % first_positions.size())
	var all_outside := true
	for spawn_position in first_positions:
		if view_now.has_point(spawn_position):
			all_outside = false
	check(all_outside, "생성 직후 위치는 모두 화면 밖")
	# 투명도 안전망
	var dummy := Node2D.new()
	add_child(dummy)
	CustomerGates.fade_in(dummy)
	check(is_zero_approx(dummy.modulate.a), "나타날 때 투명에서 시작")
	await get_tree().create_timer(CustomerGates.value("fade_seconds") + 0.2).timeout
	check(is_equal_approx(dummy.modulate.a, 1.0), "나타남이 끝나면 불투명")
	CustomerGates.fade_out(dummy)
	await get_tree().create_timer(CustomerGates.value("fade_seconds") + 0.2).timeout
	check(is_zero_approx(dummy.modulate.a), "사라짐이 끝나면 투명")
	print("CHECK_CUSTOMER_GATES checks=%d failures=%d" % [checks, failures])
	get_tree().quit(1 if failures > 0 else 0)
