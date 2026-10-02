@tool
class_name IsoObject
extends Node2D
## 여러 IsoBox 부품을 조합한 오브젝트(ㄱ자 가로등, 집 = 몸통 + 굴뚝 + 처마 등).
## 도형은 충돌·정렬 전용이고, 곡선·장식은 그림 한 장(`art`)으로 위에 씌운다.
##
## 사용법: 자식으로 IsoBox 를 넣고 `cell_offset`, `footprint_size`, `height`, `elevation`, `blocking`만 정한다.
## 회전·전체 크기·표시 여부는 이 노드가 모든 부품에 한꺼번에 전달한다.
## 부품 그리는 순서 = 자식 순서. 뒤쪽(작은 x+y)부터 넣는다.

# 오브젝트 전체 발자국(칸). 회전 계산의 기준.
@export var object_size: Vector2 = Vector2.ONE:
	set(value):
		object_size = Vector2(maxf(value.x, 0.1), maxf(value.y, 0.1))
		_apply()

@export var rotation_index: int = 0:
	set(value):
		rotation_index = posmod(value, 4)
		_apply()

# 그림 한 장(정면이 아니라 완성된 모습 전체). 없으면 도형을 그대로 그린다.
@export var art: Texture2D:
	set(value):
		art = value
		_apply()

# 그림 안에서 "바닥 발자국의 아래(S) 꼭짓점"이 오는 픽셀 위치.
@export var art_anchor: Vector2 = Vector2.ZERO:
	set(value):
		art_anchor = value
		queue_redraw()

@export var art_scale: float = 1.0:
	set(value):
		art_scale = value
		queue_redraw()

# 그림이 있어도 도형을 보이게 한다(맞추는 동안 확인용).
@export var show_shapes: bool = false:
	set(value):
		show_shapes = value
		_apply()

@export var show_outline: bool = false:
	set(value):
		show_outline = value
		_apply()


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_apply()


func set_rotation_index(value: int) -> void:
	rotation_index = value


func get_parts() -> Array[IsoBox]:
	var result: Array[IsoBox] = []

	for child in get_children():
		if child is IsoBox:
			result.append(child)

	return result


# 막는 부품의 바닥 발자국 목록(충돌 영역과 동일).
func get_blocking_polygons() -> Array[PackedVector2Array]:
	var result: Array[PackedVector2Array] = []

	for part in get_parts():
		if part.blocking:
			result.append(part.get_ground_polygon())

	return result


# 회전을 반영한 오브젝트 전체 바닥 마름모.
func get_ground_polygon() -> PackedVector2Array:
	return IsoGeometry.rect_ground(
		Vector2.ZERO,
		IsoGeometry.rotated_object_size(object_size, rotation_index)
	)


func _apply() -> void:
	if not is_inside_tree():
		return

	for part in get_parts():
		part.object_size = object_size
		part.rotation_index = rotation_index
		part.shape_visible = art == null or show_shapes
		part.show_outline = show_outline

	queue_redraw()


func _draw() -> void:
	if art == null:
		return

	var anchor_point := get_ground_polygon()[IsoGeometry.S]
	draw_texture_rect(
		art,
		Rect2(anchor_point - art_anchor * art_scale, art.get_size() * art_scale),
		false
	)
