extends Node2D


@export var storage_capacity: int = 40
@export var storage_slot_count: int = 12


# 기존 저장 데이터 및 다른 코드와의 호환용
# 실제 창고 데이터는 storage_slots가 관리한다.
var stored_items: Dictionary = {}


# 각 슬롯 구조:
# {
#     "item_id": String,
#     "amount": int
# }
var storage_slots: Array[Dictionary] = []


func _ready() -> void:
	FurnitureObjectCatalog.configure_storage(self, str(get_meta("build_id", "")))
	add_to_group(
		"warehouse_storage"
	)

	storage_capacity = maxi(
		storage_capacity,
		1
	)

	storage_slot_count = maxi(
		storage_slot_count,
		1
	)

	var legacy_items: Dictionary = (
		stored_items.duplicate(true)
	)

	_ensure_storage_slots()

	# 기존 Dictionary 방식의 데이터가 있다면
	# 슬롯 방식으로 자동 변환한다.
	if not legacy_items.is_empty():
		if not apply_stored_items(
			legacy_items
		):
			push_warning(
				"[창고 선반] 기존 보관 데이터를 슬롯으로 변환하지 못했습니다."
			)
	else:
		_rebuild_stored_items()


# =========================================================
# 슬롯 기본 처리
# =========================================================

func _create_empty_slot() -> Dictionary:
	return {
		"item_id": "",
		"amount": 0
	}


func _ensure_storage_slots() -> void:
	while storage_slots.size() < storage_slot_count:
		storage_slots.append(
			_create_empty_slot()
		)


func _is_valid_slot_index(
	slot_index: int
) -> bool:
	_ensure_storage_slots()

	return (
		slot_index >= 0
		and slot_index < storage_slots.size()
	)


func get_storage_slots() -> Array[Dictionary]:
	FoodShelfLife.settle()
	_ensure_storage_slots()

	var result: Array[Dictionary] = []

	for slot in storage_slots:
		result.append(
			slot.duplicate(true)
		)

	return result


func get_slot_item_id(
	slot_index: int
) -> String:
	if not _is_valid_slot_index(
		slot_index
	):
		return ""

	return str(
		storage_slots[
			slot_index
		].get(
			"item_id",
			""
		)
	)


func get_slot_item_count(
	slot_index: int
) -> int:
	if not _is_valid_slot_index(
		slot_index
	):
		return 0

	return maxi(
		int(
			storage_slots[
				slot_index
			].get(
				"amount",
				0
			)
		),
		0
	)


func _clear_storage_slots() -> void:
	storage_slots.clear()
	_ensure_storage_slots()


# 슬롯 데이터를 기존 Dictionary 형식으로 다시 만든다.
func _rebuild_stored_items() -> void:
	stored_items.clear()

	for slot in storage_slots:
		var item_id: String = str(
			slot.get(
				"item_id",
				""
			)
		)

		var amount: int = maxi(
			int(
				slot.get(
					"amount",
					0
				)
			),
			0
		)

		if item_id.is_empty():
			continue

		if amount <= 0:
			continue

		stored_items[item_id] = (
			int(
				stored_items.get(
					item_id,
					0
				)
			)
			+ amount
		)


# =========================================================
# 보관량
# =========================================================

func get_total_stored_amount() -> int:
	FoodShelfLife.settle()
	_ensure_storage_slots()

	var total: int = 0

	for slot in storage_slots:
		total += maxi(
			int(
				slot.get(
					"amount",
					0
				)
			),
			0
		)

	return total


func get_remaining_capacity() -> int:
	return maxi(
		storage_capacity
			- get_total_stored_amount(),
		0
	)


func get_item_count(
	item_id: String
) -> int:
	FoodShelfLife.settle()
	if item_id.is_empty():
		return 0

	_ensure_storage_slots()

	var total: int = 0

	for slot in storage_slots:
		if str(
			slot.get(
				"item_id",
				""
			)
		) != item_id:
			continue

		total += maxi(
			int(
				slot.get(
					"amount",
					0
				)
			),
			0
		)

	return total


