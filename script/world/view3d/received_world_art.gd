class_name ReceivedWorldArt
extends RefCounted
## 받은그림의 선택된 원본을 표시한다. 게임의 96x48 좌표/충돌/저장값은 그대로 둔다.
## 카메라만 64x32 표시로 맞춘다. 진열대·문은 PixelShopArt가 실제 상태로 합성한다.
const ENABLED := true
const TILE_WIDTH := 64.0
const CSV := "res://data/art/received_furniture.csv"
const FLOOR_SHADER := preload("res://script/world/view3d/shader/received_floor.gdshader")
const ROOT := "res://art/received/"
static var _paths: Dictionary = {}
static var _textures: Dictionary = {}

static func texture(path: String) -> Texture2D:
	if not _textures.has(path):
		_textures[path] = load(path) as Texture2D if ResourceLoader.exists(path) else null
	return _textures[path]

static func furniture_path(build_id: String, rotation: int) -> String:
	if _paths.is_empty():
		var file := FileAccess.open(CSV, FileAccess.READ)
		if file == null:
			return ""
		file.get_csv_line()
		while not file.eof_reached():
			var row := file.get_csv_line()
			if row.size() >= 3:
				_paths[row[0] + ":" + row[1]] = row[2]
	return str(_paths.get(build_id + ":" + str(posmod(rotation, 4)), ""))

static func floor_material(kind: String, tint: Color = Color.WHITE) -> ShaderMaterial:
	if not ENABLED or kind not in ["tile", "wood", "grass", "dirt", "road", "paving"]:
		return null
	var images: Array[Texture2D] = []
	for i in range(1, 4):
		var tex := texture(ROOT + "floors/" + kind + "_%d.png" % i)
		if tex == null:
			return null
		images.append(tex)
	var mat := ShaderMaterial.new()
	mat.shader = FLOOR_SHADER
	for i in images.size():
		mat.set_shader_parameter("tile_%d" % (i + 1), images[i])
		mat.set_shader_parameter("normal_%d" % (i + 1),SpriteNormalMaps.texture(images[i]))
	mat.set_shader_parameter("tint", tint)
	return mat

static func furniture(view: StoreView3D, key: String, node: Node, build_id: String,
		rotation: int, lo: Vector2, hi: Vector2, base: Vector2, signature: String,
		preview: bool = false, valid: bool = true) -> bool:
	if not ENABLED:
		return false
	if PixelShopArt.furniture(view, key, node, build_id, rotation, lo, hi, base, signature, preview, valid):
		return true
	if PixelProductionArt.furniture(view, key, node, build_id, rotation, lo, hi, base, signature, preview):
		return true
	var path := furniture_path(build_id, rotation)
	if path.is_empty():
		return false
	# 그림에 상품이 그려져 있다. 빈/일부 품절/쌓인 진열대를 채워진 그림으로 표시하지 않는다.
	if build_id.begins_with("shelf_") and not preview:
		if int(node.get("stack_level")) != 1:
			return false
		var slots: Array = node.get("slots")
		if slots.is_empty():
			return false
		for slot in slots:
			if str(slot.get("item_id", "")).is_empty() or int(slot.get("stock", 0)) <= 0:
				return false
	# 빈 선반 그림은 빈 상태에만. 저장품의 종류/수량 표시는 기존 동적 모델이 맡는다.
	if build_id in ["warehouse_rack", "steel_warehouse_rack", "wood_warehouse_rack"] and not preview:
		var loaded := false
		for slot in node.get("storage_slots"):
			loaded = loaded or int(slot.get("amount", 0)) > 0
		if loaded or build_id == "wood_warehouse_rack":
			return false
	var tex := texture(path)
	if tex == null:
		return false
	var anchor := Vector2(tex.get_width() * 0.5, tex.get_height() - 24.0)
	if build_id == "magic_oven":
		anchor.y = 152.0 # 합성본의 명시된 기준점(다른 가구는 아래에서 24px).
	var tint := Color.WHITE
	if preview:
		tint = tint.lerp(Color(0.55, 1.0, 0.9) if valid else Color(1.0, 0.25, 0.25), 0.4 if valid else 0.65)
	billboard(view, key, tex, anchor, lo, hi, base, signature, tint)
	return true

