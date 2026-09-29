class_name StoreExpansionData
extends RefCounted


# 매장 확장 단계별 내부 크기를 관리한다.
# 기존 매장 크기인 10×8을 1단계로 사용한다.

const MIN_LEVEL: int = 1
const MAX_LEVEL: int = 4


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
	var safe_level: int = clampi(
		expansion_level,
		MIN_LEVEL,
		MAX_LEVEL
	)

	return STORE_SIZES.get(
		safe_level,
		STORE_SIZES[MIN_LEVEL]
	)


static func can_expand(
	current_level: int
) -> bool:
	return current_level < MAX_LEVEL

# 현재 단계 다음의 확장 단계를 반환한다.
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


# 현재 단계에서 다음 단계로 확장할 때 필요한 비용
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


# 다음 확장 단계의 매장 크기
static func get_next_store_size(
	current_level: int
) -> Vector2i:
	var next_level: int = (
		get_next_level(current_level)
	)

	return get_store_size(
		next_level
	)
