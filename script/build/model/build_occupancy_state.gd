extends RefCounted


var occupied_cells: Dictionary = {}
var reserved_cells: Dictionary = {}


func clear() -> void:
	occupied_cells.clear()
	reserved_cells.clear()


func has_occupied_cell(
	cell: Vector2i
) -> bool:
	return occupied_cells.has(cell)


func has_reserved_cell(
	cell: Vector2i
) -> bool:
	return reserved_cells.has(cell)


func get_furniture_at(
	cell: Vector2i
) -> Node2D:
	if not occupied_cells.has(cell):
		return null

	var furniture = occupied_cells[cell]

	if not is_instance_valid(furniture):
		occupied_cells.erase(cell)
		return null

	if not furniture is Node2D:
		occupied_cells.erase(cell)
		return null

	return furniture as Node2D


func register_furniture(
	furniture: Node,
	furniture_cells: Array[Vector2i],
	furniture_reserved_cells: Array[Vector2i]
) -> void:
	if not is_instance_valid(furniture):
		return

	for cell in furniture_cells:
		occupied_cells[cell] = furniture

	for cell in furniture_reserved_cells:
		reserved_cells[cell] = furniture


func unregister_furniture(
	furniture: Node
) -> void:
	if not is_instance_valid(furniture):
		return

	var occupied_to_remove: Array[Vector2i] = (
		find_occupied_cells_for(furniture)
	)

	var reserved_to_remove: Array[Vector2i] = (
		find_reserved_cells_for(furniture)
	)

	for cell in occupied_to_remove:
		occupied_cells.erase(cell)

	for cell in reserved_to_remove:
		reserved_cells.erase(cell)


func find_occupied_cells_for(
	furniture: Node
) -> Array[Vector2i]:
	var result: Array[Vector2i] = []

	if not is_instance_valid(furniture):
		return result

	for raw_cell in occupied_cells.keys():
		var cell: Vector2i = raw_cell

		if occupied_cells[cell] == furniture:
			result.append(cell)

	return result


func find_reserved_cells_for(
	furniture: Node
) -> Array[Vector2i]:
	var result: Array[Vector2i] = []

	if not is_instance_valid(furniture):
		return result

	for raw_cell in reserved_cells.keys():
		var cell: Vector2i = raw_cell

		if reserved_cells[cell] == furniture:
			result.append(cell)

	return result
