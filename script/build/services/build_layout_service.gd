extends RefCounted


func collect_layout(
	objects_parent: Node,
	get_build_id: Callable
) -> Array[Dictionary]:
	var result: Array[Dictionary] = []

	if not is_instance_valid(objects_parent):
		return result

	for furniture in objects_parent.get_children():
		if not is_instance_valid(furniture):
			continue

		# 철거 후 삭제 대기 중인 가구 제외
		if furniture.is_queued_for_deletion():
			continue

		# 건축 미리보기 제외
		if bool(
			furniture.get_meta(
				"is_build_preview",
				false
			)
		):
			continue

		if not furniture.has_meta("catalog_index"):
			continue

		if not furniture.has_meta("anchor"):
			continue

		var build_id: String = get_build_id.call(
			furniture
		)

		if build_id.is_empty():
			push_warning(
				"[배치 저장] 가구 ID가 없어 제외: "
				+ str(furniture.name)
			)
			continue

		var data: Dictionary = {
			"build_id": build_id,

			# 이전 저장 방식과의 호환용
			"catalog_index": int(
				furniture.get_meta(
					"catalog_index",
					-1
				)
			),

			"rotation_index": int(
				furniture.get_meta(
					"rotation_index",
					0
				)
			),

			"anchor": furniture.get_meta("anchor")
		}

		if furniture.is_in_group("shelf"):
			append_shelf_state(
				data,
				furniture
			)

		if (
			furniture.has_method(
				"get_stored_slots"
			)
			and furniture.has_method(
				"apply_stored_slots"
			)
		):
			append_warehouse_storage_state(
				data,
				furniture
			)

		if furniture is ProductionFacility:
			data["production_state"] = (
				furniture.get_production_save_data()
			)

		result.append(data)

	return result


func append_shelf_state(
	data: Dictionary,
	furniture: Variant
) -> void:
	data["stack_level"] = int(
		furniture.stack_level
	)

	# 저장 이후 실제 진열대 상품이 바뀌어도
	# 저장 데이터가 함께 바뀌지 않도록 깊은 복사
	data["shelf_slots"] = (
		furniture.slots.duplicate(true)
	)

func append_warehouse_storage_state(
	data: Dictionary,
	furniture: Variant
) -> void:
	if not is_instance_valid(
		furniture
	):
		return

	if not furniture.has_method(
		"get_stored_slots"
	):
		return

	var saved_slots: Variant = (
		furniture.call(
			"get_stored_slots"
		)
	)

	if not saved_slots is Array:
		push_warning(
			"[창고 저장] 슬롯 데이터가 Array가 아닙니다."
		)
		return

	# 슬롯 번호와 내용이 그대로 유지되도록 깊은 복사
	data["warehouse_slots"] = (
		saved_slots.duplicate(true)
	)

	print(
		"[창고 저장] 슬롯 수: ",
		saved_slots.size()
	)

