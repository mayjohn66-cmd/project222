class_name OpeningCutscene
extends Node
## 새 게임 프롤로그 연출(새 그림 없이 3D 장면 안에서).
##   도입  검은 화면 → 밝아지면 현대 편의점 안(진열대·냉장고)과 도시 거리. 손님이 들어와 계산하고 나간다(독백 1 전)
##   독백 1  멍하니 바깥을 보다 졸음이 밀려온다 → 눈꺼풀이 감기고 소리가 멀어지다 뚝 끊긴다(검은 화면에서 마지막 줄)
##   깨어남  쿵 하는 소리와 함께 하얗게 번쩍 → 숲, 진열대는 모두 부서지고 하나만 남아 있다(독백 2)
##   마무리  독백 4가 끝나면 부서진 잔해를 치운다
## `TutorialDirector`의 프롤로그 순서에서 부른다. 시간은 이미 멈춰 있고 플레이어 입력도 막혀 있다.
## 도입에서 E/Esc 를 누르면 손님 장면을 건너뛴다. 자동 검사(헤드리스)나 `--no-cutscene` 이면 아무것도 하지 않는다.

# 시간(초)과 값은 여기서 조정한다.
const FADE_IN := 2.0
const BEFORE_VISITOR := 0.5        # 밝아진 뒤 손님이 들어오기까지
const AFTER_VISITOR := 0.6
const FLASH_UP := 0.35
const FLASH_DOWN := 2.0
const CRASH_LEAD := 0.45           # 쿵 소리가 나고 번쩍하기까지
const SHAKE_SECONDS := 0.9
const SHAKE_PIXELS := 14.0
const NOD_PIXELS := 22.0           # 졸 때 고개가 숙여지는 만큼 카메라가 내려간다
const BLACKOUT_HOLD := 1.2
const WALK_SPEED := 2.4            # 주인공 걸음(칸/초)
const VISITOR_SPEED := 2.8
const LAYER := 20                  # 대사창(30) 아래: 검은 화면 위에서도 대사가 보인다

# 졸음: [눈꺼풀이 닫힌 정도(0~1), 걸리는 시간(초), 도로 소리 크기(0~1)] 를 차례로. 마지막에 완전히 감긴다.
const DOZE_STEPS := [[0.55, 0.9, 0.8], [0.12, 0.5, 0.7], [0.8, 1.1, 0.5], [0.3, 0.45, 0.45], [1.0, 1.5, 0.15]]

# 독백 중간의 움직임: 장면 id → {방금 읽은 줄 번호: 동작}. 걷는 곳 이름은 SPOTS, "doze" 는 졸기.
const BEATS := {
	"prologue_last_shift": {0: "door", 1: "doze"},
	"prologue_unfamiliar_window": {0: "shelf", 1: "counter"},
	"prologue_food_dates": {0: "counter"},
	"prologue_keep_the_light": {0: "center"},
}
# 가게 안 칸 좌표(문 (0,4), 계산대 (4,3), 남은 진열대 (2,2)). 소수 좌표는 칸 사이.
const SPOTS := {
	"behind": Vector2(4.6, 2.1),     # 계산대 안쪽(점원 자리)
	"door": Vector2(1.3, 4.0),
	"counter": Vector2(4.0, 4.9),
	"shelf": Vector2(2.0, 3.5),
	"center": Vector2(4.5, 5.3),
}
# 걸어갈 때 거치는 점(계산대 모서리를 돌아가도록). 없으면 곧장 간다.
const ROUTES := {
	"door": [Vector2(3.1, 2.1), Vector2(3.0, 4.0)],
}
# 연출용 손님: 문으로 들어와 진열대를 둘러보고 계산한 뒤 나간다. {to: 칸, wait: 멈추는 초, beep: 삑}
const VISITOR_START := Vector2(-3.0, 5.4)
const VISITOR_ROUTE := [
	{"to": Vector2(-0.4, 4.0)},
	{"to": Vector2(1.1, 4.0)},
	{"to": Vector2(4.8, 5.4), "wait": 1.0},
	{"to": Vector2(4.4, 4.3), "wait": 1.7, "beep": true},
	{"to": Vector2(1.1, 4.0)},
	{"to": Vector2(-0.4, 4.0)},
	{"to": Vector2(-3.2, 2.4)},
]

var enabled: bool = true
var active: bool = false

