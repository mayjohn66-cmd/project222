class_name StoreLotData
extends RefCounted


# =========================
# 편의점 부지 유형
# =========================

# 두 전면 방향에 도로가 있는 모서리형 편의점
const LOT_TYPE_CORNER: String = "corner"

# 한 방향에만 도로가 있는 도로변 편의점
const LOT_TYPE_ROADSIDE: String = "roadside"


const DEFAULT_LOT_TYPE: String = (
	LOT_TYPE_CORNER
)


const VALID_LOT_TYPES: Array[String] = [
	LOT_TYPE_CORNER,
	LOT_TYPE_ROADSIDE
]


# =========================
# 부지 유형 검사
# =========================

static func is_valid_lot_type(
	lot_type: String
) -> bool:
	return VALID_LOT_TYPES.has(
		lot_type
	)


static func normalize_lot_type(
	lot_type: String
) -> String:
	if is_valid_lot_type(
		lot_type
	):
		return lot_type

	return DEFAULT_LOT_TYPE


# =========================
# 고객용 문 방향
# =========================

# 모서리형:
#   방향 1 = 오른쪽 아래 벽
#   방향 2 = 왼쪽 아래 벽
#
# 도로변형:
#   방향 2 = 왼쪽 아래 전면 벽
static func get_customer_door_rotations(
	lot_type: String
) -> Array[int]:
	var normalized_type: String = (
		normalize_lot_type(
			lot_type
		)
	)

	match normalized_type:
		LOT_TYPE_CORNER:
			return [
				1,
				2
			]

		LOT_TYPE_ROADSIDE:
			return [
				2
			]

	return []


static func is_customer_door_rotation_allowed(
	lot_type: String,
	rotation_index: int
) -> bool:
	var normalized_rotation: int = (
		posmod(
			rotation_index,
			4
		)
	)

	return get_customer_door_rotations(
		lot_type
	).has(
		normalized_rotation
	)


static func get_lot_name(
	lot_type: String
) -> String:
	match normalize_lot_type(
		lot_type
	):
		LOT_TYPE_CORNER:
			return "모서리형 편의점"

		LOT_TYPE_ROADSIDE:
			return "도로변 편의점"

	return "알 수 없는 부지"
