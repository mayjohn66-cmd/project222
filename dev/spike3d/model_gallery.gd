extends Node3D
## 3D 모델 갤러리(개발용): 가구·진열 상품·마을 건물과 소품·캐릭터를 쪽(페이지)별로 한눈에 본다.
## 실행: 이 씬을 열고 F6.   ← → = 쪽 넘기기   ↑ ↓ = 확대/축소   WASD = 화면 이동   R = 가구 회전   Space = 캐릭터 동작 바꾸기
## 스크린샷용 인자: --shot <폴더>  (모든 쪽을 PNG 로 저장하고 끝낸다)

const PITCH_DEG: float = 30.0
const YAW_DEG: float = 45.0
const PAGES: Array = ["가구(계산대·선반·설비·장식·문)", "진열 상품", "마을 건물·소품", "캐릭터", "사람별 외형(손님·직원)"]
const FURNITURE: Array = [
	["register", "계산대", 2, 0.5], ["warehouse_rack", "창고 선반", 2, 1.0], ["magic_oven", "화덕", 2, 1.0],
	["drink_machine", "음료 제조기", 1, 1.0], ["plant_small", "작은 화분", 1, 0.5], ["night_lantern", "심야의 등불", 1, 0.3],
	["antique_cabinet", "골동품 진열장", 1, 1.0], ["fridge_unit", "냉장함", 1, 1.0], ["freezer_unit", "냉동함", 2, 1.0],
]
const WALL_ITEMS: Array = [["wall_poster", "상품 포스터"], ["old_world_map", "낡은 세계지도"], ["adventurer_banner", "모험가 깃발"], ["door", "출입문"], ["warehouse_door", "창고 문"], ["production_door", "생산실 문"]]

var _page: int = 0
var _rot: int = 0
var _cam: Camera3D
var _content: Node3D
var _id_dummy: Node3D
var _title: Label
var _tags: Array = []  # {pos: Vector3, label: Label}
var _target := Vector3.ZERO
var _size: float = 12.0
var _figures: Array = []
var _fig_mode: int = 0
var _fig_timer: float = 0.0
var _p: Dictionary = VillageAssets.default_params(18, 22.0, 36.0, false)
var _shot_dir: String = ""


func _ready() -> void:
	var args := OS.get_cmdline_user_args()

	if args.has("--shot") and args.find("--shot") + 1 < args.size():
		_shot_dir = args[args.find("--shot") + 1]

	_cam = Camera3D.new()
	_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_cam.near = 0.1
	_cam.far = 200.0
	_cam.rotation_degrees = Vector3(-PITCH_DEG, YAW_DEG, 0.0)
	add_child(_cam)
	var sun := DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.rotation_degrees = Vector3(-52.0, 110.0, 0.0)
	sun.light_energy = 0.95
	add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-35.0, -60.0, 0.0)
	fill.light_energy = 0.3
	add_child(fill)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.13, 0.15, 0.14)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.85, 0.88, 0.82)
	env.ambient_light_energy = 0.7
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(120, 120)
	ground.mesh = plane
	ground.position = Vector3(10, -0.02, 10)
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.27, 0.33, 0.27)
	ground.material_override = gm
	add_child(ground)
	_content = Node3D.new()
	add_child(_content)
	_id_dummy = Node3D.new()
	_id_dummy.visible = false
	add_child(_id_dummy)
	var layer := CanvasLayer.new()
	add_child(layer)
	_title = Label.new()
	_title.position = Vector2(14, 8)
	_title.add_theme_font_size_override("font_size", 20)
	_title.add_theme_color_override("font_outline_color", Color.BLACK)
	_title.add_theme_constant_override("outline_size", 6)
	layer.add_child(_title)
	_tag_layer = layer
	_build_page.call_deferred()


var _tag_layer: CanvasLayer


func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return

	match event.keycode:
		KEY_RIGHT:
			_page = (_page + 1) % PAGES.size()
			_build_page()
		KEY_LEFT:
			_page = (_page + PAGES.size() - 1) % PAGES.size()
			_build_page()
		KEY_UP:
			_size = maxf(2.0, _size / 1.15)
		KEY_DOWN:
			_size *= 1.15
		KEY_R:
			_rot = (_rot + 1) % 4

			if _page == 0:
				_build_page()
		KEY_SPACE:
			_fig_mode = (_fig_mode + 1) % 4
		KEY_A:
			_target += Vector3(-1, 0, 1) * 1.5
		KEY_D:
			_target += Vector3(1, 0, -1) * 1.5
		KEY_W:
			_target += Vector3(-1, 0, -1) * 1.5
		KEY_S:
			_target += Vector3(1, 0, 1) * 1.5


