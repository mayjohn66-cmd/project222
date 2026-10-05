extends StaticBody2D

@export var slots_per_level: int = 2
@export var max_stack_level: int = 3
@export var slot_capacity: int = 5



var stack_level: int = 1
var reserved_worker = null

# 각 슬롯 데이터
# {
#     "item_id": "",
#     "stock": 0,
#     "capacity": 5
# }
var slots: Array = []

@onready var stock_label: Label = $StockLabel
@onready var visual = $Visual


const BUILD_AREA_RULES_SCRIPT = preload(
	"res://script/build/model/build_area_rules.gd"
)

var build_area_rules = (
	BUILD_AREA_RULES_SCRIPT.new()
)


# 기존 시스템 임시 호환용
# 지금까지 만든 보충 기능이 깨지지 않도록
# 첫 번째 슬롯을 기존 product_id / stock / capacity처럼 사용한다.
var product_id: String:
	get:
		ensure_slot_count()

		if slots.is_empty():
			return ""

		return str(slots[0]["item_id"])

	set(value):
		ensure_slot_count()

		if slots.is_empty():
			return

		slots[0]["item_id"] = value
		update_stock_label()


var stock: int:
	get:
		ensure_slot_count()

		if slots.is_empty():
			return 0

		return int(slots[0]["stock"])

	set(value):
		ensure_slot_count()

		if slots.is_empty():
			return

		var max_capacity: int = int(slots[0]["capacity"])

		slots[0]["stock"] = clampi(
			value,
			0,
			max_capacity
		)

		update_stock_label()


var capacity: int:
	get:
		ensure_slot_count()

		if slots.is_empty():
			return slot_capacity

		return int(slots[0]["capacity"])

	set(value):
		ensure_slot_count()

		if slots.is_empty():
			return

		slots[0]["capacity"] = max(1, value)
		update_stock_label()



func _ready():
	add_to_group("shelf")

	ensure_slot_count()
	update_visual()
	update_stock_label()


# BuildManager가 1×1 / 2×1에 맞춰 호출
func configure_shelf(
	new_slots_per_level: int,
	new_slot_capacity: int
):
	var build_id := str(get_meta("build_id", ""))
	if ShelfData.has_shelf(build_id):
		max_stack_level = ShelfData.get_max_stack_level(build_id)
	slots_per_level = max(
		1,
		new_slots_per_level
	)

	slot_capacity = max(
		1,
		new_slot_capacity
	)

	# 필요한 슬롯 수 확보
	ensure_slot_count()

	# 중요:
	# _ready()에서 먼저 생성된 기존 슬롯들도
	# 현재 진열대의 수용량으로 다시 맞춘다.
	for index in range(slots.size()):
		var slot: Dictionary = slots[index]

		slot["capacity"] = slot_capacity

		# 혹시 현재 재고가 새 최대치보다 많으면 보정
		slot["stock"] = min(
			int(slot.get("stock", 0)),
			slot_capacity
		)

		slots[index] = slot

	update_visual()
	update_stock_label()

func get_total_slot_count() -> int:
	return slots_per_level * stack_level

func get_next_level_world_position() -> Vector2:
	var level_height: float = 38.0

	if is_instance_valid(visual):
		level_height = float(
			visual.get("furniture_height")
		)

	return global_position + Vector2(
		0,
		-level_height * stack_level
	)

func ensure_slot_count():
	var target_count: int = get_total_slot_count()

	while slots.size() < target_count:
		slots.append(
			{
				"item_id": "",
				"stock": 0,
				"capacity": slot_capacity
			}
		)


func can_add_level() -> bool:
	return stack_level < max_stack_level


func add_level() -> bool:
	if not can_add_level():
		return false

	stack_level += 1

	ensure_slot_count()
	update_visual()
	update_stock_label()

	DebugLog.write(
		"진열대 단 추가: ",
		stack_level,
		"단 / 슬롯 ",
		slots.size(),
		"개"
	)

	return true


func top_level_has_items() -> bool:
	var start_index: int = (
		(stack_level - 1)
		* slots_per_level
	)

	for index in range(start_index, slots.size()):
		var slot: Dictionary = slots[index]

		if int(slot.get("stock", 0)) > 0:
			return true

	return false


func can_remove_level() -> bool:
	if stack_level <= 1:
		return false

	if top_level_has_items():
		return false

	return true


func remove_level() -> bool:
	if not can_remove_level():
		return false

	for i in range(slots_per_level):
		slots.pop_back()

	stack_level -= 1

	update_visual()
	update_stock_label()

	DebugLog.write(
		"진열대 단 제거: ",
		stack_level,
		"단 / 슬롯 ",
		slots.size(),
		"개"
	)

	return true


func update_visual():
	if not is_instance_valid(visual):
		return

	if visual.has_method("set_stack_level"):
		visual.set_stack_level(stack_level)


