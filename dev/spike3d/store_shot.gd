extends Node
## 매장 시험 장면을 시간대 × 법선 맵 켬/끔으로 그려 PNG 로 저장한다(개발용). 인자: --out <폴더>
func _ready() -> void:
	var out: String = ""
	var args := OS.get_cmdline_user_args()
	for i in range(args.size()):
		if args[i] == "--out" and i + 1 < args.size():
			out = args[i + 1]
	var scene = load("res://dev/spike3d/store_spike.tscn").instantiate()
	add_child(scene)
	for frame in range(420):
		await get_tree().process_frame
	scene.freeze_crowd = true
	for hour in [9.0, 12.0, 17.5, 21.0]:
		for normal_on in [false, true]:
			scene.apply_time(hour)
			scene.set_normal_map(normal_on)
			for i in 6:
				await get_tree().process_frame
			var img: Image = get_viewport().get_texture().get_image()
			img.save_png("%s/time_%02d_%s.png" % [out, int(hour * 10), "n" if normal_on else "flat"])
	print("customers=", scene.actors.size() - 1)
	get_tree().quit()
