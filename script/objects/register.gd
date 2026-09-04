extends StaticBody2D


func get_checkout_offsets(
	rotation_index: int
) -> Array[Vector2i]:

	match rotation_index % 4:
		0:
			return [
				Vector2i(0, 1),
				Vector2i(1, 1)
			]

		1:
			return [
				Vector2i(1, 0),
				Vector2i(1, 1)
			]

		2:
			return [
				Vector2i(0, -1),
				Vector2i(1, -1)
			]

		3:
			return [
				Vector2i(-1, 0),
				Vector2i(-1, 1)
			]

	return []


func get_body_cells() -> Array[Vector2i]:
	var anchor: Vector2i = get_meta(
		"anchor",
		Vector2i(-1, -1)
	)

	var rotation_index: int = int(
		get_meta(
			"rotation_index",
			0
		)
	)

	match rotation_index % 4:
		0, 2:
			return [
				anchor,
				anchor + Vector2i(1, 0)
			]

		1, 3:
			return [
				anchor,
				anchor + Vector2i(0, 1)
			]

	return []

var waiting_customer = null
var reserved_worker = null
var worker_cell_users: Dictionary = {}

func get_worker_cells() -> Array[Vector2i]:
	var anchor: Vector2i = get_meta(
		"anchor",
		Vector2i(-1, -1)
	)

	var rotation_index: int = int(
		get_meta(
			"rotation_index",
			0
		)
	)

	match rotation_index % 4:
		0:
			return [
				anchor + Vector2i(0, -1),
				anchor + Vector2i(1, -1)
			]

		1:
			return [
				anchor + Vector2i(-1, 0),
				anchor + Vector2i(-1, 1)
			]

		2:
			return [
				anchor + Vector2i(0, 1),
				anchor + Vector2i(1, 1)
			]

		3:
			return [
				anchor + Vector2i(1, 0),
				anchor + Vector2i(1, 1)
			]

	return []

func get_checkout_cells() -> Array[Vector2i]:
	var anchor: Vector2i = get_meta(
		"anchor",
		Vector2i(-1, -1)
	)

	var rotation_index: int = int(
		get_meta(
			"rotation_index",
			0
		)
	)

	match rotation_index % 4:
		0:
			return [
				anchor + Vector2i(0, 1),
				anchor + Vector2i(1, 1)
			]

		1:
			return [
				anchor + Vector2i(1, 0),
				anchor + Vector2i(1, 1)
			]

		2:
			return [
				anchor + Vector2i(0, -1),
				anchor + Vector2i(1, -1)
			]

		3:
			return [
				anchor + Vector2i(-1, 0),
				anchor + Vector2i(-1, 1)
			]

	return []

func request_checkout(customer) -> bool:
	if has_waiting_customer():
		return false

	waiting_customer = customer

	print("계산 대기 손님 등록")

	return true


func has_waiting_customer() -> bool:
	return is_instance_valid(
		waiting_customer
	)


func get_waiting_customer():
	if not has_waiting_customer():
		waiting_customer = null
		return null

	return waiting_customer


func finish_checkout():
	waiting_customer = null


func get_cashier_cells() -> Array[Vector2i]:
	var anchor: Vector2i = get_meta(
		"anchor",
		Vector2i(-1, -1)
	)

	var rotation_index: int = int(
		get_meta(
			"rotation_index",
			0
		)
	)

	var result: Array[Vector2i] = []

	match rotation_index % 4:
		0:
			result = [
				anchor + Vector2i(0, -1),
				anchor + Vector2i(1, -1)
			]

		1:
			result = [
				anchor + Vector2i(-1, 0),
				anchor + Vector2i(-1, 1)
			]

		2:
			result = [
				anchor + Vector2i(0, 1),
				anchor + Vector2i(1, 1)
			]

		3:
			result = [
				anchor + Vector2i(1, 0),
				anchor + Vector2i(1, 1)
			]

	return result


func debug_service_cells():
	print(
		"계산대 본체: ",
		get_body_cells()
	)

	print(
		"직원 위치: ",
		get_worker_cells()
	)

	print(
		"손님 위치: ",
		get_checkout_cells()
	)


func try_reserve_worker(worker_node) -> bool:
	if is_instance_valid(reserved_worker):
		return reserved_worker == worker_node

	reserved_worker = worker_node
	return true


func is_reserved_for_other(worker_node) -> bool:
	if not is_instance_valid(reserved_worker):
		reserved_worker = null
		return false

	return reserved_worker != worker_node


func release_worker_reservation(worker_node):
	if reserved_worker == worker_node:
		reserved_worker = null

func cleanup_worker_cell_users():
	var cells_to_remove: Array[Vector2i] = []

	for cell in worker_cell_users.keys():
		var worker = worker_cell_users[cell]

		if not is_instance_valid(worker):
			cells_to_remove.append(cell)

	for cell in cells_to_remove:
		worker_cell_users.erase(cell)


func is_worker_cell_available(
	cell: Vector2i,
	worker_node
) -> bool:
	cleanup_worker_cell_users()

	if not worker_cell_users.has(cell):
		return true

	return worker_cell_users[cell] == worker_node


func try_reserve_worker_cell(
	cell: Vector2i,
	worker_node
) -> bool:
	cleanup_worker_cell_users()

	if not is_worker_cell_available(
		cell,
		worker_node
	):
		return false

	worker_cell_users[cell] = worker_node

	return true


func release_worker_cell(
	worker_node
):
	cleanup_worker_cell_users()

	var cells_to_remove: Array[Vector2i] = []

	for cell in worker_cell_users.keys():
		if worker_cell_users[cell] == worker_node:
			cells_to_remove.append(cell)

	for cell in cells_to_remove:
		worker_cell_users.erase(cell)
