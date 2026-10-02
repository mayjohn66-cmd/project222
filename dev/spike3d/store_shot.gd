extends Node
## 매장 시험 장면을 몇 초 돌려 PNG 로 저장한다(개발용). 인자: --out <폴더>
func _ready() -> void:
	var out: String = ""
	var args := OS.get_cmdline_user_args()
	for i in range(args.size()):
		if args[i] == "--out" and i + 1 < args.size():
			out = args[i + 1]
	var scene = load("res://dev/spike3d/store_spike.tscn").instantiate()
	add_child(scene)
	for frame in range(900):
		await get_tree().process_frame
		if frame == 400 or frame == 899:
			var img: Image = get_viewport().get_texture().get_image()
			img.save_png("%s/store_%d.png" % [out, frame])
	print("customers=", scene.actors.size() - 1)
	get_tree().quit()