# =========================================================
# 슬롯 검색
# =========================================================

func find_item_slot(
	item_id: String
) -> int:
	_ensure_storage_slots()

	for slot_index in range(
		storage_slots.size()
	):
		if get_slot_item_id(
			slot_index
		) == item_id:
			return slot_index

	return -1


func find_empty_slot() -> int:
	_ensure_storage_slots()

	for slot_index in range(
		storage_slots.size()
	):
		var item_id: String = (
			get_slot_item_id(
				slot_index
			)
		)

		var amount: int = (
			get_slot_item_count(
				slot_index
			)
		)

		if (
			item_id.is_empty()
			or amount <= 0
		):
			return slot_index

	return -1


# =========================================================
# 입고 가능 여부
# =========================================================

func get_max_deposit_amount_for_slot(
	slot_index: int,
	item_id: String
) -> int:
	if not _is_valid_slot_index(
		slot_index
	):
		return 0

	if item_id.is_empty():
		return 0

	var current_item_id: String = (
		get_slot_item_id(
			slot_index
		)
	)

	if (
		not current_item_id.is_empty()
		and current_item_id != item_id
	):
		return 0

	var owned_amount: int = (
		GameState.get_item_count(
			item_id
		)
	)

	return mini(
		owned_amount,
		get_remaining_capacity()
	)


# =========================================================
# 지정 슬롯 입고
# =========================================================

func deposit_from_inventory_to_slot(
	slot_index: int,
	item_id: String,
	requested_amount: int
) -> int:
	if not _is_valid_slot_index(
		slot_index
	):
		return 0

	if item_id.is_empty():
		return 0

	if requested_amount <= 0:
		return 0

	var max_amount: int = (
		get_max_deposit_amount_for_slot(
			slot_index,
			item_id
		)
	)

	var moved_amount: int = mini(
		requested_amount,
		max_amount
	)

	if moved_amount <= 0:
		return 0

	var batches := FoodShelfLife.peek_inventory(item_id, moved_amount) if FoodShelfLife.tracked(item_id) else []
	var removed_amount: int = (
		GameState.remove_item(
			item_id,
			moved_amount
		)
	)

	if removed_amount <= 0:
		return 0

	var slot: Dictionary = (
		storage_slots[
			slot_index
		].duplicate(true)
	)

	slot["item_id"] = item_id
	slot["amount"] = (
		maxi(
			int(
				slot.get(
					"amount",
					0
				)
			),
			0
		)
		+ removed_amount
	)
	FoodShelfLife.add_slot(slot, removed_amount, batches, "amount")

	storage_slots[
		slot_index
	] = slot

	_rebuild_stored_items()

	DebugLog.write(
		"[창고 선반] 입고 / 슬롯 ",
		slot_index,
		" / ",
		item_id,
		" ×",
		removed_amount
	)

	return removed_amount


# =========================================================
# 기존 방식 입고
# =========================================================

func deposit_from_inventory(
	item_id: String,
	requested_amount: int
) -> int:
	if item_id.is_empty():
		return 0

	if requested_amount <= 0:
		return 0

	var target_slot_index: int = (
		find_item_slot(
			item_id
		)
	)

	if target_slot_index < 0:
		target_slot_index = (
			find_empty_slot()
		)

	if target_slot_index < 0:
		return 0

	return deposit_from_inventory_to_slot(
		target_slot_index,
		item_id,
		requested_amount
	)


func get_max_move_amount_between_slots(
	source_slot_index: int,
	target_slot_index: int
) -> int:
	if not _is_valid_slot_index(
		source_slot_index
	):
		return 0

	if not _is_valid_slot_index(
		target_slot_index
	):
		return 0

	if source_slot_index == target_slot_index:
		return 0

	var source_item_id: String = (
		get_slot_item_id(
			source_slot_index
		)
	)

	var source_amount: int = (
		get_slot_item_count(
			source_slot_index
		)
	)

	if source_item_id.is_empty():
		return 0

	if source_amount <= 0:
		return 0

	return source_amount

