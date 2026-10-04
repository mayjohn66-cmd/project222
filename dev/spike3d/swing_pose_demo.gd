extends Node3D
## 칼 휘두르기 자세를 단계별로 찍는다(개발용): 위 줄 = 게임 시점, 아래 줄 = 위에서 내려다본 시점. 인자: --out <폴더>
func _ready() -> void:
	var out := ""
	var args := OS.get_cmdline_user_args()
	for i in range(args.size()):
		if args[i] == "--out" and i + 1 < args.size():
			out = args[i + 1]
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.25, 0.3, 0.4)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.8, 0.8, 0.85)
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 120, 0)
	add_child(sun)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 2.4
	add_child(cam)
	var dummy := Node3D.new()
	add_child(dummy)
	var fig := BlockyFigure.new()
	fig.build(self, dummy, 3.0, 1.14, 0.308)
	fig.set_sorted(false)
	fig.weapon_always = true
	fig.set_weapon("sword")
	print("WEAPON_SORT ", (fig.parts[fig.parts.size() - 1]["material"] as ShaderMaterial).get_shader_parameter("use_sort"))
	fig.facing_yaw_deg = 90.0  # +x 쪽을 본다
	fig.position = Vector3(0, 0, 0)
	for i in 10: await get_tree().process_frame
	var views := {"game": [Vector3(-30, 45, 0), Vector3(0, 0.6, 0)], "top": [Vector3(-89, 45, 0), Vector3(0, 0.6, 0)]}
	var dur := 0.4
	var steps := 10
	for vname in views:
		cam.rotation_degrees = views[vname][0]
		cam.position = views[vname][1] + cam.basis.z * 20.0
		fig._atk_t = -1.0
		fig.play_attack(dur, false, 80.0)
		for k in steps:
			fig.animate(dur / float(steps))
			for i in 3: await get_tree().process_frame
			get_viewport().get_texture().get_image().save_png("%s/%s_%02d.png" % [out, vname, k])
	get_tree().quit()
