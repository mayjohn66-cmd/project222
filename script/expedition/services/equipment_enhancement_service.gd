class_name EquipmentEnhancementService
extends RefCounted


# =========================
# 강화 가능 여부
# =========================

static func can_enhance(
	placement: Dictionary
) -> bool:
	return bool(
		get_enhancement_check(
			placement
		).get(
			"success",
			false
		)
	)


static func get_enhancement_check(
	placement: Dictionary
) -> Dictionary:
	if placement.is_empty():
		return _failure(
			"강화할 장비를 찾을 수 없습니다."
		)

	var item_id: String = str(
		placement.get(
			"item_id",
			""
		)
	)

	if not ExpeditionEquipmentData.has_equipment(
		item_id
	):
		return _failure(
			"등록되지 않은 장비입니다."
		)

	if not ExpeditionEquipmentData.is_enhanceable(
		item_id
	):
		return _failure(
			"강화할 수 없는 장비입니다."
		)

	var instance_id: int = int(
		placement.get(
			"instance_id",
			-1
		)
	)

	if instance_id <= 0:
		return _failure(
			"장비 인스턴스 정보가 없습니다."
		)

	var current_level: int = int(
		placement.get(
			"enhancement_level",
			0
		)
	)

	var max_level: int = (
		ExpeditionEquipmentData
		.get_max_enhancement_level(
			item_id
		)
	)

	if current_level < 0:
		return _failure(
			"현재 강화 단계가 잘못되었습니다."
		)

	if current_level >= max_level:
		return {
			"success": false,
			"message": "이미 최대 단계까지 강화되었습니다.",
			"item_id": item_id,
			"instance_id": instance_id,
			"current_level": current_level,
			"target_level": current_level,
			"max_level": max_level,
			"costs": {},
			"missing_materials": {}
		}

	var target_level: int = (
		current_level + 1
	)

	var costs: Dictionary = (
		ExpeditionEquipmentData
		.get_enhancement_cost(
			item_id,
			target_level
		)
	)

	if costs.is_empty():
		return _failure(
			"강화 비용을 찾을 수 없습니다."
		)

	var missing_materials: Dictionary = {}

	for raw_material_id in costs.keys():
		var material_id: String = str(
			raw_material_id
		)

		var required_amount: int = int(
			costs.get(
				material_id,
				0
			)
		)

		var owned_amount: int = (
			GameState.get_item_count(
				material_id
			)
		)

		if owned_amount >= required_amount:
			continue

		missing_materials[material_id] = (
			required_amount - owned_amount
		)

	if not missing_materials.is_empty():
		return {
			"success": false,
			"message": "강화 재료가 부족합니다.",
			"item_id": item_id,
			"instance_id": instance_id,
			"current_level": current_level,
			"target_level": target_level,
			"max_level": max_level,
			"costs": costs.duplicate(true),
			"missing_materials": (
				missing_materials.duplicate(true)
			)
		}

	return {
		"success": true,
		"message": "",
		"item_id": item_id,
		"instance_id": instance_id,
		"current_level": current_level,
		"target_level": target_level,
		"max_level": max_level,
		"costs": costs.duplicate(true),
		"missing_materials": {}
	}


# =========================
# 실제 강화
# =========================

static func enhance_equipment(
	placement: Dictionary
) -> Dictionary:
	var check: Dictionary = (
		get_enhancement_check(
			placement
		)
	)

	if not bool(
		check.get(
			"success",
			false
		)
	):
		return check

	var item_id: String = str(
		check.get(
			"item_id",
			""
		)
	)

	var instance_id: int = int(
		check.get(
			"instance_id",
			-1
		)
	)

	var target_level: int = int(
		check.get(
			"target_level",
			0
		)
	)

	var costs: Dictionary = (
		check.get(
			"costs",
			{}
		)
	)

	var consumed: Dictionary = {}

	# 전체 검사가 끝난 뒤 재료를 차감한다.
	for raw_material_id in costs.keys():
		var material_id: String = str(
			raw_material_id
		)

		var required_amount: int = int(
			costs.get(
				material_id,
				0
			)
		)

		var removed_amount: int = (
			GameState.remove_item(
				material_id,
				required_amount
			)
		)

		consumed[material_id] = (
			removed_amount
		)

		if removed_amount == required_amount:
			continue

		_refund_materials(consumed)

		return _failure(
			"강화 재료 차감 중 문제가 발생했습니다."
		)

	# 장비가 보유 장비 목록에 있다면
	# GameState의 원본 인스턴스도 같이 갱신한다.
	if GameState.has_owned_equipment_instance(
		instance_id
	):
		if not GameState.set_equipment_instance_level(
			instance_id,
			target_level
		):
			_refund_materials(consumed)

			return _failure(
				"보유 장비의 강화 단계를 저장하지 못했습니다."
			)

	# 가방 안 장비는 배치 Dictionary가 원본 데이터다.
	placement["enhancement_level"] = (
		target_level
	)

	var final_value: int = (
		get_effective_value(
			placement
		)
	)

	print(
		"[장비 강화] 완료 / ",
		ItemData.get_item_name(
			item_id
		),
		" / 인스턴스: ",
		instance_id,
		" / +",
		target_level,
		" / 최종 성능: ",
		final_value
	)

	return {
		"success": true,
		"message": "강화가 완료되었습니다.",
		"item_id": item_id,
		"instance_id": instance_id,
		"previous_level": target_level - 1,
		"new_level": target_level,
		"final_value": final_value,
		"consumed": consumed.duplicate(true)
	}


# =========================
# 최종 장비 성능
# =========================

static func get_effective_value(
	placement: Dictionary
) -> int:
	if placement.is_empty():
		return 0

	var item_id: String = str(
		placement.get(
			"item_id",
			""
		)
	)

	if not ExpeditionEquipmentData.has_equipment(
		item_id
	):
		return 0

	var base_value: int = roundi(
		ExpeditionEquipmentData.get_base_value(
			item_id
		)
	)

	var enhancement_level: int = int(
		placement.get(
			"enhancement_level",
			0
		)
	)

	var max_level: int = (
		ExpeditionEquipmentData
		.get_max_enhancement_level(
			item_id
		)
	)

	var safe_level: int = clampi(
		enhancement_level,
		0,
		max_level
	)

	# 현재는 강화 1단계당 성능 +1
	return base_value + safe_level


# =========================
# 재료 반환
# =========================

static func _refund_materials(
	consumed: Dictionary
) -> void:
	for raw_material_id in consumed.keys():
		var material_id: String = str(
			raw_material_id
		)

		var amount: int = int(
			consumed.get(
				material_id,
				0
			)
		)

		if amount <= 0:
			continue

		GameState.add_item(
			material_id,
			amount
		)

	push_warning(
		"[장비 강화] 처리 실패 / 차감 재료 반환"
	)


static func _failure(
	message: String
) -> Dictionary:
	return {
		"success": false,
		"message": message,
		"item_id": "",
		"instance_id": -1,
		"current_level": 0,
		"target_level": 0,
		"max_level": 0,
		"costs": {},
		"missing_materials": {}
	}
