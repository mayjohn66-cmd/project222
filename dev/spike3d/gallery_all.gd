extends Node
## 건물·가판대를 한 화면에 나열해 직접 돌려 보는 시험 장면(종료하지 않음). 인자 없이 F6 으로 실행한다.
## 1 = 마을 건물·가게, 2 = 새 건물 종류(돌탑·돔·풍차·헛간·마구간, 풍차 날개가 돈다), 3 = 가판대 12종   [ ] = 한 화면 안에서 해(시각) 바꾸기 아님(고정)
## 방향키 = 화면 이동, +/- = 확대·축소, R = 색·지붕 조합 다시 뽑기

const PAGES: Array = [
	{"title": "마을 건물·가게", "names": ["bakery", "blacksmith", "tool_shop", "red_house", "moss_cottage", "house", "ochre_townhouse", "red_house", "house"], "cols": 3, "kind": "building"},
	{"title": "새 건물 종류 (풍차 날개가 돕니다)", "names": ["tower_house", "dome_hall", "windmill", "granary", "stable", "granary"], "cols": 3, "kind": "building"},
	{"title": "가판대 12종", "names": [], "cols": 4, "kind": "stall"},
]

var vp: SubViewport
var container: SubViewportContainer
var cam: Camera3D
var label: Label
var holder: Node3D
var page: int = 0
var cam_zoom: float = 15.0
var cam_pan: Vector2 = Vector2.ZERO
var seed_shift: int = 0
var spinners: Array = []
var shrink: int = 2


func _ready() -> void:
	var win := Vector2i(1152, 648)
	container = SubViewportContainer.new()
	container.stretch = true
	container.stretch_shrink = shrink
	container.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	container.size = Vector2(win)
	add_child(container)
	vp = SubViewport.new()
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
	cam = Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.rotation_degrees = Vector3(-30.0, 45.0, 0.0)
	vp.add_child(cam)
	var layer := CanvasLayer.new()
	add_child(layer)
	label = Label.new()
	label.position = Vector2(12, 8)
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_color", Color.WHITE)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 6)
	layer.add_child(label)
	_show_page(0)

	var args := OS.get_cmdline_user_args()

	for i in range(args.size()):
		if args[i] == "--shot" and i + 1 < args.size():
			_shoot.call_deferred(args[i + 1])


func _shoot(out: String) -> void:
	for pg in range(3):
		_show_page(pg)

		for f in range(10):
			await get_tree().process_frame

		get_viewport().get_texture().get_image().save_png("%s/gallery_%d.png" % [out, pg + 1])

	get_tree().quit()


func _process(delta: float) -> void:
	for sp in spinners:
		if is_instance_valid(sp["node"]):
			(sp["node"] as Node3D).rotate(Vector3(0.7071, 0.0, 0.7071), float(sp["speed"]) * delta)

	var pan := Vector2.ZERO

	if Input.is_key_pressed(KEY_LEFT):
		pan.x -= 1.0
	if Input.is_key_pressed(KEY_RIGHT):
		pan.x += 1.0
	if Input.is_key_pressed(KEY_UP):
		pan.y -= 1.0
	if Input.is_key_pressed(KEY_DOWN):
		pan.y += 1.0

	if pan != Vector2.ZERO:
		cam_pan += pan * delta * 6.0
		_place_camera()


func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return

	match event.keycode:
		KEY_1:
			_show_page(0)
		KEY_2:
			_show_page(1)
		KEY_3:
			_show_page(2)
		KEY_EQUAL, KEY_KP_ADD:
			cam_zoom = maxf(cam_zoom - 1.5, 5.0)
			_place_camera()
		KEY_MINUS, KEY_KP_SUBTRACT:
			cam_zoom = minf(cam_zoom + 1.5, 40.0)
			_place_camera()
		KEY_R:
			seed_shift += 1
			_show_page(page)


