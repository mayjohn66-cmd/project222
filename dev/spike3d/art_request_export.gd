extends Node
## 그림 요청용 "미리 출력": 마을 건물·소품 3D 모양(VillageAssets, 실제 게임과 같은 코드)의 면 질감 틀과 격리 미리보기를 PNG/JSON 으로 내보낸다.
## 인자: --out <폴더>  (기본 res://docs/drafts/art_requests)  →  <폴더>/<id>/face_*.png, preview.png, 그리고 assets.json (2D 원본은 복사하지 않고 경로만 적음)
## 틀 질감은 코드로 칠한 임시 그림이다: 크기와 면 배치가 "실제로 요청할 그림의 규격"이고, 그림 담당이 이 위에 새로 그린다.

const PREVIEW_BUILDING: int = 176  # 건물 미리보기 낮은 해상도 한 변(px). 3배 확대해 저장
const PREVIEW_PROP: int = 96  # 소품은 작아서 더 좁게 잡는다
const SHRINK: int = 3
const TILE_LOW: float = 36.0
const SURFACE_SHADER: Shader = preload("res://script/world/view3d/shader/sorted_surface.gdshader")

var out_dir: String = ""
var only_id: String = ""  # --only <id>: 한 자산만 다시 내보낸다(assets.json 은 덮어쓰지 않음)


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	out_dir = ProjectSettings.globalize_path("res://docs/drafts/art_requests")

	for i in range(args.size()):
		if args[i] == "--out" and i + 1 < args.size():
			out_dir = args[i + 1]

		if args[i] == "--only" and i + 1 < args.size():
			only_id = args[i + 1]

	DirAccess.make_dir_recursive_absolute(out_dir)
	var rules: Array = VillageMirror.load_rules()
	var p: Dictionary = VillageAssets.default_params(18, 22.0, TILE_LOW)
	var assets: Array = _read_assets()
	var result: Array = []

	for a in assets:
		if only_id != "" and str(a["id"]) != only_id:
			continue

		var text: String = (str(a["id"]) + " " + str(a["sprite"])).to_lower()
		var rule: Dictionary = VillageMirror.find_rule(rules, str(a["sprite"]).to_lower())

		if rule.is_empty():
			print("규칙 없음: ", a["id"])
			continue

		var cw: float = float(rule.get("canon_w", 2.0))
		var cd: float = float(rule.get("canon_d", 2.0))
		var lo := Vector2(-cw * 0.5, -cd * 0.5)
		var hi := Vector2(cw * 0.5, cd * 0.5)
		var built: Dictionary

		if str(rule["kind"]) == "gable":
			built = VillageAssets.build_gable(lo, hi, rule, p)
		else:
			built = VillageAssets.build_prop(str(rule.get("style", "")), lo, hi, rule, p)

		var folder: String = "%s/%s" % [out_dir, a["id"]]
		DirAccess.make_dir_recursive_absolute(folder)
		var faces: Array = _save_faces(folder, built["specs"], p)
		await _render_preview(folder + "/preview.png", built, p, PREVIEW_BUILDING if str(a["kind_group"]) == "building" else PREVIEW_PROP)
		var src_path: String = str(a["sprite"])  # 2D 원본은 복사하지 않고 경로만 기록(저장소 크기 때문)

		result.append({"id": a["id"], "label": a["label"], "group": a["kind_group"], "notes": a["notes"], "sprite": src_path, "kind": rule["kind"], "style": rule.get("style", ""), "canon_w": cw, "canon_d": cd, "total_blocks": built["total_blocks"], "faces": faces, "has_apron": built["apron"] != null, "tint": (rule.get("tint", Color.WHITE) as Color).to_html(false), "roof_tint": (rule.get("roof_tint", Color.WHITE) as Color).to_html(false), "awning_tint": (rule.get("awning_tint", Color.WHITE) as Color).to_html(false), "wall_blocks": rule.get("height_blocks", 0.0), "roof_blocks": rule.get("roof_blocks", 0.0)})

		if built["apron"] != null:
			var ap: Dictionary = built["apron"]
			var apron_faces: Array = _save_faces(folder, [ap["spec"]], p)
			result[-1]["faces"] += apron_faces

	if only_id == "":
		var f := FileAccess.open(out_dir + "/assets.json", FileAccess.WRITE)
		f.store_string(JSON.stringify(result, "  "))
		f.close()
	print("art_request_export done: ", result.size(), " assets -> ", out_dir)
	get_tree().quit()


