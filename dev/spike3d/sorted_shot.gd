extends Node
## 정렬 순서 깊이 켬/끔을 같은 자리에서 그려 PNG 로 저장한다(개발용). 인자: --out <폴더>
func _ready() -> void:
	var out: String = ""
	var args := OS.get_cmdline_user_args()
	for i in range(args.size()):
		if args[i] == "--out" and i + 1 < args.size():
			out = args[i + 1]
	var scene = load("res://dev/spike3d/iso_sorted_spike.tscn").instantiate()
	add_child(scene)
	scene.shrink = 3
	scene.toon = true
	scene.shadows = true
	scene._apply_shrink()
	scene.actor_half = 0.04
	for place in [["pillar", Vector3(5.5, 0.0, 5.04)], ["wall", Vector3(1.6, 0.0, 1.04)]]:
		scene.actor_logic_pos = place[1]
		for sorted_on in [false, true]:
			scene.sorted_mode = sorted_on
			scene._update_actor()
			for i in 6:
				await get_tree().process_frame
			var img: Image = get_viewport().get_texture().get_image()
			img.save_png("%s/sorted_%s_%s.png" % [out, place[0], "on" if sorted_on else "off"])
	get_tree().quit()
