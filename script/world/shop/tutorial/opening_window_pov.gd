class_name OpeningWindowPov
extends Node
## 프롤로그의 1인칭 창밖 장면. 앉은 주인공의 눈높이에서 원근 카메라로 창문 너머 거리(차, 가로등, 건물)를 보여 준다.
## 가게의 등각 3D 화면(깊이 정렬 셰이더)과는 별개의 작은 3D 세계(`SubViewport`)이므로 서로 영향이 없다.
## 화면은 작게 그려 키워서(`SHRINK`) 픽셀 그림 느낌을 낸다.
##   `attach(layer)`   화면 층에 붙인다(가장 아래). 처음엔 숨김.
##   `show_pov()` / `hide_pov()`
##   `set_drowsy(0~1)` 졸음: 고개가 숙여지고 시야가 흔들린다(눈꺼풀 막은 연출 쪽에서 따로 덮는다).

const SHRINK := 4                    # 화면 크기를 몇 분의 1로 그려 키우나(픽셀 느낌)
const FOV := 68.0
const EYE_HEIGHT := 1.12
const EYE_Z := 1.0                  # 창벽에서 눈까지 거리(앉은 자리에서 창이 화면의 일부로 보이게)
const CAR_COLORS := [Color(0.85, 0.3, 0.28), Color(0.3, 0.5, 0.85), Color(0.92, 0.92, 0.9), Color(0.3, 0.6, 0.36), Color(0.95, 0.75, 0.25)]
const BUILDING_COLORS := [Color(0.74, 0.62, 0.58), Color(0.6, 0.64, 0.74), Color(0.78, 0.72, 0.6), Color(0.58, 0.52, 0.6), Color(0.66, 0.5, 0.45)]
const LANE_Z := [-4.4, -6.4]         # 차선(앞차선은 오른쪽으로, 먼 차선은 왼쪽으로)
const WRAP_X := 16.0

var container: SubViewportContainer
var viewport: SubViewport
var camera: Camera3D
var _cars: Array[Dictionary] = []
var _time: float = 0.0
var _drowsy: float = 0.0
var _rng := RandomNumberGenerator.new()
var _built: bool = false


func attach(layer: CanvasLayer) -> void:
	container = SubViewportContainer.new()
	container.stretch = true
	container.stretch_shrink = SHRINK
	container.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	container.set_anchors_preset(Control.PRESET_FULL_RECT)
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.visible = false
	viewport = SubViewport.new()
	viewport.own_world_3d = true
	viewport.handle_input_locally = false
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	container.add_child(viewport)
	layer.add_child(container)
	layer.move_child(container, 0)


func show_pov() -> void:
	if not _built:
		_build()

	container.visible = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_time = 0.0


func hide_pov() -> void:
	if container != null:
		container.visible = false
		viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED


func is_shown() -> bool:
	return container != null and container.visible


func set_drowsy(amount: float) -> void:
	_drowsy = clampf(amount, 0.0, 1.0)


func _process(delta: float) -> void:
	if not is_shown():
		return

	_time += delta

	# 숨 쉬듯 느린 흔들림 + 졸수록 고개가 숙여지고 옆으로 기운다
	var sway: float = sin(_time * 0.7) * 0.006
	camera.rotation = Vector3(-0.1 - _drowsy * 0.3 + sway, 0.0, sin(_time * 0.45) * 0.01 + _drowsy * 0.05)
	camera.position.y = EYE_HEIGHT - _drowsy * 0.07 + sin(_time * 1.1) * 0.004

	for car in _cars:
		var node: Node3D = car["node"]
		node.position.x += float(car["speed"]) * delta

		if absf(node.position.x) > WRAP_X + 4.0 and signf(node.position.x) == signf(float(car["speed"])):
			_respawn(car)


# ---------------------------------------------------------------- 만들기

func _mat(color: Color, emit: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 1.0
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST

	if emit > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = emit

	return m


func _box(parent: Node3D, lo: Vector3, hi: Vector3, color: Color, emit: float = 0.0) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = hi - lo
	var inst := MeshInstance3D.new()
	inst.mesh = mesh
	inst.material_override = _mat(color, emit)
	inst.position = (lo + hi) * 0.5
	parent.add_child(inst)
	return inst


func _build() -> void:
	_built = true
	_rng.seed = 11
	var root := Node3D.new()
	viewport.add_child(root)

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.72, 0.84, 0.95)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.78, 0.78, 0.84)
	env.ambient_light_energy = 0.7
	env.fog_enabled = true
	env.fog_light_color = Color(0.78, 0.86, 0.94)
	env.fog_density = 0.012
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	root.add_child(world_env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48.0, -28.0, 0.0)
	sun.light_energy = 1.05
	root.add_child(sun)

	camera = Camera3D.new()
	camera.fov = FOV
	camera.position = Vector3(0.0, EYE_HEIGHT, EYE_Z)
	camera.current = true
	root.add_child(camera)

	_build_interior(root)
	_build_street(root)