func _read_assets() -> Array:
	var assets: Array = []
	var file := FileAccess.open("res://data/shop/catalogs/village_3d_assets.csv", FileAccess.READ)
	var header: PackedStringArray = file.get_csv_line()

	while not file.eof_reached():
		var cells: PackedStringArray = file.get_csv_line()

		if cells.size() < header.size() or cells[0].strip_edges().is_empty():
			continue

		var d: Dictionary = {}

		for i in range(header.size()):
			d[header[i].strip_edges()] = cells[i].strip_edges()

		assets.append(d)

	return assets


# 이름이 같은 면(여러 부품이 같은 질감을 쓸 때)은 한 번만 저장한다.
func _save_faces(folder: String, specs: Array, p: Dictionary) -> Array:
	var faces: Array = []
	var seen: Dictionary = {}

	for s in specs:
		var name: String = str(s["name"])

		if seen.has(name):
			continue

		seen[name] = true
		var tex: ImageTexture = s["tex"]
		var img: Image = tex.get_image()
		img.convert(Image.FORMAT_RGBA8)
		img.save_png("%s/face_%s.png" % [folder, name])
		var entry: Dictionary = {"name": name, "file": "face_%s.png" % name, "w": img.get_width(), "h": img.get_height(), "note": s.get("note", ""), "tileable": img.get_width() == int(p["ts"]) and img.get_height() == int(p["ts"]), "normal_file": ""}

		if s.get("normal", null) != null:
			var nimg: Image = (s["normal"] as ImageTexture).get_image()
			nimg.convert(Image.FORMAT_RGBA8)
			nimg.save_png("%s/face_%s_n.png" % [folder, name])
			entry["normal_file"] = "face_%s_n.png" % name

		faces.append(entry)

	return faces


# 격리 미리보기: 게임과 같은 카메라 각도(위 30°, 45° 회전), 낮은 해상도 → 3배 최근접 확대
func _render_preview(path: String, built: Dictionary, p: Dictionary, low: int) -> void:
	var vp := SubViewport.new()
	vp.size = Vector2i(low, low)
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_DISABLED
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.rotation_degrees = Vector3(-30.0, 45.0, 0.0)
	cam.size = float(low) / (TILE_LOW / sqrt(2.0))
	cam.near = 0.1
	cam.far = 100.0
	var total_h: float = VillageAssets.block_h(float(built["total_blocks"]), p)
	var target := Vector3(0.0, total_h * 0.38, 0.0)
	vp.add_child(cam)
	cam.position = target + cam.basis.z * 30.0
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, 25, 0)
	sun.light_energy = 1.1
	sun.shadow_enabled = true
	vp.add_child(sun)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.5, 0.55, 0.62)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.7, 0.72, 0.8)
	env.ambient_light_energy = 0.55
	var we := WorldEnvironment.new()
	we.environment = env
	vp.add_child(we)

	# 바닥(풀) — 순번 -1, 마당 -0.5, 물체 0 (store_view_3d 와 같은 규칙, 순번 개수 1)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(14, 14)
	ground.mesh = plane
	var gm := ShaderMaterial.new()
	gm.shader = SURFACE_SHADER
	gm.set_shader_parameter("albedo_tex", PlaceholderTextures.albedo("grass", int(p["ts"])))
	gm.set_shader_parameter("tint", Color(0.62, 0.6, 0.46))
	gm.set_shader_parameter("rank", -1.0)
	gm.set_shader_parameter("rank_count", 1.0)
	ground.material_override = gm
	vp.add_child(ground)

	if built["apron"] != null:
		var ap: Dictionary = built["apron"]
		var mi := MeshInstance3D.new()
		mi.mesh = ap["mesh"]
		var am: ShaderMaterial = VillageAssets.make_material(ap["spec"])
		am.set_shader_parameter("rank", -0.5)
		am.set_shader_parameter("rank_count", 1.0)
		mi.set_surface_override_material(0, am)
		vp.add_child(mi)

	var item := MeshInstance3D.new()
	item.mesh = built["mesh"]
	var mats: Array = VillageAssets.make_materials(built["specs"])

	for i in range(mats.size()):
		(mats[i] as ShaderMaterial).set_shader_parameter("rank", 0.0)
		(mats[i] as ShaderMaterial).set_shader_parameter("rank_count", 1.0)
		item.set_surface_override_material(i, mats[i])

	vp.add_child(item)

	for i in range(6):
		await get_tree().process_frame

	var img: Image = vp.get_texture().get_image()
	img.resize(low * SHRINK, low * SHRINK, Image.INTERPOLATE_NEAREST)
	img.save_png(path)
	vp.queue_free()
