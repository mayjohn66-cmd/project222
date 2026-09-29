class_name ExpeditionLoadoutService
extends RefCounted


static func validate_loadout(
	bag_model
) -> Dictionary:
	if bag_model == null:
		return _failure(
			"원정 가방을 찾을 수 없습니다."
		)

	var type_counts: Dictionary = {}
	var equipped_tool_effects: Dictionary = {}
	var checked_instance_ids: Dictionary = {}

	for placement in bag_model.placements:
		var result: Dictionary = (
			_validate_placement(
				placement,
				type_counts,
				equipped_tool_effects,
				checked_instance_ids
			)
		)

		if not bool(
			result.get(
				"success",
				false
			)
		):
			return result

	return {
		"success": true,
		"message": "",
		"type_counts": type_counts.duplicate(true)
	}


static func can_add_equipment(
	bag_model,
	incoming_placement: Dictionary
) -> Dictionary:
	if bag_model == null:
		return _failure(
			"원정 가방을 찾을 수 없습니다."
		)

	var current_result: Dictionary = (
		validate_loadout(
			bag_model
		)
	)

	if not bool(
		current_result.get(
			"success",
			false
		)
	):
		return current_result

	var type_counts: Dictionary = {}
	var equipped_tool_effects: Dictionary = {}
	var checked_instance_ids: Dictionary = {}

	for placement in bag_model.placements:
		var existing_result: Dictionary = (
			_validate_placement(
				placement,
				type_counts,
				equipped_tool_effects,
				checked_instance_ids
			)
		)

		if not bool(
			existing_result.get(
				"success",
				false
			)
		):
			return existing_result

	return _validate_placement(
		incoming_placement,
		type_counts,
		equipped_tool_effects,
		checked_instance_ids
	)


static func _validate_placement(
	placement: Dictionary,
	type_counts: Dictionary,
	equipped_tool_effects: Dictionary,
	checked_instance_ids: Dictionary
) -> Dictionary:
	var item_id: String = str(
		placement.get(
			"item_id",
			""
		)
	)

	# 재료와 전리품은 장착 제한을 사용하지 않는다.
	if not ExpeditionEquipmentData.has_equipment(
		item_id
	):
		return _success()

	var amount: int = int(
		placement.get(
			"amount",
			0
		)
	)

	if amount != 1:
		return _failure(
			"장비는 한 배치에 한 개만 넣을 수 있습니다."
		)

	var instance_id: int = int(
		placement.get(
			"instance_id",
			-1
		)
	)

	if instance_id <= 0:
		return _failure(
			ItemData.get_item_name(item_id)
			+ "의 장비 ID가 없습니다."
		)

	if checked_instance_ids.has(
		instance_id
	):
		return _failure(
			"같은 장비 인스턴스가 중복 배치되어 있습니다."
		)

	checked_instance_ids[instance_id] = true

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

	if (
		enhancement_level < 0
		or enhancement_level > max_level
	):
		return _failure(
			ItemData.get_item_name(item_id)
			+ "의 강화 단계가 잘못되었습니다."
		)

	var equipment_type: String = (
		ExpeditionEquipmentData.get_equipment_type(
			item_id
		)
	)

	var current_count: int = int(
		type_counts.get(
			equipment_type,
			0
		)
	)

	var next_count: int = current_count + 1

	var max_equipped: int = (
		ExpeditionEquipmentData.get_max_equipped(
			equipment_type
		)
	)

	if (
		max_equipped >= 0
		and next_count > max_equipped
	):
		return _failure(
			_get_limit_message(
				equipment_type,
				max_equipped
			)
		)

	type_counts[equipment_type] = next_count

	var duplicate_policy: String = (
		ExpeditionEquipmentData
		.get_duplicate_policy(
			equipment_type
		)
	)

	if (
		duplicate_policy
		== ExpeditionEquipmentData.DUPLICATE_EFFECT_ID
	):
		var effect_id: String = (
			ExpeditionEquipmentData.get_effect_id(
				item_id
			)
		)

		if effect_id.is_empty():
			return _failure(
				"도구 효과 정보가 없습니다: "
				+ ItemData.get_item_name(item_id)
			)

		if equipped_tool_effects.has(
			effect_id
		):
			var previous_item_id: String = str(
				equipped_tool_effects[
					effect_id
				]
			)

			return _failure(
				"같은 용도의 도구는 함께 장착할 수 없습니다."
				+ "\n"
				+ ItemData.get_item_name(
					previous_item_id
				)
				+ " / "
				+ ItemData.get_item_name(
					item_id
				)
			)

		equipped_tool_effects[effect_id] = item_id

	return _success()


static func _get_limit_message(
	equipment_type: String,
	max_equipped: int
) -> String:
	match equipment_type:
		ExpeditionEquipmentData.TYPE_WEAPON:
			return (
				"무기는 최대 %d개까지 장착할 수 있습니다."
				% max_equipped
			)

		ExpeditionEquipmentData.TYPE_ARMOR:
			return (
				"방어구는 최대 %d개까지 장착할 수 있습니다."
				% max_equipped
			)

		ExpeditionEquipmentData.TYPE_TOOL:
			return (
				"도구는 최대 %d개까지 장착할 수 있습니다."
				% max_equipped
			)

	return (
		"해당 장비는 최대 %d개까지 장착할 수 있습니다."
		% max_equipped
	)


static func _success() -> Dictionary:
	return {
		"success": true,
		"message": ""
	}


static func _failure(
	message: String
) -> Dictionary:
	return {
		"success": false,
		"message": message
	}
