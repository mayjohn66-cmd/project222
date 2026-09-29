class_name WarehouseExpansionData
extends RefCounted


const MIN_LEVEL: int = 1
const MAX_LEVEL: int = 4


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
	var safe_level: int = clampi(
		expansion_level,
		MIN_LEVEL,
		MAX_LEVEL
	)

	return WAREHOUSE_SIZES.get(
		safe_level,
		WAREHOUSE_SIZES[MIN_LEVEL]
	)


static func can_expand(
	current_level: int
) -> bool:
	return current_level < MAX_LEVEL


static func get_next_level(
	current_level: int
) -> int:
	if not can_expand(current_level):
		return MAX_LEVEL

	return clampi(
		current_level + 1,
		MIN_LEVEL,
		MAX_LEVEL
	)


static func get_expansion_cost(
	current_level: int
) -> int:
	if not can_expand(current_level):
		return 0

	var next_level: int = (
		get_next_level(current_level)
	)

	return int(
		EXPANSION_COSTS.get(
			next_level,
			0
		)
	)


static func get_next_warehouse_size(
	current_level: int
) -> Vector2i:
	return get_warehouse_size(
		get_next_level(
			current_level
		)
	)
