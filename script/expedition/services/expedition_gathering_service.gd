class_name ExpeditionGatheringService
extends RefCounted


func resolve_gathering(
	loot_table_id: String,
	expedition_bag,
	loot_service,
	difficulty: int = 1
) -> Dictionary:
	ExpeditionGatheringData.ensure_loaded()

	# 채집 규칙이 없는 테이블은 기존 전리품 처리로 넘긴다.
	if not ExpeditionGatheringData.has_rule(
		loot_table_id
	):
		return {
			"handled": false,
			"success": true
		}

	var rule: Dictionary = (
		ExpeditionGatheringData.get_rule(
			loot_table_id
		)
	)

	var required_effect_id: String = str(
		rule.get(
			"tool_effect_id",
			""
		)
	)

	var tool_placement: Dictionary = (
		_find_tool_placement(
			expedition_bag,
			required_effect_id
		)
	)

	var has_tool: bool = (
		not tool_placement.is_empty()
	)

	var tool_required: bool = bool(
		rule.get(
			"tool_required",
			false
		)
	)

	if tool_required and not has_tool:
		return {
			"handled": true,
			"success": true,
			"gathered": false,
			"message": (
				"필요한 채집 도구가 없어 채집할 수 없었다."
			)
		}

	var success_rate: float

	if has_tool:
		success_rate = float(
			rule.get(
				"tool_success_rate",
				1.0
			)
		)
	else:
		success_rate = float(
			rule.get(
				"no_tool_success_rate",
				0.0
			)
		)

	success_rate = clampf(
		success_rate,
		0.0,
		1.0
	)

	var roll: float = randf()

	DebugLog.write(
		"[채집 판정]"
		+ " / 테이블: ",
		loot_table_id,
		" / 도구: ",
		has_tool,
		" / 성공률: ",
		success_rate,
		" / 주사위: ",
		roll
	)

	if roll > success_rate:
		var failure_message: String

		if has_tool:
			failure_message = (
				"도구를 사용했지만 채집에 실패했다."
			)
		else:
			failure_message = (
				"도구 없이 채집을 시도했지만 실패했다."
			)

		return {
			"handled": true,
			"success": true,
			"gathered": false,
			"message": failure_message
		}

	if loot_service == null:
		return _system_failure(
			"전리품 서비스를 찾지 못했습니다."
		)

	var loot_result: Dictionary = (
		loot_service.roll_loot_table(
			loot_table_id,
			difficulty
		)
	)

	if not bool(
		loot_result.get(
			"success",
			false
		)
	):
		return _system_failure(
			str(
				loot_result.get(
					"message",
					"전리품 추첨 실패"
				)
			)
		)

	var item_id: String = str(
		loot_result.get(
			"item_id",
			""
		)
	)

	var base_amount: int = int(
		loot_result.get(
			"amount",
			0
		)
	)

	if (
		item_id.is_empty()
		or base_amount <= 0
	):
		return _system_failure(
			"채집 결과가 올바르지 않습니다."
		)

	var bonus_amount: int = 0
	var tool_name: String = ""

	if has_tool:
		var enhancement_level: int = maxi(
			int(
				tool_placement.get(
					"enhancement_level",
					0
				)
			),
			0
		)

		var base_tool_bonus: int = maxi(
			int(
				rule.get(
					"tool_bonus_amount",
					0
				)
			),
			0
		)

		var bonus_per_level: int = maxi(
			int(
				rule.get(
					"enhancement_bonus_per_level",
					0
				)
			),
			0
		)

		bonus_amount = (
			base_tool_bonus
			+ enhancement_level
			* bonus_per_level
		)

		var tool_item_id: String = str(
			tool_placement.get(
				"item_id",
				""
			)
		)

		tool_name = ItemData.get_item_name(
			tool_item_id
		)

	var final_amount: int = (
		base_amount + bonus_amount
	)

	var result_message: String

	if has_tool:
		result_message = (
			"%s을 사용해 채집했다."
			% tool_name
		)

		if bonus_amount > 0:
			result_message += (
				"\n도구 효과로 %s을(를) %d개 더 얻었다."
				% [
					ItemData.get_item_name(item_id),
					bonus_amount
				]
			)
	else:
		result_message = (
			"도구 없이 채집에 성공했다."
		)

	return {
		"handled": true,
		"success": true,
		"gathered": true,
		"item_id": item_id,
		"base_amount": base_amount,
		"bonus_amount": bonus_amount,
		"amount": final_amount,
		"message": result_message
	}


func _find_tool_placement(
	expedition_bag,
	required_effect_id: String
) -> Dictionary:
	if expedition_bag == null:
		return {}

	if required_effect_id.is_empty():
		return {}

	var best_placement: Dictionary = {}
	var best_level: int = -1

	for placement in expedition_bag.placements:
		var item_id: String = str(
			placement.get(
				"item_id",
				""
			)
		)

		if not ExpeditionEquipmentData.has_equipment(
			item_id
		):
			continue

		var equipment_type: String = (
			ExpeditionEquipmentData.get_equipment_type(
				item_id
			)
		)

		if (
			equipment_type
			!= ExpeditionEquipmentData.TYPE_TOOL
		):
			continue

		var effect_id: String = (
			ExpeditionEquipmentData.get_effect_id(
				item_id
			)
		)

		if effect_id != required_effect_id:
			continue

		var level: int = int(
			placement.get(
				"enhancement_level",
				0
			)
		)

		if level <= best_level:
			continue

		best_level = level
		best_placement = placement

	return best_placement


func _system_failure(
	message: String
) -> Dictionary:
	return {
		"handled": true,
		"success": false,
		"gathered": false,
		"message": message
	}