func move_item_between_slots(
	source_slot_index: int,
	target_slot_index: int,
	requested_amount: int
) -> int:
	FoodShelfLife.settle()
	var maximum_amount: int = (
		get_max_move_amount_between_slots(
			source_slot_index,
			target_slot_index
		)
	)

	if maximum_amount <= 0:
		return 0

	var source_slot: Dictionary = (
		storage_slots[
			source_slot_index
		].duplicate(true)
	)

	var target_slot: Dictionary = (
		storage_slots[
			target_slot_index
		].duplicate(true)
	)

	var source_item_id: String = str(
		source_slot.get(
			"item_id",
			""
		)
	)

	var target_item_id: String = str(
		target_slot.get(
			"item_id",
			""
		)
	)

	var source_amount: int = maxi(
		int(
			source_slot.get(
				"amount",
				0
			)
		),
		0
	)

	var target_amount: int = maxi(
		int(
			target_slot.get(
				"amount",
				0
			)
		),
		0
	)

	# ========================================
	# 대상에 다른 아이템이 있으면 전체 교환
	# ========================================

	if (
		not target_item_id.is_empty()
		and target_item_id != source_item_id
	):
		storage_slots[
			source_slot_index
		] = target_slot

		storage_slots[
			target_slot_index
		] = source_slot

		_rebuild_stored_items()

		DebugLog.write(
			"[창고 선반] 슬롯 교환 / ",
			source_slot_index,
			" ↔ ",
			target_slot_index,
			" / ",
			source_item_id,
			" ↔ ",
			target_item_id
		)

		return source_amount

	# ========================================
	# 빈 슬롯 또는 같은 아이템이면 수량 이동
	# ========================================

	var moved_amount: int = mini(
		requested_amount,
		source_amount
	)

	if moved_amount <= 0:
		return 0

	var remaining_source_amount: int = (
		source_amount - moved_amount
	)

	var batches: Array = []
	if FoodShelfLife.tracked(source_item_id): batches = FoodShelfLife.take(FoodShelfLife.slot_batches(source_slot, "amount"), moved_amount)
	target_slot["item_id"] = source_item_id
	target_slot["amount"] = (
		target_amount + moved_amount
	)
	FoodShelfLife.add_slot(target_slot, moved_amount, batches, "amount")

	if remaining_source_amount <= 0:
		source_slot = _create_empty_slot()
	else:
		source_slot["amount"] = (
			remaining_source_amount
		)

	storage_slots[
		source_slot_index
	] = source_slot

	storage_slots[
		target_slot_index
	] = target_slot

	_rebuild_stored_items()

	if target_item_id == source_item_id:
		DebugLog.write(
			"[창고 선반] 슬롯 합치기 / ",
			source_slot_index,
			" → ",
			target_slot_index,
			" / ",
			source_item_id,
			" ×",
			moved_amount
		)
	else:
		DebugLog.write(
			"[창고 선반] 빈 슬롯 이동 / ",
			source_slot_index,
			" → ",
			target_slot_index,
			" / ",
			source_item_id,
			" ×",
			moved_amount
		)

	return moved_amount

# =========================================================
# 지정 슬롯 출고
# =========================================================

