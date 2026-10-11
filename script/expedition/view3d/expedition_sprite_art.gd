class_name ExpeditionSpriteArt
extends RefCounted
## 준비된 정지 그림만 선택한다. 데이터 ID/보상/충돌과 도트의 종횡비는 바꾸지 않는다.
const MANIFEST := "res://data/art/expedition_sprite_assets.json"
const SHADER := preload("res://script/world/view3d/shader/actor_sprite.gdshader")
static var _assets: Dictionary = {}

static func assets() -> Dictionary:
	if _assets.is_empty():
		var data = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
		if data is Dictionary:
			for row in data.get("assets", []):
				_assets[str(row.id)] = row
	return _assets

static func object_id(kind: String, table: String) -> String:
	if kind == "chest": return "treasure_chest"
	if kind == "heal": return "healing_spring"
	if kind not in ["gather", "gather_site"] or table.is_empty(): return ""
	for row in assets().values():
		if str(row.group) == "objects" and str(row.get("table", "")) == table:
			return str(row.id)
	return ""

static func create(parent: Node3D, id: String, position: Vector3) -> MeshInstance3D:
	var row: Dictionary = assets().get(id, {})
	return create_row(parent, row, position)

static func create_row(parent: Node3D, row: Dictionary, position: Vector3) -> MeshInstance3D:
	if row.is_empty(): return null
	var id := str(row.id)
	var texture := ReceivedWorldArt.texture(str(row.path))
	if texture == null: return null
	var bounds := texture.get_image().get_used_rect()
	if bounds.size.x <= 0 or bounds.size.y <= 0: return null
	var unit := float(row.pixel_unit)
	var anchor := Vector2(float(row.anchor[0]), float(row.anchor[1]))
	var quad := QuadMesh.new()
	quad.size = Vector2(bounds.size) * unit
	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	mat.set_shader_parameter("frame_texture", texture)
	mat.set_shader_parameter("normal_texture", SpriteNormalMaps.texture(texture))
	mat.set_shader_parameter("region", Vector4(float(bounds.position.x) / texture.get_width(),
		float(bounds.position.y) / texture.get_height(), float(bounds.size.x) / texture.get_width(),
		float(bounds.size.y) / texture.get_height()))
	mat.set_shader_parameter("frame_offset", (Vector2(bounds.position) + Vector2(bounds.size) * 0.5 - anchor) * Vector2(unit, -unit))
	mat.set_shader_parameter("use_sort", false)
	var node := MeshInstance3D.new()
	node.name = "Pixel_" + id
	node.mesh = quad
	node.material_override = mat
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.position = position
	node.set_meta("expedition_sprite_id", id)
	parent.add_child(node)
	return node

static func gate(stage: ExpeditionStage3D, position: Vector3) -> bool:
	var closed := create(stage._content, "exit_closed", position)
	var opened := create(stage._content, "exit_open", position)
	if closed == null or opened == null:
		if closed != null: closed.queue_free()
		if opened != null: opened.queue_free()
		return false
	stage._exit_bars = closed
	stage._exit_glow = opened
	return true
