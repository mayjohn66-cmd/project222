class_name StoreView3D
extends Node
## 매장 안쪽을 3D 도트 방식(낮은 해상도 3D + 정렬 순서 깊이 + 한 픽셀 윤곽선 + 법선 맵)으로 다시 그리는 "보이는 층".
## 게임 규칙·충돌·길찾기·건축은 지금의 2D 코드가 그대로 맡고, 이 층은 2D 노드의 상태를 **읽기만** 한다(2D 코드를 바꾸지 않음).
## World 노드 아래에 붙인다. 읽는 곳: Floor(칸 수), WoodWalls(벽 선분), Objects(가구: 메타 build_id/anchor, Visual 의 footprint/rotation),
## Actors/Player(+ Camera2D), 그룹 customer / worker / story_npc / merchant_npc.
## 설계: docs/계획_매장_3D_적용_초안.md, 규격: docs/그림_규격서_3D도트_초안.md
## 칸 좌표: 2D 게임의 칸 좌표(칸 중심이 정수)를 그대로 3D 의 (x, z) 로 쓴다.


const GAME_TILE: Vector2 = Vector2(96.0, 48.0)  # 2D 게임의 칸 크기
# 확대 배율(shrink)에 따라 정해지는 값. 기본 3배: 낮은 해상도 칸 36×18, 블록 22px, 질감 18, 2D 줌 1.125.
# configure_scale(n) 으로 1·2·3배를 고를 수 있다(시험·비교용, 노드를 장면에 넣기 전에 호출).
var shrink: int = 3  # 낮은 해상도 → 화면 확대 배율
var tile_low: float = 36.0  # 낮은 해상도에서 한 칸 마름모 폭
var block_px: float = 22.0  # 1블록 = 낮은 해상도 세로 px
var match_zoom: float = 1.125  # 2D 카메라가 이 줌일 때 3D 와 2D 칸 크기가 같다
var texture_size: int = 18  # 질감 한 변 = 칸 폭의 절반
var actor_height_px: float = 25.0  # 캐릭터 정렬 상자 높이(블록 px 단위)
const PITCH_DEG: float = 30.0
const YAW_DEG: float = 45.0

const WALL_THICKNESS: float = 0.3
# 2D 벽 높이(96칸 기준 px)를 낮은 해상도 px 로: ×36/96. 120px → 45px ≈ 2.0블록, 75px → 28px ≈ 1.3블록 (캐릭터 25px 와의 비율도 같음)
const WALL_TALL_BLOCKS: float = 2.0  # 안쪽 벽(2D 120px)
const WALL_LOW_BLOCKS: float = 1.3  # 도로 쪽 벽(2D 75px)
const WALL_TALL_PX: float = 100.0  # 이보다 높은 2D 벽 = 안쪽 벽

const ACTOR_HEAD_RATIO: float = 3.0
const ACTOR_TOTAL: float = 1.14
const ACTOR_TORSO: float = 0.308
const ACTOR_HALF: float = 0.12

const SURFACE_SHADER: Shader = preload("res://script/world/view3d/shader/sorted_surface.gdshader")
const ID_SHADER: Shader = preload("res://script/world/view3d/shader/sorted_id.gdshader")
const OUTLINE_SHADER: Shader = preload("res://script/world/view3d/shader/outline_post.gdshader")
const FACADE_SHADER: Shader = preload("res://script/world/view3d/shader/facade.gdshader")

var world: Node2D
var floor_node: Node2D
var objects_node: Node2D
var player: Node2D
var camera2d: Camera2D

var _canvas: CanvasLayer
var _container: SubViewportContainer
var _viewport: SubViewport
var _id_viewport: SubViewport
var _camera: Camera3D
var _id_camera: Camera3D
var _sun: DirectionalLight3D
var _fill: DirectionalLight3D  # 보조광: 그림자 쪽 벽(+x 면)이 새까맣게 떨어지지 않게 반대편에서 약하게 비춘다(그림자 없음)
var _post_material: ShaderMaterial
var _ready_done: bool = false

# 키 → {mesh, material, id_mesh, id_material, min, max, center, signature}
var _items: Dictionary = {}
# 노드 인스턴스 id → {node, figure}
var _actors: Dictionary = {}
var _floor_signature: String = ""
var _wall_signature: String = ""
var _wall_timer: float = 0.0
var _ground_material: ShaderMaterial
var _ground_mesh: MeshInstance3D
var _ground_id_mesh: MeshInstance3D
var _ground_id_material: ShaderMaterial
var _texture_cache: Dictionary = {}
# 숨긴 2D 그림 노드: 인스턴스 id → [노드, 원래 visible]
var _hidden_2d: Dictionary = {}
const VIEW_MARGIN: float = 15.0  # 정렬에 넣는 범위(카메라 중심 칸 ± 이 값)
var _view_center: Vector2 = Vector2.ZERO
var _sorted_keys: Array = []
var _fixed_keys: Array = []  # 정렬 없이 고정 순번을 쓰는 항목(바닥 돌 마당 등: 바닥 바로 위, 모든 물체 뒤)
var _sort_usec: int = 0
var _env: Environment
var _lamps: Array = []
var _lamp_signature: String = ""
var day_manager: Node
var exterior: Node2D
var weather_override: String = ""  # 개발용: clear / rain / snow. 비우면 날씨 계산(WeatherSystem)을 따른다
var weather_override_intensity: float = 0.85
var weather: Dictionary = {"kind": "clear", "intensity": 0.0}  # 지금 날씨(부드럽게 변하는 값)
var _weather_overlay: WeatherOverlay
var _leaf_overlay: LeafOverlay
var decals: GroundDecals  # 물웅덩이·눈 발자국
var wetness: float = 0.0  # 젖은 정도 0~1(비가 오면 빨리 오르고, 그친 뒤 천천히 마른다)
var season_override: String = ""  # 개발용: 비우면 달력(GameState.total_day)을 따른다
var sync_collision: bool = true  # 3D 로 보이는 건물·소품의 발자국을 실제 충돌 모양으로 쓴다
## 색 단계 수(채널당). 256 = 제한 없음, 낮출수록 색이 뭉쳐서 도트 그림 같은 느낌(예: 12). 시험용 값.
# 빛 세기 배율(낮 해·환경광). 참조 화면보다 밝게 날아갈 때 낮춘다. 후처리의 knee(하이라이트 눌림)와 같이 쓴다.
var light_scale: float = 0.82
# 시간대 색을 빛에 반영하는 정도(1 = 그대로, 0 = 색 없음).
var tint_strength: float = 0.7
var color_levels: float = 256.0:
	set(value):
		color_levels = value

		if _post_material != null:
			_post_material.set_shader_parameter("levels", value)
