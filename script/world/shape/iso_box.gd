@tool
class_name IsoBox
extends StaticBody2D
## 발자국(칸 수)과 높이만 정하면 윗면·왼쪽 면·오른쪽 면과 충돌 영역이 한 번에 만들어지는 입체 상자.
## 그림은 면마다 씌운다(없으면 단색). 충돌 영역은 그림과 상관없이 발자국에서만 나온다.

@export var footprint_size: Vector2i = Vector2i.ONE:
	set(value):
		footprint_size = Vector2i(maxi(value.x, 1), maxi(value.y, 1))
		_refresh()

# 바닥에서 윗면까지의 화면 높이(픽셀).
@export var height: float = 48.0:
	set(value):
		height = maxf(value, 0.0)
		_refresh()

# 1.0 = 칸 전체. 0.5 = 한쪽 가장자리의 절반 두께(얇은 가구).
@export_range(0.1, 1.0, 0.05) var depth_ratio: float = 1.0:
	set(value):
		depth_ratio = value
		_refresh()

@export var rotation_index: int = 0:
	set(value):
		rotation_index = posmod(value, 4)
		_refresh()

@export var top_texture: Texture2D:
	set(value):
		top_texture = value
		queue_redraw()
@export var left_texture: Texture2D:
	set(value):
		left_texture = value
		queue_redraw()
@export var right_texture: Texture2D:
	set(value):
		right_texture = value
		queue_redraw()

# false = 그림을 면 크기에 맞춰 늘림, true = 그림을 이어 붙여 반복(벽돌·판자 같은 타일 그림용).
@export var repeat_side_textures: bool = false:
	set(value):
		repeat_side_textures = value
		texture_repeat = (
			CanvasItem.TEXTURE_REPEAT_ENABLED if value
			else CanvasItem.TEXTURE_REPEAT_DISABLED
		)
		queue_redraw()

@export var top_color: Color = Color(0.80, 0.66, 0.46):
	set(value):
		top_color = value
		queue_redraw()
@export var left_color: Color = Color(0.62, 0.48, 0.32):
	set(value):
		left_color = value
		queue_redraw()
@export var right_color: Color = Color(0.50, 0.38, 0.26):
	set(value):
		right_color = value
		queue_redraw()

# 충돌 영역을 자동으로 만든다. blocking 이 false 이면 지나갈 수 있다.
@export var blocking: bool = true:
	set(value):
		blocking = value
		_refresh()

@export var show_outline: bool = false:
	set(value):
		show_outline = value
		queue_redraw()

var _collision: CollisionPolygon2D = null


func _ready() -> void:
	collision_layer = 1
	collision_mask = 0
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_refresh()


func set_footprint(size_x: int, size_y: int) -> void:
	footprint_size = Vector2i(size_x, size_y)


func set_rotation_index(value: int) -> void:
	rotation_index = value


# 바닥 발자국 = 충돌 영역(월드 이동이 막히는 곳).
func get_ground_polygon() -> PackedVector2Array:
	return IsoGeometry.ground(footprint_size, rotation_index, depth_ratio)


func get_collision_polygon() -> PackedVector2Array:
	if _collision == null:
		return PackedVector2Array()

	return _collision.polygon


func _refresh() -> void:
	if not is_inside_tree():
		return

	_update_collision()
	queue_redraw()


func _update_collision() -> void:
	if _collision == null or not is_instance_valid(_collision):
		_collision = get_node_or_null("Collision") as CollisionPolygon2D

		if _collision == null:
			_collision = CollisionPolygon2D.new()
			_collision.name = "Collision"
			add_child(_collision)

	_collision.polygon = get_ground_polygon()
	_collision.disabled = not blocking


func _draw() -> void:
	var corners := get_ground_polygon()
	_draw_face(IsoGeometry.left_face(corners, height), left_texture, left_color, true)
	_draw_face(IsoGeometry.right_face(corners, height), right_texture, right_color, true)
	_draw_top(IsoGeometry.top_face(corners, height))

	if show_outline:
		var outline := PackedVector2Array(corners)
		outline.append(corners[0])
		draw_polyline(outline, Color.RED, 2.0)


func _draw_face(quad: PackedVector2Array, texture: Texture2D, color: Color, side: bool) -> void:
	if texture == null:
		draw_colored_polygon(quad, color)
		_draw_edge(quad)
		return

	var uv := PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])

	if repeat_side_textures and side:
		var tex_size := texture.get_size()
		var u: float = IsoGeometry.screen_width(quad) / tex_size.x
		var v: float = IsoGeometry.screen_height(quad) / tex_size.y
		uv = PackedVector2Array([Vector2(0, 0), Vector2(u, 0), Vector2(u, v), Vector2(0, v)])

	draw_polygon(quad, PackedColorArray([Color.WHITE]), uv, texture)


func _draw_top(quad: PackedVector2Array) -> void:
	if top_texture == null:
		draw_colored_polygon(quad, top_color)
		_draw_edge(quad)
		return

	# 마름모의 바깥 사각형을 기준으로 그림을 씌운다.
	var min_p := quad[0]
	var max_p := quad[0]

	for p in quad:
		min_p = Vector2(minf(min_p.x, p.x), minf(min_p.y, p.y))
		max_p = Vector2(maxf(max_p.x, p.x), maxf(max_p.y, p.y))

	var span := max_p - min_p
	var uv := PackedVector2Array()

	for p in quad:
		uv.append(Vector2((p.x - min_p.x) / span.x, (p.y - min_p.y) / span.y))

	draw_polygon(quad, PackedColorArray([Color.WHITE]), uv, top_texture)


func _draw_edge(quad: PackedVector2Array) -> void:
	var line := PackedVector2Array(quad)
	line.append(quad[0])
	draw_polyline(line, Color(0, 0, 0, 0.35), 1.0)
