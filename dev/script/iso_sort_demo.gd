extends Node2D
## IsoSortGroup 눈으로 확인하는 데모. 방향키로 파란 상자(캐릭터 대신)를 움직여 벽·기둥 앞뒤로 지나가 본다.
##   T 키: "상자 정렬(IsoSortGroup)" ↔ "발끝 y값 정렬(기존 y_sort)" 전환해서 차이를 비교한다.
##   Space: 파란 상자를 시작 위치로 되돌림.
## 실행: Godot 에서 이 장면(dev/scenes/iso_sort_demo.tscn)을 열고 F6.

const SPEED: float = 260.0

var group: IsoSortGroup
var actor: IsoBox
var label: Label
var box_sorting: bool = true


func _ready() -> void:
	position = Vector2(576, 150)
	group = IsoSortGroup.new()
	add_child(group)

	_add_box(Vector2(0, 0), Vector2(7, 1), 110.0, Color(0.62, 0.62, 0.72), "긴 벽")
	_add_box(Vector2(2, 3), Vector2(1, 1), 90.0, Color(0.55, 0.78, 0.55), "기둥")
	_add_box(Vector2(4, 3), Vector2(2, 1), 40.0, Color(0.85, 0.6, 0.65), "낮은 판")

	actor = IsoBox.new()
	actor.object_size = Vector2.ONE
	actor.cell_offset = Vector2(0.3, 0.3)
	actor.footprint_size = Vector2(0.4, 0.4)
	actor.height = 56.0
	actor.blocking = false
	actor.top_color = Color(0.4, 0.6, 1.0)
	actor.left_color = Color(0.3, 0.5, 0.9)
	actor.right_color = Color(0.25, 0.42, 0.78)
	actor.position = _iso(2.5, 1.8)
	group.add_child(actor)

	var layer := CanvasLayer.new()
	add_child(layer)
	label = Label.new()
	label.position = Vector2(16, 12)
	label.add_theme_font_size_override("font_size", 20)
	layer.add_child(label)
	_apply_mode()


func _add_box(cell: Vector2, size: Vector2, height: float, color: Color, _name: String) -> void:
	var box := IsoBox.new()
	box.footprint_size = size
	box.height = height
	box.top_color = color
	box.left_color = color.darkened(0.2)
	box.right_color = color.darkened(0.35)
	box.position = _iso(cell.x, cell.y)
	group.add_child(box)


func _iso(x: float, y: float) -> Vector2:
	return Vector2((x - y) * 48.0, (x + y) * 24.0)


func _process(delta: float) -> void:
	var move := Vector2(
		Input.get_axis("ui_left", "ui_right"),
		Input.get_axis("ui_up", "ui_down")
	)

	if move != Vector2.ZERO:
		actor.position += move.normalized() * SPEED * delta

	if Input.is_action_just_pressed("ui_select"):
		actor.position = _iso(2.5, 1.8)


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_T:
		box_sorting = not box_sorting
		_apply_mode()


func _apply_mode() -> void:
	group.auto_refresh = box_sorting
	group.y_sort_enabled = not box_sorting
	label.text = "방향키: 파란 상자 이동 / T: 정렬 방식 전환 / Space: 되돌리기\n지금: %s" % ("상자 정렬 (IsoSortGroup)" if box_sorting else "발끝 y값 정렬 (기존 방식)")
