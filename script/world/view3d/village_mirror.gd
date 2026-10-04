class_name VillageMirror
extends RefCounted
## 마을(매장 바깥)을 3D 도트 방식으로 옮기는 "읽기 전용 거울". StoreView3D 가 소유한다.
## 읽는 곳: StoreExterior(칸마다 풀·길·보도 → 바닥), 마을 노드들의 StaticBody2D(발자국 충돌 모양 → 상자).
## 높이·질감은 data/shop/catalogs/village_3d.csv 의 규칙(노드 이름 또는 스프라이트 그림 파일 이름에 포함된 글자)으로 정한다. 규칙이 없으면 스프라이트 높이로 추정한다.
## 게임 코드는 수정하지 않는다(2D 숨김은 StoreView3D 가 visible 만 바꿈).

var _hidden: Dictionary = {}  # 계절로 숨긴 물체 key → 서명
var _footprints: Dictionary = {}  # 물체 key → 3D 발자국(칸 좌표 Rect2)
const COLLISION_3D := "Collision3D"
const COLLISION_INSET := 0.04  # 보이는 발자국보다 살짝 안쪽(칸)
const CONTAINERS: Array = ["NearbyHouses", "VillageExtraHouses", "VillageBlacksmith", "VillageToolShop", "VillageBuildings", "VillageDecor", "VillageGathering", "DungeonRoadside", "DungeonWall"]
const RULES_PATH: String = "res://data/shop/catalogs/village_3d.csv"
const GROUND_TEXTURES: Dictionary = {"grass": ["grass", Color(0.62, 0.6, 0.46)], "road": ["brick", Color(0.5, 0.46, 0.46)], "paving": ["brick", Color(0.82, 0.76, 0.68)]}
# 깔끔한 스타일(PlaceholderTextures.clean)용: 질감 자체가 이미 밝은 색이라 곱하는 색을 거의 1 로 둔다.
const GROUND_TEXTURES_CLEAN: Dictionary = {"grass": ["grass", Color(1.0, 1.0, 1.0)], "road": ["brick", Color(0.96, 0.96, 0.98)], "paving": ["brick", Color(1.0, 0.93, 0.8)]}

# 같은 규칙을 쓰는 집(vary=1)마다 다르게 보이게 하는 색 조합(건물 번호로 정해져서 다시 만들어도 같다).
const ROOF_PALETTE: Array = ["b8503c", "4a8a5a", "5a80ac", "c8a450", "8068a0", "b0784e", "58908c", "a04c5c"]
const WALL_PALETTE: Array = ["eadfc8", "f2e6c0", "dcc8a0", "e8d0c0", "d8e0d0", "e0d8e8"]
const TRIM_PALETTE: Array = ["5c8a7a", "9a5a3a", "4a6a9a", "7a9a4a", "8a5a8a", "c08a3a"]


const TREE_VARIANTS: Array = ["round", "pine", "birch", "big_oak", "round", "autumn", "pine", "cherry", "poplar", "birch", "willow", "round", "big_oak", "cherry", "dead"]


static func apply_variation(rule: Dictionary, seed_value: int) -> Dictionary:
	if str(rule.get("style", "")) == "tree" and str(rule.get("variant", "")) == "":
		var tr: Dictionary = rule.duplicate()
		tr["variant"] = TREE_VARIANTS[(absi(seed_value * 2654435761) % 1000003 / 16) % TREE_VARIANTS.size()]
		return tr

	if not bool(rule.get("vary", false)):
		return rule

	var r: Dictionary = rule.duplicate()
	var h: int = absi(seed_value * 2654435761) % 1000003
	r["roof_tint"] = Color.html(ROOF_PALETTE[h % ROOF_PALETTE.size()])
	r["tint"] = Color.html(WALL_PALETTE[(h / 8) % WALL_PALETTE.size()])
	r["shutter_tint"] = Color.html(TRIM_PALETTE[(h / 64) % TRIM_PALETTE.size()])
	var kinds: Array = ["gable", "hip", "cross", "gambrel", "mansard", "half_hip", "gable", "cross"]
	r["roof_kind"] = kinds[(h / 512) % kinds.size()]
	# 모양 묶음(포치·지붕창·돌출 창·별채·탑·2층 허리 보)을 집마다 다르게. CSV 에 shape 가 이미 있으면 그대로 둔다.
	var shape: String = str(rule.get("shape", ""))

	if shape == "" or shape == "auto":
		shape = HouseShapes.COMBOS[(h / 1024) % HouseShapes.COMBOS.size()]

	r["shape"] = shape

	if HouseShapes.has(PackedStringArray(shape.split(";", false)), "jetty"):
		r["floors"] = 2
		r["height_blocks"] = maxf(float(rule.get("height_blocks", 2.2)), 3.3)

	if (h / 2048) % 3 == 0:
		var half_w: float = float(rule.get("canon_w", 3.0)) * 0.5
		r["extras"] = (str(rule.get("extras", "")) + ";" if str(rule.get("extras", "")) != "" else "") + "vine:%s:0.0:0.8;vine_side:0.0:0.0:0.9" % str(-half_w + 0.5)
	r["roof_blocks"] = float(rule.get("roof_blocks", 1.4)) * (0.85 + float((h / 4096) % 5) * 0.1)
	return r


