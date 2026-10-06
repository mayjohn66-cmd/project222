class_name OpeningCutscene
extends Node
## 새 게임 프롤로그 연출(새 그림 없이 3D 장면 안에서).
##   도입  검은 화면 → 밝아지며 익숙한 도시 거리·도로 소리(독백 1)
##   전환  소리가 뚝 끊기고 형광등이 깜빡 → 카메라가 유리문 쪽으로 다가가며 하얗게 번쩍 → 숲(독백 2)
##   마무리 독백 2가 끝나면 카메라가 제자리로 돌아온다
## `TutorialDirector`의 프롤로그 순서에서 부른다. 시간은 이미 멈춰 있고 플레이어 입력도 막혀 있다.
## Esc/E 를 누르면 지금 단계를 건너뛴다. 자동 검사(헤드리스)나 `--no-cutscene` 이면 아무것도 하지 않는다.

# 시간(초)과 카메라 값은 여기서 조정한다.
const FADE_IN := 2.2
const CITY_HOLD := 4.0           # 도시 소리와 지나가는 차를 보여 주는 시간(독백 시작 전)
const FLICKER := [0.0, 0.14, 0.30, 0.44, 0.62]  # 형광등이 꺼지는 순간들(초)
const FLICKER_ALPHA := 0.55
const PUSH_SECONDS := 2.6
const PUSH_ZOOM := 1.7
const PUSH_OFFSET := Vector2(-70.0, 40.0)   # 카메라가 다가갈 유리문 쪽(2D 화면 기준 픽셀)
const FLASH_UP := 0.9
const FLASH_DOWN := 1.8
const RETURN_SECONDS := 1.8

var enabled: bool = true
var active: bool = false

var view: Node
var camera2d: Camera2D
var city: OpeningCityBackdrop
var noise: OpeningRoadNoise

var _layer: CanvasLayer
var _black: ColorRect
var _dim: ColorRect
var _flash: ColorRect
var _hint: Label
var _base_zoom: float = 1.0
var _base_offset: Vector2 = Vector2.ZERO
var _skip: bool = false
var _world: Node
var _phase: String = ""


func setup(world: Node) -> void:
	# 3D 화면 노드는 이 노드보다 늦게 준비되므로 실제로 쓸 때(`_ensure`) 연결한다.
	_world = world

	if DisplayServer.get_name() == "headless" or OS.get_cmdline_user_args().has("--no-cutscene"):
		enabled = false


func _ensure() -> bool:
	if not enabled:
		return false

	if city != null:
		return true

	# 새 게임은 첫 프레임에 프롤로그가 시작되지만 3D 화면은 한 박자 늦게 만들어지므로 준비될 때까지 기다린다(최대 2초).
	var waited: int = 0

	while waited < 120:
		view = _world.get_node_or_null("StoreView3D") if _world != null else null

		if view != null and view.get("_ready_done") == true and view.get("camera2d") != null and view.get("floor_node") != null:
			break

		view = null
		await get_tree().process_frame
		waited += 1

	if view == null:
		enabled = false
		return false

	camera2d = view.camera2d
	_base_zoom = camera2d.zoom.x
	_base_offset = camera2d.offset
	city = OpeningCityBackdrop.new(view)
	noise = OpeningRoadNoise.new()
	add_child(noise)
	_layer = CanvasLayer.new()
	_layer.layer = 90
	add_child(_layer)
	_black = _rect(Color(0, 0, 0, 1.0))   # 준비되는 동안 화면이 번쩍 보이지 않게 처음부터 까맣게 시작한다
	_dim = _rect(Color(0, 0, 0, 0))
	_flash = _rect(Color(1.0, 0.98, 0.9, 0))
	_hint = Label.new()
	_hint.text = "E · Esc  건너뛰기"
	var label_settings := LabelSettings.new()
	label_settings.font_size = 18
	label_settings.font_color = Color(1, 1, 1, 0.9)
	label_settings.outline_size = 5
	label_settings.outline_color = Color(0, 0, 0, 0.85)
	_hint.label_settings = label_settings
	_hint.visible = false
	_layer.add_child(_hint)
	return true


func _rect(color: Color) -> ColorRect:
	var r := ColorRect.new()
	r.color = color
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(r)
	return r


func _process(delta: float) -> void:
	if city != null and city.built():
		city.tick(delta)

	if _hint != null:
		_hint.visible = active
		# 오른쪽 아래(메뉴 단추와 겹치지 않게 위쪽으로 조금)
		var size: Vector2 = get_viewport().get_visible_rect().size
		_hint.position = Vector2(size.x - _hint.size.x - 28.0, size.y - _hint.size.y - 150.0)


