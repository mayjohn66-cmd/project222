extends Node
## 빵집 앞에서 시각별로 2D(지금 게임) / 3D 를 같은 구도로 저장한다(개발용 비교). 인자: --out <폴더>

const HOURS: Array = [9.0, 12.0, 17.5, 19.0, 21.0]


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
	dm.hour_timer.stop()
	var plr: Node2D = scene.get_node("Actors/Player")
	plr.global_position = ex.to_global(ex.grid_to_local(Vector2i(13, 2)))

	for h in HOURS:
		dm.current_hour = int(h)
		mirror.forced_hour = h

		for m in [["2d", StoreView3D.Mode.OFF], ["3d", StoreView3D.Mode.ON]]:
			mirror.mode = m[1]

			for i in range(25):
				await get_tree().process_frame

			get_viewport().get_texture().get_image().save_png("%s/bakery_%s_%03d.png" % [out, m[0], int(h * 10)])

	get_tree().quit()