func _place_camera() -> void:
	var pg: Dictionary = PAGES[page]
	var cols: int = int(pg["cols"])
	var count: int = VillageAssets.STALL_TYPES.size() if str(pg["kind"]) == "stall" else (pg["names"] as Array).size()
	var rows: int = int(ceil(float(count) / float(cols)))
	var step: Vector2 = _step(pg)
	var cx: float = float(cols - 1) * step.x * 0.5 + cam_pan.x
	var cz: float = float(rows - 1) * step.y * 0.5 + cam_pan.y
	cam.size = cam_zoom
	cam.position = Vector3(cx, 1.5, cz) + cam.transform.basis.z * 40.0


func _step(pg: Dictionary) -> Vector2:
	return Vector2(3.4, 2.9) if str(pg["kind"]) == "stall" else Vector2(7.5, 7.5)


func _show_page(i: int) -> void:
	page = i
	cam_pan = Vector2.ZERO
	cam_zoom = 11.0 if str(PAGES[i]["kind"]) == "stall" else 15.0
	spinners.clear()

	if holder != null:
		holder.queue_free()

	holder = Node3D.new()
	vp.add_child(holder)
	var pg: Dictionary = PAGES[i]
	var p: Dictionary = {"ts": 18, "block_px": 22, "unit_px_z": (36.0 / sqrt(2.0)) * cos(deg_to_rad(30.0))}
	var step: Vector2 = _step(pg)
	var cols: int = int(pg["cols"])

	if str(pg["kind"]) == "stall":
		var kinds: Array = VillageAssets.STALL_TYPES.keys()

		for k in range(kinds.size()):
			var origin := Vector2(float(k % cols) * step.x, float(k / cols) * step.y)
			var built: Dictionary = VillageAssets.build_prop("stall", origin - Vector2(1.0, 0.5), origin + Vector2(1.0, 0.5), {"variant": kinds[k]}, p)
			_add_mesh(built["mesh"], built["specs"], Vector3.ZERO)
	else:
		var rules: Array = VillageMirror.load_rules()
		var names: Array = pg["names"]

		for k in range(names.size()):
			var rule: Dictionary = VillageMirror.find_rule(rules, str(names[k]))
			var center := Vector2(float(k % cols) * step.x, float(k / cols) * step.y)
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

			rule = VillageMirror.apply_variation(rule, absi(hash("g%d_%d_%d" % [i, k, seed_shift])) % 100003)
			var lo: Vector2 = center - Vector2(cw, cd) * 0.5
			var hi: Vector2 = center + Vector2(cw, cd) * 0.5
			var kind: String = str(rule.get("kind", "gable"))
			var built2: Dictionary = VillageAssets.build_gable(lo, hi, rule, p) if kind == "gable" else VillageAssets.build_prop(str(rule.get("style", "")), lo, hi, rule, p)
			_add_mesh(built2["mesh"], built2["specs"], Vector3.ZERO)

			if built2.get("display", null) != null:
				_add_mesh(built2["display"]["mesh"], built2["display"]["specs"], Vector3.ZERO)

			if built2.get("apron", null) != null:
				var ap: Dictionary = built2["apron"]
				var m := VillageAssets.make_material(ap["spec"])
				m.set_shader_parameter("use_sort", false)
				var mi := MeshInstance3D.new()
				mi.mesh = ap["mesh"]
				mi.material_override = m
				mi.position.y = 0.01
				holder.add_child(mi)

			for an in built2.get("anim", []):
				var node := _add_mesh(an["mesh"], an["specs"], an["pos"])
				spinners.append({"node": node, "speed": float(an["speed"])})

	label.text = "%d) %s   — 1·2·3 쪽 전환 / 방향키 이동 / +- 확대 / R 색 다시 뽑기" % [i + 1, str(pg["title"])]
	_place_camera()


func _add_mesh(mesh: Mesh, specs: Array, pos: Vector3) -> MeshInstance3D:
	var inst := MeshInstance3D.new()
	inst.mesh = mesh
	inst.position = pos
	var mats: Array = VillageAssets.make_materials(specs)
	var cutout: bool = false

	for k in range(mats.size()):
		(mats[k] as ShaderMaterial).set_shader_parameter("use_sort", false)
		inst.set_surface_override_material(k, mats[k])

		if bool((specs[k] as Dictionary).get("cutout", false)):
			cutout = true

	if cutout:
		inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	holder.add_child(inst)
	return inst