var village: VillageMirror
## 0 이상이면 게임 시계 대신 이 시각(0~24)을 쓴다(시험용). 음수면 DayManager 의 시각을 따른다.
var forced_hour: float = -1.0


func configure_scale(n: int) -> void:
	shrink = clampi(n, 1, 3)
	match_zoom = 1.125 if shrink == 3 else 1.0
	tile_low = 96.0 * match_zoom / float(shrink)
	block_px = roundf(tile_low * 22.0 / 36.0)
	texture_size = int(roundf(tile_low * 0.5))
	actor_height_px = tile_low * 25.0 / 36.0


func _ready() -> void:
	process_priority = 200  # 2D 노드들이 움직인 다음에 읽는다
	process_mode = Node.PROCESS_MODE_ALWAYS  # 건축 모드가 게임을 멈춰도(get_tree().paused) 3D 는 미리보기·가구를 계속 갱신한다
	world = get_parent() as Node2D
	_build_view.call_deferred()


func _build_view() -> void:
	floor_node = world.get_node_or_null("Floor")
	objects_node = world.get_node_or_null("Objects")
	player = world.get_node_or_null("Actors/Player")
	day_manager = world.get_node_or_null("DayManager")
	exterior = world.get_node_or_null("StoreExterior")

	if floor_node == null or objects_node == null:
		push_warning("[StoreView3D] Floor/Objects 를 찾지 못해 3D 층을 만들지 않음")
		return

	if player != null:
		camera2d = player.get_node_or_null("Camera2D")

	_canvas = CanvasLayer.new()
	_canvas.layer = 0
	add_child(_canvas)
	_container = SubViewportContainer.new()
	_container.stretch = true
	_container.stretch_shrink = shrink
	_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_container.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.add_child(_container)
	_weather_overlay = WeatherOverlay.new()
	_weather_overlay.pixel = shrink
	_weather_overlay.visible = false
	_canvas.add_child(_weather_overlay)
	_leaf_overlay = LeafOverlay.new()
	_leaf_overlay.pixel = shrink
	_leaf_overlay.visible = false
	_canvas.add_child(_leaf_overlay)

	_viewport = SubViewport.new()
	_viewport.own_world_3d = true
	_viewport.transparent_bg = true
	_viewport.msaa_3d = Viewport.MSAA_DISABLED
	_viewport.handle_input_locally = false
	_container.add_child(_viewport)

	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.rotation_degrees = Vector3(-PITCH_DEG, YAW_DEG, 0.0)
	_camera.near = 0.1
	_camera.far = 100.0
	_camera.cull_mask = 1
	_viewport.add_child(_camera)

	_sun = DirectionalLight3D.new()
	_sun.shadow_enabled = true
	_sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL  # 구간을 나누지 않아 카메라가 움직여도 그림자가 흔들리지 않게
	_sun.directional_shadow_max_distance = 90.0
	_viewport.add_child(_sun)
	_fill = DirectionalLight3D.new()
	_fill.shadow_enabled = false
	_fill.rotation_degrees = Vector3(-38.0, 90.0, 0.0)
	_viewport.add_child(_fill)

	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.7, 0.72, 0.8)
	env.ambient_light_energy = 0.55
	_env = env
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	_viewport.add_child(world_env)
	apply_hour(12.0)

	_build_id_pass()
	_post_material = ShaderMaterial.new()
	_post_material.shader = OUTLINE_SHADER
	_post_material.set_shader_parameter("id_tex", _id_viewport.get_texture())
	_container.material = _post_material
	_post_material.set_shader_parameter("levels", color_levels)
	_post_material.set_shader_parameter("shadow_amount", 0.28)  # 어두운 부분의 푸른 눌림(옛 0.45)을 줄여 그림자 속도 보이게
	_post_material.set_shader_parameter("exposure", 0.9 if PlaceholderTextures.clean else 1.0)
	if exterior != null:
		village = VillageMirror.new(self, exterior)
		decals = GroundDecals.new(self, village)

	_ready_done = true
	_apply_mode()


# 윤곽선용 번호 판: 같은 3D 세계를 층 2 카메라로 한 번 더 그린다(물체마다 순번 값만).
func _build_id_pass() -> void:
	_id_viewport = SubViewport.new()
	_id_viewport.world_3d = _viewport.world_3d
	_id_viewport.transparent_bg = false
	_id_viewport.msaa_3d = Viewport.MSAA_DISABLED
	_id_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_id_viewport)
	_id_camera = Camera3D.new()
	_id_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_id_camera.near = 0.1
	_id_camera.far = 100.0
	_id_camera.cull_mask = 2
	_id_viewport.add_child(_id_camera)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0, 0, 0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	var id_env := WorldEnvironment.new()
	id_env.environment = env
	_id_viewport.add_child(id_env)


# 처음 한 번: 3D 층을 켜고 2D 그림을 숨기며, 3D 칸 크기(화면 108px)와 2D 칸 크기를 맞추려고 2D 카메라 줌을 올린다.
func _apply_mode() -> void:
	_canvas.visible = true
	_collect_2d_to_hide()

	if camera2d != null:
		camera2d.zoom = Vector2.ONE * match_zoom

	set_process(true)


# 마을 건물·소품을 다시 만든다(art/world3d/ 에 그림을 넣거나 바꾼 뒤 게임을 껐다 켜지 않고 확인할 때, F8).
func reload_village_art() -> void:
	if village == null:
		return

	for key in _items.keys():
		if str(key).begins_with("vil"):
			_remove_item(str(key))

	village._keys.clear()
	village.reset_signatures()


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F8:
		reload_village_art()

	# F7: 날씨 강제 순환(자동 → 비 → 눈 → 맑음 → 자동), F6: 계절 강제 순환(자동 → 봄 → 여름 → 가을 → 겨울 → 자동). 개발·확인용.
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F7:
		var wl: Array = ["", "rain", "snow", "clear"]
		weather_override = wl[(wl.find(weather_override) + 1) % wl.size()]

	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F6:
		var sl: Array = ["", "spring", "summer", "autumn", "winter"]
		season_override = sl[(sl.find(season_override) + 1) % sl.size()]


# ---------------------------------------------------------------- 2D 그림 숨기기 (기존 게임 파일은 수정하지 않고 visible 만 바꿈)

func _hide_2d_node(n: CanvasItem) -> void:
	if n == null:
		return

	var id: int = n.get_instance_id()

	if not _hidden_2d.has(id):
		_hidden_2d[id] = [n, n.visible]

	n.visible = false


