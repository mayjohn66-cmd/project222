extends Node
## 상자 3D 캐릭터의 걷기 한 주기를 방향별로 PNG 로 저장한다(개발용). 인자: --out <폴더>
## 새(부드러운) 방식과 옛(4단계) 방식을 같은 자리에서 비교한다.
const FRAMES := 12
func _ready() -> void:
	var out: String = ""
	var args := OS.get_cmdline_user_args()
	for i in range(args.size()):
		if args[i] == "--out" and i + 1 < args.size():
			out = args[i + 1]
	var scene = load("res://dev/spike3d/iso_sorted_spike.tscn").instantiate()
	add_child(scene)
	scene.actor_half = 0.06
	scene.toon = true
	scene.shadows = true
	scene.outline = true
	scene.set_process(false)
	scene.shrink = 2
	scene.actor_logic_pos = Vector3(3.3, 0.0, 5.8)
	scene._apply_shrink()
	scene.blocky.destroy()
	scene.blocky = BlockyFigure.new()
	scene.blocky.build(scene.viewport, scene.viewport, 3.0, 1.14, 0.308)
	scene.use_blocky = true
	scene._update_actor()
	for i in 8: await get_tree().process_frame
	var b = scene.blocky
	var period: float = (b._step_len * 2.0) / b.move_speed
	for mode in ["new", "old"]:
		b.smooth = (mode == "new")
		for yaw in [90.0, 0.0, 180.0, -90.0]:
			b.facing_yaw_deg = yaw
			b.walking = true
			b._yaw_cur = NAN
			for i in 40: b.animate(period / FRAMES)
			for f in FRAMES:
				b.animate(period / FRAMES)
				scene._update_actor()
				for i in 3: await get_tree().process_frame
				get_viewport().get_texture().get_image().save_png("%s/%s_yaw%d_f%02d.png" % [out, mode, int(yaw), f])
	get_tree().quit()