func restore_layout(
	layout: Array[Dictionary],
	objects_parent: Node,
	occupancy_state,
	selection_state,
	catalog: Array[String],
	apply_size: Callable,
	get_world_position: Callable,
	get_cells: Callable,
	get_reserved_cells: Callable
) -> void:
	# 새 main 씬에서 배치를 복원하는 용도
	occupancy_state.clear()

	for data in layout:
		var build_id: String = str(
			data.get("build_id", "")
		)

		var catalog_index: int = -1

		if build_id.is_empty():
			# ID가 없는 옛 저장 데이터만 인덱스로 복원
			catalog_index = int(
				data.get("catalog_index", -1)
			)

			if (
				catalog_index >= 0
				and catalog_index < catalog.size()
			):
				build_id = catalog[catalog_index]
		else:
			# ID가 있으면 반드시 해당 가구로 복원
			catalog_index = catalog.find(build_id)

		if (
			build_id.is_empty()
			or catalog_index < 0
			or catalog_index >= catalog.size()
		):
			push_warning(
				"[복원 실패] 건축 데이터 없음: "
				+ build_id
			)
			continue

		var scene: PackedScene = (
			BuildObjectData.get_build_scene(build_id)
		)

		if scene == null:
			push_warning(
				"[복원 실패] 씬 없음: " + build_id
			)
			continue

		var furniture = scene.instantiate()

		if not furniture is Node2D:
			furniture.free()
			push_warning(
				"[복원 실패] 가구 루트가 Node2D가 아님: "
				+ build_id
			)
			continue

		var anchor: Vector2i = data.get(
			"anchor",
			Vector2i(-1, -1)
		)

		var saved_rotation: int = 0

		if BuildObjectData.is_rotatable(build_id):
			saved_rotation = posmod(
				int(data.get("rotation_index", 0)),
				4
			)

		# 현재 크기·위치 계산 함수에서 사용하는 상태
		selection_state.restore_selection(
			catalog_index,
			saved_rotation
		)

		furniture.set_meta("build_id", build_id)
		furniture.set_meta("catalog_index", catalog_index)
		furniture.set_meta("rotation_index", saved_rotation)
		furniture.set_meta("anchor", anchor)

		objects_parent.add_child(furniture)

		apply_size.call(furniture)

		if furniture is ProductionFacility:
			var saved_production: Variant = data.get(
				"production_state",
				{}
			)

			var production_restored: bool = false

			if saved_production is Dictionary:
				production_restored = (
					furniture.apply_production_save_data(
						saved_production
					)
				)

			if not production_restored:
				push_error(
					"[생산 복원] 생산 상태가 잘못되어 설비 복원을 중단합니다: "
					+ build_id
				)

				# 잘못된 상태를 대기 중 설비로 복원하면
				# 투입 재료나 완성품이 사라질 수 있으므로 제거
				furniture.free()
				continue

		if furniture.is_in_group("shelf"):
			restore_shelf_state(
				furniture,
				build_id,
				data
			)

		if furniture.has_method(
			"apply_stored_slots"
		):
			restore_warehouse_storage_state(
				furniture,
				build_id,
				data
			)

		var world_position: Vector2 = (
			get_world_position.call(anchor)
		)

		furniture.global_position = world_position

		var cells: Array[Vector2i] = (
			get_cells.call(anchor)
		)

		var reserved_cells: Array[Vector2i] = (
			get_reserved_cells.call(anchor)
		)

		occupancy_state.register_furniture(
			furniture,
			cells,
			reserved_cells
		)

		print(
			"[가구 복원] ",
			build_id,
			" / 위치: ",
			anchor,
			" / 회전: ",
			saved_rotation
		)

	selection_state.clear()


func restore_shelf_state(
	furniture: Variant,
	build_id: String,
	data: Dictionary
) -> void:
	var shelf_data: Dictionary = (
		ShelfData.get_shelf_data(build_id)
	)

	# 1. 기본 슬롯과 용량 설정
	if not shelf_data.is_empty():
		var slots_per_level: int = int(
			shelf_data.get("slots_per_level", 2)
		)

		var slot_capacity: int = int(
			shelf_data.get("slot_capacity", 5)
		)

		if furniture.has_method("configure_shelf"):
			furniture.configure_shelf(
				slots_per_level,
				slot_capacity
			)

	# 2. 저장된 층수 복원
	var saved_stack_level: int = clampi(
		int(data.get("stack_level", 1)),
		1,
		3
	)

	while furniture.stack_level < saved_stack_level:
		if not furniture.add_level():
			break

	# 3. 상품 슬롯 복원
	var saved_slots: Array = data.get(
		"shelf_slots",
		[]
	)

	if not saved_slots.is_empty():
		furniture.slots.clear()

		for slot_data in saved_slots:
			if slot_data is Dictionary:
				furniture.slots.append(
					slot_data.duplicate(true)
				)

	# 4. 최종 재고 표시 갱신
	if furniture.has_method("update_stock_label"):
		furniture.update_stock_label()

	print(
		"[진열대 복원] ",
		build_id,
		" / 층: ",
		furniture.stack_level,
		" / 슬롯: ",
		furniture.slots.size()
	)

func restore_warehouse_storage_state(
	furniture: Variant,
	build_id: String,
	data: Dictionary
) -> void:
	if not is_instance_valid(
		furniture
	):
		return

	if not furniture.has_method(
		"apply_stored_slots"
	):
		return

	# 예전 저장 파일에는 warehouse_slots가 없을 수 있다.
	# 이 경우 빈 창고 상태를 그대로 사용한다.
	if not data.has(
		"warehouse_slots"
	):
		print(
			"[창고 복원] 이전 저장 데이터이므로 빈 창고로 복원: ",
			build_id
		)

		return

	var saved_slots: Variant = data.get(
		"warehouse_slots",
		[]
	)

	if not saved_slots is Array:
		push_warning(
			"[창고 복원] 잘못된 슬롯 데이터: "
			+ build_id
		)

		return

	var restored: bool = bool(
		furniture.call(
			"apply_stored_slots",
			saved_slots
		)
	)

	if not restored:
		push_error(
			"[창고 복원] 슬롯 복원 실패: "
			+ build_id
		)

		return

	print(
		"[창고 복원] ",
		build_id,
		" / 슬롯 수: ",
		saved_slots.size()
	)
