extends Node
## 실제 매장 장면(main.tscn)에 3D 거울 층(StoreView3D)을 붙여, 2D 만 / 겹침 / 3D 만 을 PNG 로 저장한다(개발용).
## 가구는 게임의 배치 서비스로 실제 설치한다. 인자: --out <폴더> [--frames N]
func _place(bm: Node, build_id: String, anchor: Vector2i, rotation_index: int) -> void:
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

	for i in range(frames):
		await get_tree().process_frame

	for m in [[StoreView3D.Mode.OFF, "2d"], [StoreView3D.Mode.OVERLAY, "overlay"], [StoreView3D.Mode.ON, "3d"]]:
		mirror.mode = m[0]
		for i in range(12):
			await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png("%s/game_%s.png" % [out, m[1]])

	print("game_shot done; customers=", get_tree().get_nodes_in_group("customer").size(), " shelves=", get_tree().get_nodes_in_group("shelf").size(), " items3d=", mirror._items.size(), " actors3d=", mirror._actors.size())
	get_tree().quit()
