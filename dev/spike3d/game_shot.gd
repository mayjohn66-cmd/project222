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
	for i in range(args.size()):
		if args[i] == "--scale" and i + 1 < args.size():
			mirror.configure_scale(int(args[i + 1]))
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

	# 시간대별 3D 만(손님이 있으면 같이 찍힘)
	if "--hours" in args:
		mirror.mode = StoreView3D.Mode.ON

		for h in [9.0, 12.0, 17.5, 19.0, 21.0, 2.0]:
			mirror.forced_hour = h
			for i in range(10):
				await get_tree().process_frame
			get_viewport().get_texture().get_image().save_png("%s/hour_%02d.png" % [out, int(h * 10)])

	# 2D 숨김 확인: 3D 만 모드에서 2D 그림 노드가 정말 숨겨졌는지, 끄면 복원되는지
	mirror.forced_hour = -1.0
	mirror.mode = StoreView3D.Mode.ON
	for i in range(30):
		await get_tree().process_frame
	var fl2: Node2D = scene.get_node("Floor")
	var hidden_ok: bool = not fl2.visible and not scene.get_node("Objects").get_child(0).get_node("Visual").visible
	get_viewport().get_texture().get_image().save_png("%s/game_3d_only_hidden2d.png" % out)
	mirror.mode = StoreView3D.Mode.OFF
	for i in range(5):
		await get_tree().process_frame
	var restored_ok: bool = fl2.visible and scene.get_node("Objects").get_child(0).get_node("Visual").visible
	print("hide2d hidden_in_ON=", hidden_ok, " restored_in_OFF=", restored_ok)

	# 건물·소품 둘러보기: 각 대상의 중심으로 이동해서 2D / 3D 를 같은 시각(낮 12시)으로 저장
	if "--tour" in args:
		var ex3: Node2D = scene.get_node("StoreExterior")
		var dm3: Node = scene.get_node("DayManager")
		dm3.current_hour = 12
		dm3.hour_timer.stop()
		var plr3: Node2D = scene.get_node("Actors/Player")
		mirror.forced_hour = 12.0
		var targets: Array = [["VillageBuildings", "EditorObject1", "bakery"], ["VillageBlacksmith", "EditorObject1", "blacksmith"], ["VillageToolShop", "EditorObject1", "toolshop"], ["NearbyHouses", "EditorObject1", "redhouse"], ["VillageExtraHouses", "EditorObject1", "moss"], ["VillageBuildings", "EditorObject2", "stable"], ["VillageDecor", "EditorObject2", "well"], ["VillageDecor", "EditorObject28", "stall"], ["VillageDecor", "EditorObject5", "cart"], ["VillageGathering", "EditorObject1", "board"]]

		for t in targets:
			var holder: Node = scene.get_node_or_null(t[0])
			var body: Node = holder.get_node_or_null(t[1]) if holder != null else null

			if body == null:
				print("tour missing ", t)
				continue

			var rect: Rect2 = mirror.village._footprint_cell_rect(body)
			var c: Vector2 = rect.position + rect.size * 0.5
			plr3.global_position = ex3.to_global(Vector2((c.x - c.y) * 48.0, (c.x + c.y) * 24.0) + Vector2(0, 30))

			for m in [["2d", StoreView3D.Mode.OFF], ["3d", StoreView3D.Mode.ON]]:
				mirror.mode = m[1]

				for i in range(20):
					await get_tree().process_frame

				get_viewport().get_texture().get_image().save_png("%s/tour_%s_%s.png" % [out, t[2], m[0]])

	# 빵집 앞으로 이동해서 2D / 3D 를 같은 시각(낮 12시)으로 비교(박공 지붕 건물 시험)
	if "--bakery" in args:
		var ex2: Node2D = scene.get_node("StoreExterior")
		var dm2: Node = scene.get_node("DayManager")
		dm2.current_hour = 12
		dm2.hour_timer.stop()
		var plr2: Node2D = scene.get_node("Actors/Player")
		plr2.global_position = ex2.to_global(ex2.grid_to_local(Vector2i(13, 2)))
		mirror.forced_hour = 12.0

		for m in [["2d", StoreView3D.Mode.OFF], ["3d", StoreView3D.Mode.ON]]:
			mirror.mode = m[1]
			for i in range(25):
				await get_tree().process_frame
			get_viewport().get_texture().get_image().save_png("%s/bakery_%s.png" % [out, m[0]])

	# 마을 광장으로 이동해서 2D / 3D(마을 포함) / 3D(매장만) 를 같은 시각(낮 12시)으로 비교
	if "--square" in args:
		var ex: Node2D = scene.get_node("StoreExterior")
		var dm: Node = scene.get_node("DayManager")
		dm.current_hour = 12
		dm.hour_timer.stop()
		var plr: Node2D = scene.get_node("Actors/Player")
		var sq: Vector2i = ex.get_village_square_cell()
		plr.global_position = ex.to_global(ex.grid_to_local(sq))
		mirror.forced_hour = 12.0

		for m in [["2d", StoreView3D.Mode.OFF, true], ["3d_village", StoreView3D.Mode.ON, true], ["3d_store_only", StoreView3D.Mode.ON, false]]:
			mirror.mode = m[1]
			mirror.set_village_enabled(m[2])
			for i in range(25):
				await get_tree().process_frame
			get_viewport().get_texture().get_image().save_png("%s/square_%s.png" % [out, m[0]])

		print("square sort_usec=", mirror._sort_usec, " items=", mirror._items.size(), " sorted=", mirror._sorted_keys.size())

	# 마을 3D 켬/끔 비교 + 정렬 시간
	if "--village" in args:
		mirror.mode = StoreView3D.Mode.ON
		mirror.forced_hour = 12.0
		for i in range(20):
			await get_tree().process_frame
		var total: int = 0
		var peak: int = 0

		for i in range(60):
			await get_tree().process_frame
			total += mirror._sort_usec
			peak = maxi(peak, mirror._sort_usec)

		print("village sort_usec avg=", total / 60, " peak=", peak, " items=", mirror._items.size(), " sorted=", mirror._sorted_keys.size())
		get_viewport().get_texture().get_image().save_png("%s/village_3d.png" % out)
		mirror.set_village_enabled(false)
		for i in range(10):
			await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png("%s/village_store_only.png" % out)
		mirror.mode = StoreView3D.Mode.OFF
		for i in range(10):
			await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png("%s/village_2d.png" % out)

	print("walls3d=", mirror._items.keys().filter(func(k): return str(k).begins_with("wall")).size())
	print("game_shot done; customers=", get_tree().get_nodes_in_group("customer").size(), " shelves=", get_tree().get_nodes_in_group("shelf").size(), " items3d=", mirror._items.size(), " actors3d=", mirror._actors.size())
	get_tree().quit()