# 숨길 것: 바닥(그림만. 충돌 노드는 그대로), 판자 벽, 가구와 사람의 그림 노드(Visual). 글자 표시(재고 등)·건축 고스트·UI 는 그대로 둔다.
func _collect_2d_to_hide() -> void:
	if exterior != null:
		_hide_2d_node(exterior)

		for container_name in VillageMirror.CONTAINERS:
			_hide_2d_node(world.get_node_or_null(container_name) as CanvasItem)

	_hide_2d_node(floor_node)
	_hide_2d_node(world.get_node_or_null("WoodWalls") as CanvasItem)

	for node in objects_node.get_children():
		_hide_2d_node(node.get_node_or_null("Visual") as CanvasItem)

	for n in _collect_actor_nodes():
		_hide_2d_node(n.get_node_or_null("Visual") as CanvasItem)


# ---------------------------------------------------------------- 시간대 빛

# 게임 시각(시 + 이번 시의 진행률). day_night_tint.gd 와 같은 방식으로 계산한다.
func _current_hour() -> float:
	if forced_hour >= 0.0:
		return forced_hour

	if day_manager == null:
		return 12.0

	var hour: float = float(day_manager.current_hour)
	var timer: Timer = day_manager.hour_timer

	if timer != null and not timer.is_stopped() and timer.wait_time > 0.0:
		hour += clampf(1.0 - timer.time_left / timer.wait_time, 0.0, 1.0)

	return hour


# 날씨 목표값(override 또는 달력·시각 계산)을 향해 부드럽게 바꾸고, 비·눈 입자 판에 알린다.
func _update_weather(delta: float) -> void:
	var target: Dictionary

	WeatherSystem.debug_kind = weather_override
	WeatherSystem.debug_intensity = weather_override_intensity
	var gs: Node = get_node_or_null("/root/GameState")
	target = WeatherSystem.forecast(int(gs.get("total_day")) if gs != null else 1, _current_hour())

	var kind: String = str(target["kind"])
	var k: float = float(weather["intensity"])
	var goal: float = float(target["intensity"])

	# 종류가 바뀌면 먼저 약해져서 0 이 된 뒤 새 날씨로 바뀐다.
	if kind != str(weather["kind"]) and k > 0.01:
		goal = 0.0

	k = move_toward(k, goal, delta * 0.35)

	if k <= 0.01 and kind != str(weather["kind"]):
		weather["kind"] = kind

	weather["intensity"] = k

	# 젖음: 비가 올 때 비의 세기만큼 빠르게 오르고, 아니면 천천히 마른다(눈은 젖게 하지 않는다).
	if str(weather["kind"]) == "rain" and k > 0.01:
		wetness = move_toward(wetness, minf(1.0, k * 1.15), delta * 0.25)
	else:
		wetness = move_toward(wetness, 0.0, delta * 0.03)

	if _post_material != null:
		_post_material.set_shader_parameter("wet", wetness)
	_weather_overlay.pixel = shrink
	_weather_overlay.set_weather(str(weather["kind"]), k)

	# 가을 낙엽: leaf_fall 이 켜진 계절에만. 비·눈이 오면 줄어든다.
	var leaf_on: float = float(SeasonStyle.style(current_season()).get("leaf_fall", 0.0))
	_leaf_overlay.pixel = shrink
	_leaf_overlay.set_amount(leaf_on * (1.0 - clampf(k * 1.5, 0.0, 1.0)))


# 지금 계절(spring/summer/autumn/winter). season_override 가 있으면 그것, 아니면 달력.
func current_season() -> String:
	if season_override != "":
		return season_override

	var gs: Node = get_node_or_null("/root/GameState")

	if gs == null:
		return "spring"

	return SeasonStyle.season_of_day(int(gs.get("total_day")))


# 해/달 방향·색·세기, 환경광, 매장 등을 시각에 맞춘다. 색조는 data/shop/time_of_day.csv(2D 와 같은 표)에서 가져온다.
func apply_hour(h: float) -> void:
	if _env == null:
		return

	var hour: float = fposmod(h, 24.0)
	var raw_tint: Color = TimeOfDayData.get_tint(hour)
	var luminance: float = raw_tint.get_luminance()
	# 해·환경광 색은 시간대 색을 그대로 쓰지 않고 흰색 쪽으로 당겨(저녁·새벽이 붉게 쏠리지 않게) 쓴다.
	var tint: Color = Color.WHITE.lerp(raw_tint, tint_strength)
	var sst: Dictionary = SeasonStyle.style(current_season())
	tint = tint * (sst["sun_tint"] as Color).lerp(Color.WHITE, 0.4)
	var dark: float = 1.0 - clampf((luminance - 0.35) / 0.65, 0.0, 1.0)  # 0 = 낮, 1 = 한밤
	var day_amt: float = smoothstep(5.0, 7.0, hour) * (1.0 - smoothstep(17.0, 19.0, hour))
	var sun_curve: float = clampf(sin((hour - 6.0) / 12.0 * PI), 0.0, 1.0)
	var elev: float = lerpf(42.0, lerpf(10.0, 62.0, sun_curve), day_amt)
	var yaw: float = lerpf(-110.0, lerpf(-75.0, 75.0, clampf((hour - 6.0) / 12.0, 0.0, 1.0)), day_amt)
	_sun.rotation_degrees = Vector3(-elev, yaw, 0.0)
	_sun.light_color = tint
	# 깔끔한 스타일은 환경광을 높이고 해를 낮춰 그림자가 연하게(참조 화면처럼 밝고 대비가 낮게).
	var sun_k: float = 0.3 if PlaceholderTextures.clean else 1.0
	var amb_k: float = 1.05 if PlaceholderTextures.clean else 1.0
	_sun.light_energy = light_scale * sun_k * lerpf(0.9, lerpf(0.8, 1.2, sun_curve), day_amt)
	_env.ambient_light_color = Color(0.74, 0.76, 0.84) * tint * (sst["ambient_tint"] as Color)
	_env.ambient_light_energy = light_scale * lerpf(1.35, 1.3 * amb_k, day_amt)
	var wk: float = float(weather["intensity"])
	_sun.shadow_opacity = lerpf(1.0, 0.35, wk)  # 흐린 날은 그림자가 연하다

	if wk > 0.0:
		var rainy: bool = str(weather["kind"]) == "rain"
		_sun.light_energy *= lerpf(1.0, 0.4 if rainy else 0.65, wk)
		_env.ambient_light_color = _env.ambient_light_color.lerp(Color(0.62, 0.68, 0.8) if rainy else Color(0.8, 0.84, 0.95), wk * 0.7)
		_env.ambient_light_energy *= lerpf(1.0, 1.0 if rainy else 1.15, wk)
	_fill.light_color = tint.lerp(Color(0.85, 0.9, 1.0), 0.35)
	_fill.light_energy = lerpf(0.3, 0.3 if PlaceholderTextures.clean else 0.5, day_amt)

	for lamp in _lamps:
		(lamp as OmniLight3D).light_energy = 1.6 * dark
		(lamp as OmniLight3D).visible = dark > 0.05


