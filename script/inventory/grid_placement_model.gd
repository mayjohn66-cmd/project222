class_name GridPlacementModel
extends RefCounted


var width: int = 6
var height: int = 5

var placements: Array[Dictionary] = []

var next_uid: int = 1


func _init(
	new_width: int = 6,
	new_height: int = 5
) -> void:
	width = new_width
	height = new_height


# =========================
# 배치 가능 여부
# =========================

func can_place(
	item_id: String,
	cell: Vector2i,
	rotated: bool = false,
	ignore_uid: int = -1
) -> bool:
	if not ItemData.has_item(item_id):
		return false

	if not ItemData.can_store_in_expedition_bag(item_id):
		return false

	var item_size: Vector2i = (
		ItemData.get_bag_size(
			item_id,
			rotated
		)
	)

	if item_size == Vector2i.ZERO:
		return false

	if cell.x < 0 or cell.y < 0:
		return false

	if cell.x + item_size.x > width:
		return false

	if cell.y + item_size.y > height:
		return false

	var wanted_cells: Array[Vector2i] = (
		get_cells_for_item(
			cell,
			item_size
		)
	)

	for placement in placements:
		var uid: int = int(
			placement.get(
				"uid",
				-1
			)
		)

		if uid == ignore_uid:
			continue

		var other_item_id: String = str(
			placement.get(
				"item_id",
				""
			)
		)

		var other_cell: Vector2i = (
			placement.get(
				"cell",
				Vector2i.ZERO
			)
		)

		var other_rotated: bool = bool(
			placement.get(
				"rotated",
				false
			)
		)

		var other_size: Vector2i = (
			ItemData.get_bag_size(
				other_item_id,
				other_rotated
			)
		)

		var occupied_cells: Array[Vector2i] = (
			get_cells_for_item(
				other_cell,
				other_size
			)
		)

		for wanted_cell in wanted_cells:
			if occupied_cells.has(
				wanted_cell
			):
				return false

	return true


# =========================
# 아이템 추가
# =========================

func add_item(
	item_id: String,
	cell: Vector2i,
	amount: int = 1,
	rotated: bool = false,
	extra_data: Dictionary = {}
) -> int:
	if amount <= 0:
		return -1

	if not can_place(
		item_id,
		cell,
		rotated
	):
		return -1

	var uid: int = next_uid
	next_uid += 1

	var placement: Dictionary = {
		"uid": uid,
		"item_id": item_id,
		"amount": amount,
		"cell": cell,
		"rotated": rotated
	}

	# 원래 보유 위치 등
	# 격자 자체와 무관한 추가 정보 저장
	for raw_key in extra_data.keys():
		var key: String = str(raw_key)

		# 핵심 데이터는 extra_data가 덮어쓰지 못하게 함
		if (
			key == "uid"
			or key == "item_id"
			or key == "amount"
			or key == "cell"
			or key == "rotated"
		):
			continue

		placement[key] = extra_data[raw_key]

	placements.append(
		placement
	)

	return uid


# =========================
# 내부 이동
# =========================

func move_item(
	uid: int,
	new_cell: Vector2i
) -> bool:
	var placement: Dictionary = (
		get_placement(uid)
	)

	if placement.is_empty():
		return false

	var item_id: String = str(
		placement.get(
			"item_id",
			""
		)
	)

	var rotated: bool = bool(
		placement.get(
			"rotated",
			false
		)
	)

	if not can_place(
		item_id,
		new_cell,
		rotated,
		uid
	):
		return false

	placement["cell"] = new_cell

	return true


# =========================
# 회전
# =========================

func rotate_item(
	uid: int
) -> bool:
	var placement: Dictionary = (
		get_placement(uid)
	)

	if placement.is_empty():
		return false

	var item_id: String = str(
		placement.get(
			"item_id",
			""
		)
	)

	var cell: Vector2i = (
		placement.get(
			"cell",
			Vector2i.ZERO
		)
	)

	var new_rotated: bool = not bool(
		placement.get(
			"rotated",
			false
		)
	)

	if not can_place(
		item_id,
		cell,
		new_rotated,
		uid
	):
		return false

	placement["rotated"] = new_rotated

	return true


# =========================
# 제거
# =========================

func remove_item(
	uid: int
) -> Dictionary:
	for index in range(
		placements.size()
	):
		if int(
			placements[index].get(
				"uid",
				-1
			)
		) != uid:
			continue

		return placements.pop_at(
			index
		)

	return {}


