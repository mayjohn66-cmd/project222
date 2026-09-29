class_name ProductionRoomExpansionData
extends RefCounted


# 단계 규칙은 ExpansionLevelData를 따른다.

const MIN_LEVEL: int = ExpansionLevelData.MIN_LEVEL
const MAX_LEVEL: int = ExpansionLevelData.MAX_LEVEL


const ROOM_SIZES: Dictionary = {
	1: Vector2i(6, 6),
	2: Vector2i(8, 7),
	3: Vector2i(10, 8),
	4: Vector2i(12, 10)
}


# 해당 단계로 확장할 때 필요한 비용
const EXPANSION_COSTS: Dictionary = {
	2: 8000,
	3: 25000,
	4: 60000
}


static func get_room_size(
	expansion_level: int
) -> Vector2i:
	return ExpansionLevelData.get_size(
		ROOM_SIZES,
		expansion_level
	)


static func can_expand(
	current_level: int
) -> bool:
	return ExpansionLevelData.can_expand(
		current_level
	)


static func get_next_level(
	current_level: int
) -> int:
	return ExpansionLevelData.get_next_level(
		current_level
	)


static func get_expansion_cost(
	current_level: int
) -> int:
	return ExpansionLevelData.get_expansion_cost(
		EXPANSION_COSTS,
		current_level
	)


static func get_next_room_size(
	current_level: int
) -> Vector2i:
	return get_room_size(
		get_next_level(current_level)
	)