var view: Node  # StoreView3D
var exterior: Node2D
var enabled: bool = true
var rules: Array = []
var _ground: Dictionary = {}  # 종류 → {mesh, material, id_mesh, id_material}
var _ground_signature: String = ""
var _object_signature: String = ""
var _keys: Dictionary = {}  # 이번에 만든 항목 키 → true
var _tuft_keys: Array = []  # 풀 다발 항목 키(물체 정리 대상이 아니라 따로 관리)
var _anims: Dictionary = {}  # 움직이는 부품 항목 키 → VillageAnim 항목(mode, speed, ...)
var _time: float = 0.0


func _init(owner_view: Node, exterior_node: Node2D) -> void:
	view = owner_view
	exterior = exterior_node
	_load_rules()


func _load_rules() -> void:
	rules = load_rules()


# 규칙 표(CSV)를 읽는다. 마을 거울과 그림 요청 내보내기가 같이 쓴다.
static func load_rules() -> Array:
	var result: Array = []
	var file := FileAccess.open(RULES_PATH, FileAccess.READ)

	if file == null:
		return result

	var header: PackedStringArray = file.get_csv_line()

	while not file.eof_reached():
		var cells: PackedStringArray = file.get_csv_line()

		if cells.size() < header.size() or cells[0].strip_edges().is_empty():
			continue

		var r: Dictionary = {}

		for i in range(header.size()):
			var key: String = header[i].strip_edges()
			var value: String = cells[i].strip_edges()

			if value.is_empty():
				continue

			if key in ["height_blocks", "roof_blocks", "footprint_scale", "apron", "canon_w", "canon_d"]:
				r[key] = float(value)
			elif key in ["chimney", "awning", "step", "planters", "sign", "plinth", "shutters", "vary"]:
				r[key] = value == "1" or value.to_lower() == "true"
			elif key in ["tint", "roof_tint", "awning_tint", "goods_tint", "shutter_tint"]:
				r[key] = Color.html(value)
			elif key == "match":
				r[key] = value.to_lower()
			else:
				r[key] = value

		result.append(r)

	return result


# 규칙 찾기: 노드 이름 + 스프라이트 그림 경로(소문자)에 match 글자가 들어 있는 첫 규칙. 먼저 나온 행이 우선(구체적인 것을 위에).
func _find_rule(text: String) -> Dictionary:
	return find_rule(rules, text)


static func find_rule(rule_list: Array, text: String) -> Dictionary:
	for r in rule_list:
		if text.find(r["match"]) >= 0:
			return r

	return {}


# ---------------------------------------------------------------- 바닥

func _cell_kind(cell: Vector2i) -> String:
	var painted: String = exterior.get_layout_tile(cell)

	if painted == "road":
		return "paving"

	if painted == "grass":
		return "grass"

	var kind: String = "grass"

	if exterior._is_route_road(cell) or exterior._is_road_cell(cell):
		kind = "road"
	elif exterior._is_sidewalk_cell(cell):
		kind = "paving"

	if exterior.get_route_rect().has_point(cell) or exterior.get_forecourt_rect().has_point(cell):
		kind = "paving" if (exterior._is_route_road(cell) or exterior._is_village_courtyard(cell)) else "grass"

		if exterior.get_village_square_rect().has_point(cell):
			kind = "road"

	return kind


func sync_ground() -> void:
	var cells: Array[Vector2i] = exterior.get_connected_map_cells()
	var store_rect: Rect2i = view.floor_node.get_store_rect()
	var sig: String = "%d|%s|%d|%s|%s" % [cells.size(), str(exterior.get_village_map_extent()), exterior._layout_tiles.hash(), str(store_rect), season]

	if sig == _ground_signature:
		return

	_ground_signature = sig
	var per_kind: Dictionary = {}

	for cell in cells:
		if store_rect.has_point(cell):
			continue  # 매장 안쪽 바닥은 StoreView3D 가 그림

		var kind: String = _cell_kind(cell)

		if not per_kind.has(kind):
			per_kind[kind] = []

		(per_kind[kind] as Array).append(cell)

	for kind in _ground.keys():
		(_ground[kind]["mesh"] as Node).queue_free()
		(_ground[kind]["id_mesh"] as Node).queue_free()

	_ground.clear()

	for kind in per_kind.keys():
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)

		for cell in per_kind[kind]:
			var x0: float = float(cell.x) - 0.5
			var z0: float = float(cell.y) - 0.5
			var quad: Array = [Vector3(x0, 0, z0), Vector3(x0 + 1, 0, z0), Vector3(x0 + 1, 0, z0 + 1), Vector3(x0, 0, z0 + 1)]

			for idx in [0, 1, 2, 0, 2, 3]:
				st.set_normal(Vector3.UP)
				st.add_vertex(quad[idx])

		var mesh: ArrayMesh = st.commit()
		var ground_table: Dictionary = GROUND_TEXTURES_CLEAN if PlaceholderTextures.clean else GROUND_TEXTURES
		var info: Array = ground_table.get(kind, ground_table["grass"])
		var sst: Dictionary = SeasonStyle.style(season if season != "" else "spring")
		info = [info[0], info[1]]

		if kind == "grass":
			info[0] = str(sst["grass_kind"])
			info[1] = (info[1] as Color) * (sst["grass_tint"] as Color)
		elif kind == "road":
			info[1] = (info[1] as Color) * (sst["road_tint"] as Color)
		else:
			info[1] = (info[1] as Color) * (sst["paving_tint"] as Color)

		var material: ShaderMaterial = view._make_surface_material(str(info[0]), info[1])
		var inst := MeshInstance3D.new()
		inst.mesh = mesh
		inst.layers = 1
		inst.material_override = material
		view._viewport.add_child(inst)
		var id_inst := MeshInstance3D.new()
		id_inst.mesh = mesh
		id_inst.layers = 2
		id_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var id_material := ShaderMaterial.new()
		id_material.shader = view.ID_SHADER
		id_inst.material_override = id_material
		view._viewport.add_child(id_inst)
		_ground[kind] = {"mesh": inst, "material": material, "id_mesh": id_inst, "id_material": id_material}

	_snow_cells = per_kind.get("grass", [])
	_bush_sig = ""
	_tree_sig = ""

	_puddle_per_kind = per_kind
	_puddle_dirty = true

	if view.decals != null:
		view.decals.clear_prints()

	_snow_dirty = true
	_sync_tufts(per_kind.get("grass", []))


