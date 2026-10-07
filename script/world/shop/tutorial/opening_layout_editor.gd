class_name OpeningLayoutEditor
extends Node
## 개발자 모드(F10): 프롤로그 가게 안 집기(연출용)를 직접 배치하고 저장한다. 저장하면 `data/shop/opening_store_layout.json`이 만들어지고,
## 게임은 이 배치를 그대로 쓴다(청소 더미·손님 동선·점원 자리는 배치에서 자동으로 정해진다).
##   마우스  왼쪽 누르기 = 집기 고르기, 끌기 = 옮기기, 빈 칸 누르기 = 선택 해제
##   R 돌리기 · , . 길이 줄이기/늘리기 · Tab 종류 바꾸기 · N 새로 놓기(마우스 칸) · C 복사해 놓기 · Delete 지우기
##   Z 되돌리기 · P 저장 · 마우스 휠 확대/축소 · F10 또는 Esc 나가기(저장하지 않은 배치는 버려진다)
## 화면이 있는 실행에서만 동작한다(헤드리스 자동 검사에서는 켜지지 않는다).

signal closed

# 바닥 바로 위·모든 집기 뒤에 고정해 깊이 정렬에 끼지 않는다(집기 순서를 흐트러뜨리지 않음)
const SLAB_RANK := -0.5
const KEY_CURSOR := "cut_sedit_cur"
const KEY_SELECT := "cut_sedit_sel"
const HISTORY_LIMIT := 40
const CURSOR_TINT := Color(1.0, 0.95, 0.4)
const SELECT_TINT := Color(0.3, 1.0, 0.9)

var active: bool = false
var world: Node
var cutscene: OpeningCutscene
var view: Node
var dressing: OpeningStoreDressing

var props: Array = []
var selected: int = -1
var kind_index: int = 0
var _history: Array = []
var _dragging: bool = false
var _drag_offset: Vector2i = Vector2i.ZERO
var _hover: Vector2i = Vector2i(-99, -99)
var _layer: CanvasLayer
var _label: Label
var _note: String = ""
var _froze_player: bool = false
var _saved_zoom: Vector2 = Vector2.ONE
var _saved_offset: Vector2 = Vector2.ZERO


func setup(world_node: Node, cutscene_node: OpeningCutscene) -> void:
	world = world_node
	cutscene = cutscene_node


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey

	if key == null or not key.pressed or key.echo:
		return

	if key.keycode == KEY_F10:
		get_viewport().set_input_as_handled()
		_toggle()
		return

	if not active:
		return

	get_viewport().set_input_as_handled()

	match key.keycode:
		KEY_ESCAPE:
			_close()
		KEY_R:
			_edit(func() -> void: _rotate())
		KEY_COMMA:
			_edit(func() -> void: _resize(-1))
		KEY_PERIOD:
			_edit(func() -> void: _resize(1))
		KEY_TAB:
			_edit(func() -> void: _next_kind())
		KEY_N:
			_edit(func() -> void: _add(false))
		KEY_C:
			_edit(func() -> void: _add(true))
		KEY_DELETE, KEY_BACKSPACE:
			_edit(func() -> void: _delete())
		KEY_Z:
			_undo()
		KEY_P:
			_save()


func _unhandled_input(event: InputEvent) -> void:
	if not active:
		return

	if event is InputEventMouseMotion:
		_hover = _mouse_cell()

		if _dragging and selected >= 0:
			var anchor: Vector2i = _clamped_anchor(_hover - _drag_offset, props[selected])

			if anchor != props[selected]["anchor"]:
				props[selected]["anchor"] = anchor
				_apply()

		_refresh_marks()
		return

	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed and (event as InputEventMouseButton).button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		var z: float = clampf(view.camera2d.zoom.x + (0.1 if (event as InputEventMouseButton).button_index == MOUSE_BUTTON_WHEEL_UP else -0.1), 0.4, 1.8)
		view.camera2d.zoom = Vector2(z, z)
		return

	if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		get_viewport().set_input_as_handled()

		if (event as InputEventMouseButton).pressed:
			_push_history()
			selected = _pick(_mouse_cell())
			_dragging = selected >= 0

			if selected >= 0:
				_drag_offset = _mouse_cell() - (props[selected]["anchor"] as Vector2i)
				kind_index = maxi(0, OpeningStoreLayout.KIND_ORDER.find(str(props[selected]["model"])))
		else:
			_dragging = false

		_refresh_marks()


