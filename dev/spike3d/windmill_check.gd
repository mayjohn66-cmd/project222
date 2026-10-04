extends Node
## 마을에 풍차 시험 노드를 놓고 3D 로 두 장(시간 간격) 저장 — 날개가 도는지 확인하는 개발용. 인자: --out <폴더>

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
	var decor: Node = scene.get_node("VillageDecor")
	var body := StaticBody2D.new()
	body.name = "windmill_test"
	body.collision_layer = 1
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(150, 75)
	shape.shape = rect
	body.add_child(shape)
	decor.add_child(body)
	var at: Vector2 = ex.to_global(ex.grid_to_local(Vector2i(13, 2)))
	body.global_position = at
	plr.global_position = at + Vector2(0, 40)
	mirror.forced_hour = 12.0

	for i in range(40):
		await get_tree().process_frame

	get_viewport().get_texture().get_image().save_png("%s/mill_a.png" % out)
	await get_tree().create_timer(0.9).timeout
	get_viewport().get_texture().get_image().save_png("%s/mill_b.png" % out)
	print("anims ", mirror.village._anims.keys())
	get_tree().quit()
