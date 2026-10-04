class_name PreparationRoad3D
extends CanvasLayer
## 원정 준비 마을(출발 도로)을 3D 로 그린다. 이동·출구 판정은 PreparationVillage(2D 로직)가 그대로 맡고, 이 노드는 플레이어 위치를 읽어 그림만 그린다.
## 칸 좌표(PreparationVillage.cell_at) (x, y) 는 3D 의 (x, 0, y). 카메라는 플레이어를 따라가며 2D 때와 같은 칸 크기(가로 96px)로 맞춘다.
## 이 레이어는 2D 세계 뒤(layer -1)에 깔려서 출구 이름표 같은 2D 글자가 그 위에 보인다.

const PITCH_DEG: float = 30.0
const YAW_DEG: float = 45.0
const SHRINK: int = 3
const ROAD_X0: float = 6.5
const ROAD_X1: float = 9.5
const ROAD_Y0: float = -0.5
const ROAD_Y1: float = 14.5

var village: Node2D  # PreparationVillage
var _container: SubViewportContainer
var _vp: SubViewport
var _cam: Camera3D
var _content: Node3D
var _id_dummy: Node3D
var _player: BlockyFigure
var _glow: MeshInstance3D
var _glow_mat: StandardMaterial3D
var _light: OmniLight3D
var _cache: Dictionary = {}
var _time: float = 0.0
var _p: Dictionary = {"ts": 24, "block_px": 22.0, "unit_px_z": 20.0}


func _ready() -> void:
	layer = -1
	_container = SubViewportContainer.new()
	_container.stretch = true
	_container.stretch_shrink = SHRINK
	_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_container.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(_container)
	_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_vp = SubViewport.new()
	_vp.own_world_3d = true
	_vp.msaa_3d = Viewport.MSAA_DISABLED
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_container.add_child(_vp)
	_cam = Camera3D.new()
	_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_cam.near = 0.1
	_cam.far = 120.0
	_cam.rotation_degrees = Vector3(-PITCH_DEG, YAW_DEG, 0.0)
	_vp.add_child(_cam)
	var sun := DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.light_energy = 0.9
	sun.rotation_degrees = Vector3(-52.0, 110.0, 0.0)
	_vp.add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-35.0, -60.0, 0.0)
	fill.light_energy = 0.25
	_vp.add_child(fill)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("1f2f26")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.78, 0.84, 0.74)
	env.ambient_light_energy = 0.65
	var we := WorldEnvironment.new()
	we.environment = env
	_vp.add_child(we)
	_content = Node3D.new()
	_vp.add_child(_content)
	_id_dummy = Node3D.new()
	_id_dummy.visible = false
	_vp.add_child(_id_dummy)
	_build_ground()
	_build_scenery()
	_build_exit()
	_player = BlockyFigure.new()
	_player.build(_content, _id_dummy, 3.0, 1.14, 0.308)
	_player.set_sorted(false)


func _tpl(style: String, rule: Dictionary, key: String) -> Dictionary:
	if _cache.has(key):
		return _cache[key]

	var half := Vector2(0.5, 0.5)
	var built: Dictionary = VillageAssets.build_prop(style, -half, half, rule, _p)
	var mats: Array = VillageAssets.make_materials(built["specs"])

	for m in mats:
		(m as ShaderMaterial).set_shader_parameter("use_sort", false)

	var t: Dictionary = {"mesh": built["mesh"], "mats": mats}
	_cache[key] = t
	return t


func _inst(t: Dictionary, pos: Vector2, scale: float, yaw: float) -> void:
	var node := MeshInstance3D.new()
	node.mesh = t["mesh"]

	for i in range((t["mats"] as Array).size()):
		node.set_surface_override_material(i, t["mats"][i])

	node.position = Vector3(pos.x, 0.0, pos.y)
	node.rotation.y = yaw
	node.scale = Vector3.ONE * scale
	_content.add_child(node)


func _node(b: VillageAssets.PartBuilder) -> MeshInstance3D:
	var mesh := ArrayMesh.new()
	var specs: Array = b.commit_into(mesh)
	var mats: Array = VillageAssets.make_materials(specs)

	for m in mats:
		(m as ShaderMaterial).set_shader_parameter("use_sort", false)

	var inst := MeshInstance3D.new()
	inst.mesh = mesh

	for i in range(mats.size()):
		inst.set_surface_override_material(i, mats[i])

	_content.add_child(inst)
	return inst


func _build_ground() -> void:
	var ts: int = int(_p["ts"])
	var b := VillageAssets.PartBuilder.new()
	var parts: Dictionary = {}  # 메시 면은 최대 256개라 칸마다 만들지 않고 (종류, 밝기) 별로 하나씩만 만든다

	for y in range(-8, 24):
		for x in range(-6, 22):
			var inside: bool = float(x) > ROAD_X0 and float(x) < ROAD_X1 and float(y) > ROAD_Y0 and float(y) < ROAD_Y1
			var v: int = absi(x * 7 + y * 13 + x * y) % 3
			var kind: String = "brick" if inside else "grass"
			var tint: Color = Color(0.82, 0.76, 0.68) if inside else Color(0.5, 0.72, 0.44)
			var br: float = 0.9 + 0.07 * float(v)
			var pk: String = "prep_%s_%d" % [kind, v]

			if not parts.has(pk):
				var spec: Dictionary = VillageAssets.spec(VillageAssets._tex(kind, ts), tint * Color(br, br, br), pk, "준비 마을 바닥")
				parts[pk] = b.new_part(spec, Vector3(-6, 0, -8), Vector3(22, 0, 24))

			var st: SurfaceTool = parts[pk]
			BuildingMesh._quad(st, Vector3(x, 0, y), Vector3(x + 1, 0, y), Vector3(x + 1, 0, y + 1), Vector3(x, 0, y + 1), Vector3.UP, Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1))

	_node(b)


