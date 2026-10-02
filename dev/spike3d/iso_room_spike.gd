extends Node3D
## 3D 도형 + 2D 그림 시험 방(실험). 건물·가구는 3D 상자에 기존 2D 질감을 씌우고, 캐릭터는 2D 도트를 판(Sprite3D)으로 세운다.
## 목적: 이 방식의 모양(도트 느낌, 앞뒤 정렬, 빛과 그림자)이 마음에 드는지 눈으로 확인한다. 게임 코드와 연결하지 않은 독립 장면이다.
##   키: 1/2/3 = 화면 낮추기 배율(1배/2배/3배, 낮출수록 거칠고 도트 느낌이 강함) / L = 그림자 / T = 계단식 빛(툰) / P = 색 줄이기 / S = 픽셀 스냅 / C = 카메라 천천히 흘리기 / 방향키 = 캐릭터 이동
## 실행: Godot 에서 dev/spike3d/iso_room_spike.tscn 열고 F6.

const GRASS: String = "grass"
const PAVING: String = "brick"
const WOOD: String = "plank"
const PLAYER_SHEET: String = "res://art/characters/cozy_v1/player/sheet.png"

# 한 칸 = 1 단위. 카메라: 위에서 30도, 옆으로 45도(2:1 마름모).
const PITCH_DEG: float = 30.0
const YAW_DEG: float = 45.0
const TILE_PX: float = 96.0  # 한 칸 마름모의 폭(픽셀). 기존 게임과 같음.
# 높이 한 칸 = 3배 낮춘 화면에서 정확히 20 픽셀(= 1배에서 60). 30도 기울기에서 세로 한 단위는 (칸폭/√2)·cos30° 픽셀이라 그냥 1.0 단위로 두면
# 정수 픽셀이 되지 않아서, 높이를 이 단위로 센다(슬라이드: "블록 높이를 정수 픽셀로 맞춘다").
const BLOCK_HEIGHT_LOW_PX: float = 20.0
const LOW_TILE_PX: float = 32.0  # 3배 낮춘 화면에서 한 칸 마름모 폭

var container: SubViewportContainer
var viewport: SubViewport
var camera: Camera3D
var light: DirectionalLight3D
var actor: Sprite3D
var shrink: int = 1
var tile_px: float = TILE_PX  # 화면에서 한 칸 마름모 폭(바꾸면 칸 크기가 변함: 108 = 3배에서 낮은 해상도 36)
var low_tile_px: float = LOW_TILE_PX  # 3배 화면에서의 낮은 해상도 칸 폭(tile_px / 3 과 같게 둘 것)
var block_px: float = BLOCK_HEIGHT_LOW_PX
var shadows: bool = true
var toon: bool = false
var posterize: bool = false
var snap: bool = true  # 카메라와 캐릭터를 화면 픽셀 단위로만 움직인다(Never's End 의 픽셀 스냅)
var drift: bool = false  # 카메라를 일부러 소수 픽셀씩 흘려서 스냅 효과를 눈으로 본다
var cam_target: Vector3 = Vector3(4, 0, 4)
var actor_logic_pos: Vector3 = Vector3(3.6, 0.0, 5.4)
var drift_time: float = 0.0
var materials: Array[StandardMaterial3D] = []
var post_material: ShaderMaterial
var label: Label


func _ready() -> void:
	_build_view()
	_build_world()
	_apply_shrink()
	var layer := CanvasLayer.new()
	add_child(layer)
	label = Label.new()
	label.position = Vector2(16, 10)
	label.add_theme_font_size_override("font_size", 20)
	layer.add_child(label)
	_update_label()


func _build_view() -> void:
	container = SubViewportContainer.new()
	container.stretch = true
	container.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	container.size = Vector2(1152, 648)
	var canvas := CanvasLayer.new()
	canvas.layer = -1
	add_child(canvas)
	canvas.add_child(container)
	viewport = SubViewport.new()
	viewport.handle_input_locally = false
	viewport.msaa_3d = Viewport.MSAA_DISABLED
	viewport.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	container.add_child(viewport)
	var shader := Shader.new()
	shader.code = "shader_type canvas_item;\nuniform float levels = 256.0;\nvoid fragment() {\n\tvec4 c = texture(TEXTURE, UV);\n\tCOLOR = vec4(floor(c.rgb * levels + 0.5) / levels, c.a);\n}\n"
	post_material = ShaderMaterial.new()
	post_material.shader = shader
	container.material = post_material
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.rotation_degrees = Vector3(-PITCH_DEG, YAW_DEG, 0.0)
	camera.near = 0.1
	camera.far = 100.0
	# 한 칸 마름모 폭 = TILE_PX → 한 단위(축 방향) = TILE_PX / sqrt(2) 픽셀. 화면 높이(648) 안에 보이는 세계 높이:
	camera.size = 648.0 / (tile_px / sqrt(2.0))
	viewport.add_child(camera)
	_update_camera()


