class_name GridDragHelper
extends RefCounted


# =========================
# 아이템 UI 안에서
# 어느 칸을 잡았는지 계산
# =========================

static func get_grab_offset_from_local(
	at_position: Vector2,
	item_size: Vector2i,
	cell_size: int
) -> Vector2i:
	if cell_size <= 0:
		return Vector2i.ZERO

	return Vector2i(
		clampi(
			floori(
				at_position.x
				/ float(cell_size)
			),
			0,
			item_size.x - 1
		),
		clampi(
			floori(
				at_position.y
				/ float(cell_size)
			),
			0,
			item_size.y - 1
		)
	)


# =========================
# 드롭할 아이템의 실제 시작 칸
# =========================

static func get_target_start_cell(
	cursor_cell: Vector2i,
	data: Dictionary
) -> Vector2i:
	var grab_offset: Vector2i = (
		data.get(
			"grab_offset_cell",
			Vector2i.ZERO
		)
	)

	return (
		cursor_cell
		- grab_offset
	)


# =========================
# 공통 드래그 데이터 생성
# =========================

static func make_drag_data(
	source: String,
	uid: int,
	item_id: String,
	rotated: bool,
	grab_offset_cell: Vector2i,
	extra_data: Dictionary = {}
) -> Dictionary:
	var result: Dictionary = {
		"source": source,
		"uid": uid,
		"item_id": item_id,
		"rotated": rotated,
		"grab_offset_cell": grab_offset_cell
	}

	for raw_key in extra_data.keys():
		var key: String = str(
			raw_key
		)

		if (
			key == "source"
			or key == "uid"
			or key == "item_id"
			or key == "rotated"
			or key == "grab_offset_cell"
		):
			continue

		result[key] = extra_data[raw_key]

	return result
