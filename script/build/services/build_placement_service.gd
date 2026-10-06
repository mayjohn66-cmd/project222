extends RefCounted


var objects_parent: Node = null

var occupancy_state
var selection_state

var apply_current_size_callable: Callable
var get_world_position_callable: Callable
var get_occupied_cells_callable: Callable
var get_reserved_cells_callable: Callable
var depleted_item_callable: Callable


func configure(
	new_objects_parent: Node,
	new_occupancy_state,
	new_selection_state,
	new_apply_current_size_callable: Callable,
	new_get_world_position_callable: Callable,
	new_get_occupied_cells_callable: Callable,
	new_get_reserved_cells_callable: Callable,
	new_depleted_item_callable: Callable
) -> void:
	objects_parent = new_objects_parent
	occupancy_state = new_occupancy_state
	selection_state = new_selection_state

	apply_current_size_callable = (
		new_apply_current_size_callable
	)

	get_world_position_callable = (
		new_get_world_position_callable
	)

	get_occupied_cells_callable = (
		new_get_occupied_cells_callable
	)

	get_reserved_cells_callable = (
		new_get_reserved_cells_callable
	)

	depleted_item_callable = (
		new_depleted_item_callable
	)


func is_configured() -> bool:
	return (
		objects_parent != null
		and occupancy_state != null
		and selection_state != null
		and apply_current_size_callable.is_valid()
		and get_world_position_callable.is_valid()
		and get_occupied_cells_callable.is_valid()
		and get_reserved_cells_callable.is_valid()
		and depleted_item_callable.is_valid()
	)


func place_furniture(
	build_id: String,
	anchor: Vector2i
) -> Node2D:
	if not is_configured():
		push_error(
			"[건축 설치] 서비스가 설정되지 않음"
		)

		return null

	if build_id.is_empty():
		return null
	if not ShopSpaceProgression.can_install(build_id, objects_parent): return null

	if not GameState.has_furniture(
		build_id,
		1
	):
		DebugLog.write(
			"[건축 설치] 보유한 가구가 없음: ",
			build_id
		)

		return null

	var furniture: Node2D = (
		_create_furniture_instance(
			build_id
		)
	)

	if furniture == null:
		return null

	_apply_placement_metadata(
		furniture,
		build_id,
		anchor
	)

	objects_parent.add_child(furniture)

	var world_position: Vector2 = (
		get_world_position_callable.call(
			anchor
		)
	)

	furniture.global_position = world_position

	apply_current_size_callable.call(
		furniture
	)

	_configure_new_shelf(
		furniture,
		build_id
	)

	var furniture_cells: Array[Vector2i] = (
		get_occupied_cells_callable.call(
			anchor
		)
	)

	var furniture_reserved_cells: Array[Vector2i] = (
		get_reserved_cells_callable.call(
			anchor
		)
	)

	occupancy_state.register_furniture(
		furniture,
		furniture_cells,
		furniture_reserved_cells
	)

	var removed_amount: int = (
		GameState.remove_furniture(
			build_id,
			1
		)
	)

	if removed_amount != 1:
		push_error(
			"[건축 설치] 가구 수량 차감 실패: "
			+ build_id
		)

		_rollback_placement(
			furniture
		)

		return null

	var placed_rotation: int = (
		selection_state.rotation_index
	)

	depleted_item_callable.call(
		build_id
	)

	DebugLog.write(
		"[건축 설치] 완료 / ",
		build_id,
		" / 위치: ",
		anchor,
		" / 회전: ",
		placed_rotation
	)

	ShopSpaceProgression.placed(build_id, objects_parent)
	return furniture


func _create_furniture_instance(
	build_id: String
) -> Node2D:
	var scene: PackedScene = (
		BuildObjectData.get_build_scene(build_id)
	)

	if scene == null:
		push_error(
			"[건축 설치] 씬 없음: "
			+ build_id
		)
		return null

	var instance: Node = scene.instantiate()

	if not instance is Node2D:
		push_error(
			"[건축 설치] Node2D가 아닌 씬: "
			+ build_id
		)

		instance.free()
		return null

	return instance as Node2D


func _apply_placement_metadata(
	furniture: Node2D,
	build_id: String,
	anchor: Vector2i
) -> void:
	furniture.set_meta(
		"build_id",
		build_id
	)

	# 예전 저장 데이터 호환
	furniture.set_meta(
		"catalog_index",
		selection_state.catalog_index
	)

	furniture.set_meta(
		"rotation_index",
		selection_state.rotation_index
	)

	furniture.set_meta(
		"anchor",
		anchor
	)


func _configure_new_shelf(
	furniture: Node2D,
	build_id: String
) -> void:
	if not furniture.is_in_group("shelf"):
		return

	var shelf_data: Dictionary = (
		ShelfData.get_shelf_data(
			build_id
		)
	)

	if shelf_data.is_empty():
		push_error(
			"[건축 설치] 진열대 데이터 없음: "
			+ build_id
		)

		return

	if not furniture.has_method(
		"configure_shelf"
	):
		push_warning(
			"[건축 설치] configure_shelf 함수 없음: "
			+ build_id
		)

		return

	var slots_per_level: int = int(
		shelf_data.get(
			"slots_per_level",
			2
		)
	)

	var slot_capacity: int = int(
		shelf_data.get(
			"slot_capacity",
			5
		)
	)

	furniture.configure_shelf(
		slots_per_level,
		slot_capacity
	)


func _rollback_placement(
	furniture: Node2D
) -> void:
	if not is_instance_valid(furniture):
		return

	occupancy_state.unregister_furniture(
		furniture
	)

	furniture.queue_free()

func can_place(
	floor_grid: Node,
	furniture_cells: Array[Vector2i],
	reserved_cells: Array[Vector2i]
) -> bool:
	if not is_instance_valid(floor_grid):
		return false

	if occupancy_state == null:
		return false

	if not _are_cells_available(
		floor_grid,
		furniture_cells
	):
		return false

	if not _are_cells_available(
		floor_grid,
		reserved_cells
	):
		return false

	return true


func _are_cells_available(
	floor_grid: Node,
	cells: Array[Vector2i]
) -> bool:
	for cell in cells:
		if not floor_grid.is_cell_inside(cell):
			return false

		# 생산실 입구처럼 건축할 수 없는 칸 검사
		if floor_grid.has_method("is_cell_buildable"):
			if not floor_grid.is_cell_buildable(cell):
				return false

		if occupancy_state.has_occupied_cell(cell):
			return false

		if occupancy_state.has_reserved_cell(cell):
			return false

	return true
