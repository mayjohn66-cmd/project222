extends RefCounted


var occupancy_state


func configure(
	new_occupancy_state
) -> void:
	occupancy_state = new_occupancy_state


func remove_furniture(
	furniture: Variant,
	build_id: String
) -> bool:
	if occupancy_state == null:
		push_error(
			"[BuildRemovalService] 점유 상태가 설정되지 않음"
		)
		return false

	if not is_instance_valid(furniture):
		return false

	if furniture.is_queued_for_deletion():
		return false

	if build_id.is_empty():
		return false

	if furniture.is_in_group("shelf"):
		# 다층 진열대는 기존 방식으로 위층만 철거
		if furniture.stack_level > 1:
			return remove_shelf_level(
				furniture,
				build_id
			)

		# 마지막 한 층도 상품이 남아 있으면 철거 금지
		if furniture.top_level_has_items():
			print(
				"[건축] 진열대의 상품을 먼저 비워주세요."
			)
			return false

	return remove_entire_furniture(
		furniture,
		build_id
	)


func remove_shelf_level(
	furniture: Variant,
	build_id: String
) -> bool:
	# 위층에 상품이 있으면 철거하지 않음
	if furniture.top_level_has_items():
		print(
			"[건축] 상품이 있는 진열대 층은 철거할 수 없음"
		)
		return false

	var removed: bool = furniture.remove_level()

	if not removed:
		return false

	GameState.add_furniture(
		build_id,
		1
	)

	print(
		"[건축] 진열대 한 층 철거 / ",
		build_id,
		" / 남은 층: ",
		furniture.stack_level
	)

	return true


func remove_entire_furniture(
	furniture: Variant,
	build_id: String
) -> bool:
	if occupancy_state == null:
		return false

	if not is_instance_valid(furniture):
		return false

	if furniture.is_queued_for_deletion():
		return false

	if build_id.is_empty():
		return false

	# 생산 중이거나 완성품이 남아 있는 설비는 철거 금지
	if furniture is ProductionFacility:
		if not furniture.can_remove_facility():
			print(
				"[건축] 가공을 마치고 완성품을 회수한 뒤 "
				+ "철거할 수 있습니다."
			)
			return false

	occupancy_state.unregister_furniture(
		furniture
	)

	GameState.add_furniture(
		build_id,
		1
	)

	print(
		"[건축] 가구 철거 / ",
		build_id,
		" / 보유 수량: ",
		GameState.get_furniture_count(build_id)
	)

	furniture.queue_free()

	return true