# 매장 천장 등(밤에 켜짐): 매장 안을 격자로 4개
func _sync_lamps(rect: Rect2i) -> void:
	var sig: String = str(rect)

	if sig == _lamp_signature:
		return

	_lamp_signature = sig

	for lamp in _lamps:
		(lamp as Node).queue_free()

	_lamps.clear()

	for fx in [0.28, 0.72]:
		for fy in [0.28, 0.72]:
			var lamp := OmniLight3D.new()
			lamp.position = Vector3(float(rect.position.x) - 0.5 + float(rect.size.x) * fx, block_height(1.8), float(rect.position.y) - 0.5 + float(rect.size.y) * fy)
			lamp.omni_range = 4.5
			lamp.light_color = Color(1.0, 0.86, 0.62)
			lamp.shadow_enabled = false
			lamp.light_cull_mask = 1
			_viewport.add_child(lamp)
			_lamps.append(lamp)


# ---------------------------------------------------------------- 좌표

# 2D 세계 좌표 → 칸 좌표(연속 값, 칸 중심이 정수)
func cell_to_world(cell: Vector2) -> Vector2:
	var tile := Vector2(floor_node.tile_width, floor_node.tile_height)
	return floor_node.to_global(Vector2((cell.x - cell.y) * 0.5 * tile.x, (cell.x + cell.y) * 0.5 * tile.y))


func world_to_cell(global_pos: Vector2) -> Vector2:
	var local: Vector2 = floor_node.to_local(global_pos)
	var tile := Vector2(floor_node.tile_width, floor_node.tile_height)
	return Vector2(local.x / tile.x + local.y / tile.y, local.y / tile.y - local.x / tile.x)


func block_height(blocks: float) -> float:
	var px_per_unit_z: float = (tile_low / sqrt(2.0)) * cos(deg_to_rad(PITCH_DEG))
	return blocks * block_px / px_per_unit_z


func _pixel_world_size() -> float:
	return _camera.size / float(_viewport.size.y)


func _snap(p: Vector3) -> Vector3:
	var px: float = _pixel_world_size()
	var right: Vector3 = _camera.basis.x
	var up: Vector3 = _camera.basis.y
	var r: float = p.dot(right)
	var u: float = p.dot(up)
	return p + (roundf(r / px) * px - r) * right + (roundf(u / px) * px - u) * up


# ---------------------------------------------------------------- 매 프레임

func _process(delta: float) -> void:
	if not _ready_done:
		return

	_sync_camera()
	_update_weather(delta)

	if decals != null:
		decals.tick(delta)
	apply_hour(_current_hour())
	_wall_timer -= delta

	if _wall_timer <= 0.0:
		_wall_timer = 0.25
		_sync_floor()
		_sync_walls()
		_sync_furniture()
		_sync_build_guides()

		if village != null:
			village.set_season(current_season())
			village.sync_ground()
			village.sync_objects(world)

		_collect_2d_to_hide()

	# 건축 중에는 미리보기·안내가 마우스를 매 프레임 따라가야 하므로 0.25초 주기를 기다리지 않는다.
	var builder: Node = world.get_node_or_null("BuildManager")

	if builder != null and builder.get("build_mode") == true:
		_sync_furniture()
		_sync_build_guides()

		_collect_2d_to_hide()

	_sync_actors(delta)
	_update_wall_cutaway(delta)

	if village != null:
		village.tick(delta)

	_sort_and_update()


func _sync_camera() -> void:
	var base_size: Vector2 = get_viewport().get_visible_rect().size
	# The stretched container owns its child viewport size; manual assignment warns every frame.
	_id_viewport.size = _viewport.size
	var zoom: float = camera2d.zoom.x if camera2d != null else 1.0
	_camera.size = base_size.y / (GAME_TILE.x * zoom / sqrt(2.0))
	var center_world: Vector2 = camera2d.get_screen_center_position() if camera2d != null else floor_node.global_position
	var c: Vector2 = world_to_cell(center_world)
	_view_center = c
	var target := Vector3(c.x, 0.0, c.y)
	var pos: Vector3 = target + _camera.basis.z * 30.0
	_camera.position = _snap(pos)
	_id_camera.global_transform = _camera.global_transform
	_id_camera.size = _camera.size


# ---------------------------------------------------------------- 바닥·벽

func _sync_floor() -> void:
	var rect: Rect2i = floor_node.get_store_rect()
	var sig: String = str(rect)

	if sig == _floor_signature:
		return

	_floor_signature = sig
	_sync_lamps(rect)
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(rect.size)

	if _ground_mesh == null:
		_ground_mesh = MeshInstance3D.new()
		_ground_mesh.layers = 1
		_ground_material = _make_surface_material("plank", Color(1.0, 0.92, 0.8) if PlaceholderTextures.clean else Color(0.62, 0.38, 0.28))
		_ground_mesh.material_override = _ground_material
		_viewport.add_child(_ground_mesh)
		_ground_id_mesh = MeshInstance3D.new()
		_ground_id_mesh.layers = 2
		_ground_id_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_ground_id_material = ShaderMaterial.new()
		_ground_id_material.shader = ID_SHADER
		_ground_id_mesh.material_override = _ground_id_material
		_viewport.add_child(_ground_id_mesh)

	_ground_mesh.mesh = mesh
	_ground_id_mesh.mesh = mesh
	var center := Vector3(float(rect.position.x) + float(rect.size.x) * 0.5 - 0.5, 0.0, float(rect.position.y) + float(rect.size.y) * 0.5 - 0.5)
	_ground_mesh.position = center
	_ground_id_mesh.position = center


