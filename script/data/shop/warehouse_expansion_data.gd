class_name WarehouseExpansionData
extends RefCounted


# 단계 규칙은 ExpansionLevelData를 따른다.

const MIN_LEVEL: int = ExpansionLevelData.MIN_LEVEL
const MAX_LEVEL: int = ExpansionLevelData.MAX_LEVEL


const WAREHOUSE_SIZES: Dictionary = {
	1: Vector2i(6, 5),
	2: Vector2i(8, 6),
	3: Vector2i(10, 8),
	4: Vector2i(12, 10)
}


const EXPANSION_COSTS: Dictionary = {
	2: 7000,
	3: 22000,
	4: 55000
}


static func get_warehouse_size(
	expansion_level: int
) -> Vector2i:
	return ExpansionLevelData.get_size(
		WAREHOUSE_SIZES,
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


static func get_next_warehouse_size(
	current_level: int
) -> Vector2i:
	return get_warehouse_size(
		get_next_level(current_level)
	)
