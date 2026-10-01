@tool
extends Node2D

static var ART: Texture2D = ArtLoader.load_texture("res://art/world/cozy_v1/door.png")
static var WAREHOUSE: Texture2D = ArtLoader.load_texture("res://art/world/cozy_v6/warehouse_door.png")
static var PRODUCTION: Texture2D = ArtLoader.load_texture("res://art/world/cozy_v8/production_door.png")
@export_enum("entrance", "warehouse", "production") var door_kind: String = "entrance"

func get_door_texture() -> Texture2D:
	if door_kind == "warehouse": return WAREHOUSE
	if door_kind == "production": return PRODUCTION
	return ART

@export var tile_width: float = 96.0
@export var tile_height: float = 48.0
# 그림 비율(기울기)은 그대로 두고 크기만 키운다. 1.0 = 그림 원본 크기(52x99).
@export var art_scale: float = 1.2
# 바닥 중앙 기준 위치 보정(픽셀). 양수 x = 오른쪽, 양수 y = 아래.
@export var art_offset: Vector2 = Vector2.ZERO

var rotation_index: int = 0


func set_footprint(_size_x: int, _size_y: int):
	queue_redraw()


func set_rotation_index(value: int):
	rotation_index = value % 4
	queue_redraw()


func get_art_rect() -> Rect2:
	var texture := get_door_texture()
	var size := Vector2(tile_width * 0.5 + 4.0, 99.0)

	if texture != null:
		size = texture.get_size()

	size *= art_scale

	# 바닥 중앙을 고정하고 위로 키운다.
	return Rect2(
		Vector2(-size.x * 0.5, tile_height * 0.25 - size.y) + art_offset,
		size
	)

func _draw():
	var texture := get_door_texture()
	if texture == null:
		return

	var rect := get_art_rect()
	var left_u: float = 0.0 if rotation_index % 2 == 0 else 1.0
	var right_u: float = 1.0 - left_u
	draw_polygon(PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y),
		rect.end, Vector2(rect.position.x, rect.end.y)]), PackedColorArray([Color.WHITE]),
		PackedVector2Array([Vector2(left_u, 0), Vector2(right_u, 0), Vector2(right_u, 1), Vector2(left_u, 1)]), texture)
