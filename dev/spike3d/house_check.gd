extends Node
## 건물 앞(문 옆)에 플레이어를 세우고 3D 로 저장한다(문·창 크기를 캐릭터와 비교하는 개발용). 인자: --out <폴더>

const TARGETS: Array = [["VillageBuildings", "EditorObject1", "bakery"], ["NearbyHouses", "EditorObject1", "redhouse"], ["VillageExtraHouses", "EditorObject1", "moss"], ["VillageBlacksmith", "EditorObject1", "blacksmith"], ["VillageToolShop", "EditorObject1", "toolshop"]]


func _ready() -> void:
	var out: String = ""
	var args := OS.get_cmdline_user_args()
	for i in range(args.size()):
		if args[i] == "--out" and i + 1 < args.size():
			out = args[i + 1]

	var scene: Node = load("res://scenes/shop/main.tscn").instantiate()
	add_child(scene)
	var mirror: StoreView3D = scene.get_node("StoreView3D")
	for i in range(60):
		await get_tree().process_frame

	var ex: Node2D = scene.get_node("StoreExterior")
	var dm: Node = scene.get_node("DayManager")
	dm.current_hour = 12
	dm.hour_timer.stop()
	var plr: Node2D = scene.get_node("Actors/Player")
	mirror.forced_hour = 12.0
	mirror.mode = StoreView3D.Mode.ON
	plr.visible = false  # 건물 한가운데에 세워 화면 중앙에 오게 하므로 가린다

	for t in TARGETS:
		var holder: Node = scene.get_node_or_null(t[0])
		var body: Node = holder.get_node_or_null(t[1]) if holder != null else null

		if body == null:
			continue

		var rect: Rect2 = mirror.village._footprint_cell_rect(body)
		var c := Vector2(rect.position.x + rect.size.x * 0.5, rect.position.y + rect.size.y * 0.5 + 0.3)  # 문 오른쪽 앞
		plr.global_position = ex.to_global(Vector2((c.x - c.y) * 48.0, (c.x + c.y) * 24.0))

		for i in range(25):
			await get_tree().process_frame

		get_viewport().get_texture().get_image().save_png("%s/house_%s.png" % [out, t[2]])

	get_tree().quit()