func _process(delta: float) -> void:
	_cam.size = _size
	_cam.position = _target + _cam.basis.z * 60.0

	for t in _tags:
		var lab: Label = t["label"]
		var behind: bool = _cam.is_position_behind(t["pos"])
		lab.visible = not behind
		lab.position = _cam.unproject_position(t["pos"]) - Vector2(lab.size.x * 0.5, 0)

	if _page == 3 and not _figures.is_empty():
		_fig_timer += delta

		for i in range(_figures.size()):
			var f: BlockyFigure = _figures[i]
			f.walking = i == 1
			f.move_speed = 2.2

			if i == 2 and _fig_timer > 1.4:
				f.play_attack(0.5)
			if i == 3 and _fig_timer > 1.4:
				f.play_hurt(0.45)

			f.animate(delta)

		if _fig_timer > 1.4:
			_fig_timer = 0.0


# ---------------------------------------------------------------- 쪽 만들기

func _clear() -> void:
	for c in _content.get_children():
		c.queue_free()

	for t in _tags:
		(t["label"] as Label).queue_free()

	_tags.clear()
	_figures.clear()


func _tag(text: String, pos: Vector3) -> void:
	var lab := Label.new()
	lab.text = text
	lab.add_theme_font_size_override("font_size", 13)
	lab.add_theme_color_override("font_outline_color", Color.BLACK)
	lab.add_theme_constant_override("outline_size", 5)
	_tag_layer.add_child(lab)
	_tags.append({"pos": pos, "label": lab})


func _mesh(built: Dictionary, pos: Vector3 = Vector3.ZERO, sc: float = 1.0) -> MeshInstance3D:
	var mats: Array = VillageAssets.make_materials(built["specs"])

	for m in mats:
		(m as ShaderMaterial).set_shader_parameter("use_sort", false)

	var inst := MeshInstance3D.new()
	inst.mesh = built["mesh"]

	for i in range(mats.size()):
		inst.set_surface_override_material(i, mats[i])

	inst.position = pos
	inst.scale = Vector3.ONE * sc
	_content.add_child(inst)
	return inst


func _block(lo: Vector3, hi: Vector3, color: Color) -> void:
	var inst := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = hi - lo
	inst.mesh = bm
	inst.position = (lo + hi) * 0.5
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	inst.material_override = mat
	_content.add_child(inst)


func _build_page() -> void:
	_clear()
	_title.text = "3D 모델 갤러리 · %d/%d  %s     [← →] 쪽  [↑ ↓] 확대  [WASD] 이동  [R] 회전  [Space] 동작" % [_page + 1, PAGES.size(), PAGES[_page]]

	match _page:
		0:
			_page_furniture()
		1:
			_page_goods()
		2:
			_page_village()
		3:
			_page_characters()
		_:
			_page_looks()

	if _shot_dir != "":
		_shoot.call_deferred()


func _page_furniture() -> void:
	_size = 16.0
	_target = Vector3(7.5, 0.0, 6.0)
	var x: float = 0.0

	for e in FURNITURE:
		var fx: int = e[2]
		var d: float = e[3]
		var lo := Vector2(x, 0.0)
		var hi := Vector2(x + fx, d) if _rot % 2 == 0 else Vector2(x + d, float(fx))
		var built: Dictionary = FurnitureAssets.build(e[0], lo, hi, _rot, _p)
		_mesh(built)
		_tag(e[1], Vector3((lo.x + hi.x) * 0.5, 0.0, hi.y + 0.5))
		x += float(maxi(fx, 1)) + 1.2

	# 벽 장식과 문: 뒤 벽 조각에 붙여 보인다(앞 = 방 안쪽 = +z)
	var wx: float = 0.0

	for w in WALL_ITEMS:
		var is_door: bool = str(w[0]).ends_with("door")
		var t: float = 0.3 if is_door else 0.12
		var zc: float = 7.0
		var lo := Vector2(wx, zc - t * 0.5) if is_door else Vector2(wx, zc)
		var hi := Vector2(wx + 1.0, lo.y + t)
		var built: Dictionary = FurnitureAssets.build(w[0], lo, hi, 0, _p)
		var inst: MeshInstance3D = _mesh(built)

		if str(w[0]) in ["wall_poster", "old_world_map"]:
			inst.position.y = 1.0
		elif str(w[0]) == "adventurer_banner":
			inst.position.y = 0.8

		_block(Vector3(wx - 0.4, 0.0, zc - 0.25), Vector3(wx + 1.4, 2.1 if not is_door else 1.9, zc - 0.0 if not is_door else zc - 0.15), Color(0.8, 0.55, 0.45))

		if is_door:
			_block(Vector3(wx - 0.4, 0.0, zc - 0.15), Vector3(wx, 1.9, zc + 0.15), Color(0.8, 0.55, 0.45))
			_block(Vector3(wx + 1.0, 0.0, zc - 0.15), Vector3(wx + 1.4, 1.9, zc + 0.15), Color(0.8, 0.55, 0.45))

		_tag(w[1], Vector3(wx + 0.5, 0.0, zc + 1.2))
		wx += 2.2