func update_stock_label():
	if not is_instance_valid(stock_label):
		return

	# Place the caption below the front edge of every footprint size.
	if is_instance_valid(visual):
		var width: int = int(visual.footprint_x)
		var depth: int = int(visual.footprint_y)
		stock_label.position = Vector2(
			(width - depth) * visual.tile_width * 0.25 - 48.0,
			(width + depth - 1) * visual.tile_height * 0.5 + 4.0)

	stock_label.text = (
		str(stack_level)
		+ "단"
		+ " · 슬롯 "
		+ str(slots.size())
	)


func get_interaction_distance(world_pos: Vector2) -> float:
	if not is_instance_valid(visual):
		return global_position.distance_to(world_pos)

	var footprint_x: int = int(
		visual.get("footprint_x")
	)

	var footprint_y: int = int(
		visual.get("footprint_y")
	)

	var nearest_distance: float = INF

	for y in range(footprint_y):
		for x in range(footprint_x):
			var local_point: Vector2 = visual.grid_point(
				float(x),
				float(y)
			)

			var world_point: Vector2 = visual.to_global(
				local_point
			)

			var distance: float = world_pos.distance_to(
				world_point
			)

			nearest_distance = min(
				nearest_distance,
				distance
			)

	return nearest_distance



func get_item_stock(
	item_id: String
) -> int:
	FoodShelfLife.settle()
	var total_stock: int = 0

	for slot in slots:
		var slot_item_id: String = str(
			slot.get(
				"item_id",
				""
			)
		)

		if slot_item_id != item_id:
			continue

		total_stock += maxi(
			int(
				slot.get(
					"stock",
					0
				)
			),
			0
		)

	return total_stock


func take_items_by_id(
	item_id: String,
	requested_amount: int
) -> int:
	if FoodShelfLife.tracked(item_id): return FoodShelfLife.take_shelf(self, item_id, requested_amount)
	if item_id.is_empty():
		return 0

	if requested_amount <= 0:
		return 0

	var remaining_amount: int = (
		requested_amount
	)

	var taken_amount: int = 0

	for index in range(slots.size()):
		if remaining_amount <= 0:
			break

		var slot: Dictionary = slots[index]

		var slot_item_id: String = str(
			slot.get(
				"item_id",
				""
			)
		)

		if slot_item_id != item_id:
			continue

		var slot_stock: int = maxi(
			int(
				slot.get(
					"stock",
					0
				)
			),
			0
		)

		if slot_stock <= 0:
			continue

		var amount_from_slot: int = min(
			slot_stock,
			remaining_amount
		)

		slot["stock"] = (
			slot_stock
			- amount_from_slot
		)

		slots[index] = slot

		taken_amount += amount_from_slot
		remaining_amount -= amount_from_slot

	if taken_amount <= 0:
		return 0

	update_stock_label()

	DebugLog.write(
		"[진열대] 상품 꺼냄: ",
		item_id,
		" / 요청: ",
		requested_amount,
		" / 실제: ",
		taken_amount,
		" / 남은 전체 재고: ",
		get_item_stock(item_id)
	)

	return taken_amount


# 기존 코드와의 호환용
func take_one_item_by_id(
	item_id: String
) -> String:
	var taken_amount: int = (
		take_items_by_id(
			item_id,
			1
		)
	)

	if taken_amount <= 0:
		return ""

	return item_id

func get_customer_access_cells() -> Array[Vector2i]:
	var result: Array[Vector2i] = []

	if not has_meta("anchor"):
		return result

	var build_id: String = str(
		get_meta("build_id", "")
	)

	if build_id.is_empty():
		push_warning(
			"[진열대] 접근 영역을 조회할 build_id가 없음"
		)
		return result

	var build_data: Dictionary = (
		BuildObjectData.get_build_object(build_id)
	)

	if build_data.is_empty():
		return result

	var anchor: Vector2i = get_meta("anchor")

	var saved_rotation: int = int(
		get_meta("rotation_index", 0)
	)

	var base_size: Vector2i = build_data.get(
		"grid_size",
		Vector2i.ZERO
	)

	var current_size: Vector2i = (
		build_area_rules.get_rotated_size(
			base_size,
			saved_rotation
		)
	)

	var offsets: Array[Vector2i] = (
		build_area_rules.get_shelf_access_offsets(
			current_size,
			saved_rotation
		)
	)

	for offset in offsets:
		var cell: Vector2i = anchor + offset

		if not result.has(cell):
			result.append(cell)

	return result


func has_item_in_stock(
	item_id: String
) -> bool:
	FoodShelfLife.settle()

	for slot in slots:
		var slot_item_id: String = str(
			slot.get("item_id", "")
		)

		var slot_stock: int = int(
			slot.get("stock", 0)
		)

		if (
			slot_item_id == item_id
			and slot_stock > 0
		):
			return true

	return false
	
	