# ---------------------------------------------------------------- 켜고 끄기

func _toggle() -> void:
	if active:
		_close()
	else:
		_open()


func _open() -> void:
	if cutscene == null or not cutscene.enabled:
		return  # 화면이 없는 실행(자동 검사)에서는 쓰지 않는다

	if not await cutscene._ensure():
		return

	view = cutscene.view
	dressing = cutscene.dressing
	props = _copy(OpeningStoreLayout.props())
	_history.clear()
	selected = -1
	active = true
	_note = "개발자 모드를 켰습니다."
	var player = world.get_node_or_null("Actors/Player")

	if player != null and player.is_physics_processing():
		player.set_physics_process(false)
		_froze_player = true

	# 가게 전체가 보이게 카메라를 가게 가운데로 옮기고 조금 멀리 본다(마우스 휠로 확대·축소)
	_saved_zoom = view.camera2d.zoom
	_saved_offset = view.camera2d.offset
	var center_world: Vector2 = view.cell_to_world(Vector2(4.5, 3.5))
	view.camera2d.zoom = Vector2(0.85, 0.85)
	view.camera2d.offset = center_world - (player.global_position if player != null else center_world)
	_ensure_ui()
	_layer.visible = true
	_apply()
	_refresh_marks()


func _close() -> void:
	active = false
	_dragging = false
	_layer.visible = false

	if view != null:
		view._remove_item(KEY_CURSOR)
		view._remove_item(KEY_SELECT)

	# 저장하지 않은 배치는 버리고 저장된 배치(또는 기본)로 돌아간다
	OpeningStoreLayout.reload()
	OpeningCleanup.reset()

	if dressing != null:
		dressing.clear_all()

	var player = world.get_node_or_null("Actors/Player")

	if view != null:
		view.camera2d.zoom = _saved_zoom
		view.camera2d.offset = _saved_offset

	if _froze_player and player != null:
		player.set_physics_process(true)

	_froze_player = false
	closed.emit()


# ---------------------------------------------------------------- 편집

func _copy(list: Array) -> Array:
	var out: Array = []

	for p in list:
		out.append((p as Dictionary).duplicate(true))

	return out


func _push_history() -> void:
	_history.append(_copy(props))

	if _history.size() > HISTORY_LIMIT:
		_history.pop_front()


func _edit(change: Callable) -> void:
	_push_history()
	change.call()
	_apply()
	_refresh_marks()


func _undo() -> void:
	if _history.is_empty():
		_note = "되돌릴 것이 없습니다."
		return

	props = _history.pop_back()
	selected = mini(selected, props.size() - 1)
	_apply()
	_refresh_marks()


# 작업 중인 배치를 3D 화면에 다시 그린다.
func _apply() -> void:
	OpeningStoreLayout.set_props(props)
	dressing.rebuild()


func _mouse_cell() -> Vector2i:
	var world_pos: Vector2 = get_viewport().get_canvas_transform().affine_inverse() * get_viewport().get_mouse_position()
	var c: Vector2 = view.world_to_cell(world_pos)
	return Vector2i(roundi(c.x), roundi(c.y))


func _pick(cell: Vector2i) -> int:
	for i in range(props.size() - 1, -1, -1):
		if OpeningStoreLayout.cells_of(props[i]).has_point(cell):
			return i

	return -1


func _clamped_anchor(anchor: Vector2i, prop: Dictionary) -> Vector2i:
	var size: Vector2i = prop["size"]
	var store: Rect2i = OpeningStoreLayout.STORE_CELLS
	return Vector2i(clampi(anchor.x, store.position.x, store.end.x - size.x), clampi(anchor.y, store.position.y, store.end.y - size.y))


func _rotate() -> void:
	if selected < 0:
		return

	var prop: Dictionary = props[selected]
	var size: Vector2i = prop["size"]
	prop["rot"] = posmod(int(prop["rot"]) + 1, 4)
	prop["size"] = Vector2i(size.y, size.x)
	prop["anchor"] = _clamped_anchor(prop["anchor"], prop)


func _resize(delta: int) -> void:
	if selected < 0:
		return

	var prop: Dictionary = props[selected]
	var size: Vector2i = prop["size"]
	var along_x: bool = posmod(int(prop["rot"]), 2) == 0
	var length: int = clampi((size.x if along_x else size.y) + delta, 1, 6)
	prop["size"] = Vector2i(length, size.y) if along_x else Vector2i(size.x, length)
	prop["anchor"] = _clamped_anchor(prop["anchor"], prop)