var view: Node
var camera2d: Camera2D
var city: OpeningCityBackdrop
var dressing: OpeningStoreDressing
var noise: OpeningRoadNoise

var _layer: CanvasLayer
var _black: ColorRect
var _lid_top: ColorRect
var _lid_bottom: ColorRect
var _flash: ColorRect
var _hint: Label
var _base_zoom: float = 1.0
var _base_offset: Vector2 = Vector2.ZERO
var _skip: bool = false
var _world: Node
var _phase: String = ""
var _visitor: Node2D
var _shaking: bool = false


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
	dressing = OpeningStoreDressing.new(view)
	noise = OpeningRoadNoise.new()
	add_child(noise)
	_layer = CanvasLayer.new()
	_layer.layer = LAYER
	add_child(_layer)
	_black = _rect(Color(0, 0, 0, 1.0))   # 준비되는 동안 화면이 번쩍 보이지 않게 처음부터 까맣게 시작한다
	_lid_top = _rect(Color(0, 0, 0, 1.0))
	_lid_bottom = _rect(Color(0, 0, 0, 1.0))
	_set_lids(0.0)
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


# 눈꺼풀: 위아래에서 검은 막이 내려와 closure(0~1)만큼 화면을 덮는다. 고개가 숙여지듯 카메라도 조금 내려간다.
func _set_lids(closure: float) -> void:
	var half: float = get_viewport().get_visible_rect().size.y * 0.5 * clampf(closure, 0.0, 1.0)
	_lid_top.anchor_bottom = 0.0
	_lid_top.offset_top = 0.0
	_lid_top.offset_bottom = half
	_lid_bottom.anchor_top = 1.0
	_lid_bottom.anchor_bottom = 1.0
	_lid_bottom.offset_top = -half
	_lid_bottom.offset_bottom = 0.0

	if camera2d != null and not _shaking:
		camera2d.offset = _base_offset + Vector2(0.0, NOD_PIXELS * closure)


# ---------------------------------------------------------------- 단계

func play_intro() -> void:
	if not await _ensure():
		return

	active = true
	_skip = false
	_phase = "intro"
	city.build()
	dressing.build_modern()
	_place_player(SPOTS["behind"])
	_set_alpha(_black, 1.0)
	noise.play("city")
	await _wait(0.4)
	await _tween(FADE_IN, func(f: float) -> void: _set_alpha(_black, 1.0 - f))
	await _wait(BEFORE_VISITOR)
	await _visitor_scene()
	await _wait(AFTER_VISITOR)
	active = false
	_skip = false


# 손님이 들어와 둘러보고 계산한 뒤 나간다.
func _visitor_scene() -> void:
	var actors: Node = _world.get_node_or_null("Actors") if _world != null else null

	if actors == null or view == null:
		return

	_visitor = Node2D.new()
	_visitor.name = "CutsceneVisitor"
	_visitor.add_to_group("cutscene_actor")
	_visitor.set_meta("look_key", "backpacker")
	actors.add_child(_visitor)
	_visitor.global_position = view.cell_to_world(VISITOR_START)

	for step in VISITOR_ROUTE:
		if _skip:
			break

		await _move_node(_visitor, step["to"], VISITOR_SPEED)

		if step.get("beep", false):
			noise.beep()

		await _wait(float(step.get("wait", 0.0)))

	_free_visitor()


func _free_visitor() -> void:
	if is_instance_valid(_visitor):
		_visitor.queue_free()

	_visitor = null


# 졸음 → 소리가 멀어지다 뚝 끊기고 화면이 까매진다(독백 1 의 마지막 줄은 이 검은 화면 위에서 나온다).
func _doze() -> void:
	var closure: float = 0.0

	for step in DOZE_STEPS:
		var from: float = closure
		var to: float = float(step[0])
		noise.set_level(float(step[2]), float(step[1]))
		await _tween(float(step[1]), func(f: float) -> void: _set_lids(lerpf(from, to, f)))
		closure = to

	noise.silence()
	_set_alpha(_black, 1.0)
	_set_lids(0.0)
	await _wait(BLACKOUT_HOLD)