# 이 칸(소수 좌표 가능)이 눈 덮인 풀밭인지(발자국이 남는 곳).
func is_snow_ground(cell: Vector2) -> bool:
	if str(SeasonStyle.style(season if season != "" else "spring").get("grass_kind", "grass")) != "snow":
		return false

	return _cell_kind(Vector2i(roundi(cell.x), roundi(cell.y))) == "grass"


func clear_ground() -> void:
	_clear_tufts()
	_clear_snowmen()
	_clear_bushes()
	_clear_trees()

	for kind in _ground.keys():
		(_ground[kind]["mesh"] as Node).queue_free()
		(_ground[kind]["id_mesh"] as Node).queue_free()

	_ground.clear()


# 돌아가는 부품(풍차 날개 등)을 돌린다. 날개는 건물 앞면(+z)과 같은 평면이므로 그 평면의 수직 축(+z)으로 돌린다. 부품마다 axis 로 바꿀 수 있다.
func tick(delta: float) -> void:
	_time += delta

	for k in _anims.keys():
		if not view._items.has(k):
			continue

		var inst: Node3D = view._items[k]["mesh"]

		if is_instance_valid(inst):
			VillageAnim.apply(inst, view._items[k]["materials"], _anims[k], _time, delta)


var season: String = ""


# 계절이 바뀌면 땅(색·종류)·풀 다발·모든 물체(잎·지붕 눈)를 다시 만들게 한다.
func set_season(season_id: String) -> void:
	if season_id == season:
		return

	season = season_id
	reset_signatures()


func reset_signatures() -> void:
	_hidden.clear()
	_bush_sig = ""
	_tree_sig = ""
	_puddle_dirty = true
	_snow_dirty = true
	_ground_signature = ""
	_object_signature = ""


# 바닥은 가장 뒤(순번 -1)에 그린다. 순번 개수가 바뀔 때마다 갱신.
func update_ground_params(count: float) -> void:
	for kind in _ground.keys():
		var g: Dictionary = _ground[kind]
		(g["material"] as ShaderMaterial).set_shader_parameter("rank", -1.0)
		(g["material"] as ShaderMaterial).set_shader_parameter("rank_count", count)
		(g["material"] as ShaderMaterial).set_shader_parameter("center_world", Vector3.ZERO)
		(g["id_material"] as ShaderMaterial).set_shader_parameter("rank", -1.0)
		(g["id_material"] as ShaderMaterial).set_shader_parameter("rank_count", count)
		(g["id_material"] as ShaderMaterial).set_shader_parameter("id", 0.0)



# ---------------------------------------------------------------- 풀 다발(십자 컷아웃)

const TUFT_CHUNK: int = 8
const CUTOUT_SHADER: Shader = preload("res://script/world/view3d/shader/cutout.gdshader")
const TUFT_RANK: float = -0.6  # 바닥(-1) 위, 돌 마당(-0.5)·모든 물체 뒤


func _cutout_material(texture: Texture2D) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = CUTOUT_SHADER
	m.set_shader_parameter("albedo_tex", texture)
	return m


func _clear_tufts() -> void:
	for k in _tuft_keys:
		view._remove_item(str(k))

	_tuft_keys.clear()