# WoodWalls 의 판자 벽 선분(칸 한 변 길이)을 읽어서 이어 붙인 상자로 만든다.
func _sync_walls() -> void:
	var walls: Node = world.get_node_or_null("WoodWalls")
	var segments: Array = []

	if walls != null:
		for panel in walls.get_children():
			if not panel is Node2D:
				continue

			var start_w: Vector2 = (panel as Node2D).global_position + (panel.get("start") as Vector2)
			var end_w: Vector2 = (panel as Node2D).global_position + (panel.get("end") as Vector2)
			var a: Vector2 = world_to_cell(start_w)
			var b: Vector2 = world_to_cell(end_w)
			var tall: bool = float(panel.get("wall_height")) > WALL_TALL_PX
			segments.append({"a": a, "b": b, "direction": int(panel.get("direction")), "tall": tall})

	var sig: String = str(segments.size())

	for s in segments:
		sig += "|%.2f,%.2f,%.2f,%.2f,%d,%s" % [s["a"].x, s["a"].y, s["b"].x, s["b"].y, s["direction"], s["tall"]]

	if sig == _wall_signature:
		return

	_wall_signature = sig

	for key in _items.keys():
		if str(key).begins_with("wall"):
			_remove_item(key)

	# 같은 방향·높이이고 끝과 시작이 맞닿는 선분을 한 상자로 합친다.
	var runs: Array = []

	for s in segments:
		var along_x: bool = absf(s["a"].y - s["b"].y) < 0.05
		var line: float = s["a"].y if along_x else s["a"].x
		var lo: float = minf(s["a"].x, s["b"].x) if along_x else minf(s["a"].y, s["b"].y)
		var hi: float = maxf(s["a"].x, s["b"].x) if along_x else maxf(s["a"].y, s["b"].y)
		runs.append({"along_x": along_x, "line": snappedf(line, 0.01), "lo": lo, "hi": hi, "direction": s["direction"], "tall": s["tall"]})

	runs.sort_custom(func(p, q):
		if p["direction"] != q["direction"]:
			return p["direction"] < q["direction"]

		if p["line"] != q["line"]:
			return p["line"] < q["line"]

		return p["lo"] < q["lo"])
	var merged: Array = []

	for r in runs:
		if not merged.is_empty():
			var last: Dictionary = merged[-1]

			if last["direction"] == r["direction"] and last["line"] == r["line"] and last["tall"] == r["tall"] and absf(last["hi"] - r["lo"]) < 0.05:
				last["hi"] = r["hi"]
				continue

		merged.append(r.duplicate())

	var index: int = 0

	for r in merged:
		var lo_v: Vector2
		var hi_v: Vector2
		var line_v: float = r["line"]

		if r["along_x"]:
			# 방향 0 = 뒤쪽(y 작은 쪽) 바깥, 2 = 앞쪽(y 큰 쪽) 바깥
			var outward: float = -1.0 if r["direction"] == 0 else 1.0
			var y0: float = line_v if outward > 0.0 else line_v - WALL_THICKNESS
			lo_v = Vector2(r["lo"], y0)
			hi_v = Vector2(r["hi"], y0 + WALL_THICKNESS)
		else:
			var outward_x: float = -1.0 if r["direction"] == 3 else 1.0
			var x0: float = line_v if outward_x > 0.0 else line_v - WALL_THICKNESS
			lo_v = Vector2(x0, r["lo"])
			hi_v = Vector2(x0 + WALL_THICKNESS, r["hi"])

		var wall_blocks: float = WALL_TALL_BLOCKS if r["tall"] else WALL_LOW_BLOCKS
		_set_item("wall%d" % index, lo_v, hi_v, wall_blocks, "brick", Color(1.2, 1.08, 0.92) if PlaceholderTextures.clean else Color(0.85, 0.7, 0.55), "")
		# 앞쪽 벽(카메라에 가까운 동·남쪽 면)은 플레이어가 가까이 오면 낮아진다(벽 뒤에 서면 몸이 가려지므로). 뒤쪽 벽은 그대로.
		_items["wall%d" % index]["cutaway"] = {"rect": Rect2(lo_v, hi_v - lo_v), "h": block_height(wall_blocks), "factor": 1.0} if r["direction"] == 1 or r["direction"] == 2 else {}
		index += 1


# 앞쪽 벽 투시: 플레이어가 벽 2.4칸 안으로 들어오면 벽 높이를 부드럽게 0.38배까지 낮추고, 멀어지면 되돌린다.
const CUTAWAY_NEAR: float = 1.2
const CUTAWAY_FAR: float = 2.6
const CUTAWAY_MIN: float = 0.38


func _update_wall_cutaway(delta: float) -> void:
	if player == null or floor_node == null:
		return

	var pc: Vector2 = world_to_cell(player.global_position)

	for key in _items.keys():
		if not str(key).begins_with("wall"):
			continue

		var item: Dictionary = _items[key]
		var cut: Dictionary = item.get("cutaway", {})

		if cut.is_empty():
			continue

		var rect: Rect2 = cut["rect"]
		var nearest := Vector2(clampf(pc.x, rect.position.x, rect.end.x), clampf(pc.y, rect.position.y, rect.end.y))
		var dist: float = pc.distance_to(nearest)
		var target: float = lerpf(CUTAWAY_MIN, 1.0, clampf((dist - CUTAWAY_NEAR) / (CUTAWAY_FAR - CUTAWAY_NEAR), 0.0, 1.0))
		var f: float = move_toward(float(cut["factor"]), target, delta * 2.5)

		if absf(f - float(cut["factor"])) < 0.0005:
			continue

		cut["factor"] = f
		var h: float = float(cut["h"])

		for node_key in ["mesh", "id_mesh"]:
			var inst: MeshInstance3D = item.get(node_key)

			if inst != null and is_instance_valid(inst):
				inst.scale.y = f
				inst.position.y = h * 0.5 * f


# ---------------------------------------------------------------- 가구

func _sync_furniture() -> void:
	var alive: Dictionary = {}

	for node in objects_node.get_children():
		if not node is Node2D or not node.has_meta("build_id"):
			continue

		var is_preview: bool = bool(node.get_meta("is_build_preview", false))

		# 건축 미리보기: 보일 때만, 칸이 정해진 뒤에만 실제 가구처럼 3D 로 그린다(가능 = 밝은 청록, 불가 = 붉은색).
		if is_preview and (not (node as Node2D).is_visible_in_tree() or not node.has_meta("anchor")):
			continue

		var build_id: String = str(node.get_meta("build_id"))
		var row: Dictionary = Furniture3DData.get_row(build_id)

		if row["kind"] == "door" or row["kind"] == "wall_plate":
			_sync_wall_mounted(node, build_id, row, alive)
			continue

		if row["kind"] != "box":
			continue

		var visual: Node = node.get_node_or_null("Visual")
		var anchor: Vector2i = node.get_meta("anchor", Vector2i.ZERO)
		var rotation_index: int = int(visual.get("rotation_index")) if visual != null and visual.get("rotation_index") != null else int(node.get_meta("rotation_index", 0))
		var fx: int = int(visual.get("footprint_x")) if visual != null and visual.get("footprint_x") != null else 1
		var fy: int = int(visual.get("footprint_y")) if visual != null and visual.get("footprint_y") != null else 1
		var stack: int = int(node.get("stack_level")) if node.get("stack_level") != null else 1
		var preview_valid: bool = bool(node.get_meta("preview_valid", true))

		if is_preview:
			stack = int(node.get_meta("preview_stack", 1))
			rotation_index = int(node.get_meta("rotation_index", rotation_index))

		var key: String = "furn%d" % node.get_instance_id()
		alive[key] = true
		var sig: String = "%s|%s|%d|%d|%d|%d|%s|%s" % [build_id, str(anchor), rotation_index, fx, fy, stack, str(is_preview), str(preview_valid)]

		if _items.has(key) and _items[key]["signature"] == sig:
			continue

		# FurnitureFootprint 와 같은 규칙: 칸 중심이 정수, 두께(depth_ratio)는 회전에 따라 한쪽 변에 붙는다.
		var lo := Vector2(float(anchor.x) - 0.5, float(anchor.y) - 0.5)
		var hi := Vector2(float(anchor.x + fx) - 0.5, float(anchor.y + fy) - 0.5)
		var depth: float = row["depth_ratio"]

		if depth < 1.0:
			match posmod(rotation_index, 4):
				0:
					hi.y = lo.y + depth
				1:
					hi.x = lo.x + depth
				2:
					lo.y = hi.y - depth
				3:
					lo.x = hi.x - depth

		var height_blocks: float = float(row["height_blocks"]) + float(row["stack_step_blocks"]) * float(maxi(stack - 1, 0))
		var item_tint: Color = row["tint"]

		if is_preview:
			item_tint = item_tint.lerp(Color(0.55, 1.0, 0.9) if preview_valid else Color(1.0, 0.25, 0.25), 0.4 if preview_valid else 0.65)

		_set_item(key, lo, hi, height_blocks, str(row["texture"]), item_tint, sig)

	for key in _items.keys():
		if (str(key).begins_with("furn") or str(key).begins_with("wmount")) and not alive.has(key):
			_remove_item(key)


