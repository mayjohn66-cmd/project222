class_name PixelActorFigure
extends BlockyFigure
## 매장용 도트 인물. BlockyFigure 상태/정렬 인터페이스를 공유하며 관절 모델은 만들지 않는다.

const SPRITE_SHADER := preload("res://script/world/view3d/shader/actor_sprite.gdshader")
const SPRITE_ID_SHADER := preload("res://script/world/view3d/shader/actor_sprite_id.gdshader")
const STEP_LENGTH := 0.8 # 8프레임 한 주기의 이동 거리(칸)
const PROJECTION_HEIGHT := 0.8660254 # 기존 30도 카메라의 인물 높이와 맞춤
var sprite_key := ""
var frame_set: Dictionary = {}
var direction := "south-east"
var frame_index := -1
var display_height := 1.14
var _camera_yaw := 45.0
var _mesh: MeshInstance3D
var _id_mesh: MeshInstance3D
var _material: ShaderMaterial
var _id_material: ShaderMaterial
var _last_frame_path := ""


func build(parent: Node, id_parent: Node, _head_ratio: float = 3.0, total: float = 0.95, _torso_fixed: float = -1.0, look: Dictionary = {}) -> void:
	display_height = float(look.get("total", total)) * PROJECTION_HEIGHT
	parent.add_child(self)
	_id_root = Node3D.new()
	id_parent.add_child(_id_root)
	_mesh = _make_mesh(SPRITE_SHADER, 1)
	add_child(_mesh)
	_id_mesh = _make_mesh(SPRITE_ID_SHADER, 2)
	_id_root.add_child(_id_mesh)
	_material = _mesh.material_override as ShaderMaterial
	_id_material = _id_mesh.material_override as ShaderMaterial
	_apply_frame()


func _make_mesh(shader: Shader, layer: int) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	mesh.mesh = QuadMesh.new()
	mesh.layers = layer
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := ShaderMaterial.new()
	material.shader = shader
	mesh.material_override = material
	return mesh


func animate(delta: float) -> void:
	if walking and delta > 0.0:
		phase = fposmod(phase + maxf(move_speed, 0.0) * delta / STEP_LENGTH, 1.0)
		frame_index = int(floor(phase * ActorSpriteFrames.FRAME_COUNT))
	else:
		phase = 0.0
		frame_index = -1
	direction = ActorSpriteFrames.direction_for(facing_yaw_deg, _camera_yaw)
	_apply_frame()


func _apply_frame() -> void:
	if frame_set.is_empty() or _material == null:
		return
	var pose: Dictionary = frame_set.directions[direction]
	var frame: Dictionary = pose.idle if frame_index < 0 else pose.walk[frame_index]
	if _last_frame_path == frame.path:
		return
	_last_frame_path = frame.path
	var bounds: Rect2i = frame.bounds
	var texture: Texture2D = frame.texture
	var anchor: Vector2 = pose.anchor + texture.get_size() * 0.5
	var unit := display_height / float(frame_set.reference_height)
	var extent := Vector2(bounds.size) * unit
	# Quad/UV crop preserves all source pixels; anchor ignores differing canvas padding.
	var offset := Vector2((float(bounds.position.x) + bounds.size.x * 0.5 - anchor.x) * unit,
		(anchor.y - float(bounds.position.y) - bounds.size.y * 0.5) * unit)
	var region := Vector4(float(bounds.position.x) / texture.get_width(), float(bounds.position.y) / texture.get_height(),
		float(bounds.size.x) / texture.get_width(), float(bounds.size.y) / texture.get_height())
	(_mesh.mesh as QuadMesh).size = extent
	(_id_mesh.mesh as QuadMesh).size = extent
	for material in [_material, _id_material]:
		material.set_shader_parameter("frame_texture", texture)
		material.set_shader_parameter("region", region)
		material.set_shader_parameter("frame_offset", offset)


func sync_sort(rank: float, count: float, camera: Camera3D, id_value: float) -> void:
	_camera_yaw = camera.global_rotation_degrees.y
	direction = ActorSpriteFrames.direction_for(facing_yaw_deg, _camera_yaw)
	_apply_frame()
	_id_root.global_transform = global_transform
	for material in [_material, _id_material]:
		material.set_shader_parameter("rank", rank)
		material.set_shader_parameter("rank_count", count)
	_id_material.set_shader_parameter("id", id_value)


func set_sorted(sorted: bool) -> void:
	_sorted = sorted
	if _material != null:
		_material.set_shader_parameter("use_sort", sorted)
		_id_material.set_shader_parameter("use_sort", sorted)


func set_light_tint(tint: Color) -> void:
	_material.set_shader_parameter("light_tint", tint)
