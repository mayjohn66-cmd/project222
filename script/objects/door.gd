extends Node2D


@onready var floor_node = $"../../Floor"

func _ready():
	add_to_group("door")

func get_customer_target_position() -> Vector2:
	var anchor: Vector2i = get_meta(
		"anchor",
		Vector2i(-1, -1)
	)

	if anchor.x < 0 or anchor.y < 0:
		return global_position

	var floor_local: Vector2 = (
		floor_node.grid_to_local(anchor)
	)

	return floor_node.to_global(floor_local)