# 화면 한 픽셀이 세계에서 차지하는 길이(카메라 오른쪽·위 방향). 낮춘 화면 기준.
func pixel_world_size() -> float:
	return 1.0 / ((tile_px / float(shrink)) / sqrt(2.0))


# 세계 위치를 카메라 오른쪽·위 방향으로 화면 픽셀 격자에 맞춘다(깊이 방향은 그대로).
func snap_to_pixels(p: Vector3) -> Vector3:
	var px: float = pixel_world_size()
	var right: Vector3 = camera.basis.x
	var up: Vector3 = camera.basis.y
	var r: float = p.dot(right)
	var u: float = p.dot(up)
	return p + (roundf(r / px) * px - r) * right + (roundf(u / px) * px - u) * up


func _update_camera() -> void:
	var pos: Vector3 = cam_target + camera.basis.z * 30.0
	camera.position = snap_to_pixels(pos) if snap else pos


# 시험용 도트 질감(코드로 만든 임시 그림). 실제로는 Pixel Lab 으로 만든 질감 한 장이 들어갈 자리다.
# 기존 art/world/cozy_v3 의 풀·돌·나무 그림은 64x64 단색이라 3D 에 씌워도 모양이 안 보여서 쓰지 않았다.
static func make_texture(kind: String, size: int = 16) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(kind)

	for y in range(size):
		for x in range(size):
			var c: Color

			match kind:
				"grass":
					var shade: float = rng.randf_range(-0.07, 0.07)
					c = Color(0.36 + shade, 0.6 + shade, 0.3 + shade)

					if rng.randf() < 0.05:
						c = Color(0.5, 0.74, 0.36)
				"brick":
					var row: int = y / 8
					var offset: int = (row % 2) * 8
					var mortar: bool = (y % 8 == 0) or ((x + offset) % 16 == 0)
					var tone: float = rng.randf_range(-0.04, 0.04)
					c = Color(0.3, 0.3, 0.38) if mortar else Color(0.5 + tone, 0.5 + tone, 0.58 + tone)
				_:  # plank
					var plank: bool = (y % 8 == 0)
					var grain: float = rng.randf_range(-0.03, 0.03)
					c = Color(0.3, 0.2, 0.12) if plank else Color(0.62 + grain, 0.43 + grain, 0.27 + grain)

			img.set_pixel(x, y, c)

	return ImageTexture.create_from_image(img)


func _material(kind: String, tint: Color = Color.WHITE) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.set_meta("kind", kind)
	m.albedo_texture = make_texture(kind, _texture_size())
	m.albedo_color = tint
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3(1, 1, 1)  # 한 칸에 그림 한 장
	m.roughness = 1.0
	m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	materials.append(m)
	return m


# 높이 "칸 수"(blocks)를 세계 높이로 바꾼다: 한 칸 = 3배 낮춘 화면의 20픽셀.
func block_height(blocks: float) -> float:
	var px_per_unit_z: float = (low_tile_px / sqrt(2.0)) * cos(deg_to_rad(PITCH_DEG))
	return blocks * block_px / px_per_unit_z


func _add_box(cell: Vector2, size: Vector2, height: float, material: Material, base_height: float = 0.0) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(size.x, height, size.y)
	var inst := MeshInstance3D.new()
	inst.mesh = mesh
	inst.material_override = material
	# 칸 (cell) 의 왼쪽 위 모서리를 기준으로 놓는다(IsoBox 와 같은 규칙).
	inst.position = Vector3(cell.x + size.x * 0.5, base_height + height * 0.5, cell.y + size.y * 0.5)
	viewport.add_child(inst)
	return inst