# ---------------------------------------------------------------- 건축 안내(발자국 윤곽·점유 칸·직원/결제/접근 칸)

var _build_guide: MeshInstance3D
var _build_guide_sig: String = ""


# BuildManager.get_build_overlay() 의 데이터를 바닥에 색 칸으로 그린다(2D _draw 의 안내를 대신함). 깊이 검사 없이 가구 위에도 보인다.
func _sync_build_guides() -> void:
	var manager: Node = world.get_node_or_null("BuildManager")
	var data: Dictionary = manager.get_build_overlay() if manager != null and manager.has_method("get_build_overlay") else {}

	if data.is_empty():
		if _build_guide != null:
			_build_guide.visible = false

		return

	var sig: String = str(data)

	if sig == _build_guide_sig and _build_guide != null:
		_build_guide.visible = true
		return

	_build_guide_sig = sig

	if _build_guide == null:
		_build_guide = MeshInstance3D.new()
		_build_guide.layers = 1
		_build_guide.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.vertex_color_use_as_albedo = true
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.no_depth_test = true
		mat.render_priority = 100
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		_build_guide.material_override = mat
		_viewport.add_child(_build_guide)

	var verts := PackedVector3Array()
	var colors := PackedColorArray()
	var y: float = 0.06

	var quad := func(x0: float, z0: float, x1: float, z1: float, c: Color) -> void:
		for p in [Vector3(x0, y, z0), Vector3(x1, y, z0), Vector3(x1, y, z1), Vector3(x0, y, z0), Vector3(x1, y, z1), Vector3(x0, y, z1)]:
			verts.append(p)
			colors.append(c)

	for cell in data["base_cells"]:
		quad.call(float(cell.x) - 0.5, float(cell.y) - 0.5, float(cell.x) + 0.5, float(cell.y) + 0.5, Color(0.6, 0.8, 0.9, 0.18))

	for g in data["guides"]:
		var c: Vector2i = g["cell"]
		quad.call(float(c.x) - 0.5, float(c.y) - 0.5, float(c.x) + 0.5, float(c.y) + 0.5, g["color"])

	# 발자국 윤곽(가구 3D 와 같은 칸 규칙): 얇은 테두리 네 줄
	var row: Dictionary = Furniture3DData.get_row(str(data["build_id"]))

	if row["kind"] == "box":
		var anchor: Vector2i = data["anchor"]
		var size: Vector2i = data["size"]
		var lo := Vector2(float(anchor.x) - 0.5, float(anchor.y) - 0.5)
		var hi := Vector2(float(anchor.x + size.x) - 0.5, float(anchor.y + size.y) - 0.5)
		var depth: float = row["depth_ratio"]

		if depth < 1.0:
			match posmod(int(data["rotation"]), 4):
				0:
					hi.y = lo.y + depth
				1:
					hi.x = lo.x + depth
				2:
					lo.y = hi.y - depth
				3:
					lo.x = hi.x - depth

		var edge: Color = Color(0.4, 0.95, 1.0, 0.95) if data["valid"] else Color(1.0, 0.3, 0.3, 0.95)
		var t: float = 0.04
		quad.call(lo.x, lo.y, hi.x, lo.y + t, edge)
		quad.call(lo.x, hi.y - t, hi.x, hi.y, edge)
		quad.call(lo.x, lo.y, lo.x + t, hi.y, edge)
		quad.call(hi.x - t, lo.y, hi.x, hi.y, edge)

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_COLOR] = colors
	var mesh := ArrayMesh.new()

	if verts.size() > 0:
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	_build_guide.mesh = mesh
	_build_guide.visible = true