# =========================
# UID로 검색
# =========================

func get_placement(
	uid: int
) -> Dictionary:
	for placement in placements:
		if int(
			placement.get(
				"uid",
				-1
			)
		) == uid:
			return placement

	return {}


# =========================
# 크기만 알고 있을 때 배치 검사
# =========================

func can_place_size(
	cell: Vector2i,
	item_size: Vector2i,
	ignore_uid: int = -1
) -> bool:
	if item_size.x <= 0 or item_size.y <= 0:
		return false

	if cell.x < 0 or cell.y < 0:
		return false

	if cell.x + item_size.x > width:
		return false

	if cell.y + item_size.y > height:
		return false

	var wanted_cells: Array[Vector2i] = (
		get_cells_for_item(
			cell,
			item_size
		)
	)

	for placement in placements:
		var uid: int = int(
			placement.get(
				"uid",
				-1
			)
		)

		if uid == ignore_uid:
			continue

		var other_item_id: String = str(
			placement.get(
				"item_id",
				""
			)
		)

		var other_cell: Vector2i = (
			placement.get(
				"cell",
				Vector2i.ZERO
			)
		)

		var other_rotated: bool = bool(
			placement.get(
				"rotated",
				false
			)
		)

		var other_size: Vector2i = (
			ItemData.get_bag_size(
				other_item_id,
				other_rotated
			)
		)

		var occupied_cells: Array[Vector2i] = (
			get_cells_for_item(
				other_cell,
				other_size
			)
		)

		for wanted_cell in wanted_cells:
			if occupied_cells.has(
				wanted_cell
			):
				return false

	return true


# =========================
# 첫 번째 빈 위치 검색
# =========================

func find_free_position(
	item_id: String,
	rotated: bool = false
) -> Vector2i:
	var item_size: Vector2i = (
		ItemData.get_bag_size(
			item_id,
			rotated
		)
	)

	if item_size == Vector2i.ZERO:
		return Vector2i(-1, -1)

	for y in range(
		height - item_size.y + 1
	):
		for x in range(
			width - item_size.x + 1
		):
			var cell := Vector2i(
				x,
				y
			)

			if can_place(
				item_id,
				cell,
				rotated
			):
				return cell

	return Vector2i(-1, -1)


# =========================
# 아이템이 사용하는 모든 칸
# =========================

func get_cells_for_item(
	start_cell: Vector2i,
	item_size: Vector2i
) -> Array[Vector2i]:
	var result: Array[Vector2i] = []

	for y in range(item_size.y):
		for x in range(item_size.x):
			result.append(
				start_cell
				+ Vector2i(
					x,
					y
				)
			)

	return result


# =========================
# 전체 초기화
# =========================

func clear() -> void:
	placements.clear()
	next_uid = 1

func load_placements(
	saved_placements: Array[Dictionary]
) -> bool:
	# 실제 가방을 변경하지 않고 임시 모델에서 검사
	var restored_model := GridPlacementModel.new(
		width,
		height
	)

	for saved in saved_placements:
		# 변환하기 전에 저장 데이터의 타입 확인
		if (
			not saved.get("item_id", "") is String
			or not saved.get("amount", 1) is int
			or not saved.get("cell") is Vector2i
			or not saved.get("rotated", false) is bool
		):
			push_warning(
				"[격자] 잘못된 저장 배치 데이터: "
				+ str(saved)
			)
			return false

		var item_id: String = saved.get(
			"item_id",
			""
		)

		var amount: int = saved.get(
			"amount",
			1
		)

		var cell: Vector2i = saved["cell"]

		var rotated: bool = saved.get(
			"rotated",
			false
		)

		# 원래 보유 위치 등 부가 정보도 깊은 복사
		# 핵심 필드는 add_item()에서 덮어쓰지 못하게 처리함
		var extra_data: Dictionary = saved.duplicate(true)

		var restored_uid: int = restored_model.add_item(
			item_id,
			cell,
			amount,
			rotated,
			extra_data
		)

		if restored_uid < 0:
			push_warning(
				"[격자] 가방 복원 중단: "
				+ item_id
				+ " / 위치: "
				+ str(cell)
				+ " / 수량: "
				+ str(amount)
			)
			return false

	# 전부 성공한 경우에만 실제 가방 교체
	placements.clear()
	placements.append_array(
		restored_model.placements
	)

	next_uid = restored_model.next_uid

	return true
