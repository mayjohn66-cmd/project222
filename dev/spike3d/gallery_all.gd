extends Node
## 건물·가판대를 한 화면에 나열해 직접 돌려 보는 시험 장면(종료하지 않음). 인자 없이 F6 으로 실행한다.
## 1 = 마을 건물·가게, 2 = 새 건물 종류(돌탑·돔·풍차·헛간·마구간, 풍차 날개가 돈다), 3 = 가판대 12종,
## 4 = 새 집 모양 12가지(지붕 종류·포치·지붕창·돌출 창·별채·탑·2층), 5 = 나무 변형과 소품(건초·통·우물·수레)
## 방향키 = 화면 이동, +/- = 확대·축소, R = 색·지붕 조합 다시 뽑기

const PAGES: Array = [
	{"title": "마을 건물·가게", "names": ["bakery", "blacksmith", "tool_shop", "red_house", "moss_cottage", "house", "ochre_townhouse", "red_house", "house"], "cols": 3, "kind": "building"},
	{"title": "새 건물 종류 (풍차 날개가 돕니다)", "names": ["tower_house", "dome_hall", "windmill", "granary", "stable", "granary"], "cols": 3, "kind": "building"},
	{"title": "가판대 12종", "names": [], "cols": 4, "kind": "stall"},
	{"title": "새 집 모양 12가지 (지붕 종류 / 포치·지붕창·돌출 창·별채·탑·2층)", "cols": 4, "kind": "shape", "cases": [
		["house", "gable", "porch"], ["house", "gable", "porch;dormer:2"], ["house", "gambrel", "bay;dormer:1"], ["house", "mansard", "porch;dormer:2"],
		["house", "half_hip", "annex;porch"], ["house", "hip", "tower;porch"], ["house", "gable", "jetty;dormer:2"], ["house", "cross", "bay;annex"],
		["house", "gambrel", "jetty;porch"], ["ochre_townhouse", "mansard", "jetty;dormer:2"], ["moss_cottage", "half_hip", "porch;bay;dormer:1"], ["red_house", "gable", "annex;dormer:1"],
	]},
	{"title": "나무 12종 (둥근·소나무·자작·큰 참나무·가을·벚꽃·버드나무·고사목·포플러) + 덤불", "cols": 4, "kind": "propvar", "cases": [
		["apple_tree", "round", "tree"], ["pine_tree", "pine", "tree"], ["birch_tree", "birch", "tree"], ["oak_tree", "big_oak", "tree"],
		["apple_tree", "autumn", "tree"], ["cherry_tree", "cherry", "tree"], ["willow_tree", "willow", "tree"], ["dead_tree", "dead", "tree"],
		["poplar_tree", "poplar", "tree"], ["berry_bush", "berry", "flower_bush"], ["bush", "", "flower_bush"], ["hedge", "hedge", "flower_bush"],
	]},
	{"title": "소품 (바위·그루터기·통나무·버섯·분수·허수아비·모닥불·꽃밭·건초·통·우물·수레)", "cols": 4, "kind": "propvar", "cases": [
		["rock", "", "rock"], ["stump", "", "stump"], ["log_pile", "", "log"], ["mushrooms", "", "mushroom"],
		["fountain", "", "fountain"], ["scarecrow", "", "scarecrow"], ["campfire", "", "campfire"], ["flowerbed", "", "flowerbed"],
		["apple_tree", "", "hay"], ["apple_tree", "", "barrels"], ["village_well", "", "well"], ["supply_cart", "", "cart"],
	]},
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
var anim_time: float = 0.0
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
	for pg in range(PAGES.size()):
		_show_page(pg)

		for f in range(10):
			await get_tree().process_frame

		get_viewport().get_texture().get_image().save_png("%s/gallery_%d.png" % [out, pg + 1])

		# 움직임 확인: 0.7초 뒤 한 장 더(애니메이션이 있는 쪽 비교용)
		if pg >= 3:
			var t_end: float = anim_time + 0.7

			while anim_time < t_end:
				await get_tree().process_frame

			get_viewport().get_texture().get_image().save_png("%s/gallery_%d_later.png" % [out, pg + 1])

	get_tree().quit()


func _process(delta: float) -> void:
	anim_time += delta

	for sp in spinners:
		if is_instance_valid(sp["node"]):
			VillageAnim.apply(sp["node"] as Node3D, sp["mats"], sp["an"], anim_time, delta)

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
		KEY_4:
			_show_page(3)
		KEY_5:
			_show_page(4)
		KEY_6:
			_show_page(5)
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
	var count: int = VillageAssets.STALL_TYPES.size() if str(pg["kind"]) == "stall" else ((pg["cases"] as Array).size() if pg.has("cases") else (pg["names"] as Array).size())
	var rows: int = int(ceil(float(count) / float(cols)))
	var step: Vector2 = _step(pg)
	var cx: float = float(cols - 1) * step.x * 0.5 + cam_pan.x
	var cz: float = float(rows - 1) * step.y * 0.5 + cam_pan.y
	cam.size = cam_zoom
	cam.position = Vector3(cx, 1.5, cz) + cam.transform.basis.z * 40.0


func _step(pg: Dictionary) -> Vector2:
	var kind: String = str(pg["kind"])

	if kind == "stall":
		return Vector2(4.6, 3.6)

	if kind == "shape":
		return Vector2(8.5, 8.5)

	if kind == "propvar":
		return Vector2(4.8, 4.8)

	return Vector2(7.5, 7.5)


func _show_page(i: int) -> void:
	page = i
	cam_pan = Vector2.ZERO
	var zk: String = str(PAGES[i]["kind"])
	cam_zoom = 14.0 if zk == "stall" else (24.0 if zk == "shape" else (16.0 if zk == "propvar" else 15.0))
	spinners.clear()

	if holder != null:
		holder.queue_free()

	holder = Node3D.new()
	vp.add_child(holder)
	var pg: Dictionary = PAGES[i]
	var p: Dictionary = {"ts": 18, "block_px": 22, "unit_px_z": (36.0 / sqrt(2.0)) * cos(deg_to_rad(30.0))}
	var step: Vector2 = _step(pg)
	var cols: int = int(pg["cols"])

	if str(pg["kind"]) == "shape" or str(pg["kind"]) == "propvar":
		var rules0: Array = VillageMirror.load_rules()
		var cases: Array = pg["cases"]

		for k in range(cases.size()):
			var rule0: Dictionary = VillageMirror.find_rule(rules0, str(cases[k][0]))
			var center0 := Vector2(float(k % cols) * step.x, float(k / cols) * step.y)
			var cw0: float = float(rule0.get("canon_w", 3.0))
			var cd0: float = float(rule0.get("canon_d", 3.0))
			rule0 = VillageMirror.apply_variation(rule0, absi(hash("s%d_%d_%d" % [i, k, seed_shift])) % 100003)

			if str(pg["kind"]) == "shape":
				rule0["roof_kind"] = cases[k][1]
				rule0["shape"] = cases[k][2]
				rule0["floors"] = 2 if "jetty" in str(cases[k][2]) else 1

				if int(rule0["floors"]) == 2:
					rule0["height_blocks"] = maxf(float(rule0.get("height_blocks", 2.2)), 3.3)
			else:
				rule0["variant"] = cases[k][1]
				rule0["style"] = cases[k][2]
				rule0["kind"] = "prop"

			var lo0: Vector2 = center0 - Vector2(cw0, cd0) * 0.5
			var hi0: Vector2 = center0 + Vector2(cw0, cd0) * 0.5
			var built0: Dictionary = VillageAssets.build_gable(lo0, hi0, rule0, p) if str(rule0.get("kind", "gable")) == "gable" else VillageAssets.build_prop(str(rule0.get("style", "")), lo0, hi0, rule0, p)
			_add_mesh(built0["mesh"], built0["specs"], Vector3.ZERO)

			if built0.get("display", null) != null:
				_add_mesh(built0["display"]["mesh"], built0["display"]["specs"], Vector3.ZERO)

			for an0 in built0.get("anim", []):
				var node0 := _add_mesh(an0["mesh"], an0["specs"], an0["pos"])
				spinners.append({"node": node0, "an": an0, "mats": node_mats(node0)})

			if built0.get("apron", null) != null:
				var ap0: Dictionary = built0["apron"]
				var m0 := VillageAssets.make_material(ap0["spec"])
				m0.set_shader_parameter("use_sort", false)
				var mi0 := MeshInstance3D.new()
				mi0.mesh = ap0["mesh"]
				mi0.material_override = m0
				mi0.position.y = 0.01
				holder.add_child(mi0)
	elif str(pg["kind"]) == "stall":
		var kinds: Array = VillageAssets.STALL_TYPES.keys()

		for k in range(kinds.size()):
			var origin := Vector2(float(k % cols) * step.x, float(k / cols) * step.y)
			var built: Dictionary = VillageAssets.build_prop("stall", origin - Vector2(1.5, 0.7), origin + Vector2(1.5, 0.7), {"variant": kinds[k]}, p)
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
				spinners.append({"node": node, "an": an, "mats": node_mats(node)})

	label.text = "%d) %s   — 1~6 쪽 전환 / 방향키 이동 / +- 확대 / R 색 다시 뽑기" % [i + 1, str(pg["title"])]
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


func node_mats(node: MeshInstance3D) -> Array:
	var out: Array = []

	for i in range(node.mesh.get_surface_count()):
		out.append(node.get_surface_override_material(i))

	return out
