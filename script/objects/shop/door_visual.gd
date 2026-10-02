@tool
extends Node2D

static var ART: Texture2D = ArtLoader.load_texture("res://art/world/shop_entrance_door_front.png")
static var WAREHOUSE: Texture2D = ArtLoader.load_texture("res://art/world/cozy_v6/warehouse_door.png")
static var PRODUCTION: Texture2D = ArtLoader.load_texture("res://art/world/cozy_v8/production_door.png")
@export_enum("entrance", "warehouse", "production") var door_kind: String = "entrance"

func get_door_texture() -> Texture2D:
	if door_kind == "warehouse": return WAREHOUSE
	if door_kind == "production": return PRODUCTION
	return ART

@export var tile_width: float = 96.0
@export var tile_height: float = 48.0

# true  = 그림이 "정면"이고 기울기·크기는 코드가 계산한다(권장).
#         문은 마름모 한 변(가로 tile_width/2, 세로 tile_height/2 = 2:1)에 서는 평행사변형으로 그려진다.
# false = 그림에 이미 기울기가 들어 있다(옛 방식, art_scale로 크기만 조절).
@export var art_is_frontal: bool = true

# 정면 그림용: 문이 벽면에서 차지하는 가로(타일 변보다 약간 넓게)와 세로(안쪽 벽 높이 120에 맞춤).
@export var door_width: float = 52.0
@export var door_height: float = 110.0

# 옛 방식(art_is_frontal = false)용 배율. 1.0 = 그림 원본 크기.
@export var art_scale: float = 1.2

# 확인용: 켜면 문이 서는 평행사변형 테두리를 빨간 선으로 그린다(코드가 적용됐는지 확인할 때).
@export var show_outline: bool = false

# 바닥 중앙 기준 위치 보정(픽셀). 양수 x = 오른쪽, 양수 y = 아래.
@export var art_offset: Vector2 = Vector2.ZERO

var rotation_index: int = 0


func set_footprint(_size_x: int, _size_y: int):
	queue_redraw()


func set_rotation_index(value: int):
	rotation_index = value % 4
	queue_redraw()


# 옛 방식: 그림 원본 크기 x art_scale 직사각형, 바닥 중앙 고정.
func get_art_rect() -> Rect2:
	var texture := get_door_texture()
	var size := Vector2(tile_width * 0.5 + 4.0, 99.0)

	if texture != null:
		size = texture.get_size()

	size *= art_scale

	return Rect2(
		Vector2(-size.x * 0.5, tile_height * 0.25 - size.y) + art_offset,
		size
	)


# 정면 그림: 문이 서는 벽면의 네 꼭짓점(왼쪽 위, 오른쪽 위, 오른쪽 아래, 왼쪽 아래).
# 짝수 회전은 `\`(오른쪽이 낮음), 홀수 회전은 `/`(왼쪽이 낮음)로 기울고 그림은 뒤집지 않는다.
func get_wall_quad() -> PackedVector2Array:
	var quad := IsoGeometry.edge_plane(
		door_width,
		door_height,
		tile_height * 0.25,
		rotation_index % 2 == 0
	)

	for i in quad.size():
		quad[i] += art_offset

	return quad


func _draw():
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var texture := get_door_texture()
	if texture == null:
		return

	if art_is_frontal:
		if show_outline:
			var quad := get_wall_quad()
			draw_polyline(PackedVector2Array([quad[0], quad[1], quad[2], quad[3], quad[0]]), Color.RED, 2.0)

		draw_polygon(
			get_wall_quad(),
			PackedColorArray([Color.WHITE]),
			PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]),
			texture
		)
		return

	var rect := get_art_rect()
	var left_u: float = 0.0 if rotation_index % 2 == 0 else 1.0
	var right_u: float = 1.0 - left_u
	draw_polygon(PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y),
		rect.end, Vector2(rect.position.x, rect.end.y)]), PackedColorArray([Color.WHITE]),
		PackedVector2Array([Vector2(left_u, 0), Vector2(right_u, 0), Vector2(right_u, 1), Vector2(left_u, 1)]), texture)