func _page_goods() -> void:
	_size = 9.5
	var ids: Array = ItemData.get_sellable_items()
	var cols: int = 10
	_target = Vector3(float(cols) * 0.65, 0.0, float(ids.size() / cols) * 0.85 + 0.5)

	for i in range(ids.size()):
		var id: String = ids[i]
		var gx: float = float(i % cols) * 1.3
		var gz: float = float(i / cols) * 1.7
		_block(Vector3(gx - 0.3, 0.0, gz - 0.3), Vector3(gx + 0.3, 0.06, gz + 0.3), Color(0.78, 0.6, 0.4))
		var built: Dictionary = ShelfAssets.build_good(id, _p, 2.6)
		_mesh(built, Vector3(gx, 0.06, gz))
		_tag("%s · %s" % [ItemData.get_item_name(id), ShelfAssets.shape_of(id)], Vector3(gx, 0.0, gz + 0.55))


func _page_village() -> void:
	_size = 28.0
	var rules: Array = VillageMirror.load_rules()
	var file := FileAccess.open("res://data/shop/catalogs/village_3d_assets.csv", FileAccess.READ)
	var header: PackedStringArray = file.get_csv_line()
	var x: float = 0.0
	var z: float = 0.0
	var row_h: float = 0.0
	var max_x: float = 0.0

	while not file.eof_reached():
		var row: PackedStringArray = file.get_csv_line()

		if row.size() < 4 or row[0].is_empty():
			continue

		var a: Dictionary = {}

		for i in range(mini(header.size(), row.size())):
			a[header[i]] = row[i]

		var rule: Dictionary = VillageMirror.find_rule(rules, str(a["sprite"]).to_lower())

		if rule.is_empty():
			continue

		var cw: float = float(rule.get("canon_w", 2.0))
		var cd: float = float(rule.get("canon_d", 2.0))

		if x + cw > 26.0:
			x = 0.0
			z += row_h + 1.6
			row_h = 0.0

		var lo := Vector2(-cw * 0.5, -cd * 0.5)
		var hi := Vector2(cw * 0.5, cd * 0.5)
		var built: Dictionary

		if str(rule["kind"]) == "gable":
			built = VillageAssets.build_gable(lo, hi, rule, _p)
		else:
			built = VillageAssets.build_prop(str(rule.get("style", "")), lo, hi, rule, _p)

		var pos := Vector3(x + cw * 0.5, 0.0, z + cd * 0.5)
		_mesh(built, pos)
		_tag(str(a["label"]), Vector3(pos.x, 0.0, pos.z + cd * 0.5 + 0.5))
		x += cw + 1.4
		row_h = maxf(row_h, cd)
		max_x = maxf(max_x, x)

	_target = Vector3(max_x * 0.5, 0.0, z * 0.5)


func _page_characters() -> void:
	_size = 5.0
	_target = Vector3(3.0, 0.0, 0.0)
	var names: Array = ["서 있기", "걷기", "공격(검)", "피격"]

	for i in range(4):
		var f := BlockyFigure.new()
		f.build(_content, _id_dummy, 3.0, 1.14, 0.308)
		f.set_sorted(false)
		f.weapon_always = i == 2
		f.facing_yaw_deg = 45.0
		f.position = Vector3(float(i) * 1.8, 0.0, 0.0)
		_figures.append(f)
		_tag(names[i], Vector3(float(i) * 1.8, 0.0, 0.7))


# actor_looks_3d.csv 의 모든 외형을 8열로 늘어놓는다.
func _page_looks() -> void:
	var keys: Array = []
	var file := FileAccess.open(ActorLooks.DATA_PATH, FileAccess.READ)
	file.get_csv_line()

	while not file.eof_reached():
		var cells: PackedStringArray = file.get_csv_line()

		if cells.size() > 1 and not cells[0].is_empty():
			keys.append(cells[0])

	var cols: int = 8
	_size = 17.0
	_target = Vector3(float(cols - 1) * 0.9, 0.0, float((keys.size() - 1) / cols) * 0.9)

	for i in range(keys.size()):
		var pos := Vector3(float(i % cols) * 1.8, 0.0, float(i / cols) * 1.8)
		var f := BlockyFigure.new()
		f.build(_content, _id_dummy, 3.0, 1.14, 0.308, ActorLooks.get_look(keys[i]))
		f.set_sorted(false)
		f.facing_yaw_deg = 45.0
		f.position = pos
		_figures.append(f)
		_tag(keys[i], pos + Vector3(0.0, 0.0, 0.7))


func _shoot() -> void:
	for i in 30:
		await get_tree().process_frame

	DirAccess.make_dir_recursive_absolute(_shot_dir)
	get_viewport().get_texture().get_image().save_png("%s/gallery_%d.png" % [_shot_dir, _page + 1])

	if _page < PAGES.size() - 1:
		_page += 1
		_build_page()
	else:
		get_tree().quit()