static func billboard(view: StoreView3D, key: String, tex: Texture2D, anchor: Vector2,
		lo: Vector2, hi: Vector2, base: Vector2, signature: String, tint: Color = Color.WHITE,
		scale_factor: float = 1.0, normal_source_path: String = "") -> void:
	var unit := sqrt(2.0) / TILE_WIDTH * scale_factor
	var bounds := tex.get_image().get_used_rect()
	var quad := QuadMesh.new()
	quad.size = Vector2(bounds.size) * unit
	var offset := (Vector2(bounds.position) + Vector2(bounds.size) * 0.5 - anchor) * Vector2(unit, -unit)
	var region := Vector4(float(bounds.position.x) / tex.get_width(), float(bounds.position.y) / tex.get_height(),
		float(bounds.size.x) / tex.get_width(), float(bounds.size.y) / tex.get_height())
	var mat := ShaderMaterial.new()
	mat.shader = PixelActorFigure.SPRITE_SHADER
	mat.set_shader_parameter("frame_texture", tex)
	mat.set_shader_parameter("frame_offset", offset)
	mat.set_shader_parameter("region", region)
	mat.set_shader_parameter("light_tint", tint)
	var normal_source := tex if normal_source_path.is_empty() else texture(normal_source_path)
	var extra := maxi(0,tex.get_height()-normal_source.get_height())
	mat.set_shader_parameter("normal_texture",SpriteNormalMaps.top_padding(SpriteNormalMaps.texture(normal_source),extra))
	if extra > 0:
		mat.set_shader_parameter("unlit_top",float(normal_source.get_image().get_used_rect().position.y+extra)/tex.get_height())
	quad.material = mat
	var height_blocks := maxf(1.0, (anchor.y - bounds.position.y) * scale_factor / view.block_px)
	view._set_mesh_item(key, quad, [mat], lo, hi, height_blocks, signature, NAN, false)
	var item: Dictionary = view._items[key]
	item["received_art"] = tex.resource_path
	item["art_tint"] = tint
	var id_mat := ShaderMaterial.new()
	id_mat.shader = PixelActorFigure.SPRITE_ID_SHADER
	id_mat.set_shader_parameter("frame_texture", tex)
	id_mat.set_shader_parameter("region", region)
	id_mat.set_shader_parameter("frame_offset", offset)
	item["id_material"] = id_mat
	(item["id_mesh"] as MeshInstance3D).material_override = id_mat
	(item["id_mesh"] as MeshInstance3D).visible = true
	for n in [item["mesh"], item["id_mesh"]]:
		n.position = Vector3(base.x, 0.0, base.y)
		n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

static func lighting(view: StoreView3D) -> void:
	# 실제 환경광/태양/보조광/점등은 spatial 셰이더가 계산한다. 원본에 색조를 중복 곱하지 않는다.
	for item in view._items.values():
		if item.has("received_art"):
			(item["material"] as ShaderMaterial).set_shader_parameter("light_tint",item["art_tint"])


static func nature(view: StoreView3D, key: String, lo: Vector2, hi: Vector2, rule: Dictionary,
		signature: String, scale_factor: float = 1.0) -> bool:
	if not ENABLED:
		return false
	var style := str(rule.get("style", ""))
	var variant := str(rule.get("variant", ""))
	var name := ""
	if style == "tree":
		if variant == "autumn":
			return false # 부위별 단풍 색조와 낙엽은 기존 계절 모델을 유지한다.
		name = "iso_tree_round" if variant == "round" or variant.is_empty() else "tree_" + variant
	elif style == "flower_bush":
		if variant == "berry":
			return false # 실제 열매 표시와 수확 상태를 기존 모델이 표현한다.
		name = "flower_bush"
	elif style in ["rocks", "rock", "stump", "log", "mushroom"]:
		name = "iso_" + style if style in ["stump", "log"] else ("rocks" if style == "rock" else style)
	if name.is_empty():
		return false
	var tex := texture(ROOT + "nature/" + name + ".png")
	if tex == null:
		return false
	var bounds := tex.get_image().get_used_rect()
	var anchor := Vector2(bounds.get_center().x, bounds.end.y)
	billboard(view, key, tex, anchor, lo, hi, (lo + hi) * 0.5, signature, Color.WHITE, scale_factor)
	return true
