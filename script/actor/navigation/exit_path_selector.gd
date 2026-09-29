extends RefCounted


func find_exit_cell(
	doors: Array,
	current_cell: Vector2i,
	floor_node: Node,
	is_cell_blocked: Callable,
	create_path: Callable
) -> Vector2i:
	var best_cell := Vector2i(-1, -1)
	var best_path_size: int = 2147483647

	var directions: Array[Vector2i] = [
		Vector2i(1, 0),
		Vector2i(-1, 0),
		Vector2i(0, 1),
		Vector2i(0, -1)
	]

	for door in doors:
		if not is_instance_valid(door):
			continue

		if door.is_queued_for_deletion():
			continue

		if bool(
			door.get_meta("is_build_preview", false)
		):
			continue

		if not door.has_meta("anchor"):
			continue

		var door_cell: Vector2i = door.get_meta("anchor")

		if not floor_node.is_cell_inside(door_cell):
			continue

		if current_cell == door_cell:
			return door_cell

		var candidates: Array[Vector2i] = []

		if not is_cell_blocked.call(door_cell):
			candidates.append(door_cell)
		else:
			for direction in directions:
				var adjacent_cell: Vector2i = (
					door_cell + direction
				)

				if not floor_node.is_cell_inside(adjacent_cell):
					continue

				if is_cell_blocked.call(adjacent_cell):
					continue

				candidates.append(adjacent_cell)

		for candidate in candidates:
			if candidate == current_cell:
				return candidate

			var path: Array[Vector2i] = create_path.call(
				current_cell,
				candidate
			)

			if path.is_empty():
				continue

			# 요청한 출구 접근 칸에 도착하는 경로만 허용
			if path[path.size() - 1] != candidate:
				continue

			if path.size() < best_path_size:
				best_path_size = path.size()
				best_cell = candidate

	return best_cell