func _unhandled_input(event: InputEvent) -> void:
	if active and (event.is_action_pressed("ui_cancel") or event.is_action_pressed("interact")) and not event.is_echo():
		_skip = true
		get_viewport().set_input_as_handled()


# 매 프레임 `step(0~1)`을 불러 부드럽게 바꾼다. 건너뛰면 곧바로 1로 끝낸다.
func _tween(seconds: float, step: Callable, easing: bool = true) -> void:
	var t: float = 0.0

	while t < seconds and not _skip:
		await get_tree().process_frame
		t += get_process_delta_time()
		var f: float = clampf(t / seconds, 0.0, 1.0)
		step.call(ease(f, -2.0) if easing else f)

	step.call(1.0)


func _wait(seconds: float) -> void:
	var t: float = 0.0

	while t < seconds and not _skip:
		await get_tree().process_frame
		t += get_process_delta_time()


func _set_alpha(rect: ColorRect, a: float) -> void:
	var c: Color = rect.color
	rect.color = Color(c.r, c.g, c.b, clampf(a, 0.0, 1.0))


# ---------------------------------------------------------------- 단계

func play_intro() -> void:
	if not await _ensure():
		return

	active = true
	_skip = false
	_phase = "intro"
	city.build()
	_set_alpha(_black, 1.0)
	noise.play("city")
	await _wait(0.4)
	await _tween(FADE_IN, func(f: float) -> void: _set_alpha(_black, 1.0 - f))
	await _wait(CITY_HOLD)
	active = false
	_skip = false


func play_transition() -> void:
	if not await _ensure():
		return

	active = true
	_skip = false
	_phase = "transition"

	if not city.built():
		city.build()

	# 1) 도로 소리가 뚝 끊기고 형광등이 몇 번 깜빡인다
	noise.silence()
	await _wait(0.5)

	for t in FLICKER:
		_set_alpha(_dim, FLICKER_ALPHA)
		await _wait(0.07)
		_set_alpha(_dim, 0.0)
		await _wait(0.1)

		if _skip:
			break

	# 2) 카메라가 유리문 쪽으로 다가가며(기다리지 않고 동시에) 하얗게 번쩍
	_push_camera()
	await _wait(PUSH_SECONDS - FLASH_UP * 0.6)
	await _tween(FLASH_UP, func(f: float) -> void: _set_alpha(_flash, f))

	# 3) 하얀 화면 뒤에서 도시를 지우고 숲을 되돌린다
	city.show_forest()
	noise.play("wind")
	await _wait(0.2)
	await _tween(FLASH_DOWN, func(f: float) -> void: _set_alpha(_flash, 1.0 - f))
	active = false
	_skip = false


func _push_camera() -> void:
	var from_zoom: float = camera2d.zoom.x
	var from_offset: Vector2 = camera2d.offset
	var offset_to: Vector2 = _base_offset + PUSH_OFFSET
	await _tween(PUSH_SECONDS, func(f: float) -> void:
		var z: float = lerpf(from_zoom, PUSH_ZOOM, f)
		camera2d.zoom = Vector2(z, z)
		camera2d.offset = from_offset.lerp(offset_to, f))


# 독백 2가 끝난 뒤 카메라를 제자리로. 기다리지 않는다.
func play_outro() -> void:
	if not enabled or camera2d == null or city == null:
		return

	_phase = "outro"
	var from_zoom: float = camera2d.zoom.x
	var from_offset: Vector2 = camera2d.offset
	_skip = false
	await _tween(RETURN_SECONDS, func(f: float) -> void:
		var z: float = lerpf(from_zoom, _base_zoom, f)
		camera2d.zoom = Vector2(z, z)
		camera2d.offset = from_offset.lerp(_base_offset, f))
	noise.fade_out(2.5)
	_phase = ""


# 연출 도중 나가거나 장면이 바뀌어도 화면과 숲이 원래대로 남게 한다.
func restore() -> void:
	if not enabled or city == null:
		return

	_skip = true

	if city != null and city.built():
		city.show_forest()

	if camera2d != null:
		camera2d.zoom = Vector2(_base_zoom, _base_zoom)
		camera2d.offset = _base_offset

	for rect in [_black, _dim, _flash]:
		if rect != null:
			_set_alpha(rect, 0.0)

	if noise != null:
		noise.silence()

	active = false
