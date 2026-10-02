class_name VillageMirror
extends RefCounted
## 마을(매장 바깥)을 3D 도트 방식으로 옮기는 "읽기 전용 거울". StoreView3D 가 소유한다.
## 읽는 곳: StoreExterior(칸마다 풀·길·보도 → 바닥), 마을 노드들의 StaticBody2D(발자국 충돌 모양 → 상자).
## 높이·질감은 data/shop/catalogs/village_3d.csv 의 규칙(노드 이름 또는 스프라이트 그림 파일 이름에 포함된 글자)으로 정한다. 규칙이 없으면 스프라이트 높이로 추정한다.
## 게임 코드는 수정하지 않는다(2D 숨김은 StoreView3D 가 visible 만 바꿈).

const CONTAINERS: Array = ["NearbyHouses", "VillageExtraHouses", "VillageBlacksmith", "VillageToolShop", "VillageBuildings", "VillageDecor", "VillageGathering", "DungeonRoadside", "DungeonWall"]
const RULES_PATH: String = "res://data/shop/catalogs/village_3d.csv"
const GROUND_TEXTURES: Dictionary = {"grass": ["grass", Color(0.74, 0.68, 0.56)], "road": ["brick", Color(0.5, 0.46, 0.46)], "paving": ["brick", Color(0.82, 0.76, 0.68)]}

var view: Node  # StoreView3D
var exterior: Node2D
var enabled: bool = true
var rules: Array = []
var _ground: Dictionary = {}  # 종류 → {mesh, material, id_mesh, id_material}
var _ground_signature: String = ""
var _object_signature: String = ""
var _keys: Dictionary = {}  # 이번에 만든 항목 키 → true


func _init(owner_view: Node, exterior_node: Node2D) -> void:
	view = owner_view
	exterior = exterior_node
	_load_rules()


func _load_rules() -> void:
	rules.clear()
	var file := FileAccess.open(RULES_PATH, FileAccess.READ)

	if file == null:
		return

	var header: PackedStringArray = file.get_csv_line()

	while not file.eof_reached():
		var cells: PackedStringArray = file.get_csv_line()

		if cells.size() < header.size() or cells[0].strip_edges().is_empty():
			continue

		rules.append({"match": cells[0].strip_edges().to_lower(), "kind": cells[1].strip_edges(), "height_blocks": float(cells[2]), "texture": cells[3].strip_edges(), "tint": Color.html(cells[4].strip_edges()), "roof_blocks": float(cells[5]) if cells.size() > 5 else 0.0, "roof_tint": Color.html(cells[6].strip_edges()) if cells.size() > 6 else Color.WHITE, "footprint_scale": float(cells[7]) if cells.size() > 7 else 1.0})


# 규칙 찾기: 노드 이름 + 스프라이트 그림 경로(소문자)에 match 글자가 들어 있는 첫 규칙. 먼저 나온 행이 우선(구체적인 것을 위에).
func _find_rule(text: String) -> Dictionary:
	for r in rules:
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
		var info: Array = GROUND_TEXTURES.get(kind, GROUND_TEXTURES["grass"])
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


func clear_ground() -> void:
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
	for suffix in ["a", "b"]:
		view._remove_item(base + suffix)
		_keys.erase(base + suffix)


func _create_object(key: String, rect: Rect2, rule: Dictionary, sprite_height_px: float, sig: String) -> void:
	var lo := rect.position
	var hi := rect.position + rect.size

	# 너무 얇은 발자국(나무 밑동 등)은 최소 크기를 준다.
	if hi.x - lo.x < 0.3:
		var cx: float = (lo.x + hi.x) * 0.5
		lo.x = cx - 0.15
		hi.x = cx + 0.15

	if hi.y - lo.y < 0.3:
		var cy: float = (lo.y + hi.y) * 0.5
		lo.y = cy - 0.15
		hi.y = cy + 0.15

	var kind: String = str(rule.get("kind", "box"))
	var tex: String = str(rule.get("texture", "plank"))
	var tint: Color = rule.get("tint", Color(0.8, 0.8, 0.8))
	var height: float = float(rule.get("height_blocks", 0.0))

	if height <= 0.0:
		# 규칙이 없으면 2D 그림 높이로 추정: 낮은 해상도 px = 2D px × 36/96, 지붕·여백 몫을 빼고 0.6배
		height = clampf(sprite_height_px * 0.375 * 0.6 / view.block_px, 0.6, 3.5)

	if kind == "gable":
		# 충돌 발자국은 그림보다 넓으므로 건물 모양은 중심 기준으로 줄인다(footprint_scale).
		var scale_f: float = float(rule.get("footprint_scale", 1.0))
		var center: Vector2 = (lo + hi) * 0.5
		var half: Vector2 = (hi - lo) * 0.5 * scale_f
		_create_gable(key, center - half, center + half, rule, sig)
		return

	if kind == "tree":
		# 줄기(발자국) + 더 넓은 잎 덩어리
		var c: Vector2 = (lo + hi) * 0.5
		view._set_item(key + "a", lo, hi, height * 0.45, "plank", Color(0.55, 0.38, 0.25), sig)
		view._set_item(key + "b", c - Vector2(0.55, 0.55), c + Vector2(0.55, 0.55), height * 0.55, tex, tint, sig, height * 0.45)
		_keys[key + "a"] = true
		_keys[key + "b"] = true
	else:
		view._set_item(key + "a", lo, hi, height, tex, tint, sig)
		_keys[key + "a"] = true


