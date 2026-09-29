extends RefCounted


var occupancy_state

var furniture: Node2D = null

var original_anchor: Vector2i = Vector2i.ZERO
var original_global_position: Vector2 = Vector2.ZERO

var original_cells: Array[Vector2i] = []
var original_reserved_cells: Array[Vector2i] = []


func configure(
	new_occupancy_state
) -> void:
	occupancy_state = new_occupancy_state


func is_active() -> bool:
	return is_instance_valid(furniture)


func get_furniture() -> Node2D:
	if not is_active():
		return null

	return furniture


func get_original_cells() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	result.append_array(original_cells)
	return result


func get_original_reserved_cells() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	result.append_array(original_reserved_cells)
	return result


func clear() -> void:
	furniture = null
	original_anchor = Vector2i.ZERO
	original_global_position = Vector2.ZERO

	original_cells.clear()
	original_reserved_cells.clear()


func begin_move(
	target_furniture: Node2D,
	fallback_anchor: Vector2i
) -> bool:
	if occupancy_state == null:
		push_error(
			"[건축 이동] 점유 상태가 설정되지 않음"
		)
		return false

	if not is_instance_valid(target_furniture):
		return false

	if is_active():
		return false

	clear()

	furniture = target_furniture

	original_anchor = target_furniture.get_meta(
		"anchor",
		fallback_anchor
	)

	original_global_position = (
		target_furniture.global_position
	)

	# 원래 점유 정보를 별도 배열로 보관
	original_cells.append_array(
		occupancy_state.find_occupied_cells_for(
			target_furniture
		)
	)

	original_reserved_cells.append_array(
		occupancy_state.find_reserved_cells_for(
			target_furniture
		)
	)

	# 이동 중에는 원래 위치를 비워 둠
	occupancy_state.unregister_furniture(
		target_furniture
	)

	target_furniture.visible = false

	return true


func finish_move(
	new_anchor: Vector2i,
	new_world_position: Vector2,
	catalog_index: int,
	rotation_index: int,
	new_cells: Array[Vector2i],
	new_reserved_cells: Array[Vector2i]
) -> bool:
	var target_furniture: Node2D = get_furniture()

	if not is_instance_valid(target_furniture):
		clear()
		return false

	target_furniture.global_position = new_world_position

	target_furniture.set_meta(
		"catalog_index",
		catalog_index
	)

	target_furniture.set_meta(
		"rotation_index",
		rotation_index
	)

	target_furniture.set_meta(
		"anchor",
		new_anchor
	)

	occupancy_state.register_furniture(
		target_furniture,
		new_cells,
		new_reserved_cells
	)

	target_furniture.visible = true
	clear()

	return true


func cancel_move() -> bool:
	var target_furniture: Node2D = get_furniture()

	if not is_instance_valid(target_furniture):
		clear()
		return false

	occupancy_state.register_furniture(
		target_furniture,
		get_original_cells(),
		get_original_reserved_cells()
	)

	# 문도 이동 전 실제 위치로 정확히 복구
	target_furniture.global_position = (
		original_global_position
	)

	target_furniture.visible = true
	clear()

	return true