# 도로 양옆을 나무·덤불·풀로 두른다(간격·크기·종류가 제각각이라 자연스럽게). 도로 안쪽은 비운다.
func _build_scenery() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var grass := _tpl("flower_bush", {"variant": ""}, "bush")

	for side in [-1, 1]:
		var y: float = -3.0

		while y < 18.0:
			var edge: float = ROAD_X0 if side < 0 else ROAD_X1
			var x: float = edge + float(side) * (2.2 + rng.randf_range(0.0, 1.6))  # 나무는 도로에서 떨어뜨려 길과 플레이어를 가리지 않게
			var v: String = ["pine", "round", "birch", "big_oak", "pine"][rng.randi() % 5]
			_inst(_tpl("tree", {"variant": v}, "tree_" + v), Vector2(x, y), rng.randf_range(0.95, 1.35), rng.randf() * TAU)

			if rng.randf() < 0.55:
				_inst(grass, Vector2(edge + float(side) * rng.randf_range(0.5, 1.4), y + rng.randf_range(0.2, 0.8)), rng.randf_range(0.9, 1.3), rng.randf() * TAU)

			y += rng.randf_range(1.0, 2.0)

	# 뒤쪽(출구 너머) 큰 나무 몇 그루
	for i in range(6):
		var v2: String = ["big_oak", "pine", "round"][i % 3]
		_inst(_tpl("tree", {"variant": v2}, "tree_" + v2), Vector2(5.4 + float(i) * 1.0, -2.6 + rng.randf_range(-0.3, 0.3)), rng.randf_range(1.2, 1.5), rng.randf() * TAU)


# 출구(칸 8,1): 돌기둥 두 개와 상인방으로 만든 문, 그 사이에 빛이 번진다. 가까이 가면 더 밝아진다.
func _build_exit() -> void:
	var b := VillageAssets.PartBuilder.new()
	var stone: Dictionary = VillageAssets.stone_spec(_p, Color(0.85, 0.8, 0.7), "prep_gate")
	var ex: float = 8.0
	var ez: float = 0.55
	VillageAssets.box(b, "post_l", stone, Vector3(ex - 1.15, 0, ez - 0.2), Vector3(ex - 0.85, 1.7, ez + 0.2))
	VillageAssets.box(b, "post_r", stone, Vector3(ex + 0.85, 0, ez - 0.2), Vector3(ex + 1.15, 1.7, ez + 0.2))
	VillageAssets.box(b, "lintel", stone, Vector3(ex - 1.2, 1.55, ez - 0.22), Vector3(ex + 1.2, 1.85, ez + 0.22))
	_node(b)
	_glow_mat = StandardMaterial3D.new()
	_glow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_glow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_glow_mat.albedo_color = Color(1.0, 0.9, 0.55, 0.35)
	_glow_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var quad := QuadMesh.new()
	quad.size = Vector2(1.7, 1.6)
	_glow = MeshInstance3D.new()
	_glow.mesh = quad
	_glow.material_override = _glow_mat
	_glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_glow.position = Vector3(ex, 0.8, ez)
	_glow.rotation_degrees = Vector3(0.0, 0.0, 0.0)
	_content.add_child(_glow)
	_light = OmniLight3D.new()
	_light.position = Vector3(ex, 1.0, ez + 0.5)
	_light.light_color = Color(1.0, 0.9, 0.6)
	_light.light_energy = 0.8
	_light.omni_range = 4.0
	_content.add_child(_light)


func _process(delta: float) -> void:
	if village == null or _player == null:
		return

	var shown: bool = village.visible
	_container.visible = shown

	if not shown:
		return

	_time += delta
	var body: CharacterBody2D = village.player
	var cell: Vector2 = village.cell_at(body.position)
	# 2D 속도(px/s) → 칸 방향 속도
	var v: Vector2 = body.velocity
	var vc := Vector2(v.x / 96.0 + v.y / 48.0, v.y / 48.0 - v.x / 96.0)
	_player.walking = vc.length() > 0.05

	if _player.walking:
		_player.facing_yaw_deg = rad_to_deg(atan2(vc.x, vc.y))
		_player.move_speed = lerpf(_player.move_speed, 2.2, 0.3)

	_player.animate(delta)
	_player.position = Vector3(cell.x, 0.0, cell.y)
	_layout(cell)
	var near: bool = village.near_exit()
	_glow_mat.albedo_color = Color(1.0, 0.92, 0.6, 0.62 if near else 0.3 + 0.06 * sin(_time * 3.0))
	_light.light_energy = 1.4 if near else 0.8


# 카메라를 플레이어 칸에 맞춘다(한 칸 가로 96px). 이동이 칸 픽셀 격자에 맞게 스냅해 도트가 흔들리지 않게 한다.
func _layout(center_cell: Vector2) -> void:
	var screen_h: float = get_viewport().get_visible_rect().size.y
	var ppu: float = 96.0 / sqrt(2.0)
	_cam.size = screen_h / ppu
	var target := Vector3(center_cell.x, 0.0, center_cell.y)
	var px: float = _cam.size / maxf(1.0, float(_vp.size.y))
	var right: Vector3 = _cam.basis.x
	var up: Vector3 = _cam.basis.y
	var r: float = target.dot(right)
	var u: float = target.dot(up)
	target += (roundf(r / px) * px - r) * right + (roundf(u / px) * px - u) * up
	_cam.position = target + _cam.basis.z * 40.0
