extends Node
## 캐릭터 크기·그림 방식 비교: 배율(3/2배)별로 캐릭터를 줄여서 판에 씌운 모습을 PNG 로 저장한다(개발용). 인자: --out <폴더>
func _ready() -> void:
	var out: String = ""
	var args := OS.get_cmdline_user_args()
	for i in range(args.size()):
		if args[i] == "--out" and i + 1 < args.size():
			out = args[i + 1]
	var scene = load("res://dev/spike3d/iso_sorted_spike.tscn").instantiate()
	add_child(scene)
	scene.actor_half = 0.04
	scene.toon = true
	scene.shadows = true
	scene.outline = true
	# 캐릭터를 벽 앞 빈 자리와 기둥 옆에 한 명씩 보기 위해 위치를 두 곳으로
	for cfg in [["1x_orig", 1, 0, "nearest"], ["2x_lanczos", 2, 0, "lanczos"], ["2x_nearest", 2, 0, "nearest"], ["3x_lanczos", 3, 0, "lanczos"], ["3x_nearest", 3, 0, "nearest"]]:
		scene.shrink = cfg[1]
		scene.actor_logic_pos = Vector3(3.3, 0.0, 5.8)
		scene._apply_shrink()
		# 배율에 맞춰 줄인 캐릭터(1배는 원본)
		if cfg[1] == 1:
			scene.set_actor_art(0, "nearest")
		else:
			scene.set_actor_art(int(round(64.0 / float(cfg[1]))), cfg[3])
		scene._update_actor()
		for i in 8:
			await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png("%s/char_%s.png" % [out, cfg[0]])
	get_tree().quit()
