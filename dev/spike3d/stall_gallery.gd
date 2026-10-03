extends Node
## 가판대 종류(STALL_TYPES)를 한 장에 나열해 렌더링하는 개발용 장면. 인자: --out <폴더> [--shrink N]
## 실제 게임과 같은 방식(낮은 해상도 SubViewport 를 정수 배로 키움)으로 그린다.

func _ready() -> void:
	var out: String = ""
	var shrink: int = 3
	var args := OS.get_cmdline_user_args()
	for i in range(args.size()):
		if args[i] == "--out" and i + 1 < args.size():
			out = args[i + 1]
		if args[i] == "--shrink" and i + 1 < args.size():
			shrink = int(args[i + 1])

	var kinds: Array = VillageAssets.STALL_TYPES.keys()
	var cols: int = 4
	var rows: int = int(ceil(float(kinds.size()) / float(cols)))
	var win := Vector2i(1152, 648)
	var container := SubViewportContainer.new()
	container.stretch = true
	container.stretch_shrink = shrink
	container.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	container.size = Vector2(win)
	add_child(container)
	var vp := SubViewport.new()
	vp.size = win / shrink
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	container.add_child(vp)

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.78, 0.8, 0.84)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.78, 0.8, 0.88)
	env.ambient_light_energy = 0.7
	var we := WorldEnvironment.new()
	we.environment = env
	vp.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-62.0, -30.0, 0.0)
	sun.light_energy = 0.55
	vp.add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-38.0, 90.0, 0.0)
	fill.light_energy = 0.22
	vp.add_child(fill)

	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.rotation_degrees = Vector3(-30.0, 45.0, 0.0)
	cam.size = 10.5
	var cx: float = float(cols - 1) * 1.7 * 0.5
	var cz: float = float(rows - 1) * 2.2 * 0.5
	cam.position = Vector3(cx, 0.0, cz) + cam.transform.basis.z * 30.0
	vp.add_child(cam)

	var p: Dictionary = {"ts": 18, "block_px": 22, "unit_px_z": (36.0 / sqrt(2.0)) * cos(deg_to_rad(30.0))}

	for i in range(kinds.size()):
		var kind: String = kinds[i]
		var col: int = i % cols
		var row: int = i / cols
		var origin := Vector2(float(col) * 3.4, float(row) * 2.9)
		var built: Dictionary = VillageAssets.build_prop("stall", origin - Vector2(1.0, 0.5), origin + Vector2(1.0, 0.5), {"variant": kind}, p)
		var inst := MeshInstance3D.new()
		inst.mesh = built["mesh"]
		var mats: Array = VillageAssets.make_materials(built["specs"])

		for k in range(mats.size()):
			(mats[k] as ShaderMaterial).set_shader_parameter("use_sort", false)
			inst.set_surface_override_material(k, mats[k])

		inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		vp.add_child(inst)

	for i in range(8):
		await get_tree().process_frame

	get_viewport().get_texture().get_image().save_png("%s/stalls.png" % out)
	get_tree().quit()
