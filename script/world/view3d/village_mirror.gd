class_name VillageMirror
extends RefCounted
## 마을(매장 바깥)을 3D 도트 방식으로 옮기는 "읽기 전용 거울". StoreView3D 가 소유한다.
## 읽는 곳: StoreExterior(칸마다 풀·길·보도 → 바닥), 마을 노드들의 StaticBody2D(발자국 충돌 모양 → 상자).
## 높이·질감은 data/shop/catalogs/village_3d.csv 의 규칙(노드 이름 또는 스프라이트 그림 파일 이름에 포함된 글자)으로 정한다. 규칙이 없으면 스프라이트 높이로 추정한다.
## 게임 코드는 수정하지 않는다(2D 숨김은 StoreView3D 가 visible 만 바꿈).

const CONTAINERS: Array = ["NearbyHouses", "VillageExtraHouses", "VillageBlacksmith", "VillageToolShop", "VillageBuildings", "VillageDecor", "VillageGathering", "DungeonRoadside", "DungeonWall"]
const RULES_PATH: String = "res://data/shop/catalogs/village_3d.csv"
const GROUND_TEXTURES: Dictionary = {"grass": ["grass", Color(0.62, 0.6, 0.46)], "road": ["brick", Color(0.5, 0.46, 0.46)], "paving": ["brick", Color(0.82, 0.76, 0.68)]}
# 깔끔한 스타일(PlaceholderTextures.clean)용: 질감 자체가 이미 밝은 색이라 곱하는 색을 거의 1 로 둔다.
const GROUND_TEXTURES_CLEAN: Dictionary = {"grass": ["grass", Color(1.0, 1.0, 1.0)], "road": ["brick", Color(0.96, 0.96, 0.98)], "paving": ["brick", Color(1.0, 0.93, 0.8)]}

var view: Node  # StoreView3D
var exterior: Node2D
var enabled: bool = true
var rules: Array = []
var _ground: Dictionary = {}  # 종류 → {mesh, material, id_mesh, id_material}
var _ground_signature: String = ""
var _object_signature: String = ""
var _keys: Dictionary = {}  # 이번에 만든 항목 키 → true
var _tuft_keys: Array = []  # 풀 다발 항목 키(물체 정리 대상이 아니라 따로 관리)


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
			elif key in ["chimney", "awning", "step", "planters", "sign", "plinth", "shutters"]:
				r[key] = value == "1" or value.to_lower() == "true"
			elif key in ["tint", "roof_tint", "awning_tint", "goods_tint"]:
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
	var sig: String = "%d|%s|%d|%s" % [cells.size(), str(exterior.get_village_map_extent()), exterior._layout_tiles.hash(), str(store_rect)]

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

	_sync_tufts(per_kind.get("grass", []))


func clear_ground() -> void:
	_clear_tufts()

	for kind in _ground.keys():
		(_ground[kind]["mesh"] as Node).queue_free()
		(_ground[kind]["id_mesh"] as Node).queue_free()

	_ground.clear()


func reset_signatures() -> void:
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

	var mat_plain: ShaderMaterial = _cutout_material(PlaceholderTextures.grass_tuft(false))
	var mat_flower: ShaderMaterial = _cutout_material(PlaceholderTextures.grass_tuft(true))
	var half_w: float = 0.2
	var height: float = 0.32

	for ck in chunks.keys():
		var st_plain := SurfaceTool.new()
		st_plain.begin(Mesh.PRIMITIVE_TRIANGLES)
		var st_flower := SurfaceTool.new()
		st_flower.begin(Mesh.PRIMITIVE_TRIANGLES)
		var n_plain: int = 0
		var n_flower: int = 0
		var lo := Vector2(INF, INF)
		var hi := Vector2(-INF, -INF)

		for cell in chunks[ck]:
			var h: int = absi((cell.x * 73856093) ^ (cell.y * 19349663)) % 1000

			if h >= 560:
				continue

			var count: int = 2 if h < 140 else 1

			for k in range(count):
				var hh: int = absi(h * 31 + k * 977) % 1000
				var cx: float = float(cell.x) + (float(hh % 100) / 100.0 - 0.5) * 0.7
				var cz: float = float(cell.y) + (float((hh / 100) % 10) / 10.0 - 0.5) * 0.7
				var flower: bool = (hh % 7) == 0
				var st: SurfaceTool = st_flower if flower else st_plain
				_add_tuft(st, cx, cz, half_w, height)

				if flower:
					n_flower += 1
				else:
					n_plain += 1

				lo = Vector2(minf(lo.x, cx - half_w), minf(lo.y, cz - half_w))
				hi = Vector2(maxf(hi.x, cx + half_w), maxf(hi.y, cz + half_w))

		if n_plain + n_flower == 0:
			continue

		var mesh := ArrayMesh.new()
		var mats: Array = []

		if n_plain > 0:
			st_plain.commit(mesh)
			mats.append(mat_plain)

		if n_flower > 0:
			st_flower.commit(mesh)
			mats.append(mat_flower)

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
			var rule: Dictionary = _find_rule(text)
			var key: String = "vil%d" % body.get_instance_id()
			var sig: String = "%s|%s|%s" % [str(rect.position.snapped(Vector2(0.02, 0.02))), str(rect.size.snapped(Vector2(0.02, 0.02))), text]
			seen[key] = true
			parts.append(sig)

			if view._items.has(key + "a") and view._items[key + "a"]["signature"] == sig:
				continue

			_remove_keys(key)
			_create_object(key, rect, rule, float(sprite_info["height_px"]), sig)

	# 사라진 물체 정리
	for k in _keys.keys():
		var base: String = str(k).substr(0, str(k).length() - 1)

		if not seen.has(base):
			view._remove_item(str(k))
			_keys.erase(k)


func _remove_keys(base: String) -> void:
	for suffix in ["a", "b", "c"]:
		view._remove_item(base + suffix)
		_keys.erase(base + suffix)


func _params() -> Dictionary:
	return {"ts": view.texture_size, "block_px": view.block_px, "unit_px_z": (view.tile_low / sqrt(2.0)) * cos(deg_to_rad(30.0))}


func _create_object(key: String, rect: Rect2, rule: Dictionary, sprite_height_px: float, sig: String) -> void:
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

		if swap:
			var tmp: float = cw
			cw = cd
			cd = tmp

		half = Vector2(cw, cd) * 0.5
	half = Vector2(maxf(half.x, 0.15), maxf(half.y, 0.15))
	lo = center - half
	hi = center + half

	if kind == "gable" or kind == "prop":
		var built: Dictionary
		var p: Dictionary = _params()

		if kind == "gable":
			built = VillageAssets.build_gable(lo, hi, rule, p)
		else:
			built = VillageAssets.build_prop(str(rule.get("style", "")), lo, hi, rule, p)

		view._set_mesh_item(key + "a", built["mesh"], VillageAssets.make_materials(built["specs"]), built["lo"], built["hi"], float(built["total_blocks"]), sig)
		_keys[key + "a"] = true

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