# 풀밭 칸 일부에 작은 풀 다발을 십자(서로 직각인 두 장, 앞뒤 양면)로 세운다. 투명 컷아웃이라 사각형이 아니라 풀 모양으로 보인다.
# 칸 위치로 결정되는 값(무작위 아님)이라 다시 만들어도 같은 자리에 난다. 윤곽선 판에는 넣지 않는다.
func _sync_tufts(grass_cells: Array) -> void:
	_clear_tufts()
	var chunks: Dictionary = {}

	for cell in grass_cells:
		var ck := Vector2i(int(floorf(float(cell.x) / float(TUFT_CHUNK))), int(floorf(float(cell.y) / float(TUFT_CHUNK))))

		if not chunks.has(ck):
			chunks[ck] = []

		(chunks[ck] as Array).append(cell)

	var sst: Dictionary = SeasonStyle.style(season if season != "" else "spring")

	if float(sst["tufts"]) < 0.5:
		return  # 겨울: 눈에 덮여 풀 다발이 없다

	var mat_plain: ShaderMaterial = _cutout_material(PlaceholderTextures.grass_tuft(false))
	mat_plain.set_shader_parameter("tint", sst["tuft_tint"])
	var mat_flowers: Array = []  # 꽃 색 4가지마다 재질 하나

	for fv in range(4):
		var mf: ShaderMaterial = _cutout_material(PlaceholderTextures.grass_tuft(true, fv))
		mf.set_shader_parameter("tint", sst["tuft_tint"])
		mat_flowers.append(mf)

	var density: float = float(sst.get("tuft_density", 0.56))
	var flower_rate: float = float(sst["flower_rate"])
	var tuft_h: float = float(sst.get("tuft_height", 1.0))
	var half_w: float = 0.2 * (1.0 + 0.25 * (tuft_h - 1.0))
	var height: float = 0.32 * tuft_h

	for ck in chunks.keys():
		var st_plain := SurfaceTool.new()
		st_plain.begin(Mesh.PRIMITIVE_TRIANGLES)
		var st_flowers: Array = []

		for fv in range(4):
			var stf := SurfaceTool.new()
			stf.begin(Mesh.PRIMITIVE_TRIANGLES)
			st_flowers.append(stf)

		var n_plain: int = 0
		var n_flower: Array = [0, 0, 0, 0]
		var lo := Vector2(INF, INF)
		var hi := Vector2(-INF, -INF)

		for cell in chunks[ck]:
			var h: int = absi((cell.x * 73856093) ^ (cell.y * 19349663)) % 1000

			if float(h) >= density * 1000.0:
				continue

			# 풀이 무성한 계절(density 높음)은 한 칸에 최대 셋까지 난다.
			var count: int = 1

			if float(h) < density * 250.0:
				count = 2

			if density > 0.8 and float(h) < density * 90.0:
				count = 3

			for k in range(count):
				var hh: int = absi(h * 31 + k * 977) % 1000
				var cx: float = float(cell.x) + (float(hh % 100) / 100.0 - 0.5) * 0.8
				var cz: float = float(cell.y) + (float((hh / 100) % 10) / 10.0 - 0.5) * 0.8
				var flower: bool = float(hh % 97) < 14.0 * flower_rate
				var fv: int = (hh / 7) % 4

				if flower:
					_add_tuft(st_flowers[fv], cx, cz, half_w, height)
					n_flower[fv] += 1
				else:
					_add_tuft(st_plain, cx, cz, half_w, height * (0.85 + float(hh % 5) * 0.08))  # 키도 제각각
					n_plain += 1

				lo = Vector2(minf(lo.x, cx - half_w), minf(lo.y, cz - half_w))
				hi = Vector2(maxf(hi.x, cx + half_w), maxf(hi.y, cz + half_w))

		if n_plain + int(n_flower[0]) + int(n_flower[1]) + int(n_flower[2]) + int(n_flower[3]) == 0:
			continue

		var mesh := ArrayMesh.new()
		var mats: Array = []

		if n_plain > 0:
			st_plain.commit(mesh)
			mats.append(mat_plain)

		for fv in range(4):
			if int(n_flower[fv]) > 0:
				(st_flowers[fv] as SurfaceTool).commit(mesh)
				mats.append(mat_flowers[fv])

		var key: String = "tuft_%d_%d" % [ck.x, ck.y]
		view._set_mesh_item(key, mesh, mats, lo, hi, 0.3, "tuft", TUFT_RANK, false)
		(view._items[key]["mesh"] as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_tuft_keys.append(key)


# 십자 두 장(x 방향, z 방향), 각각 앞뒤 양면. 법선은 위로 기울여 바닥과 비슷한 밝기로 보이게 한다.
static func _add_tuft(st: SurfaceTool, cx: float, cz: float, half_w: float, height: float) -> void:
	var n_front := Vector3(0.0, 0.9, 0.43).normalized()
	var n_back := Vector3(0.0, 0.9, -0.43).normalized()
	var n_right := Vector3(0.43, 0.9, 0.0).normalized()
	var n_left := Vector3(-0.43, 0.9, 0.0).normalized()
	var uv0 := Vector2(0, 1)
	var uv1 := Vector2(1, 1)
	var uv2 := Vector2(1, 0)
	var uv3 := Vector2(0, 0)
	# x 방향 판(z = cz 고정)
	var a := Vector3(cx - half_w, 0.0, cz)
	var b := Vector3(cx + half_w, 0.0, cz)
	var c := Vector3(cx + half_w, height, cz)
	var d := Vector3(cx - half_w, height, cz)
	BuildingMesh._quad(st, a, b, c, d, n_front, uv0, uv1, uv2, uv3)
	BuildingMesh._quad(st, a, b, c, d, n_back, uv0, uv1, uv2, uv3)
	# z 방향 판(x = cx 고정)
	var e := Vector3(cx, 0.0, cz - half_w)
	var f := Vector3(cx, 0.0, cz + half_w)
	var g := Vector3(cx, height, cz + half_w)
	var h2 := Vector3(cx, height, cz - half_w)
	BuildingMesh._quad(st, e, f, g, h2, n_right, uv0, uv1, uv2, uv3)
	BuildingMesh._quad(st, e, f, g, h2, n_left, uv0, uv1, uv2, uv3)


# ---------------------------------------------------------------- 물체

func _footprint_cell_rect(body: StaticBody2D) -> Rect2:
	var points: Array = []

	for child in body.get_children():
		if child.name == COLLISION_3D:
			continue

		if child is CollisionPolygon2D:
			for p in (child as CollisionPolygon2D).polygon:
				points.append(view.world_to_cell(body.to_global((child as Node2D).position + p)))
		elif child is CollisionShape2D:
			var shape: Shape2D = (child as CollisionShape2D).shape

			if shape is CircleShape2D:
				for k in range(8):
					var a: float = TAU * float(k) / 8.0
					points.append(view.world_to_cell(body.to_global((child as Node2D).position + Vector2(cos(a), sin(a)) * (shape as CircleShape2D).radius)))
			elif shape is RectangleShape2D:
				var e: Vector2 = (shape as RectangleShape2D).size * 0.5

				for corner in [Vector2(-e.x, -e.y), Vector2(e.x, -e.y), Vector2(e.x, e.y), Vector2(-e.x, e.y)]:
					points.append(view.world_to_cell(body.to_global((child as Node2D).position + corner)))

	if points.is_empty():
		return Rect2()

	var lo: Vector2 = points[0]
	var hi: Vector2 = points[0]

	for p in points:
		lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.y))
		hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.y))

	return Rect2(lo, hi - lo)


