extends StaticBody2D


@export var tile_width: float = 96.0
@export var tile_height: float = 48.0

var footprint_width: int = 2
var footprint_height: int = 1
var blocking: bool = true

var collision_shape: CollisionShape2D = null


func _ready() -> void:
	collision_shape = CollisionShape2D.new()
	collision_shape.name = "CollisionShape2D"

	add_child(
		collision_shape
	)

	_update_shape()


func set_footprint(
	width: int,
	height: int
) -> void:
	footprint_width = maxi(width, 1)
	footprint_height = maxi(height, 1)

	_update_shape()


func set_blocking(
	value: bool
) -> void:
	blocking = value

	collision_layer = 1 if blocking else 0
	collision_mask = 0

	if is_instance_valid(collision_shape):
		collision_shape.disabled = not blocking


func _update_shape() -> void:
	if not is_instance_valid(collision_shape):
		return

	var width: float = float(
		footprint_width
	)

	var height: float = float(
		footprint_height
	)

	var polygon := ConvexPolygonShape2D.new()

	polygon.points = PackedVector2Array([
		Vector2(
			0.0,
			-tile_height * 0.5
		),
		Vector2(
			width * tile_width * 0.5,
			(width - 1.0) * tile_height * 0.5
		),
		Vector2(
			(width - height) * tile_width * 0.5,
			(width + height - 1.0)
				* tile_height
				* 0.5
		),
		Vector2(
			-height * tile_width * 0.5,
			(height - 1.0) * tile_height * 0.5
		)
	])

	collision_shape.shape = polygon
	collision_shape.disabled = not blocking
