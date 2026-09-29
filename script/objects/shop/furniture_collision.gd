@tool
extends CollisionPolygon2D

@export var tile_width: float = 96.0
@export var tile_height: float = 48.0

@export var depth_ratio: float = 1.0
var rotation_index: int = 0

func set_rotation_index(value: int) -> void:
	rotation_index = posmod(value,4)
	update_collision()

var footprint_x: int = 1
var footprint_y: int = 1


func _ready():
	update_collision()


func set_footprint(size_x: int, size_y: int):
	footprint_x = max(1, size_x)
	footprint_y = max(1, size_y)

	update_collision()


func set_blocking(value: bool):
	disabled = not value

	var obstacle: NavigationObstacle2D = (
		get_parent().get_node_or_null("NavigationObstacle")
	)

	if obstacle != null:
		obstacle.avoidance_enabled = value


func update_collision():
	polygon = FurnitureFootprint.polygon(Vector2i(footprint_x,footprint_y), depth_ratio,
		rotation_index, Vector2(tile_width,tile_height))

	var obstacle: NavigationObstacle2D = (
		get_parent().get_node_or_null("NavigationObstacle")
	)

	if obstacle != null:
		obstacle.vertices = polygon


func grid_point(x: float, y: float) -> Vector2:
	return Vector2(
		(x - y) * tile_width * 0.5,
		(x + y) * tile_height * 0.5
	)

func apply_furniture_collision(
	furniture,
	size: Vector2i,
	blocking: bool
):
	var collision = furniture.get_node_or_null(
		"Collision"
	)

	if collision == null:
		DebugLog.write(
			"Collision 노드 없음: ",
			furniture.name
		)
		return

	if collision.has_method("set_footprint"):
		collision.set_footprint(
			size.x,
			size.y
		)

	if collision.has_method("set_blocking"):
		collision.set_blocking(blocking)

	DebugLog.write(
		"충돌 크기 적용: ",
		furniture.name,
		" / ",
		size
	)