func _sprite_info(body: StaticBody2D) -> Dictionary:
	for child in body.get_children():
		if child is Sprite2D and (child as Sprite2D).texture != null:
			var sprite := child as Sprite2D
			return {"path": sprite.texture.resource_path.to_lower(), "height_px": float(sprite.texture.get_height()) * absf(sprite.scale.y)}

	return {"path": "", "height_px": 0.0}


# 3D 로 보이는 발자국(칸 좌표 사각형)과 같은 충돌 다각형을 몸체에 달고, 옛 2D 충돌 모양은 꺼 둔다.
func _apply_collision(body: StaticBody2D, lo: Vector2, hi: Vector2, blocked_off: bool = false) -> void:
	var poly := body.get_node_or_null(COLLISION_3D) as CollisionPolygon2D

	if poly == null:
		poly = CollisionPolygon2D.new()
		poly.name = COLLISION_3D
		body.add_child(poly)
		var off: Array = []

		for child in body.get_children():
			if child != poly and (child is CollisionPolygon2D or child is CollisionShape2D) and not (child as Node).get("disabled"):
				child.set("disabled", true)
				off.append(str(child.name))

		body.set_meta("c3_off", off)

	poly.disabled = blocked_off

	if blocked_off:
		poly.polygon = PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(0, 1)])  # 숨긴 물체: 충돌 없음(다각형은 자리만 채움)
		return

	var inset := Vector2(COLLISION_INSET, COLLISION_INSET)
	var a: Vector2 = lo + inset
	var b: Vector2 = hi - inset
	var pts := PackedVector2Array()

	for c in [Vector2(a.x, a.y), Vector2(b.x, a.y), Vector2(b.x, b.y), Vector2(a.x, b.y)]:
		pts.append(body.to_local(view.cell_to_world(c)))

	poly.polygon = pts


var _snow_cells: Array = []
var _snow_keys: Array = []
var _snow_bodies: Array = []  # 눈사람 충돌 몸체(2D). 3D 를 끄면 지운다
var _snow_dirty: bool = true
var _bush_keys: Array = []
var _bush_sig: String = ""
var _tree_keys: Array = []
var _tree_bodies: Array = []
var _tree_sig: String = ""
var _puddle_per_kind: Dictionary = {}
var _puddle_dirty: bool = true


func _clear_snowmen() -> void:
	for k in _snow_keys:
		view._remove_item(str(k))

	_snow_keys.clear()

	for body in _snow_bodies:
		if is_instance_valid(body):
			(body as Node).queue_free()

	_snow_bodies.clear()


# 겨울(snowman_rate > 0): 풀밭 칸 중 아주 일부에 눈사람을 세운다. 칸 위치로 정해지는 값이라 다시 만들어도 같은 자리이고,
# 8칸 구역마다 하나까지, 건물·소품 발자국 근처는 피한다. 충돌은 없는 장식.
func _sync_snowmen() -> void:
	_clear_snowmen()
	var rate: float = float(SeasonStyle.style(season if season != "" else "spring").get("snowman_rate", 0.0))

	if rate <= 0.0:
		return

	var placed: Dictionary = {}
	var p: Dictionary = _params()

	for cell in _snow_cells:
		var h: int = absi((cell.x * 2654435761) ^ (cell.y * 40503 + 17)) % 10000

		if float(h) >= rate * 10000.0:
			continue

		var ck := Vector2i(int(floorf(float(cell.x) / 8.0)), int(floorf(float(cell.y) / 8.0)))

		if placed.has(ck):
			continue

		var spot := Rect2(float(cell.x) - 0.9, float(cell.y) - 0.9, 1.8, 1.8)
		var blocked: bool = false

		for fp in _footprints.values():
			if (fp as Rect2).intersects(spot):
				blocked = true
				break

		if blocked:
			continue

		placed[ck] = true
		var lo := Vector2(float(cell.x) - 0.5, float(cell.y) - 0.5)
		var built: Dictionary = VillageAssets.build_prop("snowman", lo, lo + Vector2.ONE, {}, p)
		var key: String = "snowman_%d_%d" % [cell.x, cell.y]
		view._set_mesh_item(key, built["mesh"], VillageAssets.make_materials(built["specs"]), built["lo"], built["hi"], float(built["total_blocks"]), "snowman", NAN, true)
		_snow_keys.append(key)

		if view.sync_collision and view.world != null:
			var body := StaticBody2D.new()
			body.name = "SnowmanCollider%d_%d" % [cell.x, cell.y]
			body.collision_layer = 1
			body.collision_mask = 0
			view.world.add_child(body)
			var poly := CollisionPolygon2D.new()
			var pts := PackedVector2Array()
			var r: float = 0.3

			for corner in [Vector2(-r, -r), Vector2(r, -r), Vector2(r, r), Vector2(-r, r)]:
				pts.append(body.to_local(view.cell_to_world(Vector2(cell.x, cell.y) + corner)))

			poly.polygon = pts
			body.add_child(poly)
			_snow_bodies.append(body)


func _clear_trees() -> void:
	for k in _tree_keys:
		view._remove_item(str(k))

	_tree_keys.clear()

	for body in _tree_bodies:
		if is_instance_valid(body):
			(body as Node).queue_free()

	_tree_bodies.clear()
	_tree_sig = ""


