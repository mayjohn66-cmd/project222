extends Node2D


@onready var floor_node = $"../../Floor"

# 손님이 문에서 몇 칸 떨어진 외부에 등장할지 결정한다.
const CUSTOMER_ARRIVAL_DISTANCE: int = 4

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

# 문의 회전 방향을 기준으로
# 매장 바깥쪽에 있는 셀을 반환한다.
func get_outside_cell() -> Vector2i:
	var anchor: Vector2i = get_meta(
		"anchor",
		Vector2i(-1, -1)
	)

	var rotation_index: int = int(
		get_meta(
			"rotation_index",
			-1
		)
	)

	match rotation_index:
		0:
			# 위쪽 벽
			return anchor + Vector2i(0, -1)

		1:
			# 오른쪽 벽
			return anchor + Vector2i(1, 0)

		2:
			# 아래쪽 벽
			return anchor + Vector2i(0, 1)

		3:
			# 왼쪽 벽
			return anchor + Vector2i(-1, 0)

	return anchor


# 손님이 외부에서 등장할 위치를 반환한다.
func get_customer_spawn_position() -> Vector2:
	var outside_cell: Vector2i = (
		get_outside_cell()
	)

	var outside_local: Vector2 = (
		floor_node.grid_to_local(
			outside_cell
		)
	)

	return floor_node.to_global(
		outside_local
	)

# 문 방향으로부터 충분히 떨어진 외부 등장 위치를 반환한다.
func get_customer_arrival_position() -> Vector2:
	var anchor: Vector2i = get_meta(
		"anchor",
		Vector2i(-1, -1)
	)

	var rotation_index: int = int(
		get_meta(
			"rotation_index",
			-1
		)
	)

	var outside_direction := Vector2i.ZERO

	match rotation_index:
		0:
			outside_direction = Vector2i(0, -1)

		1:
			outside_direction = Vector2i(1, 0)

		2:
			outside_direction = Vector2i(0, 1)

		3:
			outside_direction = Vector2i(-1, 0)

	var arrival_cell: Vector2i = (
		anchor
		+ outside_direction
		* CUSTOMER_ARRIVAL_DISTANCE
	)

	return floor_node.to_global(
		floor_node.grid_to_local(
			arrival_cell
		)
	)
