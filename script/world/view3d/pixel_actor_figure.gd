class_name PixelActorFigure
extends BlockyFigure
## 매장용 도트 인물. BlockyFigure 상태/정렬 인터페이스를 공유하며 관절 모델은 만들지 않는다.

const SPRITE_SHADER := preload("res://script/world/view3d/shader/actor_sprite.gdshader")
const SPRITE_ID_SHADER := preload("res://script/world/view3d/shader/actor_sprite_id.gdshader")
# 걷기 그림 8프레임이 바뀌는 속도. 이동 속도에 비례하되 눈에 읽히는 범위(초당 MIN~MAX 프레임)로 묶는다.
# 예전에는 한 주기 0.8칸이라 주인공(초당 약 4칸)이 초당 40프레임으로 걸어 발이 안 보이고 떨려 보였다(2026-10-09 확인).
const STEP_LENGTH := 2.4 # 8프레임 한 주기의 이동 거리(칸). 느리게 걸을 때 발이 땅과 어긋나 보이지 않게 맞춘 값
const MIN_FPS := 6.0 # 아무리 느려도 이보다 느리게 바뀌지 않는다
const MAX_FPS := 12.0 # 아무리 빨라도 이보다 빠르게 바뀌지 않는다(발이 보이는 한계)
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
var work_pose: Dictionary = {}
var work_direction := ""


func build(parent: Node, id_parent: Node, _head_ratio: float = 3.0, total: float = 0.95, _torso_fixed: float = -1.0, look: Dictionary = {}) -> void:
	display_height = float(frame_set.get("display_height", float(look.get("total", total)) * PROJECTION_HEIGHT))
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
	direction = str(frame_set.get("static_direction", ActorSpriteFrames.direction_for(facing_yaw_deg, _camera_yaw)))
	var walk_frames: Array = frame_set.get("directions",{}).get(direction,{}).get("walk",[])
	if walking and delta > 0.0 and not walk_frames.is_empty() and not frame_set.has("static_direction"):
		var frames_per_second := clampf(maxf(move_speed, 0.0) / STEP_LENGTH * float(ActorSpriteFrames.FRAME_COUNT), MIN_FPS, MAX_FPS)
		phase = fposmod(phase + frames_per_second / float(ActorSpriteFrames.FRAME_COUNT) * delta, 1.0)
		frame_index = int(floor(phase * ActorSpriteFrames.FRAME_COUNT))
	else:
		phase = 0.0
		frame_index = -1
	_apply_frame()


func _apply_frame() -> void:
	if frame_set.is_empty() or _material == null:
		return
	direction = str(frame_set.get("static_direction", direction))
	var pose: Dictionary = frame_set.directions[direction]
	var frame: Dictionary = pose.idle if frame_index < 0 or frame_index >= pose.walk.size() else pose.walk[frame_index]
	if not work_pose.is_empty():
		pose = frame_set.directions[work_direction]
		frame = work_pose
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
	_material.set_shader_parameter("normal_texture", SpriteNormalMaps.texture(texture))


func set_work_pose(value: Dictionary, facing: String) -> void:
	work_pose = value
	work_direction = facing


func sync_sort(rank: float, count: float, camera: Camera3D, id_value: float) -> void:
	_camera_yaw = camera.global_rotation_degrees.y
	direction = str(frame_set.get("static_direction", ActorSpriteFrames.direction_for(facing_yaw_deg, _camera_yaw)))
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
