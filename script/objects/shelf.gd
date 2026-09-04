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

	print(
		"진열대 단 추가: ",
		stack_level,
		"단 / 슬롯 ",
		slots.size(),
		"개"
	)

	return true


func top_level_has_items() -> bool:
	if stack_level <= 1:
		return false

	var start_index: int = (
		(stack_level - 1)
		* slots_per_level
	)

	for index in range(start_index, slots.size()):
		if int(slots[index]["stock"]) > 0:
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

	print(
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


# 기존 보충 시스템 임시 호환
# 현재는 첫 번째 슬롯에 상품을 넣는다.
func add_stock(amount: int) -> int:
	ensure_slot_count()

	if slots.is_empty():
		return 0

	if product_id.is_empty():
		print("이 진열대에는 상품이 지정되지 않음")
		return 0

	if stock >= capacity:
		print("진열대가 이미 가득 참")
		return 0

	var available_space: int = capacity - stock
	var added_amount: int = min(amount, available_space)

	stock += added_amount

	update_stock_label()

	return added_amount


# 기존 상품 지정 기능 임시 호환
func set_product(new_product_id: String) -> void:
	if not ItemData.has_item(new_product_id):
		return

	if not ItemData.is_shelf_allowed(new_product_id):
		return

	product_id = new_product_id
	update_stock_label()


func get_product_name() -> String:
	if product_id.is_empty():
		return "상품 없음"

	return ItemData.get_item_name(
		product_id
	)


func update_stock_label():
	if not is_instance_valid(stock_label):
		return

	# 지금은 슬롯 시스템 테스트용 표시
	stock_label.text = (
		str(stack_level)
		+ "단"
		+ "\n슬롯 "
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



func has_sellable_stock() -> bool:
	for slot in slots:
		var item_id: String = str(
			slot.get("item_id", "")
		)

		var slot_stock: int = int(
			slot.get("stock", 0)
		)

		if not item_id.is_empty() and slot_stock > 0:
			return true

	return false

func take_one_item_by_id(
	item_id: String
) -> String:

	for index in range(slots.size()):
		var slot: Dictionary = slots[index]

		var slot_item_id: String = str(
			slot.get("item_id", "")
		)

		var slot_stock: int = int(
			slot.get("stock", 0)
		)

		if slot_item_id != item_id:
			continue

		if slot_stock <= 0:
			continue

		slot["stock"] = slot_stock - 1
		slots[index] = slot

		update_stock_label()

		print(
			"상품 꺼냄: ",
			item_id,
			" / 남은 재고: ",
			slot["stock"]
		)

		return item_id

	return ""

func get_customer_access_cells() -> Array[Vector2i]:
	var anchor: Vector2i = get_meta(
		"anchor",
		Vector2i(-1, -1)
	)

	var rotation_index: int = int(
		get_meta(
			"rotation_index",
			0
		)
	)

	var catalog_index: int = int(
		get_meta(
			"catalog_index",
			0
		)
	)

	var size: Vector2i = Vector2i(1, 1)

	match catalog_index:
		0:
			size = Vector2i(1, 1)

		1:
			size = Vector2i(2, 1)

		2:
			size = Vector2i(3, 1)

	if rotation_index % 2 == 1:
		size = Vector2i(
			size.y,
			size.x
		)

	var result: Array[Vector2i] = []

	match rotation_index % 4:

		0:
			for x in range(size.x):
				result.append(
					anchor + Vector2i(x, size.y)
				)

		1:
			for y in range(size.y):
				result.append(
					anchor + Vector2i(size.x, y)
				)

		2:
			for x in range(size.x):
				result.append(
					anchor + Vector2i(x, -1)
				)

		3:
			for y in range(size.y):
				result.append(
					anchor + Vector2i(-1, y)
				)

	return result

func has_item_in_stock(
	item_id: String
) -> bool:

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

		slots[index] = slot

		update_stock_label()

		print(
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
	amount: int
) -> int:
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

	slots[slot_index] = slot

	print(
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