# 벽에 붙는 가구(문 틀, 포스터·지도·깃발 판). 앵커 칸과 회전으로 벽 변(가장자리)을 정한다.
# 회전 0 = 뒤쪽 y 작은 변, 1 = x 큰 변, 2 = y 큰 변, 3 = x 작은 변(벽 선분 규칙 wood_walls.gd 와 같음).
func _sync_wall_mounted(node: Node2D, build_id: String, row: Dictionary, alive: Dictionary) -> void:
	var anchor: Vector2i = node.get_meta("anchor", Vector2i.ZERO)
	var rotation_index: int = posmod(int(node.get_meta("rotation_index", 0)), 4)
	var visual: Node = node.get_node_or_null("Visual")

	if visual != null and visual.get("rotation_index") != null:
		rotation_index = posmod(int(visual.get("rotation_index")), 4)

	var rect: Rect2i = floor_node.get_store_rect()
	var base_key: String = "wmount%d" % node.get_instance_id()
	var sig: String = "%s|%s|%d" % [build_id, str(anchor), rotation_index]
	alive[base_key + "a"] = true
	alive[base_key + "b"] = true
	alive[base_key + "c"] = true

	if _items.has(base_key + "a") and _items[base_key + "a"]["signature"] == sig:
		return

	for suffix in ["a", "b", "c"]:
		_remove_item(base_key + suffix)

	var along_x: bool = rotation_index == 0 or rotation_index == 2
	var line: float = 0.0
	var inward: float = 1.0

	match rotation_index:
		0:
			line = -0.5
			inward = 1.0
		1:
			line = float(rect.position.x + rect.size.x) - 0.5
			inward = -1.0
		2:
			line = float(rect.position.y + rect.size.y) - 0.5
			inward = -1.0
		3:
			line = -0.5
			inward = 1.0

	var center_along: float = float(anchor.x) if along_x else float(anchor.y)
	var tint: Color = row["tint"]
	var tex: String = str(row["texture"])

	if row["kind"] == "door":
		# 문 틀: 양쪽 기둥 + 윗 가로대(가운데는 비워 둠, 손님이 지나감)
		var post: float = 0.12
		var t: float = WALL_THICKNESS
		var depth_lo: float = line - t * 0.5
		var depth_hi: float = line + t * 0.5
		var h: float = float(row["height_blocks"])

		for k in [["a", -0.5, -0.5 + post], ["b", 0.5 - post, 0.5]]:
			var lo_v: Vector2 = Vector2(center_along + k[1], depth_lo) if along_x else Vector2(depth_lo, center_along + k[1])
			var hi_v: Vector2 = Vector2(center_along + k[2], depth_hi) if along_x else Vector2(depth_hi, center_along + k[2])
			_set_item(base_key + k[0], lo_v, hi_v, h, tex, tint, sig)

		var lo_c: Vector2 = Vector2(center_along - 0.5, depth_lo) if along_x else Vector2(depth_lo, center_along - 0.5)
		var hi_c: Vector2 = Vector2(center_along + 0.5, depth_hi) if along_x else Vector2(depth_hi, center_along + 0.5)
		_set_item(base_key + "c", lo_c, hi_c, 0.4, tex, tint, sig, h - 0.4)
	else:
		# 얇은 판: 벽 안쪽 면에 붙인다.
		var thin: float = 0.06
		var lo_p: Vector2
		var hi_p: Vector2
		var a0: float = line if inward > 0.0 else line - thin
		var a1: float = a0 + thin

		if along_x:
			lo_p = Vector2(center_along - 0.4, a0)
			hi_p = Vector2(center_along + 0.4, a1)
		else:
			lo_p = Vector2(a0, center_along - 0.4)
			hi_p = Vector2(a1, center_along + 0.4)

		_set_item(base_key + "a", lo_p, hi_p, float(row["height_blocks"]), tex, tint, sig, float(row["base_blocks"]))

	# 정리: 쓰지 않은 키는 빈 항목 제거(문은 a·b·c 모두 쓰지만 판은 a 만 씀)
	if row["kind"] != "door":
		alive.erase(base_key + "b")
		alive.erase(base_key + "c")


# ---------------------------------------------------------------- 상자 만들기·지우기

func _make_surface_material(kind: String, tint: Color) -> ShaderMaterial:
	if not _texture_cache.has(kind):
		_texture_cache[kind] = {"albedo": PlaceholderTextures.albedo(kind, texture_size), "normal": PlaceholderTextures.normal(kind, texture_size)}

	var m := ShaderMaterial.new()
	m.shader = SURFACE_SHADER
	m.set_shader_parameter("albedo_tex", _texture_cache[kind]["albedo"])
	m.set_shader_parameter("normal_tex", _texture_cache[kind]["normal"])
	m.set_shader_parameter("use_normal", true)
	m.set_shader_parameter("tint", tint)
	m.set_shader_parameter("texel_per_unit", 1.0)
	return m


# 보이는 메시는 순번 깊이(DEPTH)를 직접 써서 그림자 패스에서 그림자 깊이가 순번·개수에 따라 변한다(걸어 다닐 때 그림자가 움직이는 원인).
# → 보이는 쪽은 그림자를 끄고, 같은 메시를 보통 재질로 그리는 그림자 전용 자식을 달아 그림자를 드리운다.
func _add_shadow_caster(inst: MeshInstance3D) -> void:
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var caster := MeshInstance3D.new()
	caster.mesh = inst.mesh
	caster.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	inst.add_child(caster)


func _set_item(key: String, lo: Vector2, hi: Vector2, height_blocks: float, texture_kind: String, tint: Color, signature: String, base_blocks: float = 0.0) -> void:
	_remove_item(key)
	var h: float = block_height(height_blocks)
	var base_h: float = block_height(base_blocks)
	var mesh := BoxMesh.new()
	mesh.size = Vector3(hi.x - lo.x, h, hi.y - lo.y)
	var material: ShaderMaterial = _make_surface_material(texture_kind, tint)
	var inst := MeshInstance3D.new()
	inst.mesh = mesh
	inst.layers = 1
	inst.material_override = material
	inst.position = Vector3((lo.x + hi.x) * 0.5, base_h + h * 0.5, (lo.y + hi.y) * 0.5)
	_viewport.add_child(inst)
	_add_shadow_caster(inst)
	var id_inst := MeshInstance3D.new()
	id_inst.mesh = mesh
	id_inst.layers = 2
	id_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var id_material := ShaderMaterial.new()
	id_material.shader = ID_SHADER
	id_inst.material_override = id_material
	id_inst.position = inst.position
	_viewport.add_child(id_inst)
	_items[key] = {"mesh": inst, "material": material, "materials": [material], "id_mesh": id_inst, "id_material": id_material, "min": Vector3(lo.x, lo.y, base_blocks * block_px), "max": Vector3(hi.x, hi.y, (base_blocks + height_blocks) * block_px), "center": inst.position, "signature": signature}


# 면마다 다른 재질을 쓰는 건물 메시 항목(박공 지붕 건물 등). materials 는 메시 면(surface) 순서대로.
func _set_mesh_item(key: String, mesh: Mesh, materials: Array, lo: Vector2, hi: Vector2, total_blocks: float, signature: String, fixed_rank: float = NAN, outline: bool = true) -> void:
	_remove_item(key)
	var inst := MeshInstance3D.new()
	inst.mesh = mesh
	inst.layers = 1

	for i in range(materials.size()):
		inst.set_surface_override_material(i, materials[i])

	_viewport.add_child(inst)
	if outline:
		_add_shadow_caster(inst)
	var id_inst := MeshInstance3D.new()
	id_inst.mesh = mesh
	id_inst.layers = 2
	id_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var id_material := ShaderMaterial.new()
	id_material.shader = ID_SHADER
	id_inst.material_override = id_material
	id_inst.visible = outline  # 투명 컷아웃(풀 다발)은 윤곽선 판에 사각형이 찍히지 않게 끈다
	_viewport.add_child(id_inst)
	var center := Vector3((lo.x + hi.x) * 0.5, 0.0, (lo.y + hi.y) * 0.5)
	_items[key] = {"mesh": inst, "material": materials[0], "materials": materials, "id_mesh": id_inst, "id_material": id_material, "min": Vector3(lo.x, lo.y, 0.0), "max": Vector3(hi.x, hi.y, total_blocks * block_px), "center": center, "signature": signature, "fixed_rank": fixed_rank}