func _build_world() -> void:
	# 바닥: 풀 질감 12x12 칸
	var floor_mesh := PlaneMesh.new()
	floor_mesh.size = Vector2(14, 12)
	var floor_inst := MeshInstance3D.new()
	floor_inst.mesh = floor_mesh
	floor_inst.material_override = _material(GRASS)
	floor_inst.position = Vector3(5.0, 0.0, 4.0)
	viewport.add_child(floor_inst)

	# 긴 벽, 기둥, 낮은 판, 상자 두 개(글의 장면과 비슷한 배치)
	_add_box(Vector2(0, 0), Vector2(8, 1), block_height(2.0), _material(PAVING))
	_add_box(Vector2(5, 4), Vector2(1, 1), block_height(3.0), _material(WOOD, Color(0.55, 0.95, 0.65)))
	_add_box(Vector2(6, 4), Vector2(3, 1), block_height(1.0), _material(WOOD, Color(0.95, 0.65, 0.75)))
	_add_box(Vector2(2, 2), Vector2(1, 1), block_height(1.0), _material(WOOD))
	_add_box(Vector2(2, 5), Vector2(1, 1), block_height(1.0), _material(WOOD))

	# 캐릭터: 2D 도트 한 장을 세운 판. 항상 카메라를 향하되 위아래로는 눕지 않는다.
	actor = Sprite3D.new()
	var atlas := AtlasTexture.new()
	atlas.atlas = load(PLAYER_SHEET)
	atlas.region = Rect2(0, 0, 64, 64)
	actor.texture = atlas
	actor.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	actor.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	actor.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	actor.shaded = true
	actor.pixel_size = (1.0 / (tile_px / sqrt(2.0)))  # 그림 한 픽셀 = 화면 한 픽셀
	actor_logic_pos = Vector3(3.6, 0.0, 5.4)
	actor.position = actor_logic_pos + Vector3(0.0, 32.0 * actor.pixel_size, 0.0)
	viewport.add_child(actor)

	light = DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-55, 25, 0)
	light.shadow_enabled = true
	light.light_energy = 1.1
	viewport.add_child(light)

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.55, 0.72, 0.9)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.7, 0.72, 0.8)
	env.ambient_light_energy = 0.55
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	viewport.add_child(world_env)


# 한 칸의 텍셀 수: 낮은 해상도일수록 적게(한 텍셀 ≈ 화면 한 픽셀이 되도록).
func _texture_size() -> int:
	return int(roundf(tile_px / float(shrink) * 0.5))


func _apply_shrink() -> void:
	container.stretch_shrink = shrink
	light.shadow_enabled = shadows

	for m in materials:
		m.albedo_texture = make_texture(str(m.get_meta("kind")), _texture_size())
		m.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON if toon else BaseMaterial3D.DIFFUSE_LAMBERT

	if post_material != null:
		post_material.set_shader_parameter("levels", 8.0 if posterize else 256.0)


func _process(delta: float) -> void:
	var move := Vector3(Input.get_axis("ui_left", "ui_right"), 0.0, Input.get_axis("ui_up", "ui_down"))

	if move != Vector3.ZERO and actor != null:
		# 화면 기준 방향키를 바닥 평면 방향으로 바꾼다(카메라가 45도 돌아 있으므로).
		var dir: Vector3 = Vector3(move.x + move.z, 0.0, move.z - move.x).normalized()
		actor_logic_pos += dir * 2.2 * delta

	if drift:
		drift_time += delta
		cam_target = Vector3(4, 0, 4) + camera.basis.x * (sin(drift_time * 0.6) * 1.5) * 1.0 + camera.basis.y * 0.0

	_update_camera()
	_update_actor()


# 캐릭터 그림 위치: 논리 위치(연속)를 스냅이 켜져 있으면 화면 픽셀 격자에 맞춘다(발이 땅에 붙도록 높이는 그대로).
func _update_actor() -> void:
	if actor == null:
		return

	var foot: Vector3 = snap_to_pixels(actor_logic_pos) if snap else actor_logic_pos
	actor.position = foot + Vector3(0.0, 32.0 * actor.pixel_size, 0.0)


func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return

	match event.keycode:
		KEY_1:
			shrink = 1
		KEY_2:
			shrink = 2
		KEY_3:
			shrink = 3
		KEY_L:
			shadows = not shadows
		KEY_T:
			toon = not toon
		KEY_P:
			posterize = not posterize
		KEY_S:
			snap = not snap
		KEY_C:
			drift = not drift
		_:
			return

	_apply_shrink()
	_update_label()


func _update_label() -> void:
	label.text = "1/2/3 낮추기 %d배 / L 그림자 %s / T 계단식 빛 %s / P 색 줄이기 %s / S 픽셀 스냅 %s / C 카메라 흘리기 %s" % [shrink, "켬" if shadows else "끔", "켬" if toon else "끔", "켬" if posterize else "끔", "켬" if snap else "끔", "켬" if drift else "끔"]