func withdraw_slot_to_inventory(
	slot_index: int,
	requested_amount: int
) -> int:
	FoodShelfLife.settle()
	if not _is_valid_slot_index(
		slot_index
	):
		return 0

	if requested_amount <= 0:
		return 0

	var slot: Dictionary = (
		storage_slots[
			slot_index
		].duplicate(true)
	)

	var item_id: String = str(
		slot.get(
			"item_id",
			""
		)
	)

	var stored_amount: int = maxi(
		int(
			slot.get(
				"amount",
				0
			)
		),
		0
	)

	if item_id.is_empty():
		return 0

	var moved_amount: int = mini(
		requested_amount,
		stored_amount
	)

	if moved_amount <= 0:
		return 0

	var batches: Array = []
	if FoodShelfLife.tracked(item_id): batches = FoodShelfLife.take(FoodShelfLife.slot_batches(slot, "amount"), moved_amount)
	var remaining_amount: int = (
		stored_amount - moved_amount
	)

	if remaining_amount <= 0:
		slot = _create_empty_slot()
	else:
		slot["amount"] = remaining_amount

	storage_slots[
		slot_index
	] = slot

	GameState.add_item(
		item_id,
		moved_amount,
		batches
	)

	_rebuild_stored_items()

	DebugLog.write(
		"[창고 선반] 출고 / 슬롯 ",
		slot_index,
		" / ",
		item_id,
		" ×",
		moved_amount
	)

	return moved_amount


# =========================================================
# 기존 방식 출고
# =========================================================

# =========================================================
# 저장 데이터
# =========================================================

# 기존 Dictionary 저장 형식과의 호환용
func get_stored_items() -> Dictionary:
	FoodShelfLife.settle()
	_rebuild_stored_items()

	return stored_items.duplicate(
		true
	)


# 새 슬롯 저장 형식
func get_stored_slots() -> Array[Dictionary]:
	return get_storage_slots()


# 기존 Dictionary 데이터를 슬롯으로 복구
func apply_stored_items(
	data: Dictionary
) -> bool:
	var restored_total: int = 0
	var item_ids: Array[String] = []

	for raw_item_id in data.keys():
		if not raw_item_id is String:
			return false

		var item_id: String = str(
			raw_item_id
		)

		if not ItemData.has_item(
			item_id
		):
			return false

		if not data[item_id] is int:
			return false

		var amount: int = int(
			data[item_id]
		)

		if amount < 0:
			return false

		if amount == 0:
			continue

		restored_total += amount
		item_ids.append(
			item_id
		)

	if restored_total > storage_capacity:
		return false

	if item_ids.size() > storage_slot_count:
		return false

	item_ids.sort()

	_clear_storage_slots()

	for slot_index in range(
		item_ids.size()
	):
		var item_id: String = (
			item_ids[
				slot_index
			]
		)

		storage_slots[
			slot_index
		] = {
			"item_id": item_id,
			"amount": int(
				data[item_id]
			)
		}

	_rebuild_stored_items()

	return true


# 새 슬롯 데이터를 그대로 복구
func apply_stored_slots(
	data: Array
) -> bool:
	if data.size() > storage_slot_count:
		return false

	var restored_slots: Array[Dictionary] = []
	var restored_total: int = 0

	for raw_slot in data:
		if not raw_slot is Dictionary:
			return false

		var slot: Dictionary = raw_slot

		var item_id: String = str(
			slot.get(
				"item_id",
				""
			)
		)

		var amount: int = int(
			slot.get(
				"amount",
				0
			)
		)

		if amount < 0:
			return false

		if item_id.is_empty():
			if amount > 0:
				return false

			restored_slots.append(
				_create_empty_slot()
			)

			continue

		if not ItemData.has_item(
			item_id
		):
			return false

		if amount <= 0:
			return false

		restored_total += amount

		restored_slots.append(
			{
				"item_id": item_id,
				"amount": amount
			}
		)
		if slot.has("food_batches"):
			if not FoodShelfLife.valid_batches(slot["food_batches"], amount, GameState.total_day): return false
			restored_slots[-1]["food_batches"] = slot["food_batches"].duplicate(true)

	if restored_total > storage_capacity:
		return false

	while restored_slots.size() < storage_slot_count:
		restored_slots.append(
			_create_empty_slot()
		)

	storage_slots = restored_slots

	_rebuild_stored_items()

	return true


# =========================================================
# 철거 및 정보
# =========================================================

func can_remove_storage() -> bool:
	return get_total_stored_amount() <= 0