# 가게 안쪽: 창이 난 벽, 창턱, 가운데 창살, 앞에 놓인 탁자와 컵
func _build_interior(root: Node3D) -> void:
	var wall := Color(0.9, 0.84, 0.76)
	var dark := Color(0.2, 0.17, 0.15)
	var z0: float = -0.75
	var z1: float = -0.55
	var sill: float = 0.45           # 편의점 통유리처럼 낮게 시작해 앞 도로까지 보인다
	var top: float = 2.3
	var half: float = 1.9
	_box(root, Vector3(-4.0, -0.2, z0), Vector3(4.0, sill, z1), wall)         # 창 아래 벽
	_box(root, Vector3(-4.0, top, z0), Vector3(4.0, 3.2, z1), wall)           # 창 위 벽
	_box(root, Vector3(-4.0, sill, z0), Vector3(-half, top, z1), wall)        # 왼쪽 벽
	_box(root, Vector3(half, sill, z0), Vector3(4.0, top, z1), wall)          # 오른쪽 벽
	_box(root, Vector3(-half, sill - 0.04, z0 - 0.05), Vector3(half, sill + 0.02, -0.4), Color(0.62, 0.45, 0.3))   # 창턱
	# 창살: 세로 둘 + 가로 한 줄 + 바깥 틀
	for vx in [-0.63, 0.63]:
		_box(root, Vector3(vx - 0.03, sill, z0 + 0.02), Vector3(vx + 0.03, top, z0 + 0.1), dark)
	_box(root, Vector3(-half, 1.85, z0 + 0.02), Vector3(half, 1.9, z0 + 0.1), dark)
	_box(root, Vector3(-half - 0.03, sill, z0 + 0.02), Vector3(-half + 0.04, top, z0 + 0.1), dark)
	_box(root, Vector3(half - 0.04, sill, z0 + 0.02), Vector3(half + 0.03, top, z0 + 0.1), dark)
	# 유리: 연한 하늘색 반투명(반사)
	var glass := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(half * 2.0, top - sill)
	glass.mesh = quad
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.8, 0.92, 1.0, 0.1)
	gm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	gm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glass.material_override = gm
	glass.position = Vector3(0.0, (sill + top) * 0.5, z0 + 0.06)
	root.add_child(glass)
	# 옆 벽과 천장·바닥(시야 가장자리가 비지 않게)
	_box(root, Vector3(-4.2, -0.2, -0.75), Vector3(-4.0, 3.2, 3.5), wall)
	_box(root, Vector3(4.0, -0.2, -0.75), Vector3(4.2, 3.2, 3.5), wall)
	_box(root, Vector3(-4.2, 2.9, -0.75), Vector3(4.2, 3.1, 3.5), Color(0.95, 0.93, 0.9))
	_box(root, Vector3(-4.2, -0.3, -0.75), Vector3(4.2, -0.2, 3.5), Color(0.72, 0.6, 0.5))   # 바닥
	# 시식대 탁자(앞쪽 아래)와 종이컵
	_box(root, Vector3(-0.8, 0.66, 0.3), Vector3(0.8, 0.72, 0.95), Color(0.58, 0.4, 0.26))
	_box(root, Vector3(0.25, 0.72, 0.4), Vector3(0.37, 0.84, 0.52), Color(0.95, 0.95, 0.95))
	_box(root, Vector3(0.25, 0.84, 0.4), Vector3(0.37, 0.86, 0.52), Color(0.45, 0.28, 0.18))


