extends Node3D
## 3D 도형 + 2D 그림 시험 방(실험). 건물·가구는 3D 상자에 기존 2D 질감을 씌우고, 캐릭터는 2D 도트를 판(Sprite3D)으로 세운다.
## 목적: 이 방식의 모양(도트 느낌, 앞뒤 정렬, 빛과 그림자)이 마음에 드는지 눈으로 확인한다. 게임 코드와 연결하지 않은 독립 장면이다.
##   키: 1/2/3 = 화면 낮추기 배율(1배/2배/3배, 낮출수록 거칠고 도트 느낌이 강함) / L = 빛·그림자 켜기·끄기 / 방향키 = 캐릭터 이동
## 실행: Godot 에서 dev/spike3d/iso_room_spike.tscn 열고 F6.

const GRASS: String = "grass"
const PAVING: String = "brick"
const WOOD: String = "plank"
const PLAYER_SHEET: String = "res://art/characters/cozy_v1/player/sheet.png"

# 한 칸 = 1 단위. 카메라: 위에서 30도, 옆으로 45도(2:1 마름모).
const PITCH_DEG: float = 30.0
const YAW_DEG: float = 45.0
const TILE_PX: float = 96.0  # 한 칸 마름모의 폭(픽셀). 기존 게임과 같음.

var container: SubViewportContainer
var viewport: SubViewport
var camera: Camera3D
var light: DirectionalLight3D
var actor: Sprite3D
var shrink: int = 1
var shadows: bool = true
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
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.rotation_degrees = Vector3(-PITCH_DEG, YAW_DEG, 0.0)
	camera.position = Vector3(4, 0, 4) + camera.basis.z * 30.0
	camera.near = 0.1
	camera.far = 100.0
	# 한 칸 마름모 폭 = TILE_PX → 한 단위(축 방향) = TILE_PX / sqrt(2) 픽셀. 화면 높이(648) 안에 보이는 세계 높이:
	camera.size = 648.0 / (TILE_PX / sqrt(2.0))
	viewport.add_child(camera)


# 시험용 도트 질감(코드로 만든 임시 그림). 실제로는 Pixel Lab 으로 만든 질감 한 장이 들어갈 자리다.
# 기존 art/world/cozy_v3 의 풀·돌·나무 그림은 64x64 단색이라 3D 에 씌워도 모양이 안 보여서 쓰지 않았다.
static func make_texture(kind: String, size: int = 32) -> ImageTexture:
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
	m.albedo_texture = make_texture(kind)
	m.albedo_color = tint
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3(1, 1, 1)  # 한 칸에 그림 한 장
	m.roughness = 1.0
	return m


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
	_add_box(Vector2(0, 0), Vector2(8, 1), 1.8, _material(PAVING))
	_add_box(Vector2(5, 4), Vector2(1, 1), 2.6, _material(WOOD, Color(0.55, 0.95, 0.65)))
	_add_box(Vector2(6, 4), Vector2(3, 1), 0.7, _material(WOOD, Color(0.95, 0.65, 0.75)))
	_add_box(Vector2(2, 2), Vector2(1, 1), 0.9, _material(WOOD))
	_add_box(Vector2(2, 5), Vector2(1, 1), 0.9, _material(WOOD))

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
	actor.pixel_size = (1.0 / (TILE_PX / sqrt(2.0)))  # 그림 한 픽셀 = 화면 한 픽셀
	actor.position = Vector3(3.6, 32.0 * actor.pixel_size, 5.4)
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


func _apply_shrink() -> void:
	container.stretch_shrink = shrink
	light.shadow_enabled = shadows


func _process(delta: float) -> void:
	var move := Vector3(Input.get_axis("ui_left", "ui_right"), 0.0, Input.get_axis("ui_up", "ui_down"))

	if move != Vector3.ZERO and actor != null:
		# 화면 기준 방향키를 바닥 평면 방향으로 바꾼다(카메라가 45도 돌아 있으므로).
		var dir: Vector3 = Vector3(move.x + move.z, 0.0, move.z - move.x).normalized()
		actor.position += dir * 2.2 * delta


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
		_:
			return

	_apply_shrink()
	_update_label()


func _update_label() -> void:
	label.text = "1/2/3: 화면 낮추기 %d배 / L: 그림자 %s / 방향키: 캐릭터 이동" % [shrink, "켬" if shadows else "끔"]
