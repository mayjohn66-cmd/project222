class_name ExpeditionEnvironmentArt
extends RefCounted
## Shared 64×32 ground tiles and transparent sprites for the room composition profiles.
const MANIFEST := "res://data/art/expedition_environment_assets.json"
const FLOOR := preload("res://script/expedition/view3d/expedition_floor.gdshader")
static var _rows: Dictionary = {}

static func assets() -> Dictionary:
	if _rows.is_empty():
		var data = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
		if data is Dictionary:
			for row in data.get("assets", []): _rows[str(row.id)] = row
	return _rows

static func template(key: String) -> Dictionary:
	var id := key + "_rot0" if key.begins_with("r_wall_") else key
	var row: Dictionary = assets().get(id, {})
	return {"pixel_key":key} if not row.is_empty() and ReceivedWorldArt.texture(str(row.path)) != null else {}

static func create(stage: ExpeditionStage3D, key: String, pos: Vector2,
		scale: float = 1.0, yaw: float = 0.0, height: float = 0.0) -> MeshInstance3D:
	var id := key
	if key.begins_with("r_wall_"):
		id += "_rot%d" % posmod(roundi(yaw / (PI * 0.5)), 4)
	var row: Dictionary = assets().get(id, {}).duplicate()
	if row.is_empty(): return null
	# The camera-facing shader discards node scale; scale the quad AND its anchor uniformly.
	row.pixel_unit = float(row.pixel_unit) * scale
	var node := ExpeditionSpriteArt.create_row(stage._content, row, Vector3(pos.x,height,pos.y))
	if node != null:
		node.set_meta("environment_sprite_key", key)
		node.set_meta("environment_uniform_scale", scale)
	return node

static func build_floor(stage: ExpeditionStage3D) -> bool:
	stage._pixel_floor_material = null
	var mat := ShaderMaterial.new()
	mat.shader = FLOOR
	var grass := str(stage._theme.floor) == "grass"
	var kind := "grass" if grass else "paving"
	for group in ["tile", "dirt", "water"]:
		for i in range(1,4):
			var path := "res://art/received/floors/%s_%d.png" % [kind if group == "tile" else "dirt",i]
			if group == "water": path = "res://art/received/fishing/water_%d.png" % i
			var tex := ReceivedWorldArt.texture(path)
			if tex == null: return false
			mat.set_shader_parameter("%s_%d" % [group,i],tex)
			mat.set_shader_parameter("%s_normal_%d" % [group,i],SpriteNormalMaps.texture(tex))
	var composition := ExpeditionRoomComposition.profile(str(stage._backdrop.get_meta("region_id",stage.view.region_id)))
	var tint := Color(str(composition.get("floor_tint","ffffff")))
	tint = ExpeditionEnvironment.floor_tint(tint,stage.view.weather_overlay.environment,grass)
	mat.set_shader_parameter("tint",tint)
	mat.set_shader_parameter("ring_tint",float(stage._theme.ring_tint))
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(11,11)
	var node := MeshInstance3D.new()
	node.name = "PixelGround"
	node.mesh = mesh
	node.material_override = mat
	node.position = Vector3(4,0,4)
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.set_meta("environment_floor_kind",kind)
	node.set_meta("puddles",PackedVector3Array())
	stage._content.add_child(node)
	stage._pixel_floor_material = mat
	stage._pixel_floor = node
	return true

static func puddle(stage: ExpeditionStage3D, pos: Vector2, radius: float) -> void:
	var points: PackedVector3Array = stage._pixel_floor.get_meta("puddles")
	if points.size() >= 32: return
	points.append(Vector3(pos.x,pos.y,radius*0.97))
	stage._pixel_floor.set_meta("puddles",points)
	stage._pixel_floor_material.set_shader_parameter("puddle_count",points.size())
	var padded := points.duplicate()
	padded.resize(32)
	stage._pixel_floor_material.set_shader_parameter("puddles",padded)
