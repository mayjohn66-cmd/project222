class_name ExpeditionBackdrop
extends MeshInstance3D
## 카메라 뒤 배경에 한 장만 배치한다. 원본 비율과 바닥·인물의 깊이를 유지한다.
const SHADER := preload("res://script/expedition/view3d/expedition_backdrop.gdshader")
var _material: ShaderMaterial
var _image_size := Vector2.ONE

func _init() -> void:
	name = "ExpeditionBackdrop"
	mesh = QuadMesh.new()
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_material = ShaderMaterial.new()
	_material.shader = SHADER
	material_override = _material

func configure(stage: ExpeditionStage3D, region: String) -> void:
	var row := ExpeditionRoomComposition.profile(region)
	var texture := ReceivedWorldArt.texture(str(row.get("background_path", "")))
	visible = texture != null
	if texture == null: return
	_image_size = texture.get_size()
	_material.set_shader_parameter("background_texture",texture)
	_material.set_shader_parameter("image_size",_image_size)
	var outdoors := str(stage._theme.floor) == "grass"
	var tint := ExpeditionEnvironment.floor_tint(Color.WHITE,stage.view.weather_overlay.environment,outdoors)
	_material.set_shader_parameter("tint",tint)
	set_meta("region_id",region)
	set_meta("background_path",texture.resource_path)
	set_meta("source_aspect",_image_size.x / _image_size.y)

func layout(camera: Camera3D, viewport_size: Vector2i) -> void:
	if viewport_size.y <= 0: return
	var screen := Vector2(viewport_size)
	(mesh as QuadMesh).size = Vector2(camera.size * screen.x / screen.y, camera.size)
	_material.set_shader_parameter("viewport_size",screen)
	var camera_transform := camera.get_camera_transform()
	basis = camera_transform.basis
	position = camera_transform.origin - camera_transform.basis.z * 80.0
