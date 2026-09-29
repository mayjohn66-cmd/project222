extends RefCounted

# 창고 슬롯 데이터와 건축 배치 데이터 사이의 변환만 담당한다.


static func attach_storage_slots(
	layout: Array[Dictionary],
	occupancy_state
) -> void:
	for entry in layout:
		var anchor: Vector2i = entry.get(
			"anchor",
			Vector2i(-1, -1)
		)

		if anchor == Vector2i(-1, -1):
			push_warning(
				"[창고 저장] 배치 좌표가 없습니다."
			)
			continue

		var storage: Node = (
			occupancy_state.get_furniture_at(anchor)
		)

		if not is_instance_valid(storage):
			continue

		if not storage.has_method("get_stored_slots"):
			continue

		entry["storage_slots"] = storage.call(
			"get_stored_slots"
		)


static func restore_storage_slots(
	layout: Array[Dictionary],
	occupancy_state
) -> void:
	for entry in layout:
		if not entry.has("storage_slots"):
			continue

		if not entry["storage_slots"] is Array:
			push_warning(
				"[창고 복구] 슬롯 데이터 형식이 잘못되었습니다."
			)
			continue

		var anchor: Vector2i = entry.get(
			"anchor",
			Vector2i(-1, -1)
		)

		if anchor == Vector2i(-1, -1):
			push_warning(
				"[창고 복구] 배치 좌표가 없습니다."
			)
			continue

		var storage: Node = (
			occupancy_state.get_furniture_at(anchor)
		)

		if not is_instance_valid(storage):
			push_warning(
				"[창고 복구] 생성된 창고를 찾지 못했습니다: "
				+ str(anchor)
			)
			continue

		if not storage.has_method("apply_stored_slots"):
			push_warning(
				"[창고 복구] 슬롯 복구 함수를 찾지 못했습니다: "
				+ str(anchor)
			)
			continue

		if not bool(
			storage.call(
				"apply_stored_slots",
				entry["storage_slots"]
			)
		):
			push_warning(
				"[창고 복구] 슬롯 데이터 적용 실패: "
				+ str(anchor)
			)
