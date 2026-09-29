extends RefCounted



func get_register_worker_offsets(
	rotation_index: int,
	profile: RegisterAreaProfile
) -> Array[Vector2i]:
	if profile == null:
		return []

	return profile.get_worker_offsets(rotation_index)


func get_register_checkout_offsets(
	rotation_index: int,
	profile: RegisterAreaProfile
) -> Array[Vector2i]:
	if profile == null:
		return []

	return profile.get_checkout_offsets(rotation_index)


func get_register_reserved_cells(
	anchor: Vector2i,
	rotation_index: int,
	profile: RegisterAreaProfile
) -> Array[Vector2i]:
	var result: Array[Vector2i] = []

	var offsets: Array[Vector2i] = (
		get_register_worker_offsets(
			rotation_index,
			profile
		)
	)

	offsets.append_array(
		get_register_checkout_offsets(
			rotation_index,
			profile
		)
	)

	for offset in offsets:
		var cell: Vector2i = anchor + offset

		if not result.has(cell):
			result.append(cell)

	return result


func get_shelf_access_offsets(
	size: Vector2i,
	rotation_index: int
) -> Array[Vector2i]:
	var result: Array[Vector2i] = []

	match posmod(rotation_index, 4):
		0:
			for x in range(size.x):
				result.append(
					Vector2i(x, size.y)
				)

		1:
			for y in range(size.y):
				result.append(
					Vector2i(size.x, y)
				)

		2:
			for x in range(size.x):
				result.append(
					Vector2i(x, -1)
				)

		3:
			for y in range(size.y):
				result.append(
					Vector2i(-1, y)
				)

	return result

func get_rotated_size(
	base_size: Vector2i,
	rotation_index: int
) -> Vector2i:
	if posmod(rotation_index, 2) == 1:
		return Vector2i(
			base_size.y,
			base_size.x
		)

	return base_size


func get_occupied_cells(
	anchor: Vector2i,
	size: Vector2i
) -> Array[Vector2i]:
	var result: Array[Vector2i] = []

	for x in range(size.x):
		for y in range(size.y):
			result.append(
				anchor + Vector2i(x, y)
			)

	return result