# 풀밭에 나무가 "자란다": 자리와 종류는 칸 위치로 영구히 정해지고(계절이 바뀌어도 같은 자리), 심어진 날(칸마다 다름)에서 시간이 지날수록
# 묘목 → 어린 나무 → 큰 나무로 커진다. 종류는 계절 규칙(벚꽃은 봄만, 가을 단풍, 겨울 맨가지·일부 사라짐)을 따른다.
# 건물·소품에서 떨어진 곳에만 나고, 줄기 크기의 충돌이 있다. 3그룹(3×3칸 구역)마다 하나까지.
func _sync_trees() -> void:
	var st: Dictionary = SeasonStyle.style(season if season != "" else "spring")
	var rate: float = float(st.get("tree_rate", 0.0))
	var gstate: Dictionary = _grow_state()
	var total_day: int = int(gstate["total"])
	var sig: String = "%s|%d|%d" % [season, total_day / 5, _footprints.size()]

	if sig == _tree_sig:
		return

	_clear_trees()
	_tree_sig = sig

	if rate <= 0.0:
		return

	var p: Dictionary = _params()
	var placed: Dictionary = {}

	for cell in _snow_cells:
		var h: int = absi(((cell.x * 2654435761) ^ (cell.y * 97531)) + 9173) % 10000

		if float(h) >= rate * 10000.0:
			continue

		var gk := Vector2i(int(floorf(float(cell.x) / 3.0)), int(floorf(float(cell.y) / 3.0)))

		if placed.has(gk):
			continue

		var age: int = total_day + (h % 150)
		var scale_f: float = 0.45 if age < 20 else (0.65 if age < 50 else (0.85 if age < 90 else 1.0))
		var spot := Rect2(float(cell.x) - 0.5 - 1.2, float(cell.y) - 0.5 - 1.2, 1.0 + 2.4, 1.0 + 2.4)
		var blocked: bool = false

		for fp in _footprints.values():
			if (fp as Rect2).intersects(spot):
				blocked = true
				break

		if blocked:
			continue

		var variant: String = TREE_VARIANTS[(h / 16) % TREE_VARIANTS.size()]
		var rule: Dictionary = {"style": "tree", "kind": "prop", "variant": variant, "generated": true}
		rule = SeasonStyle.adjust_rule(rule, season if season != "" else "spring", h)

		if bool(rule.get("season_hide", false)):
			continue

		placed[gk] = true
		var half := Vector2(0.5, 0.5)
		var built: Dictionary = VillageAssets.build_prop("tree", -half, half, rule, p)
		SeasonStyle.tint_specs(built["specs"], rule, season if season != "" else "spring")
		var key: String = "tree_%d_%d" % [cell.x, cell.y]
		var lo := Vector2(float(cell.x) - 0.5, float(cell.y) - 0.5)
		view._set_mesh_item(key, built["mesh"], VillageAssets.make_materials(built["specs"]), lo, lo + Vector2.ONE, float(built["total_blocks"]) * scale_f, "tree", NAN, true)
		var inst: MeshInstance3D = view._items[key]["mesh"]
		inst.position = Vector3(float(cell.x), 0.0, float(cell.y))
		inst.scale = Vector3.ONE * scale_f
		_tree_keys.append(key)

		if view.sync_collision and view.world != null:
			var body := StaticBody2D.new()
			body.name = "TreeCollider%d_%d" % [cell.x, cell.y]
			body.collision_layer = 1
			body.collision_mask = 0
			view.world.add_child(body)
			var poly := CollisionPolygon2D.new()
			var pts := PackedVector2Array()
			var r: float = 0.22 * maxf(scale_f, 0.6)

			for corner in [Vector2(-r, -r), Vector2(r, -r), Vector2(r, r), Vector2(-r, r)]:
				pts.append(body.to_local(view.cell_to_world(Vector2(cell.x, cell.y) + corner)))

			poly.polygon = pts
			body.add_child(poly)
			_tree_bodies.append(body)


func _clear_bushes() -> void:
	for k in _bush_keys:
		view._remove_item(str(k))

	_bush_keys.clear()
	_bush_sig = ""


# 날짜 기준 자람 상태: seed(계절 단위, 계절이 바뀌면 배치가 새로 정해진다), day(계절 안 며칠째, 1~28). 개발용으로 계절을 강제하면 다 자란 날(20일)로 본다.
func _grow_state() -> Dictionary:
	var gs: Node = view.get_node_or_null("/root/GameState")

	if view.season_override != "" or gs == null:
		return {"seed": hash(season), "day": 20, "total": 400}

	var td: int = int(gs.get("total_day"))
	return {"seed": (td - 1) / CalendarData.DAYS_PER_SEASON, "day": ((td - 1) % CalendarData.DAYS_PER_SEASON) + 1, "total": td}


