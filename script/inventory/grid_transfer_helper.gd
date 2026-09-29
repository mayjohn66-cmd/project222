class_name GridTransferHelper
extends RefCounted


# =========================
# 이동 / 전송 가능 여부
# =========================

static func can_move_or_transfer(
	source_model,
	target_model,
	uid: int,
	target_cell: Vector2i
) -> bool:
	if source_model == null:
		return false

	if target_model == null:
		return false

	if uid == -1:
		return false

	var placement: Dictionary = (
		source_model.get_placement(uid)
	)

	if placement.is_empty():
		return false

	var item_id: String = str(
		placement.get(
			"item_id",
			""
		)
	)

	var rotated: bool = bool(
		placement.get(
			"rotated",
			false
		)
	)

	if item_id.is_empty():
		return false

	# 같은 격자 내부 이동
	if source_model == target_model:
		return source_model.can_place(
			item_id,
			target_cell,
			rotated,
			uid
		)

	# 다른 격자로 이동
	return target_model.can_place(
		item_id,
		target_cell,
		rotated
	)


# =========================
# 실제 이동 / 전송
# =========================

static func move_or_transfer(
	source_model,
	target_model,
	uid: int,
	target_cell: Vector2i,
	destination_extra_data: Dictionary = {}
) -> Dictionary:
	if not can_move_or_transfer(
		source_model,
		target_model,
		uid,
		target_cell
	):
		return {
			"success": false
		}

	var placement: Dictionary = (
		source_model.get_placement(uid)
	)

	if placement.is_empty():
		return {
			"success": false
		}

	var item_id: String = str(
		placement.get(
			"item_id",
			""
		)
	)

	var amount: int = int(
		placement.get(
			"amount",
			1
		)
	)

	var rotated: bool = bool(
		placement.get(
			"rotated",
			false
		)
	)

	# 이동하기 전에 반드시 저장
	var old_cell: Vector2i = (
		placement.get(
			"cell",
			Vector2i.ZERO
		)
	)

	# =========================
	# 같은 격자 내부 이동
	# =========================

	if source_model == target_model:
		var moved: bool = (
			source_model.move_item(
				uid,
				target_cell
			)
		)

		return {
			"success": moved,
			"transferred": false,
			"uid": uid,
			"item_id": item_id,
			"amount": amount,
			"rotated": rotated,
			"old_cell": old_cell,
			"new_cell": target_cell
		}

	# =========================
	# 다른 격자로 전송
	# =========================

	# 강화 단계 같은 부가 데이터를 원본 배치에서 계승한다.
	var transferred_extra_data: Dictionary = (
		placement.duplicate(true)
	)

	# 목적지에서 지정한 데이터가 우선한다.
	for raw_key in destination_extra_data.keys():
		transferred_extra_data[raw_key] = (
			destination_extra_data[raw_key]
		)

	var new_uid: int = (
		target_model.add_item(
			item_id,
			target_cell,
			amount,
			rotated,
			transferred_extra_data
		)
	)

	if new_uid == -1:
		return {
			"success": false
		}

	var removed: Dictionary = (
		source_model.remove_item(uid)
	)

	# 출발지 제거 실패 → 목적지 롤백
	if removed.is_empty():
		target_model.remove_item(
			new_uid
		)

		return {
			"success": false
		}

	return {
		"success": true,
		"transferred": true,
		"old_uid": uid,
		"new_uid": new_uid,
		"item_id": item_id,
		"amount": amount,
		"rotated": rotated,
		"old_cell": old_cell,
		"new_cell": target_cell
	}