func return_items_by_id(
	item_id: String,
	amount: int,
	food_batches: Array = []
) -> int:
	if FoodShelfLife.tracked(item_id): return FoodShelfLife.return_shelf(self, item_id, amount, food_batches)
	if item_id.is_empty():
		return 0

	if amount <= 0:
		return 0

	var remaining_amount: int = amount
	var returned_amount: int = 0

	for index in range(slots.size()):
		if remaining_amount <= 0:
			break

		var slot: Dictionary = slots[index]

		var slot_item_id: String = str(
			slot.get(
				"item_id",
				""
			)
		)

		if slot_item_id != item_id:
			continue

		var slot_stock: int = int(
			slot.get(
				"stock",
				0
			)
		)

		var current_capacity: int = int(
			slot.get(
				"capacity",
				0
			)
		)

		var empty_space: int = maxi(
			current_capacity - slot_stock,
			0
		)

		if empty_space <= 0:
			continue

		var returned_to_slot: int = min(
			remaining_amount,
			empty_space
		)

		slot["stock"] = (
			slot_stock
			+ returned_to_slot
		)

		slots[index] = slot

		returned_amount += returned_to_slot
		remaining_amount -= returned_to_slot

	if returned_amount > 0:
		update_stock_label()

		DebugLog.write(
			"[진열대] 미결제 상품 반환: ",
			item_id,
			" ×",
			returned_amount
		)

	if returned_amount < amount:
		push_warning(
			"[진열대] 상품을 모두 반환하지 못했습니다: "
			+ item_id
			+ " / "
			+ str(returned_amount)
			+ " / "
			+ str(amount)
		)

	return returned_amount

func worker_restock(
	inventory_owner
) -> bool:

	for index in range(slots.size()):
		var slot: Dictionary = slots[index]

		var item_id: String = str(
			slot.get("item_id", "")
		)

		if item_id.is_empty():
			continue

		var slot_stock: int = int(
			slot.get("stock", 0)
		)

		var current_slot_capacity: int = int(
			slot.get("capacity", 0)
		)

		if slot_stock >= current_slot_capacity:
			continue

		var available: int = (
			inventory_owner.get_item_count(
				item_id
			)
		)

		if available <= 0:
			continue

		var needed: int = (
			current_slot_capacity - slot_stock
		)

		var amount: int = min(
			needed,
			available
		)

		var batches := FoodShelfLife.peek_inventory(item_id, amount) if FoodShelfLife.tracked(item_id) else []
		var removed: int = (
			inventory_owner.remove_item(
				item_id,
				amount
			)
		)

		if removed <= 0:
			continue

		slot["stock"] = (
			slot_stock + removed
		)
		FoodShelfLife.add_slot(slot, removed, batches)

		slots[index] = slot

		update_stock_label()

		DebugLog.write(
			"자동 진열: ",
			item_id,
			" +",
			removed
		)

		return true

	return false

func needs_worker_restock(
	inventory_owner
) -> bool:

	for slot in slots:
		var item_id: String = str(
			slot.get("item_id", "")
		)

		if item_id.is_empty():
			continue

		var slot_stock: int = int(
			slot.get("stock", 0)
		)

		var current_slot_capacity: int = int(
			slot.get("capacity", 0)
		)

		if slot_stock >= current_slot_capacity:
			continue

		var available: int = (
			inventory_owner.get_item_count(
				item_id
			)
		)

		if available > 0:
			return true

	return false


func try_reserve_worker(worker_node) -> bool:
	if is_instance_valid(reserved_worker):
		return reserved_worker == worker_node

	reserved_worker = worker_node
	return true


func is_reserved_for_other(worker_node) -> bool:
	if not is_instance_valid(reserved_worker):
		reserved_worker = null
		return false

	return reserved_worker != worker_node


func release_worker_reservation(worker_node):
	if reserved_worker == worker_node:
		reserved_worker = null

func add_stock_to_slot(
	slot_index: int,
	amount: int,
	food_batches: Array = []
) -> int:
	FoodShelfLife.settle()
	if slot_index < 0:
		return 0

	if slot_index >= slots.size():
		return 0

	if amount <= 0:
		return 0

	var slot: Dictionary = slots[slot_index]

	var item_id: String = str(
		slot.get(
			"item_id",
			""
		)
	)

	# 상품이 지정되지 않은 슬롯
	if item_id.is_empty():
		return 0

	var current_stock: int = int(
		slot.get(
			"stock",
			0
		)
	)

	var current_capacity: int = int(
		slot.get(
			"capacity",
			0
		)
	)

	if current_capacity <= 0:
		return 0

	var empty_space: int = (
		current_capacity - current_stock
	)

	if empty_space <= 0:
		return 0

	var added_amount: int = min(
		amount,
		empty_space
	)

	slot["stock"] = (
		current_stock + added_amount
	)
	FoodShelfLife.add_slot(slot, added_amount, food_batches)

	slots[slot_index] = slot

	DebugLog.write(
		"[진열대] 슬롯 ",
		slot_index,
		" / ",
		item_id,
		" ",
		current_stock,
		" → ",
		slot["stock"],
		" / ",
		current_capacity
	)

	update_stock_label()

	return added_amount
