extends Node
## 윤곽선 켬/끔을 같은 화면으로 그려 PNG 로 저장한다(개발용). 인자: --out <폴더>
func _ready() -> void:
	var out: String = ""
	var args := OS.get_cmdline_user_args()
	for i in range(args.size()):
		if args[i] == "--out" and i + 1 < args.size():
			out = args[i + 1]
	var scene = load("res://dev/spike3d/iso_sorted_spike.tscn").instantiate()
	add_child(scene)
	scene.actor_half = 0.04
	scene.actor_logic_pos = Vector3(5.5, 0.0, 5.04)
	for cfg in [[3, false], [3, true], [2, true]]:
		scene.shrink = cfg[0]
		scene.toon = true
		scene.shadows = true
		scene.outline = cfg[1]
		scene.posterize = false
		scene._apply_shrink()
		scene._update_actor()
		for i in 8:
			await get_tree().process_frame
		print("shrink=", scene.shrink, " container.stretch_shrink=", scene.container.stretch_shrink, " viewport.size=", scene.viewport.size, " id_viewport.size=", scene.id_viewport.size)
		get_viewport().get_texture().get_image().save_png("%s/outline_%dx_%s.png" % [out, cfg[0], "on" if cfg[1] else "off"])
	get_tree().quit()
