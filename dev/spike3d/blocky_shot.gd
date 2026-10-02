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
	for n in [2, 3]:
		scene.shrink = n
		scene.actor_logic_pos = Vector3(3.3, 0.0, 5.8)
		scene._apply_shrink()
		scene.set_actor_art(int(round(64.0 / float(n))), "nearest")
		# 1) 도트 판
		scene.use_blocky = false
		scene._update_actor()
		for i in 8: await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png("%s/blocky_%dx_sprite.png" % [out, n])
		# 2) 상자 캐릭터: 방향 4가지(정면·옆·뒤·반대 옆)
		scene.use_blocky = true
		for yaw in [45.0, 135.0, 225.0, 315.0]:
			scene.blocky.facing_yaw_deg = yaw
			scene.blocky.walking = false
			scene.blocky.walk_time = 0.0
			scene._update_actor()
			for i in 6: await get_tree().process_frame
			get_viewport().get_texture().get_image().save_png("%s/blocky_%dx_yaw%d.png" % [out, n, int(yaw)])
		# 3) 걸음 단계 4개
		scene.blocky.facing_yaw_deg = 45.0
		scene.blocky.walking = true
		for st in 4:
			scene.blocky.walk_time = (float(st) + 0.5) / 8.0
			scene.blocky.animate(0.0)
			scene._update_actor()
			for i in 6: await get_tree().process_frame
			get_viewport().get_texture().get_image().save_png("%s/blocky_%dx_walk%d.png" % [out, n, st])
	get_tree().quit()