# 풀밭에 덤불이 "자란다": 칸 위치와 계절 번호로 자리가 정해지고(같은 계절엔 같은 자리), 계절 안에서 싹 트는 날이 제각각이라
# 처음엔 작고 점점 커지며 늘어난다. 건물·소품 발자국에서 떨어진 곳에만 난다. 충돌은 없는 장식.
func _sync_bushes() -> void:
	var st: Dictionary = SeasonStyle.style(season if season != "" else "spring")
	var rate: float = float(st.get("bush_rate", 0.0))
	var gstate: Dictionary = _grow_state()
	var gday: int = int(gstate["day"])
	var sig: String = "%s|%d|%d|%d" % [season, int(gstate["seed"]), gday / 2, _footprints.size()]

	if sig == _bush_sig:
		return

	_clear_bushes()
	_bush_sig = sig

	if rate <= 0.0:
		return

	var p: Dictionary = _params()
	var seed_v: int = int(gstate["seed"]) * 1000003 + 12345

	for cell in _snow_cells:
		var h: int = absi(((cell.x * 73856093) ^ (cell.y * 19349663)) + seed_v) % 10000

		if float(h) >= rate * 10000.0:
			continue

		var sprout: int = 1 + (h / 7) % 20  # 계절 안에서 싹 트는 날
		var age: int = gday - sprout

		if age < 0:
			continue

		var scale_f: float = 0.5 if age < 3 else (0.78 if age < 7 else 1.0)
		var spot := Rect2(float(cell.x) - 0.5 - 0.7, float(cell.y) - 0.5 - 0.7, 1.0 + 1.4, 1.0 + 1.4)
		var blocked: bool = false

		for fp in _footprints.values():
			if (fp as Rect2).intersects(spot):
				blocked = true
				break

		if blocked:
			continue

		var rule: Dictionary = {"variant": "berry" if (h / 3) % 4 == 0 else ""}
		var half := Vector2(0.5, 0.5)
		var built: Dictionary = VillageAssets.build_prop("flower_bush", -half, half, rule, p)  # 원점 기준으로 만들고 칸 위치로 옮긴다
		SeasonStyle.tint_specs(built["specs"], rule, season if season != "" else "spring")
		var key: String = "bush_%d_%d" % [cell.x, cell.y]
		var lo := Vector2(float(cell.x) - 0.5, float(cell.y) - 0.5)
		view._set_mesh_item(key, built["mesh"], VillageAssets.make_materials(built["specs"]), lo, lo + Vector2.ONE, float(built["total_blocks"]) * scale_f, "bush", NAN, true)
		var inst: MeshInstance3D = view._items[key]["mesh"]
		inst.position = Vector3(float(cell.x), 0.0, float(cell.y))
		inst.scale = Vector3.ONE * scale_f
		_bush_keys.append(key)


func sync_objects(world: Node) -> void:
	var seen: Dictionary = {}
	var parts: PackedStringArray = PackedStringArray()

	for container_name in CONTAINERS:
		var container: Node = world.get_node_or_null(container_name)

		if container == null:
			continue

		for body in container.get_children():
			if not body is StaticBody2D or not (body as StaticBody2D).visible or (body as StaticBody2D).collision_layer == 0:
				continue

			var rect: Rect2 = _footprint_cell_rect(body)

			if rect.size == Vector2.ZERO:
				continue

			var sprite_info: Dictionary = _sprite_info(body)
			var text: String = (str(body.name) + " " + str(sprite_info["path"])).to_lower()
			var obj_seed: int = absi(hash(container_name + "/" + str(body.name))) % 100003
			var rule: Dictionary = apply_variation(_find_rule(text), obj_seed)
			if container_name == "VillageGathering":
				rule = rule.duplicate()
				rule["fixed_spot"] = true  # 채집 자리: 덤불·나무를 랜덤 배치로 바꾸지 않고 그 자리에 둔다

			rule = SeasonStyle.adjust_rule(rule, season if season != "" else "spring", obj_seed)
			var key: String = "vil%d" % body.get_instance_id()
			var sig: String = "%s|%s|%s|%s" % [str(rect.position.snapped(Vector2(0.02, 0.02))), str(rect.size.snapped(Vector2(0.02, 0.02))), text, season]
			seen[key] = true
			parts.append(sig)

			# 계절 때문에 안 보이는 물체(겨울의 덤불·일부 나무): 3D 물체를 만들지 않고 충돌도 끈다.
			if bool(rule.get("season_hide", false)):
				if _hidden.get(key, "") != sig or body.get_node_or_null(COLLISION_3D) == null:
					_remove_keys(key)
					_footprints.erase(key)
					_snow_dirty = true
					_puddle_dirty = true

					if view.sync_collision:
						_apply_collision(body, Vector2.ZERO, Vector2.ZERO, true)

					_hidden[key] = sig

				continue

			_hidden.erase(key)

			if view._items.has(key + "a") and view._items[key + "a"]["signature"] == sig:
				if view.sync_collision and _footprints.has(key) and body.get_node_or_null(COLLISION_3D) == null:
					_apply_collision(body, (_footprints[key] as Rect2).position, (_footprints[key] as Rect2).end)

				continue

			_remove_keys(key)
			_create_object(key, rect, rule, float(sprite_info["height_px"]), sig, body)

	if _snow_dirty:
		_snow_dirty = false
		_sync_snowmen()

	_sync_bushes()
	_sync_trees()

	if _puddle_dirty and view.decals != null:
		_puddle_dirty = false
		var snowy: bool = str(SeasonStyle.style(season if season != "" else "spring").get("grass_kind", "grass")) == "snow"
		view.decals.rebuild_puddles(_puddle_per_kind, snowy, _footprints.values())
		view.decals.rebuild_litter(_puddle_per_kind.get("grass", []), float(SeasonStyle.style(season if season != "" else "spring").get("litter_rate", 0.0)), _footprints.values())

	# 사라진 물체 정리
	for k in _keys.keys():
		var kk: String = str(k)
		var base: String = kk.substr(0, kk.rfind("d")) if kk.rfind("d") > 3 and kk.substr(kk.rfind("d") + 1).is_valid_int() else kk.substr(0, kk.length() - 1)

		if not seen.has(base):
			view._remove_item(str(k))
			_anims.erase(str(k))
			_keys.erase(k)


