extends Node
## 도트 판 캐릭터와 상자 3D 캐릭터를 같은 자리에서 비교해 PNG 로 저장한다(개발용). 인자: --out <폴더>
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
	scene.set_process(false)  # 장면의 키·자동 갱신 대신 이 시험이 직접 정한다
	var n: int = 2
	scene.shrink = n
	scene.actor_logic_pos = Vector3(3.3, 0.0, 5.8)
	scene._apply_shrink()
	scene.set_actor_art(32, "nearest")
	scene.use_blocky = false
	scene._update_actor()
	for i in 8: await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("%s/ratio_sprite.png" % out)
	scene.use_blocky = true

	for ratio in [2.0, 3.0]:
		scene.set_head_ratio(ratio)

		for yaw in [90.0, 0.0, 45.0]:
			scene.blocky.facing_yaw_deg = yaw
			scene.blocky.walking = false
			scene.blocky.walk_time = 0.0
			scene._update_actor()
			for i in 6: await get_tree().process_frame
			get_viewport().get_texture().get_image().save_png("%s/ratio_%d_yaw%d.png" % [out, int(ratio), int(yaw)])

		scene.blocky.facing_yaw_deg = 90.0
		scene.blocky.walking = true

		for st in 4:
			scene.blocky.walk_time = (float(st) + 0.5) / 8.0
			scene.blocky.animate(0.0)
			scene._update_actor()
			for i in 6: await get_tree().process_frame
			get_viewport().get_texture().get_image().save_png("%s/ratio_%d_walk%d.png" % [out, int(ratio), st])

	# 상자 옆에 세워서 키 비교(같은 장면에 둘 다 보이도록 각각 한 장씩)
	get_tree().quit()
