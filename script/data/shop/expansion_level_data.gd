class_name ExpansionLevelData
extends RefCounted


# 매장·창고·생산실이 공유하는 확장 단계 규칙.
# 단계별 크기와 비용 표는 각 확장 데이터 클래스가 가진다.

const MIN_LEVEL: int = 1
const MAX_LEVEL: int = 4


static func clamp_level(
	level: int
) -> int:
	return clampi(
		level,
		MIN_LEVEL,
		MAX_LEVEL
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

	return clamp_level(
		current_level + 1
	)


# costs는 {확장할 단계: 비용} 표이다.
static func get_expansion_cost(
	costs: Dictionary,
	current_level: int
) -> int:
	if not can_expand(current_level):
		return 0

	return int(
		costs.get(
			get_next_level(current_level),
			0
		)
	)


# sizes는 {단계: 크기} 표이다.
static func get_size(
	sizes: Dictionary,
	level: int
) -> Vector2i:
	return sizes.get(
		clamp_level(level),
		sizes[MIN_LEVEL]
	)
