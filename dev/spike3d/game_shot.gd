extends Node
## 실제 매장 장면(main.tscn)에 3D 거울 층(StoreView3D)을 붙여, 2D 만 / 겹침 / 3D 만 을 PNG 로 저장한다(개발용).
## 가구는 게임의 배치 서비스로 실제 설치한다. 인자: --out <폴더> [--frames N]
func _place(bm: Node, build_id: String, anchor: Vector2i, rotation_index: int) -> void:
	if not GameState.has_furniture(build_id, 1):
		GameState.add_furniture(build_id, 1)  # 시험용으로 보유 처리
	var index: int = bm.get_catalog_index_from_build_id(build_id)
	bm.build_selection_state.restore_selection(index, rotation_index)
	var node: Node2D = bm.build_placement_service.place_furniture(build_id, anchor)
	print("place ", build_id, " ", anchor, " rot=", rotation_index, " -> ", node != null)


func _ready() -> void:
	var out: String = ""
	var frames: int = 200
	var args := OS.get_cmdline_user_args()
	for i in range(args.size()):
		if args[i] == "--out" and i + 1 < args.size():
			out = args[i + 1]
		if args[i] == "--frames" and i + 1 < args.size():
			frames = int(args[i + 1])
	var scene = load("res://scenes/shop/main.tscn").instantiate()
	add_child(scene)
	var mirror := StoreView3D.new()
	scene.add_child(mirror)
	for i in range(60):
		await get_tree().process_frame

	var bm: Node = scene.get_node("BuildManager")
	_place(bm, "shelf_2x1", Vector2i(2, 1), 0)
	_place(bm, "shelf_3x1", Vector2i(5, 1), 0)
	_place(bm, "shelf_2x1", Vector2i(2, 4), 1)
	_place(bm, "register", Vector2i(6, 5), 0)
	_place(bm, "drink_machine", Vector2i(8, 2), 0)
	_place(bm, "door", Vector2i(4, 7), 2)  # 도로 쪽(앞쪽) 벽의 문
	_place(bm, "wall_poster", Vector2i(3, 0), 0)  # 뒤쪽 벽 포스터
	_place(bm, "adventurer_banner", Vector2i(0, 5), 3)  # 왼쪽(안쪽) 벽 깃발
	for i in range(30):
		await get_tree().process_frame

	# 손님: 게임의 손님 생성기를 직접 호출(문과 도로 경로가 있어야 생성됨)
	var spawner: Node = scene.get_node("CustomerSpawner")
	spawner.max_customers = 12
	var spawn_every: int = 45

	for i in range(frames):
		if i % spawn_every == 0:
			spawner.spawn_customer()
		await get_tree().process_frame

	# 가게 안에 손님을 일부러 몰아 놓고(2D 이동 상태머신은 건드리지 않고 위치만 옮김) 정렬을 본다.
	if "--crowd" in args:
		var fl: Node2D = scene.get_node("Floor")
		var cells: Array = [Vector2(3.0, 3.0), Vector2(3.4, 3.2), Vector2(3.7, 3.0), Vector2(4.1, 3.3), Vector2(2.8, 2.7), Vector2(5.0, 3.0), Vector2(5.3, 2.6), Vector2(4.6, 2.2), Vector2(2.1, 2.9), Vector2(7.0, 4.2)]
		var customers: Array = get_tree().get_nodes_in_group("customer")

		for k in range(mini(cells.size(), customers.size())):
			var c: Vector2 = cells[k]
			(customers[k] as Node2D).global_position = fl.to_global(Vector2((c.x - c.y) * 48.0, (c.x + c.y) * 24.0))

		for i in range(3):
			await get_tree().process_frame

	for m in [[StoreView3D.Mode.OFF, "2d"], [StoreView3D.Mode.OVERLAY, "overlay"], [StoreView3D.Mode.ON, "3d"]]:
		mirror.mode = m[0]
		for i in range(12):
			await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png("%s/game_%s.png" % [out, m[1]])

	print("walls3d=", mirror._items.keys().filter(func(k): return str(k).begins_with("wall")).size())
	print("game_shot done; customers=", get_tree().get_nodes_in_group("customer").size(), " shelves=", get_tree().get_nodes_in_group("shelf").size(), " items3d=", mirror._items.size(), " actors3d=", mirror._actors.size())
	get_tree().quit()