func _next_kind() -> void:
	kind_index = (kind_index + 1) % OpeningStoreLayout.KIND_ORDER.size()

	if selected < 0:
		return

	var old: Dictionary = props[selected]
	var made: Dictionary = OpeningStoreLayout.make(OpeningStoreLayout.KIND_ORDER[kind_index], old["anchor"], int(old["rot"]))
	made["anchor"] = _clamped_anchor(made["anchor"], made)
	props[selected] = made


func _add(copy_selected: bool) -> void:
	var cell: Vector2i = _hover if _hover.x > -50 else Vector2i(4, 4)
	var made: Dictionary

	if copy_selected and selected >= 0:
		made = (props[selected] as Dictionary).duplicate(true)
	else:
		made = OpeningStoreLayout.make(OpeningStoreLayout.KIND_ORDER[kind_index], cell, 0)

	made["anchor"] = _clamped_anchor(cell, made)
	props.append(made)
	selected = props.size() - 1


func _delete() -> void:
	if selected < 0:
		return

	props.remove_at(selected)
	selected = -1


func _save() -> void:
	OpeningStoreLayout.set_props(props)
	var error: String = OpeningStoreLayout.save()
	OpeningCleanup.reset()
	_note = ("저장했습니다: %s" % OpeningStoreLayout.PATH) if error.is_empty() else ("저장 실패: " + error)
	_refresh_marks()


# ---------------------------------------------------------------- 표시

func _ensure_ui() -> void:
	if _layer != null:
		return

	_layer = CanvasLayer.new()
	_layer.layer = 70
	add_child(_layer)
	_label = Label.new()
	_label.position = Vector2(16, 90)
	var settings := LabelSettings.new()
	settings.font_size = 16
	settings.font_color = Color(1, 1, 1)
	settings.outline_size = 5
	settings.outline_color = Color(0, 0, 0, 0.9)
	_label.label_settings = settings
	_layer.add_child(_label)


func _refresh_marks() -> void:
	if view == null:
		return

	# 마우스 칸 표시와 고른 집기 바닥 표시(얇은 판 하나씩)
	if _hover.x > -50:
		view._set_item(KEY_CURSOR, Vector2(_hover) - Vector2(0.5, 0.5), Vector2(_hover) + Vector2(0.5, 0.5), 0.03, "tile", CURSOR_TINT, "")
		view._items[KEY_CURSOR]["fixed_rank"] = SLAB_RANK
	else:
		view._remove_item(KEY_CURSOR)

	if selected >= 0 and selected < props.size():
		var rect: Rect2 = OpeningStoreLayout.rect_of(props[selected])
		var cells: Rect2i = OpeningStoreLayout.cells_of(props[selected])
		view._set_item(KEY_SELECT, Vector2(cells.position) - Vector2(0.5, 0.5), Vector2(cells.end) - Vector2(0.5, 0.5), 0.02, "tile", SELECT_TINT, "")
		view._items[KEY_SELECT]["fixed_rank"] = SLAB_RANK
		rect = rect
	else:
		view._remove_item(KEY_SELECT)

	var lines: Array[String] = [
		"[개발자 모드] 프롤로그 가게 배치   집기 %d개" % props.size(),
		"마우스: 누르기=고르기 / 끌기=옮기기    R 돌리기   , . 길이   Tab 종류 바꾸기",
		"N 새로 놓기(마우스 칸)   C 복사해 놓기   Delete 지우기   Z 되돌리기   P 저장   휠 확대/축소   F10/Esc 나가기",
		"새로 놓을 종류: %s" % OpeningStoreLayout.KINDS[OpeningStoreLayout.KIND_ORDER[kind_index]]["name"],
	]

	if selected >= 0 and selected < props.size():
		var p: Dictionary = props[selected]
		lines.append("고른 집기: %s  칸 (%d,%d)  크기 %d×%d  방향 %d" % [OpeningStoreLayout.KINDS[str(p["model"])]["name"], p["anchor"].x, p["anchor"].y, p["size"].x, p["size"].y, p["rot"]])
	else:
		lines.append("고른 집기 없음")

	if not _note.is_empty():
		lines.append(_note)

	_label.text = "\n".join(lines)
