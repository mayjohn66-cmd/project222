class_name StoreExpansionData
extends RefCounted


# 매장 확장 단계별 내부 크기를 관리한다.
# 기존 매장 크기인 10×8을 1단계로 사용한다.
# 단계 규칙은 ExpansionLevelData를 따른다.

const MIN_LEVEL: int = ExpansionLevelData.MIN_LEVEL
const MAX_LEVEL: int = ExpansionLevelData.MAX_LEVEL


const STORE_SIZES: Dictionary = {
	1: Vector2i(10, 8),
	2: Vector2i(12, 10),
	3: Vector2i(14, 12),
	4: Vector2i(16, 14)
}

# 해당 단계로 확장할 때 필요한 비용
# 1단계는 기본 매장이므로 비용이 없다.
const EXPANSION_COSTS: Dictionary = {
	2: 5000,
	3: 15000,
	4: 40000
}


static func get_store_size(
	expansion_level: int
) -> Vector2i:
	return ExpansionLevelData.get_size(
		STORE_SIZES,
		expansion_level
	)


static func can_expand(
	current_level: int
) -> bool:
	return ExpansionLevelData.can_expand(
		current_level
	)


# 현재 단계 다음의 확장 단계를 반환한다.
static func get_next_level(
	current_level: int
) -> int:
	return ExpansionLevelData.get_next_level(
		current_level
	)


# 현재 단계에서 다음 단계로 확장할 때 필요한 비용
static func get_expansion_cost(
	current_level: int
) -> int:
	return ExpansionLevelData.get_expansion_cost(
		EXPANSION_COSTS,
		current_level
	)


# 다음 확장 단계의 매장 크기
static func get_next_store_size(
	current_level: int
) -> Vector2i:
	return get_store_size(
		get_next_level(current_level)
	)
