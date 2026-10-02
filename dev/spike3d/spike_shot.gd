extends Node
## 시험 방을 몇 가지 설정으로 그려서 PNG 로 저장한다(개발용). 인자: --out <폴더>
func _ready() -> void:
	var out: String = ""
	var args := OS.get_cmdline_user_args()
	for i in range(args.size()):
		if args[i] == "--out" and i + 1 < args.size():
			out = args[i + 1]
	var scene = load("res://dev/spike3d/iso_room_spike.tscn").instantiate()
	add_child(scene)
	for cfg in [[1, true], [3, true], [1, false]]:
		scene.shrink = cfg[0]
		scene.shadows = cfg[1]
		scene._apply_shrink()
		for i in 6:
			await get_tree().process_frame
		var img: Image = get_viewport().get_texture().get_image()
		img.save_png("%s/spike_shrink%d_shadow%s.png" % [out, cfg[0], str(cfg[1])])
	get_tree().quit()