# 박공 지붕 건물: 벽(창문·문 임시 질감) + 두께 있는 기와 지붕 + 용마루 덮개 + 굴뚝 + 차양 + 바닥 돌 마당.
# 문은 카메라에 보이는 +z 면에 둔다(2D 그림의 문 방향은 반영하지 않음). 질감은 모두 코드로 칠한 임시 그림.
func _create_gable(key: String, lo: Vector2, hi: Vector2, rule: Dictionary, sig: String) -> void:
	var wall_blocks: float = float(rule["height_blocks"])
	var roof_blocks: float = float(rule.get("roof_blocks", 1.0))
	var options: Dictionary = {"chimney": true, "awning": true, "apron": 0.45}
	var built: Dictionary = BuildingMesh.build(lo, hi, view.block_height(wall_blocks), view.block_height(roof_blocks), options)
	var ts: int = view.texture_size
	var width: float = hi.x - lo.x
	var depth: float = hi.y - lo.y
	var h_texels: int = int(roundf(wall_blocks * view.block_px))
	var plaster: Color = rule["tint"]
	var roof_tint: Color = rule.get("roof_tint", Color(0.85, 0.44, 0.23))
	var timber := Color(0.34, 0.22, 0.14)
	var tex_z: ImageTexture = PlaceholderTextures.wall_facade(int(roundf(width * ts)), h_texels, true, maxi(int(roundf(width)), 1), plaster, timber)
	var tex_x: ImageTexture = PlaceholderTextures.wall_facade(int(roundf(depth * ts)), h_texels, false, maxi(int(roundf(depth)), 1), plaster, timber)
	var roof_mat: ShaderMaterial = view._make_facade_material(PlaceholderTextures.roof_tiles(ts, roof_tint))
	roof_mat.set_shader_parameter("normal_tex", PlaceholderTextures.roof_normal(ts))
	roof_mat.set_shader_parameter("use_normal", true)
	var materials: Array = [
		view._make_facade_material(tex_z),
		view._make_facade_material(tex_x),
		roof_mat,
		view._make_facade_material(PlaceholderTextures.wall_facade(ts, ts, false, 1, plaster, timber)),
		view._make_facade_material(PlaceholderTextures.flat_color(ts, roof_tint.darkened(0.45))),
		view._make_facade_material(PlaceholderTextures.albedo("brick", ts), Color(0.95, 0.78, 0.7)),
		view._make_facade_material(PlaceholderTextures.awning_stripes(ts, Color(0.96, 0.9, 0.78), Color(0.88, 0.45, 0.22))),
	]
	view._set_mesh_item(key + "a", built["mesh"], materials, lo, hi, wall_blocks + roof_blocks, sig)
	_keys[key + "a"] = true

	# 바닥 돌 마당: 정렬 없이 바닥(-1) 바로 위(-0.5)에 그린다.
	if (built["apron_mesh"] as ArrayMesh).get_surface_count() > 0:
		var apron_mat: ShaderMaterial = view._make_facade_material(PlaceholderTextures.albedo("brick", ts), Color(1.45, 1.35, 1.2))
		view._set_mesh_item(key + "b", built["apron_mesh"], [apron_mat], lo, hi, 0.0, sig, -0.5)
		_keys[key + "b"] = true