func _remove_keys(base: String) -> void:
	for suffix in ["a", "b", "c", "d0", "d1", "d2", "d3"]:
		_anims.erase(base + suffix)
		view._remove_item(base + suffix)
		_keys.erase(base + suffix)


func _params() -> Dictionary:
	return {"ts": view.texture_size, "block_px": view.block_px, "unit_px_z": (view.tile_low / sqrt(2.0)) * cos(deg_to_rad(30.0))}


func _create_object(key: String, rect: Rect2, rule: Dictionary, sprite_height_px: float, sig: String, body: StaticBody2D = null) -> void:
	var lo := rect.position
	var hi := rect.position + rect.size
	var kind: String = str(rule.get("kind", "box"))

	# 충돌 발자국은 그림보다 넓으므로 건물·소품 모양은 중심 기준으로 줄인다(footprint_scale).
	var scale_f: float = float(rule.get("footprint_scale", 1.0))
	var center: Vector2 = (lo + hi) * 0.5
	var half: Vector2 = (hi - lo) * 0.5 * scale_f

	# 규칙에 기준 크기(canon_w × canon_d, 칸)가 있으면 발자국 대신 그 크기를 쓴다 → 면 질감(그림) 크기가 종류마다 고정된다.
	# 긴 쪽 방향은 발자국의 긴 쪽에 맞춘다.
	if rule.has("canon_w") and rule.has("canon_d"):
		var cw: float = float(rule["canon_w"])
		var cd: float = float(rule["canon_d"])

		# axis=x 면 긴 쪽을 항상 x(문이 있는 +z 면이 긴 면) 방향으로 둔다. 그 외에는 발자국의 긴 쪽에 맞춘다.
		var swap: bool = ((hi.x - lo.x) >= (hi.y - lo.y)) != (cw >= cd)

		if str(rule.get("axis", "")) == "x":
			swap = cw < cd
		elif str(rule.get("axis", "")) == "y":
			swap = cw > cd  # 긴 쪽을 y(앞뒤)로: 좁은 쪽(박공 끝)이 앞(+z)을 본다

		if swap:
			var tmp: float = cw
			cw = cd
			cd = tmp

		half = Vector2(cw, cd) * 0.5
	half = Vector2(maxf(half.x, 0.15), maxf(half.y, 0.15))
	lo = center - half
	hi = center + half

	_footprints[key] = Rect2(lo, hi - lo)
	_puddle_dirty = true
	_snow_dirty = true  # 새 건물이 생기면 눈사람 자리를 다시 고른다(건물 안에 서지 않게)

	if body != null and view.sync_collision:
		_apply_collision(body, lo, hi)

	if kind == "gable" or kind == "prop":
		var built: Dictionary
		var p: Dictionary = _params()

		if kind == "gable":
			built = VillageAssets.build_gable(lo, hi, rule, p)
		else:
			built = VillageAssets.build_prop(str(rule.get("style", "")), lo, hi, rule, p)

		SeasonStyle.tint_specs(built["specs"], rule, season if season != "" else "spring")

		var has_cutout: bool = false

		for sp in built["specs"]:
			if bool((sp as Dictionary).get("cutout", false)):
				has_cutout = true

		# 투명 컷아웃(상품 카드)이 든 물체는 그림자를 끄고 윤곽선 판에서도 뺀다(셰이더 파일 설명 참고).
		view._set_mesh_item(key + "a", built["mesh"], VillageAssets.make_materials(built["specs"]), built["lo"], built["hi"], float(built["total_blocks"]), sig, NAN, not has_cutout)

		if has_cutout:
			(view._items[key + "a"]["mesh"] as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

		_keys[key + "a"] = true

		var anims: Array = built.get("anim", [])

		for ai in range(anims.size()):
			var an: Dictionary = anims[ai]
			var akey: String = key + "d%d" % ai
			var pos: Vector3 = an["pos"]
			var ahalf: float = float(an.get("half", 1.5))
			view._set_mesh_item(akey, an["mesh"], VillageAssets.make_materials(an["specs"]), Vector2(pos.x - ahalf, pos.z - ahalf), Vector2(pos.x + ahalf, pos.z + ahalf), pos.y + ahalf, sig, NAN, false)
			var ainst: MeshInstance3D = view._items[akey]["mesh"]
			ainst.position = pos
			ainst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			var entry: Dictionary = an.duplicate()
			entry.erase("mesh")
			entry.erase("specs")
			_anims[akey] = entry
			_keys[akey] = true

		if built.get("display", null) != null:
			var dp: Dictionary = built["display"]
			view._set_mesh_item(key + "c", dp["mesh"], VillageAssets.make_materials(dp["specs"]), dp["lo"], dp["hi"], float(dp["total_blocks"]), sig, NAN, false)
			(view._items[key + "c"]["mesh"] as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_keys[key + "c"] = true

		if built["apron"] != null:
			var ap: Dictionary = built["apron"]
			view._set_mesh_item(key + "b", ap["mesh"], [VillageAssets.make_material(ap["spec"])], lo, hi, 0.0, sig, -0.5)
			_keys[key + "b"] = true

		return

	# 규칙이 없는 물체: 2D 그림 높이로 추정한 상자
	var height: float = clampf(sprite_height_px * 0.375 * 0.6 / view.block_px, 0.6, 3.5)
	view._set_item(key + "a", lo, hi, height, "plank", Color(0.75, 0.75, 0.75), sig)
	_keys[key + "a"] = true
