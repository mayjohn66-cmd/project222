extends Node
## 건물 규칙(village_3d.csv)을 이름으로 골라 한 장에 나열하는 개발용 장면. 인자: --out <폴더> --names a,b,c [--shrink N] [--cols N]
## 규칙의 canon 크기로 발자국을 만들어 build_gable 로 그린다(게임 노드 없이).

func _ready() -> void:
	var out: String = ""
	var names: PackedStringArray = PackedStringArray()
	var shrink: int = 3
	var cols: int = 3
	var args := OS.get_cmdline_user_args()
	for i in range(args.size()):
		if args[i] == "--out" and i + 1 < args.size():
			out = args[i + 1]
		if args[i] == "--names" and i + 1 < args.size():
			names = args[i + 1].split(",")
		if args[i] == "--shrink" and i + 1 < args.size():
			shrink = int(args[i + 1])
		if args[i] == "--cols" and i + 1 < args.size():
			cols = int(args[i + 1])

	var rules: Array = VillageMirror.load_rules()
	var rows: int = int(ceil(float(names.size()) / float(cols)))
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
	env.background_color = Color(0.56, 0.74, 0.46)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.78, 0.8, 0.9)
	env.ambient_light_energy = 0.75
	var we := WorldEnvironment.new()
	we.environment = env
	vp.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-60.0, -25.0, 0.0)
	sun.light_energy = 0.6
	sun.shadow_enabled = true
	vp.add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-38.0, 90.0, 0.0)
	fill.light_energy = 0.22
	vp.add_child(fill)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.rotation_degrees = Vector3(-30.0, 45.0, 0.0)
	cam.size = 14.0
	var step := Vector2(7.5, 7.5)
	var cx: float = float(cols - 1) * step.x * 0.5
	var cz: float = float(rows - 1) * step.y * 0.5
	cam.position = Vector3(cx, 1.5, cz) + cam.transform.basis.z * 40.0
	vp.add_child(cam)
	var p: Dictionary = {"ts": 18, "block_px": 22, "unit_px_z": (36.0 / sqrt(2.0)) * cos(deg_to_rad(30.0))}

	for i in range(names.size()):
		var rule: Dictionary = VillageMirror.find_rule(rules, names[i])
		var col: int = i % cols
		var row: int = i / cols
		var center := Vector2(float(col) * step.x, float(row) * step.y)
		var cw: float = float(rule.get("canon_w", 3.0))
		var cd: float = float(rule.get("canon_d", 3.0))
		var axis: String = str(rule.get("axis", ""))

		if axis == "x" and cw < cd:
			var t0: float = cw
			cw = cd
			cd = t0
		elif axis == "y" and cw > cd:
			var t1: float = cw
			cw = cd
			cd = t1

		rule = VillageMirror.apply_variation(rule, i * 7 + 3)
		var lo: Vector2 = center - Vector2(cw, cd) * 0.5
		var hi: Vector2 = center + Vector2(cw, cd) * 0.5
		var kind: String = str(rule.get("kind", "gable"))
		var built: Dictionary = VillageAssets.build_gable(lo, hi, rule, p) if kind == "gable" else VillageAssets.build_prop(str(rule.get("style", "")), lo, hi, rule, p)
		_add(vp, built["mesh"], built["specs"])

		if built.get("display", null) != null:
			_add(vp, built["display"]["mesh"], built["display"]["specs"])

		if built.get("apron", null) != null:
			var ap: Dictionary = built["apron"]
			var m := VillageAssets.make_material(ap["spec"])
			m.set_shader_parameter("use_sort", false)
			var mi := MeshInstance3D.new()
			mi.mesh = ap["mesh"]
			mi.material_override = m
			mi.position.y = 0.01
			vp.add_child(mi)

	for i in range(8):
		await get_tree().process_frame

	get_viewport().get_texture().get_image().save_png("%s/buildings.png" % out)
	get_tree().quit()


func _add(vp: SubViewport, mesh: Mesh, specs: Array) -> void:
	var inst := MeshInstance3D.new()
	inst.mesh = mesh
	var mats: Array = VillageAssets.make_materials(specs)
	var cutout: bool = false

	for k in range(mats.size()):
		(mats[k] as ShaderMaterial).set_shader_parameter("use_sort", false)
		inst.set_surface_override_material(k, mats[k])

		if bool((specs[k] as Dictionary).get("cutout", false)):
			cutout = true

	if cutout:
		inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	vp.add_child(inst)