# 독백 2 앞: 쿵 하는 소리 → 하얗게 번쩍 → 도시가 사라지고 숲, 가게 안은 부서진 진열대(깨어남).
func play_transition() -> void:
	if not await _ensure():
		return

	active = true
	_skip = false
	_phase = "wake"

	if not city.built():
		city.build()

	_set_alpha(_black, 1.0)
	noise.silence()
	noise.crash()
	await _wait(CRASH_LEAD)
	await _tween(FLASH_UP, func(f: float) -> void: _set_alpha(_flash, f), false)
	# 하얀 화면 뒤에서 도시를 지우고 숲과 부서진 가게를 보이게 한다
	_set_alpha(_black, 0.0)
	city.show_forest()
	dressing.smash()
	noise.play("wind")
	_shake()
	await _wait(0.2)
	await _tween(FLASH_DOWN, func(f: float) -> void: _set_alpha(_flash, 1.0 - f))
	active = false
	_skip = false


# 깨어날 때 화면이 한 번 크게 흔들린다(기다리지 않는다).
func _shake() -> void:
	if camera2d == null or _shaking:
		return

	_shaking = true
	var t: float = 0.0

	while t < SHAKE_SECONDS:
		await get_tree().process_frame
		t += get_process_delta_time()
		var power: float = SHAKE_PIXELS * (1.0 - t / SHAKE_SECONDS)
		camera2d.offset = _base_offset + Vector2(randf_range(-power, power), randf_range(-power, power))

	camera2d.offset = _base_offset
	_shaking = false


# ---------------------------------------------------------------- 독백 사이

# 대사 한 줄을 읽은 뒤(다음 줄 전에) 정해진 동작을 한다. 걷는 동안 대사창은 숨겨져 있다.
func beat(moment_id: String, read_index: int) -> void:
	if not enabled:
		return

	var action: String = str((BEATS.get(moment_id, {}) as Dictionary).get(read_index, ""))

	if action.is_empty() or not await _ensure():
		return

	if action == "doze":
		await _doze()
		return

	var route: Array = (ROUTES.get(action, []) as Array).duplicate()
	route.append(SPOTS[action])
	var player: Node2D = _world.get_node_or_null("Actors/Player") if _world != null else null

	if player == null or view == null:
		return

	for point in route:
		await _move_node(player, point, WALK_SPEED)

	await get_tree().process_frame
	await get_tree().process_frame


# 노드를 칸 좌표 cell 까지 일정한 속도로 옮긴다. 3D 인물은 2D 위치가 바뀌면 걷는 동작과 방향을 스스로 만든다.
func _move_node(node: Node2D, cell: Vector2, speed: float) -> void:
	if not is_instance_valid(node) or view == null:
		return

	var from: Vector2 = node.global_position
	var to: Vector2 = view.cell_to_world(cell)
	var seconds: float = maxf(0.05, view.world_to_cell(from).distance_to(cell) / speed)
	var t: float = 0.0

	while t < seconds and not _skip:
		await get_tree().process_frame

		if not is_instance_valid(node):
			return

		t += get_process_delta_time()
		node.global_position = from.lerp(to, clampf(t / seconds, 0.0, 1.0))

	if is_instance_valid(node):
		node.global_position = to


func _place_player(cell: Vector2) -> void:
	var player: Node2D = _world.get_node_or_null("Actors/Player") if _world != null else null

	if player != null and view != null:
		player.global_position = view.cell_to_world(cell)


# 독백 2가 끝난 뒤 바람 소리를 서서히 줄인다.
func play_outro() -> void:
	if not enabled or noise == null:
		return

	_phase = "outro"
	noise.fade_out(2.5)
	_phase = ""


# 독백 4가 끝나면(가게부터 정리하기로 했으므로) 부서진 잔해를 몇 개씩 치운다. 기다리지 않는다.
func play_cleanup() -> void:
	if not enabled or dressing == null:
		return

	while dressing.clear_debris_step(6) > 0:
		await get_tree().create_timer(0.12).timeout


# 연출 도중 나가거나 장면이 바뀌어도 화면과 숲이 원래대로 남게 한다.
func restore() -> void:
	if not enabled or city == null:
		return

	_skip = true
	_free_visitor()

	if city.built():
		city.show_forest()

	if dressing != null:
		dressing.clear_all()

	if camera2d != null:
		camera2d.zoom = Vector2(_base_zoom, _base_zoom)
		camera2d.offset = _base_offset

	for rect in [_black, _flash]:
		if rect != null:
			_set_alpha(rect, 0.0)

	if _lid_top != null:
		_set_lids(0.0)

	if noise != null:
		noise.silence()

	active = false