func _make_facade_material(texture: Texture2D, tint: Color = Color.WHITE, uv_scale: Vector2 = Vector2.ONE) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = FACADE_SHADER
	m.set_shader_parameter("albedo_tex", texture)
	m.set_shader_parameter("tint", tint)
	m.set_shader_parameter("uv_scale", uv_scale)
	return m


func _remove_item(key: String) -> void:
	if not _items.has(key):
		return

	(_items[key]["mesh"] as Node).queue_free()
	(_items[key]["id_mesh"] as Node).queue_free()
	_items.erase(key)


# ---------------------------------------------------------------- 사람

func _collect_actor_nodes() -> Array:
	var nodes: Array = []

	if player != null:
		nodes.append(player)

	for group_name in ["customer", "worker", "story_npc", "merchant_npc"]:
		for n in get_tree().get_nodes_in_group(group_name):
			if n is Node2D and not nodes.has(n):
				nodes.append(n)

	return nodes


func _sync_actors(delta: float) -> void:
	var seen: Dictionary = {}

	for n in _collect_actor_nodes():
		var id: int = n.get_instance_id()
		seen[id] = true

		if not _actors.has(id):
			var figure := BlockyFigure.new()
			figure.build(_viewport, _viewport, ACTOR_HEAD_RATIO, ACTOR_TOTAL, ACTOR_TORSO)
			_actors[id] = {"node": n, "figure": figure, "cell": world_to_cell((n as Node2D).global_position)}

		var entry: Dictionary = _actors[id]
		var figure: BlockyFigure = entry["figure"]
		var cell: Vector2 = world_to_cell((n as Node2D).global_position)
		var move: Vector2 = cell - (entry["cell"] as Vector2)
		entry["cell"] = cell
		figure.set_shown((n as Node2D).is_visible_in_tree())
		figure.walking = move.length() > 0.0005 and delta > 0.0

		if decals != null and village != null and (n as Node2D).is_visible_in_tree():
			decals.walk(id, cell, move, village.is_snow_ground(cell))
		if figure.walking:
			figure.move_speed = lerpf(figure.move_speed, clampf(move.length() / delta, 0.4, 4.0), 0.25)

		if move.length() > 0.0005:
			figure.facing_yaw_deg = rad_to_deg(atan2(move.x, move.y))

		figure.animate(delta)

	for id in _actors.keys():
		if not seen.has(id):
			(_actors[id]["figure"] as BlockyFigure).destroy()
			_actors.erase(id)


# ---------------------------------------------------------------- 정렬·깊이 순서

func _sort_and_update() -> void:
	var t0: int = Time.get_ticks_usec()
	var boxes: Array = []
	# 카메라 주변(보이는 범위 + 여유)의 물체만 정렬에 넣는다(마을 전체를 매 프레임 정렬하면 느림).
	var window := Rect2(_view_center - Vector2(VIEW_MARGIN, VIEW_MARGIN), Vector2(VIEW_MARGIN, VIEW_MARGIN) * 2.0)
	_sorted_keys.clear()
	_fixed_keys.clear()

	for key in _items.keys():
		var mn: Vector3 = _items[key]["min"]
		var mx: Vector3 = _items[key]["max"]

		if not window.intersects(Rect2(mn.x, mn.y, mx.x - mn.x, mx.y - mn.y)):
			continue

		if not is_nan(float(_items[key].get("fixed_rank", NAN))):
			_fixed_keys.append(key)
			continue

		_sorted_keys.append(key)
		boxes.append({"id": key, "min": mn, "max": mx})

	for id in _actors.keys():
		var cell: Vector2 = _actors[id]["cell"]
		boxes.append({"id": "a%d" % id, "min": Vector3(cell.x - ACTOR_HALF, cell.y - ACTOR_HALF, 0.0), "max": Vector3(cell.x + ACTOR_HALF, cell.y + ACTOR_HALF, actor_height_px)})

	var result: Dictionary = IsoSorter.sort_items(boxes)
	var rank_of: Dictionary = {}

	for i in range(result["order"].size()):
		rank_of[result["order"][i]] = float(i)

	var count: float = float(boxes.size())

	for key in _sorted_keys:
		var it: Dictionary = _items[key]
		var rank: float = rank_of[key]
		# 순번·개수가 그대로면 셰이더 값을 다시 넣지 않는다(재질이 많아서 비용이 큼).
		if it.get("last_rank", -99.0) == rank and it.get("last_count", -1.0) == count:
			continue

		it["last_rank"] = rank
		it["last_count"] = count

		for m in it["materials"]:
			(m as ShaderMaterial).set_shader_parameter("rank", rank)
			(m as ShaderMaterial).set_shader_parameter("rank_count", count)
			(m as ShaderMaterial).set_shader_parameter("center_world", it["center"])

		var idm: ShaderMaterial = it["id_material"]
		idm.set_shader_parameter("rank", rank)
		idm.set_shader_parameter("rank_count", count)
		idm.set_shader_parameter("id", (rank + 1.0) / (count + 1.0))

	if _ground_material != null:
		_ground_material.set_shader_parameter("rank", -1.0)
		_ground_material.set_shader_parameter("rank_count", count)
		_ground_material.set_shader_parameter("center_world", _ground_mesh.position)
		_ground_id_material.set_shader_parameter("rank", -1.0)
		_ground_id_material.set_shader_parameter("rank_count", count)
		_ground_id_material.set_shader_parameter("id", 0.0)

	for key in _fixed_keys:
		var fit: Dictionary = _items[key]
		var fr: float = float(fit["fixed_rank"])

		for m in fit["materials"]:
			(m as ShaderMaterial).set_shader_parameter("rank", fr)
			(m as ShaderMaterial).set_shader_parameter("rank_count", count)

		var fidm: ShaderMaterial = fit["id_material"]
		fidm.set_shader_parameter("rank", fr)
		fidm.set_shader_parameter("rank_count", count)
		fidm.set_shader_parameter("id", 0.0)

	if village != null:
		village.update_ground_params(count)

	for id in _actors.keys():
		var entry: Dictionary = _actors[id]
		var figure: BlockyFigure = entry["figure"]
		var cell: Vector2 = entry["cell"]
		var foot := Vector3(cell.x, 0.0, cell.y)
		figure.position = _snap(foot)
		var r: float = rank_of["a%d" % id]
		figure.sync_sort(r, count, _camera, (r + 1.0) / (count + 1.0))
	_sort_usec = Time.get_ticks_usec() - t0
