extends Node2D

@onready var floor_node = $"../../Floor"


func _ready() -> void:
	add_to_group("production_room")

	# World objects share the foot-position depth order with walls and actors.
	z_index = 0


func get_return_cell() -> Vector2i:
	# 문이 붙어 있는 매장 안쪽 칸
	return get_meta(
		"anchor",
		Vector2i(-1, -1)
	)


func get_return_world_position() -> Vector2:
	var return_cell: Vector2i = get_return_cell()

	if return_cell.x < 0 or return_cell.y < 0:
		return global_position

	if not is_instance_valid(floor_node):
		return global_position

	if floor_node.has_method("is_store_cell"):
		if not floor_node.is_store_cell(return_cell):
			return global_position

	return floor_node.to_global(
		floor_node.grid_to_local(
			return_cell
		)
	)