# 창밖 거리: 인도·도로·건너편 건물·가로등, 지나가는 차
func _build_street(root: Node3D) -> void:
	var street := Node3D.new()
	root.add_child(street)
	_box(street, Vector3(-40.0, -0.3, -2.9), Vector3(40.0, 0.05, -0.75), Color(0.78, 0.72, 0.68))     # 앞 인도
	_box(street, Vector3(-40.0, -0.3, -8.2), Vector3(40.0, 0.0, -2.9), Color(0.26, 0.26, 0.3))        # 도로
	_box(street, Vector3(-40.0, -0.3, -10.0), Vector3(40.0, 0.05, -8.2), Color(0.78, 0.72, 0.68))     # 건너편 인도

	for i in range(-8, 9):
		_box(street, Vector3(float(i) * 2.4 - 0.5, 0.0, -5.45), Vector3(float(i) * 2.4 + 0.5, 0.012, -5.35), Color(0.95, 0.95, 0.9))

	# 건너편 건물 줄(층마다 창)
	var x: float = -34.0
	var index: int = 0

	while x < 34.0:
		var width: float = _rng.randf_range(5.0, 9.0)
		var height: float = _rng.randf_range(5.0, 12.0)
		var color: Color = BUILDING_COLORS[index % BUILDING_COLORS.size()]
		var b := Node3D.new()
		street.add_child(b)
		_box(b, Vector3(x, 0.0, -16.0), Vector3(x + width, height, -10.2), color)

		for fy in range(0, int(height / 2.6)):
			for fx in range(0, int(width / 1.8)):
				var lit: bool = _rng.randf() < 0.3
				var wc: Color = Color(1.0, 0.9, 0.6) if lit else Color(0.34, 0.42, 0.52)
				_box(b, Vector3(x + 0.5 + float(fx) * 1.8, 1.3 + float(fy) * 2.6, -10.22), Vector3(x + 1.3 + float(fx) * 1.8, 2.3 + float(fy) * 2.6, -10.18), wc, 0.8 if lit else 0.0)

		_box(b, Vector3(x, 0.0, -10.25), Vector3(x + width, 0.9, -10.15), color.darkened(0.25))     # 1층 띠
		x += width + _rng.randf_range(0.2, 1.2)
		index += 1

	# 가로등
	for i in range(-3, 4):
		var lx: float = float(i) * 6.0 + 1.5
		_box(street, Vector3(lx - 0.05, 0.0, -2.4), Vector3(lx + 0.05, 3.6, -2.3), Color(0.15, 0.15, 0.17))
		_box(street, Vector3(lx - 0.18, 3.6, -2.5), Vector3(lx + 0.18, 3.75, -2.2), Color(1.0, 0.82, 0.4), 0.9)

	# 지나가는 차(앞 차선은 오른쪽으로, 먼 차선은 왼쪽으로)
	for i in range(5):
		var lane: int = i % 2
		var node := Node3D.new()
		street.add_child(node)
		var car: Dictionary = {"node": node, "lane": lane, "speed": 0.0}
		_cars.append(car)
		_style_car(car, true, float(i))


# 차 한 대를 새로 꾸미고 출발 위치에 둔다. first 면 화면 안에 흩어 놓는다.
func _style_car(car: Dictionary, first: bool, spread: float) -> void:
	var node: Node3D = car["node"]

	for child in node.get_children():
		child.queue_free()

	var lane: int = int(car["lane"])
	var dir: float = 1.0 if lane == 0 else -1.0
	var color: Color = CAR_COLORS[_rng.randi() % CAR_COLORS.size()]
	var length: float = _rng.randf_range(3.6, 4.6)
	var truck: bool = _rng.randf() < 0.2
	_box(node, Vector3(-length * 0.5, 0.25, -0.85), Vector3(length * 0.5, 0.85, 0.85), color)                                     # 차체
	_box(node, Vector3(-length * 0.22, 0.85, -0.78), Vector3(length * (0.3 if truck else 0.18), 1.4 if not truck else 1.9, 0.78), color if truck else Color(0.7, 0.85, 0.95))
	_box(node, Vector3(-length * 0.5, 0.0, -0.8), Vector3(-length * 0.34, 0.25, 0.8), Color(0.12, 0.12, 0.14))
	_box(node, Vector3(length * 0.34, 0.0, -0.8), Vector3(length * 0.5, 0.25, 0.8), Color(0.12, 0.12, 0.14))
	_box(node, Vector3(length * 0.5 * dir - 0.03, 0.45, -0.7), Vector3(length * 0.5 * dir + 0.03, 0.62, -0.45), Color(1.0, 0.95, 0.7), 1.0)   # 앞 전조등
	_box(node, Vector3(length * 0.5 * dir - 0.03, 0.45, 0.45), Vector3(length * 0.5 * dir + 0.03, 0.62, 0.7), Color(1.0, 0.95, 0.7), 1.0)
	car["speed"] = dir * _rng.randf_range(3.2, 6.2)
	node.position = Vector3(-dir * (WRAP_X + 3.0) + dir * (spread * 5.0 if first else 0.0), 0.0, float(LANE_Z[lane]))


func _respawn(car: Dictionary) -> void:
	_style_car(car, false, 0.0)
	# 다음 차까지 간격을 두어 빈 도로 장면도 생기게 한다
	(car["node"] as Node3D).position.x -= signf(float(car["speed"])) * _rng.randf_range(0.0, 14.0)
