extends Node

# 씬이 바뀌어도 유지되어야 하는 게임 진행 데이터를 보관한다.
# UI 노드를 직접 다루지 않으며, 저장 가능한 값과 도메인 상태만 관리한다.


const RESUME_SCENE_STORE: String = "store"
const RESUME_SCENE_EXPEDITION: String = "expedition"


var resume_scene_id: String = RESUME_SCENE_STORE
var expedition_checkpoint: Dictionary = {}


# =========================
# 게임 진행 상태
# =========================

var current_day: int = 1
var total_day: int = 1
var preservation_state: Dictionary = {}


# =========================
# 플레이어 상태
# =========================

var player_state: Dictionary = {}


# =========================
# 편의점 상태
# =========================

var store_layout: Array[Dictionary] = []

# =========================
# 소지금
# =========================

var money: int = 0
var saved_expedition_bag: Array[Dictionary] = []

var furniture_inventory: Dictionary = {}
var furniture_inventory_initialized: bool = false

const BUILD_QUICK_SLOT_COUNT: int = 9

var build_quick_slots: Array[String] = []
var first_settlement_done: bool = false

const SAVE_VERSION: int = 1
const SAVE_PATH: String = GameConfig.SAVE_PATH
const SAVE_TEST_PATH: String = GameConfig.SAVE_TEST_PATH


signal furniture_inventory_changed(
	furniture_id: String,
	count: int
)

signal build_quick_slot_changed(
	slot_index: int,
	previous_build_id: String,
	new_build_id: String
)

signal store_event_discovered(
	event_id: String,
	discovery_day: int
)

signal store_expansion_changed(
	previous_level: int,
	new_level: int,
	new_store_size: Vector2i
)

signal production_room_expansion_changed(
	previous_level: int,
	new_level: int,
	new_room_size: Vector2i
)

signal warehouse_expansion_changed(
	previous_level: int,
	new_level: int,
	new_warehouse_size: Vector2i
)

var discovered_store_events: Dictionary = {}
var daily_shop_history: Array[Dictionary] = []
var employee_states: Dictionary = {}


# =========================
# 직원 급여 상태
# =========================

var employee_salary_records: Dictionary = {}
var unpaid_employee_salary: int = 0


# 현재 본점 내부의 확장 단계
var store_expansion_level: int = 1

# 본점 생산실의 현재 확장 단계
var production_room_expansion_level: int = 1

# 현재 본점이 사용하는 외부 부지 유형
var store_lot_type: String = (
	StoreLotData.DEFAULT_LOT_TYPE
)

# 본점 창고의 현재 확장 단계
var warehouse_expansion_level: int = 1

# ================================================================= #


# =========================
# 플레이어 상태 저장
# =========================

func save_player_state(
	data: Dictionary
):
	player_state = data.duplicate(true)

	DebugLog.write(
		"[GameState] 플레이어 상태 저장"
	)

# 가방 밖에 보관 중인 무기·방어구·도구
# 같은 item_id라도 서로 다른 강화 단계를 가질 수 있다.
var owned_equipment_instances: Array[Dictionary] = []

var next_equipment_instance_id: int = 1

var inventory: Dictionary = {}

const PLAYER_INVENTORY_SLOT_COUNT: int = 12
const PLAYER_INVENTORY_STACK_LIMIT: int = 999

var inventory_slots: Array[Dictionary] = []

# 도구는 종류별로 하나만 보유하므로
# item_id를 기준으로 강화 단계를 저장한다.
var tool_enhancement_levels: Dictionary = {}

func _ready() -> void:
	initialize_new_game()


	set_build_quick_slot(
		0,
		"shelf_1x1"
	)

	set_build_quick_slot(
		1,
		"drink_machine"
	)

	DebugLog.write(
		"[GameState] 초기 상태 준비 완료"
	)


# =========================
# 새 게임 초기화
# =========================

func initialize_new_game():
	for key in ["shop_return_context","shop_expedition_prep"]:
		if has_meta(key): remove_meta(key)
	current_day = 1
	total_day = 1
	preservation_state = PreservationService.initial_state(total_day)

	PlayerProgress.reset()
	BlacksmithProgressionRecords.new_game()

	store_expansion_level = (
		StoreExpansionData.MIN_LEVEL
	)

	store_lot_type = (
		StoreLotData.DEFAULT_LOT_TYPE
	)

	production_room_expansion_level = (
		ProductionRoomExpansionData.MIN_LEVEL
	)

	warehouse_expansion_level = (
		WarehouseExpansionData.MIN_LEVEL
	)

	player_state.clear()
	store_layout.clear()
	saved_expedition_bag.clear()
	discovered_store_events.clear()
	daily_shop_history.clear()

	employee_states.clear()
	employee_salary_records.clear()
	unpaid_employee_salary = 0
	ensure_employee_salary_records()

	inventory.clear()
	owned_equipment_instances.clear()
	next_equipment_instance_id = 1
	tool_enhancement_levels.clear()
	furniture_inventory.clear()
	furniture_inventory_initialized = false
	initialize_furniture_inventory()
	initialize_build_quick_slots()
	money = GameConfig.STARTING_MONEY
	first_settlement_done = false
	clear_expedition_checkpoint()

	for raw_item_id in GameConfig.STARTING_INVENTORY.keys():

		var item_id: String = str(raw_item_id)
		var amount: int = int(
			GameConfig.STARTING_INVENTORY[item_id]
		)

		if not ItemData.has_item(item_id):
			push_warning(
				"[GameState] 등록되지 않은 시작 아이템: "
				+ item_id
			)
			continue

		if amount <= 0:
			push_warning(
				"[GameState] 잘못된 시작 수량: "
				+ item_id
				+ " / "
				+ str(amount)
			)
			continue

		inventory[item_id] = amount

	if not rebuild_inventory_slots_from_counts():
		push_error(
			"[GameState] 시작 인벤토리를 슬롯으로 변환하지 못했습니다."
		)

	DebugLog.write(
		"[GameState] 초기 인벤토리 생성: ",
		inventory
	)

	DebugLog.write(
		"[GameState] 초기 소지금: ",
		money,
		" G"
	)

func get_player_state() -> Dictionary:
	return player_state.duplicate(true)


func has_player_state() -> bool:
	return not player_state.is_empty()


func save_store_layout(
	layout: Array[Dictionary]
):
	store_layout = layout.duplicate(true)

	DebugLog.write(
		"[GameState] 편의점 배치 저장 / ",
		store_layout.size(),
		"개"
	)


func get_store_layout() -> Array[Dictionary]:
	return store_layout.duplicate(true)


func has_store_layout() -> bool:
	return not store_layout.is_empty()

func create_empty_inventory_slot() -> Dictionary:
	return {
		"item_id": "",
		"amount": 0
	}



func rebuild_inventory_slots_from_counts() -> bool:
	# Counts are the saved source of truth. The legacy slot projection must
	# represent actual inventory, including more than the initial twelve slots.
	inventory_slots = InventoryCountSlots.build(inventory, PLAYER_INVENTORY_SLOT_COUNT, PLAYER_INVENTORY_STACK_LIMIT)
	return true


# =========================
# 일반 아이템 인벤토리
# =========================

func get_item_count(
	item_id: String
) -> int:
	PreservationService.settle()
	return int(
		inventory.get(
			item_id,
			0
		)
	)


func add_item(
	item_id: String,
	amount: int,
	food_batches: Array = []
) -> void:
	if not ItemData.has_item(item_id):
		push_warning(
			"[GameState] 등록되지 않은 아이템 추가 시도: "
			+ item_id
		)
		return

	if amount <= 0:
		return

	inventory[item_id] = (
		get_item_count(item_id)
		+ amount
	)
	FoodShelfLife.inventory_added(item_id, amount, food_batches)
	PreservationLessonRecords.record_found(item_id)


func remove_item(
	item_id: String,
	amount: int
) -> int:
	if amount <= 0:
		return 0

	var current_count: int = (
		get_item_count(item_id)
	)

	var removed_amount: int = min(
		amount,
		current_count
	)

	FoodShelfLife.inventory_removed(item_id, removed_amount)
	inventory[item_id] = (
		current_count - removed_amount
	)

	return removed_amount


func get_inventory_data() -> Dictionary:
	PreservationService.settle()
	return inventory.duplicate(true)


func get_money() -> int:
	return money


func add_money(amount: int) -> void:
	if amount <= 0:
		return

	money += amount

func can_afford(amount: int) -> bool:
	if amount < 0:
		return false

	return money >= amount


func spend_money(amount: int) -> bool:
	if amount <= 0:
		return false

	if not can_afford(amount):
		return false

	money -= amount
	return true

func save_expedition_bag(
	placements: Array[Dictionary]
) -> void:
	saved_expedition_bag.clear()

	for placement in placements:
		saved_expedition_bag.append(
			placement.duplicate(true)
		)

	DebugLog.write(
		"[GameState] 원정 가방 저장 / 아이템 수: ",
		saved_expedition_bag.size()
	)


func get_saved_expedition_bag() -> Array[Dictionary]:
	var result: Array[Dictionary] = []

	for placement in saved_expedition_bag:
		result.append(
			placement.duplicate(true)
		)

	return result


# =========================
# 가구 인벤토리
# =========================

func initialize_furniture_inventory() -> void:
	if furniture_inventory_initialized:
		return

	furniture_inventory.clear()

	var path: String = (
		"res://data/shop/catalogs/starting_furniture.csv"
	)

	if not FileAccess.file_exists(path):
		push_error(
			"[GameState] starting_furniture.csv 없음"
		)
		return

	var file := FileAccess.open(
		path,
		FileAccess.READ
	)

	if file == null:
		push_error(
			"[GameState] starting_furniture.csv 열기 실패"
		)
		return

	# 헤더
	if not file.eof_reached():
		file.get_csv_line()

	while not file.eof_reached():
		var row := file.get_csv_line()

		if row.is_empty():
			continue

		if row.size() < 2:
			continue

		var furniture_id: String = str(
			row[0]
		).strip_edges()

		var count: int = int(
			row[1]
		)

		if furniture_id.is_empty():
			continue

		furniture_inventory[
			furniture_id
		] = max(
			count,
			0
		)

	furniture_inventory_initialized = true

	DebugLog.write(
		"[GameState] 초기 가구 인벤토리 생성: ",
		furniture_inventory
	)


func get_furniture_count(
	furniture_id: String
) -> int:
	initialize_furniture_inventory()

	return int(
		furniture_inventory.get(
			furniture_id,
			0
		)
	)


func add_furniture(
	furniture_id: String,
	amount: int = 1
) -> void:
	if amount <= 0:
		return

	initialize_furniture_inventory()

	furniture_inventory[
		furniture_id
	] = (
		get_furniture_count(
			furniture_id
		)
		+ amount
	)

	furniture_inventory_changed.emit(
		furniture_id,
		get_furniture_count(
			furniture_id
		)
	)


func remove_furniture(
	furniture_id: String,
	amount: int = 1
) -> int:
	if amount <= 0:
		return 0

	initialize_furniture_inventory()

	var current: int = (
		get_furniture_count(
			furniture_id
		)
	)

	var removed: int = min(
		current,
		amount
	)

	furniture_inventory[
		furniture_id
	] = current - removed

	furniture_inventory_changed.emit(
		furniture_id,
		get_furniture_count(
			furniture_id
		)
	)

	return removed


func has_furniture(
	furniture_id: String,
	amount: int = 1
) -> bool:
	return (
		get_furniture_count(
			furniture_id
		)
		>= amount
	)

func get_furniture_inventory_ids() -> Array[String]:
	initialize_furniture_inventory()

	var result: Array[String] = []

	for raw_furniture_id in furniture_inventory.keys():
		result.append(
			str(raw_furniture_id)
		)

	return result

# =========================
# 건축 퀵슬롯
# =========================

func initialize_build_quick_slots() -> void:
	build_quick_slots.clear()

	for _i in range(BUILD_QUICK_SLOT_COUNT):
		build_quick_slots.append("")

	DebugLog.write(
		"[GameState] 건축 퀵슬롯 초기화 / 슬롯 수: ",
		build_quick_slots.size()
	)


func is_valid_build_quick_slot_index(
	slot_index: int
) -> bool:
	return (
		slot_index >= 0
		and slot_index < BUILD_QUICK_SLOT_COUNT
		and slot_index < build_quick_slots.size()
	)


func set_build_quick_slot(
	slot_index: int,
	build_id: String
) -> bool:
	if not is_valid_build_quick_slot_index(
		slot_index
	):
		return false

	if (
		not build_id.is_empty()
		and not FurnitureData.has_furniture(build_id)
	):
		push_warning(
			"[GameState] 존재하지 않는 가구 ID: "
			+ build_id
		)

		return false

	var previous_build_id: String = (
		build_quick_slots[slot_index]
	)

	# 같은 값이면 변경할 필요 없음
	if previous_build_id == build_id:
		return true

	build_quick_slots[slot_index] = build_id

	build_quick_slot_changed.emit(
		slot_index,
		previous_build_id,
		build_id
	)

	if build_id.is_empty():
		DebugLog.write(
			"[건축 퀵슬롯] 해제 / ",
			slot_index + 1,
			"번"
		)
	else:
		DebugLog.write(
			"[건축 퀵슬롯] 등록 / ",
			slot_index + 1,
			"번 = ",
			build_id
		)

	return true


func get_build_quick_slot(
	slot_index: int
) -> String:
	if not is_valid_build_quick_slot_index(
		slot_index
	):
		return ""

	return build_quick_slots[slot_index]


func clear_build_quick_slot(
	slot_index: int
) -> void:
	set_build_quick_slot(
		slot_index,
		""
	)


func find_build_quick_slot(
	build_id: String
) -> int:
	if build_id.is_empty():
		return -1

	for slot_index in range(
		build_quick_slots.size()
	):
		if (
			build_quick_slots[slot_index]
			== build_id
		):
			return slot_index

	return -1


# =========================
# 저장 파일 직렬화 및 복원
# =========================

func create_save_data() -> Dictionary:
	PreservationService.settle()
	FoodShelfLife.prepare_save()
	return {
		"save_version": SAVE_VERSION,
		"current_day": current_day,
		"total_day": total_day,
		"money": money,
		"employee_salary_records": employee_salary_records.duplicate(true),
		"store_expansion_level": get_store_expansion_level(),
		"production_room_expansion_level": get_production_room_expansion_level(),
		"warehouse_expansion_level": get_warehouse_expansion_level(),
		"store_lot_type": get_store_lot_type(),
		"unpaid_employee_salary": unpaid_employee_salary,
		"player_state": player_state.duplicate(true),
		"inventory": inventory.duplicate(true),
		"preservation": preservation_state.duplicate(true),
		"furniture_inventory": furniture_inventory.duplicate(true),
		"build_quick_slots": build_quick_slots.duplicate(),
		"store_layout": store_layout.duplicate(true),
		"saved_expedition_bag": saved_expedition_bag.duplicate(true),
		"discovered_store_events": discovered_store_events.duplicate(true),
		"daily_shop_history": daily_shop_history.duplicate(true),
		"employee_states": employee_states.duplicate(true),
		"first_settlement_done": first_settlement_done,
		"tool_enhancement_levels": tool_enhancement_levels.duplicate(true),
		"owned_equipment_instances": owned_equipment_instances.duplicate(true),
		"next_equipment_instance_id": next_equipment_instance_id,
		"resume_scene_id": resume_scene_id,
		"expedition_checkpoint": expedition_checkpoint.duplicate(true),
		"progress": PlayerProgress.to_save_data(),
	}

func write_save_file(
	data: Dictionary,
	path: String = SAVE_PATH
) -> bool:
	var file := FileAccess.open(
		path,
		FileAccess.WRITE
	)

	if file == null:
		push_error(
			"[저장] 파일 열기 실패: "
			+ path
			+ " / 오류: "
			+ str(FileAccess.get_open_error())
		)
		return false

	# 노드나 객체를 저장하지 않고 데이터만 기록
	file.store_var(data, false)
	file.flush()

	var write_error: Error = file.get_error()
	file.close()

	if write_error != OK:
		push_error(
			"[저장] 기록 실패 / 오류: "
			+ str(write_error)
		)
		return false

	DebugLog.write("[저장] 파일 기록 완료: ", path)
	return true

func read_save_file(
	path: String = SAVE_PATH
) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}

	var file := FileAccess.open(
		path,
		FileAccess.READ
	)

	if file == null:
		push_error(
			"[불러오기] 파일 열기 실패: "
			+ path
		)
		return {}

	var loaded: Variant = file.get_var(false)
	var read_error: Error = file.get_error()
	file.close()

	if read_error != OK:
		push_error(
			"[불러오기] 파일 읽기 실패 / 오류: "
			+ str(read_error)
		)
		return {}

	if not loaded is Dictionary:
		push_error("[불러오기] 저장 데이터 형식이 잘못됨")
		return {}

	var data: Dictionary = loaded

	if data.get("save_version", -1) != SAVE_VERSION:
		push_error("[불러오기] 지원하지 않는 저장 버전")
		return {}

	return data


func is_save_data_valid(data: Dictionary) -> bool:
	if not SaveProgressGuard.valid(data): return false
	if not FoodShelfLife.valid_save(data): return false
	if data.has("preservation") and not PreservationService.valid_state(data["preservation"], int(data.get("total_day", data.get("current_day", 1)))):
		return false
	if data.get("save_version", -1) != SAVE_VERSION:
		return false

	if not data.get("current_day") is int:
		return false

	if int(data["current_day"]) < 1:
		return false

	# 기존 저장 파일에는 total_day가 없을 수 있으므로
	# 값이 들어 있을 때만 검사한다.
	if data.has("total_day"):
		if not data.get("total_day") is int:
			return false

		if int(data["total_day"]) < 1:
			return false

	if not data.get("money") is int:
		return false

	if int(data["money"]) < 0:
		return false

	if not data.get("player_state") is Dictionary:
		return false

	if data.has(
		"warehouse_expansion_level"
	):
		if not data.get(
			"warehouse_expansion_level"
		) is int:
			return false

		var warehouse_level: int = int(
			data["warehouse_expansion_level"]
		)

		if (
			warehouse_level
			< WarehouseExpansionData.MIN_LEVEL
			or warehouse_level
			> WarehouseExpansionData.MAX_LEVEL
		):
			return false

	# 상품·가구 수량 검사
	for key in ["inventory", "furniture_inventory"]:
		if not data.get(key) is Dictionary:
			return false

		var counts: Dictionary = data[key]

		for item_id in counts:
			if not item_id is String:
				return false

			if not counts[item_id] is int:
				return false

			if int(counts[item_id]) < 0:
				return false

	if data.has("store_expansion_level"):
		if not data.get(
			"store_expansion_level"
		) is int:
			return false

		var saved_expansion_level: int = int(
			data["store_expansion_level"]
		)

		if (
			saved_expansion_level
			< StoreExpansionData.MIN_LEVEL
			or saved_expansion_level
			> StoreExpansionData.MAX_LEVEL
		):
			return false

	if data.has("store_lot_type"):
		if not data.get(
			"store_lot_type"
		) is String:
			return false

	# 퀵슬롯 검사
	if not data.get("build_quick_slots") is Array:
		return false

	var saved_slots: Array = data["build_quick_slots"]

	if saved_slots.size() != BUILD_QUICK_SLOT_COUNT:
		return false

	for build_id in saved_slots:
		if not build_id is String:
			return false

	# 배치·가방의 기본 구조 검사
	for key in ["store_layout", "saved_expedition_bag"]:
		if not data.get(key) is Array:
			return false

		for entry in data[key]:
			if not entry is Dictionary:
				return false

	if data.has("tool_enhancement_levels"):
		if not data.get(
			"tool_enhancement_levels"
		) is Dictionary:
			return false

		var saved_tool_levels: Dictionary = (
			data["tool_enhancement_levels"]
		)

		for raw_item_id in saved_tool_levels.keys():
			if not raw_item_id is String:
				return false

			var item_id: String = str(
				raw_item_id
			)

			if not ExpeditionEquipmentData.has_equipment(item_id):
				return false

			if not saved_tool_levels[item_id] is int:
				return false

			var level: int = int(
				saved_tool_levels[item_id]
			)

			var tool_data: Dictionary = (
				ExpeditionEquipmentData.get_equipment_data(item_id)
			)

			var max_level: int = int(
				tool_data.get(
					"max_enhancement_level",
					0
				)
			)

			if level < 0 or level > max_level:
				return false

	# 개별 장비 인스턴스 검사
	if data.has("owned_equipment_instances"):
		if not data.get(
			"owned_equipment_instances"
		) is Array:
			return false

		var checked_instance_ids: Array[int] = []

		for instance_data in data[
			"owned_equipment_instances"
		]:
			if not instance_data is Dictionary:
				return false

			if not is_equipment_instance_data_valid(
				instance_data
			):
				return false

			var instance_id: int = int(
				instance_data.get(
					"instance_id",
					-1
				)
			)

			if checked_instance_ids.has(
				instance_id
			):
				return false

			checked_instance_ids.append(
				instance_id
			)

	if data.has("next_equipment_instance_id"):
		if not data.get(
			"next_equipment_instance_id"
		) is int:
			return false

		if int(
			data["next_equipment_instance_id"]
		) <= 0:
			return false

	# 현재 복원 코드가 사용하는 배치 필드 검사
	for entry in data["store_layout"]:
		if not entry.get("anchor") is Vector2i:
			return false

		if not entry.get("rotation_index", 0) is int:
			return false

		if not entry.get("build_id", "") is String:
			return false

		if not entry.get("catalog_index", -1) is int:
			return false

		if not entry.get("stack_level", 1) is int:
			return false

		if entry.has("shelf_slots"):
			if not entry["shelf_slots"] is Array:
				return false

			for slot in entry["shelf_slots"]:
				if not slot is Dictionary:
					return false

				if not slot.get("item_id", "") is String:
					return false

				if not slot.get("stock", 0) is int:
					return false

				if int(slot.get("stock", 0)) < 0:
					return false

				if not slot.get("capacity", 0) is int:
					return false

		# 창고 슬롯 데이터 검사
		# 예전 저장 파일에는 storage_slots가 없을 수 있으므로
		# 필드가 있을 때만 검사한다.
		if entry.has("storage_slots"):
			if not entry["storage_slots"] is Array:
				return false

			for slot in entry["storage_slots"]:
				if not slot is Dictionary:
					return false

				if not slot.get(
					"item_id",
					""
				) is String:
					return false

				if not slot.get(
					"amount",
					0
				) is int:
					return false

				var warehouse_item_id: String = str(
					slot.get(
						"item_id",
						""
					)
				)

				var warehouse_amount: int = int(
					slot.get(
						"amount",
						0
					)
				)

				if warehouse_amount < 0:
					return false

				# 빈 슬롯은 수량도 0이어야 한다.
				if (
					warehouse_item_id.is_empty()
					and warehouse_amount != 0
				):
					return false

				# 아이템이 있는 슬롯은 수량이 1 이상이어야 한다.
				if (
					not warehouse_item_id.is_empty()
					and warehouse_amount <= 0
				):
					return false

				if (
					not warehouse_item_id.is_empty()
					and not ItemData.has_item(
						warehouse_item_id
					)
				):
					return false

	if not data.get("first_settlement_done", false) is bool:
		return false

	if data.has(
		"discovered_store_events"
	):
		if not data.get(
			"discovered_store_events"
		) is Dictionary:
			return false

		var discovered_events: Dictionary = (
			data["discovered_store_events"]
		)

		for raw_event_id in discovered_events.keys():
			if not raw_event_id is String:
				return false

			if not discovered_events[
				raw_event_id
			] is int:
				return false

			if int(
				discovered_events[raw_event_id]
			) < 1:
				return false

	if data.has(
		"daily_shop_history"
	):
		if not data.get(
			"daily_shop_history"
		) is Array:
			return false

		for record in data["daily_shop_history"]:
			if not record is Dictionary:
				return false

			if not record.get(
				"total_day"
			) is int:
				return false

			if int(
				record["total_day"]
			) < 1:
				return false

			if not record.get(
				"weekday"
			) is int:
				return false

			var saved_weekday: int = int(
				record["weekday"]
			)

			if saved_weekday < 1 or saved_weekday > 7:
				return false

			for number_key in [
				"visitors",
				"sales",
				"missed",
				"revenue"
			]:
				if not record.get(
					number_key
				) is int:
					return false

				if int(
					record[number_key]
				) < 0:
					return false

			for dictionary_key in [
				"visitors_by_customer_type",
				"sold_items",
				"unmet_demand"
			]:
				if not record.get(
					dictionary_key
				) is Dictionary:
					return false

				var counts: Dictionary = (
					record[dictionary_key]
				)

				for raw_id in counts.keys():
					if not raw_id is String:
						return false

					if not counts[raw_id] is int:
						return false

					if int(counts[raw_id]) < 0:
						return false

			for salary_key in [
				"salary_due",
				"salary_paid",
				"unpaid_salary"
			]:
				if not record.has(salary_key):
					continue

				if not record.get(salary_key) is int:
					return false

				if int(record[salary_key]) < 0:
					return false

			if record.has("net_cash_flow"):
				if not record.get(
					"net_cash_flow"
				) is int:
					return false

	if data.has(
		"production_room_expansion_level"
	):
		if not data.get(
			"production_room_expansion_level"
		) is int:
			return false

		var production_level: int = int(
			data["production_room_expansion_level"]
		)

		if (
			production_level
			< ProductionRoomExpansionData.MIN_LEVEL
			or production_level
			> ProductionRoomExpansionData.MAX_LEVEL
		):
			return false

	# 이전 저장 파일은 직원 데이터가 없어도 허용
	if data.has("employee_states"):
		if not data["employee_states"] is Dictionary:
			return false

		var saved_employees: Dictionary = data["employee_states"]

		for raw_employee_id in saved_employees:
			if not raw_employee_id is String:
				return false

			if str(raw_employee_id).is_empty():
				return false

			if not saved_employees[raw_employee_id] is Dictionary:
				return false

			var employee_data: Dictionary = (
				saved_employees[raw_employee_id]
			)

			if not is_employee_state_valid(employee_data):
				return false

	if data.has("unpaid_employee_salary"):
		if not data.get(
			"unpaid_employee_salary"
		) is int:
			return false

		if int(
			data["unpaid_employee_salary"]
		) < 0:
			return false

	return true


func apply_save_data(data: Dictionary) -> bool:
	if not is_save_data_valid(data):
		push_error("[불러오기] 저장 데이터 검사 실패")
		return false

	employee_salary_records = (
		data.get(
			"employee_salary_records",
			{}
		).duplicate(true)
	)

	unpaid_employee_salary = maxi(
		int(
			data.get(
				"unpaid_employee_salary",
				0
			)
		),
		0
	)

	# 기존 저장 파일에 직원 급여 기록이 없다면 자동 생성
	ensure_employee_salary_records()

	PlayerProgress.load_save_data(
		data.get(
			"progress",
			{}
		)
	)

	warehouse_expansion_level = clampi(
		int(
			data.get(
				"warehouse_expansion_level",
				WarehouseExpansionData.MIN_LEVEL
			)
		),
		WarehouseExpansionData.MIN_LEVEL,
		WarehouseExpansionData.MAX_LEVEL
	)

	# 타입이 지정된 배열을 먼저 준비
	var restored_layout: Array[Dictionary] = []

	for entry in data["store_layout"]:
		restored_layout.append(
			entry.duplicate(true)
		)

	var restored_bag: Array[Dictionary] = []

	for entry in data["saved_expedition_bag"]:
		restored_bag.append(
			entry.duplicate(true)
		)

	var restored_quick_slots: Array[String] = []

	for build_id in data["build_quick_slots"]:
		restored_quick_slots.append(build_id)

		# 검사가 끝난 데이터를 적용
	current_day = int(data["current_day"])


	var restored_shop_history: Array[Dictionary] = []

	if data.has(
		"daily_shop_history"
	):
		for record in data["daily_shop_history"]:
			restored_shop_history.append(
				record.duplicate(true)
			)


	var restored_discovered_events: Dictionary = {}

	if data.has(
		"discovered_store_events"
	):
		restored_discovered_events = (
			data["discovered_store_events"].duplicate(true)
		)

	# 예전 저장 파일에는 total_day가 없으므로
	# 현재 요일을 첫 주의 날짜로 사용한다.
	total_day = int(
		data.get(
			"total_day",
			current_day
		)
	)

	money = int(data["money"])
	store_expansion_level = clampi(
		int(
			data.get(
				"store_expansion_level",
				StoreExpansionData.MIN_LEVEL
			)
		),
		StoreExpansionData.MIN_LEVEL,
		StoreExpansionData.MAX_LEVEL
	)

	production_room_expansion_level = clampi(
		int(
			data.get(
				"production_room_expansion_level",
				ProductionRoomExpansionData.MIN_LEVEL
			)
		),
		ProductionRoomExpansionData.MIN_LEVEL,
		ProductionRoomExpansionData.MAX_LEVEL
	)

	store_lot_type = (
		StoreLotData.normalize_lot_type(
			str(
				data.get(
					"store_lot_type",
					StoreLotData.DEFAULT_LOT_TYPE
				)
			)
		)
	)
	first_settlement_done = bool(
		data.get("first_settlement_done", false)
	)


	player_state = data["player_state"].duplicate(true)
	inventory = data["inventory"].duplicate(true)
	preservation_state = data.get("preservation", PreservationService.initial_state(total_day)).duplicate(true)

	if not rebuild_inventory_slots_from_counts():
		push_error(
			"[불러오기] 플레이어 인벤토리 슬롯 변환 실패"
		)
		return false

	furniture_inventory = (
		data["furniture_inventory"].duplicate(true)
	)

	var saved_tool_levels: Dictionary = (
		data.get(
			"tool_enhancement_levels",
			{}
		)
	)

	tool_enhancement_levels = (
		saved_tool_levels.duplicate(true)
	)

	# 시작 가구 CSV로 다시 초기화되지 않도록 표시
	furniture_inventory_initialized = true

	store_layout = restored_layout
	saved_expedition_bag = restored_bag
	build_quick_slots = restored_quick_slots
	daily_shop_history = restored_shop_history

	# 직원 정보가 없는 옛 저장은 CSV 기본값을 사용하도록 비움
	employee_states = {}

	if data.has("employee_states"):
		employee_states = data["employee_states"].duplicate(true)

	discovered_store_events = (
		restored_discovered_events
	)

	owned_equipment_instances.clear()

	var saved_equipment_instances: Array = (
		data.get(
			"owned_equipment_instances",
			[]
		)
	)

	var highest_instance_id: int = 0

	for instance_data in saved_equipment_instances:
		var copied_data: Dictionary = (
			instance_data.duplicate(true)
		)

		owned_equipment_instances.append(
			copied_data
		)

		highest_instance_id = maxi(
			highest_instance_id,
			int(
				copied_data.get(
					"instance_id",
					0
				)
			)
		)

	next_equipment_instance_id = maxi(
		int(
			data.get(
				"next_equipment_instance_id",
				highest_instance_id + 1
			)
		),
		highest_instance_id + 1
	)


	DebugLog.write(
		"[불러오기] 상태 적용 완료 / ",
		current_day,
		"일차 / 소지금: ",
		money,
		" / 배치 가구: ",
		store_layout.size()
	)

	resume_scene_id = str(
		data.get(
			"resume_scene_id",
			RESUME_SCENE_STORE
		)
	)

	if (
		resume_scene_id != RESUME_SCENE_STORE
		and resume_scene_id != RESUME_SCENE_EXPEDITION
	):
		resume_scene_id = RESUME_SCENE_STORE


	var raw_expedition_checkpoint: Variant = (
		data.get(
			"expedition_checkpoint",
			{}
		)
	)

	if raw_expedition_checkpoint is Dictionary:
		expedition_checkpoint = (
			raw_expedition_checkpoint.duplicate(true)
		)
	else:
		expedition_checkpoint = {}

	return true


# =========================
# 달력 진행
# =========================

func advance_calendar_day() -> int:
	# 종료되는 오늘 하루의 고용 상태 기록
	accrue_employee_salary_for_current_day()

	var new_salary_due: int = 0

	# 각 계절의 마지막 날에 월급 확정
	if (
		CalendarData.get_day_of_season(
			total_day
		)
		== CalendarData.DAYS_PER_SEASON
	):
		var salary_result: Dictionary = (
			close_employee_salary_period()
		)

		new_salary_due = int(
			salary_result.get(
				"new_salary_due",
				0
			)
		)

		DebugLog.write(
			"[직원 월급] 월말 정산 / 신규 급여: ",
			new_salary_due,
			"G"
		)

	# 이번 달 급여와 기존 미지급 급여 납부
	var salary_paid: int = (
		pay_unpaid_employee_salary()
	)

	# show_day_summary()에서 미리 만든 당일 기록에
	# 급여 결과를 추가
	attach_employee_salary_to_daily_history(
		total_day,
		new_salary_due,
		salary_paid
	)

	total_day += 1
	PreservationService.settle()
	current_day += 1

	if current_day > 7:
		current_day = 1

	DebugLog.write(
		"[달력] ",
		total_day,
		"일차 / 요일 값: ",
		current_day
	)

	return current_day


# =========================
# 매장 이벤트와 영업 기록
# =========================

func discover_store_event(
	event_id: String
) -> bool:
	var normalized_event_id: String = (
		event_id.strip_edges()
	)

	if normalized_event_id.is_empty():
		push_warning(
			"[이벤트 발견] 이벤트 ID가 비어 있습니다."
		)

		return false

	# 이미 발견한 이벤트
	if discovered_store_events.has(
		normalized_event_id
	):
		return false

	discovered_store_events[
		normalized_event_id
	] = total_day

	store_event_discovered.emit(
		normalized_event_id,
		total_day
	)

	DebugLog.write(
		"[이벤트 발견] ",
		normalized_event_id,
		" / 발견일: ",
		total_day
	)

	return true


func has_discovered_store_event(
	event_id: String
) -> bool:
	return discovered_store_events.has(
		event_id
	)


func get_store_event_discovery_day(
	event_id: String
) -> int:
	return int(
		discovered_store_events.get(
			event_id,
			-1
		)
	)


func get_discovered_store_event_ids() -> Array[String]:
	var result: Array[String] = []

	for raw_event_id in discovered_store_events.keys():
		result.append(
			str(raw_event_id)
		)

	return result


func get_discovered_store_events() -> Dictionary:
	return discovered_store_events.duplicate(true)

func record_daily_shop_result(
	result_day: int,
	weekday: int,
	stats: Dictionary
) -> bool:
	if result_day < 1:
		push_warning(
			"[영업 기록] 잘못된 날짜: "
			+ str(result_day)
		)

		return false

	if weekday < 1 or weekday > 7:
		push_warning(
			"[영업 기록] 잘못된 요일: "
			+ str(weekday)
		)

		return false

	var record: Dictionary = {
		"total_day": result_day,
		"weekday": weekday,

		"visitors": maxi(
			int(stats.get("visitors", 0)),
			0
		),

		"sales": maxi(
			int(stats.get("sales", 0)),
			0
		),

		"missed": maxi(
			int(stats.get("missed", 0)),
			0
		),

		"revenue": maxi(
			int(stats.get("revenue", 0)),
			0
		),

		"active_event_ids": (
			stats.get(
				"active_event_ids",
				[]
			).duplicate()
		),

		"visitors_by_customer_type": (
			stats.get(
				"visitors_by_customer_type",
				{}
			).duplicate(true)
		),

		"sold_items": (
			stats.get(
				"sold_items",
				{}
			).duplicate(true)
		),

		"unmet_demand": (
			stats.get(
				"unmet_demand",
				{}
			).duplicate(true)
		)
	}

	# 같은 날짜의 기록이 이미 있으면 교체
	for index in range(
		daily_shop_history.size()
	):
		var previous_record: Dictionary = (
			daily_shop_history[index]
		)

		if int(
			previous_record.get(
				"total_day",
				-1
			)
		) != result_day:
			continue

		daily_shop_history[index] = record

		DebugLog.write(
			"[영업 기록] 기존 기록 교체 / ",
			result_day,
			"일차"
		)

		return true

	daily_shop_history.append(
		record
	)

	DebugLog.write(
		"[영업 기록] 추가 / ",
		result_day,
		"일차 / 매출: ",
		record["revenue"],
		"G"
	)

	return true


func get_daily_shop_history() -> Array[Dictionary]:
	var result: Array[Dictionary] = []

	for record in daily_shop_history:
		result.append(
			record.duplicate(true)
		)

	return result


# =========================
# 직원 상태와 급여
# =========================

func is_employee_state_valid(data: Dictionary) -> bool:
	if not data.get("is_hired") is bool:
		return false

	if not data.get("work_periods") is Array:
		return false

	var periods: Array[String] = []

	for raw_period in data["work_periods"]:
		if not raw_period is String:
			return false

		periods.append(raw_period)

	if not EmployeeData.is_work_periods_valid(periods):
		return false

	if data.has("training_levels"):
		if not data["training_levels"] is Dictionary:
			return false

		var levels: Dictionary = data["training_levels"]

		if not EmployeeTrainingData.is_levels_valid(levels):
			return false

	return true


func get_employee_state(employee_id: String) -> Dictionary:
	if not employee_states.has(employee_id):
		return {}

	return employee_states[employee_id].duplicate(true)


func set_employee_state(
	employee_id: String,
	hired: bool,
	periods: Array[String]
) -> bool:
	if employee_id.is_empty():
		return false

	if EmployeeData.get_employee(employee_id).is_empty():
		return false

	var data: Dictionary = get_employee_state(employee_id)

	if not data.has("training_levels"):
		data["training_levels"] = (
			EmployeeTrainingData.create_default_levels()
		)

	data["is_hired"] = hired
	data["work_periods"] = periods.duplicate()

	if not is_employee_state_valid(data):
		return false

	employee_states[employee_id] = data.duplicate(true)
	return true

func upgrade_employee_training(
	employee_id: String,
	stat_id: String
) -> bool:
	if not EmployeeTrainingData.STAT_IDS.has(stat_id):
		return false

	var data: Dictionary = get_employee_state(employee_id)

	if not is_employee_state_valid(data):
		return false

	if not bool(data["is_hired"]):
		return false

	var levels: Dictionary = data.get(
		"training_levels",
		EmployeeTrainingData.create_default_levels()
	).duplicate(true)

	var current_level: int = int(levels.get(stat_id, 0))

	var current_data: Dictionary = (
		EmployeeTrainingData.get_level_data(
			stat_id,
			current_level
		)
	)

	var next_data: Dictionary = (
		EmployeeTrainingData.get_level_data(
			stat_id,
			current_level + 1
		)
	)

	if current_data.is_empty() or next_data.is_empty():
		return false

	var cost: int = int(current_data["upgrade_cost"])

	if cost < 0 or not can_afford(cost):
		return false

	levels[stat_id] = current_level + 1
	data["training_levels"] = levels

	if not is_employee_state_valid(data):
		return false

	if cost > 0:
		if not spend_money(cost):
			return false

	employee_states[employee_id] = data.duplicate(true)
	return true

func ensure_employee_salary_records() -> void:
	for employee_id in EmployeeData.get_all_employee_ids():
		if employee_salary_records.has(employee_id):
			continue

		employee_salary_records[employee_id] = {
			"accrued_days": 0,
			"last_accrual_day": 0
		}


func accrue_employee_salary_for_current_day() -> void:
	ensure_employee_salary_records()

	for employee_id in EmployeeData.get_all_employee_ids():
		var employee_state: Dictionary = (
			get_employee_state(employee_id)
		)

		if employee_state.is_empty():
			continue

		# 근무표가 비어 있어도 고용 중이면 월급이 누적된다.
		if not bool(
			employee_state.get("is_hired", false)
		):
			continue

		var record: Dictionary = (
			employee_salary_records[
				employee_id
			].duplicate(true)
		)

		# 하루 정산이 중복 호출되어도 한 번만 기록한다.
		if int(
			record.get("last_accrual_day", 0)
		) == total_day:
			continue

		record["accrued_days"] = (
			int(record.get("accrued_days", 0))
			+ 1
		)

		record["last_accrual_day"] = total_day

		employee_salary_records[
			employee_id
		] = record

		DebugLog.write(
			"[직원 급여] 근속일 누적 / ",
			employee_id,
			" / ",
			record["accrued_days"],
			"일"
		)


func get_employee_salary_record(
	employee_id: String
) -> Dictionary:
	ensure_employee_salary_records()

	if not employee_salary_records.has(employee_id):
		return {}

	return employee_salary_records[
		employee_id
	].duplicate(true)


func get_employee_accrued_salary(
	employee_id: String
) -> int:
	var record: Dictionary = (
		get_employee_salary_record(employee_id)
	)

	if record.is_empty():
		return 0

	var monthly_salary: int = (
		EmployeeData.get_monthly_salary(employee_id)
	)

	var accrued_days: int = maxi(
		int(record.get("accrued_days", 0)),
		0
	)

	return roundi(
		float(monthly_salary)
		* float(accrued_days)
		/ float(CalendarData.DAYS_PER_SEASON)
	)

func close_employee_salary_period() -> Dictionary:
	ensure_employee_salary_records()

	var new_salary_due: int = 0
	var salary_details: Dictionary = {}

	for employee_id in EmployeeData.get_all_employee_ids():
		var record: Dictionary = (
			employee_salary_records[
				employee_id
			].duplicate(true)
		)

		var accrued_days: int = maxi(
			int(record.get("accrued_days", 0)),
			0
		)

		if accrued_days > 0:
			var monthly_salary: int = (
				EmployeeData.get_monthly_salary(
					employee_id
				)
			)

			var salary_amount: int = roundi(
				float(monthly_salary)
				* float(accrued_days)
				/ float(CalendarData.DAYS_PER_SEASON)
			)

			salary_amount = maxi(
				salary_amount,
				0
			)

			new_salary_due += salary_amount

			salary_details[employee_id] = {
				"accrued_days": accrued_days,
				"salary_amount": salary_amount
			}

			DebugLog.write(
				"[직원 월급] 급여 확정 / ",
				employee_id,
				" / 근속 ",
				accrued_days,
				"일 / ",
				salary_amount,
				"G"
			)

		# 새로운 급여 기간 시작
		record["accrued_days"] = 0

		employee_salary_records[
			employee_id
		] = record

	unpaid_employee_salary += new_salary_due

	return {
		"new_salary_due": new_salary_due,
		"salary_details": salary_details
	}

func pay_unpaid_employee_salary() -> int:
	if unpaid_employee_salary <= 0:
		return 0

	if money <= 0:
		DebugLog.write(
			"[직원 월급] 지급할 소지금 없음 / 미지급: ",
			unpaid_employee_salary,
			"G"
		)

		return 0

	var paid_amount: int = mini(
		money,
		unpaid_employee_salary
	)

	money -= paid_amount
	unpaid_employee_salary -= paid_amount

	DebugLog.write(
		"[직원 월급] 지급 / ",
		paid_amount,
		"G / 남은 미지급: ",
		unpaid_employee_salary,
		"G"
	)

	return paid_amount


func get_unpaid_employee_salary() -> int:
	return maxi(
		unpaid_employee_salary,
		0
	)

func attach_employee_salary_to_daily_history(
	result_day: int,
	new_salary_due: int,
	salary_paid: int
) -> void:
	for index in range(
		daily_shop_history.size()
	):
		var record: Dictionary = (
			daily_shop_history[index]
			.duplicate(true)
		)

		if int(
			record.get(
				"total_day",
				-1
			)
		) != result_day:
			continue

		var revenue: int = int(
			record.get(
				"revenue",
				0
			)
		)

		record["salary_due"] = maxi(
			new_salary_due,
			0
		)

		record["salary_paid"] = maxi(
			salary_paid,
			0
		)

		record["unpaid_salary"] = maxi(
			unpaid_employee_salary,
			0
		)

		# 당일 매출에서 실제 지급된 급여를 제외한 금액
		record["net_cash_flow"] = (
			revenue - salary_paid
		)

		daily_shop_history[index] = record

		DebugLog.write(
			"[영업 기록] 급여 반영 / ",
			result_day,
			"일차 / 지급: ",
			salary_paid,
			"G / 미지급: ",
			unpaid_employee_salary,
			"G"
		)

		return

# =========================
# 개별 장비 인스턴스
# =========================

func create_owned_equipment_instance(
	item_id: String,
	enhancement_level: int = 0
) -> int:
	if not ExpeditionEquipmentData.has_equipment(
		item_id
	):
		push_warning(
			"[장비 인스턴스] 등록되지 않은 장비: "
			+ item_id
		)
		return -1

	var max_level: int = (
		ExpeditionEquipmentData
		.get_max_enhancement_level(
			item_id
		)
	)

	if (
		enhancement_level < 0
		or enhancement_level > max_level
	):
		push_warning(
			"[장비 인스턴스] 강화 단계 범위 오류: "
			+ item_id
			+ " / +"
			+ str(enhancement_level)
		)
		return -1

	var instance_id: int = (
		next_equipment_instance_id
	)

	next_equipment_instance_id += 1

	owned_equipment_instances.append(
		{
			"instance_id": instance_id,
			"item_id": item_id,
			"enhancement_level": enhancement_level
		}
	)

	DebugLog.write(
		"[장비 인스턴스] 생성 / ",
		item_id,
		" / ID: ",
		instance_id,
		" / 강화: +",
		enhancement_level
	)

	return instance_id


func get_owned_equipment_instances() -> Array[Dictionary]:
	return owned_equipment_instances.duplicate(
		true
	)


func get_owned_equipment_instance(
	instance_id: int
) -> Dictionary:
	for instance_data in owned_equipment_instances:
		if int(
			instance_data.get(
				"instance_id",
				-1
			)
		) != instance_id:
			continue

		return instance_data.duplicate(true)

	return {}


func has_owned_equipment_instance(
	instance_id: int
) -> bool:
	return not get_owned_equipment_instance(
		instance_id
	).is_empty()


func get_owned_equipment_count(
	item_id: String
) -> int:
	var count: int = 0

	for instance_data in owned_equipment_instances:
		if str(
			instance_data.get(
				"item_id",
				""
			)
		) == item_id:
			count += 1

	return count


func take_owned_equipment_instance(
	instance_id: int
) -> Dictionary:
	for index in range(
		owned_equipment_instances.size()
	):
		var instance_data: Dictionary = (
			owned_equipment_instances[index]
		)

		if int(
			instance_data.get(
				"instance_id",
				-1
			)
		) != instance_id:
			continue

		var removed: Dictionary = (
			owned_equipment_instances.pop_at(
				index
			)
		)

		DebugLog.write(
			"[장비 인스턴스] 보관함에서 꺼냄 / ID: ",
			instance_id
		)

		return removed

	return {}


func return_owned_equipment_instance(
	instance_data: Dictionary
) -> bool:
	if not is_equipment_instance_data_valid(
		instance_data
	):
		push_warning(
			"[장비 인스턴스] 반환 데이터 오류: "
			+ str(instance_data)
		)
		return false

	var instance_id: int = int(
		instance_data.get(
			"instance_id",
			-1
		)
	)

	if has_owned_equipment_instance(
		instance_id
	):
		push_warning(
			"[장비 인스턴스] 중복 반환 ID: "
			+ str(instance_id)
		)
		return false

	owned_equipment_instances.append(
		instance_data.duplicate(true)
	)

	next_equipment_instance_id = maxi(
		next_equipment_instance_id,
		instance_id + 1
	)

	DebugLog.write(
		"[장비 인스턴스] 보관함으로 반환 / ",
		instance_data.get(
			"item_id",
			""
		),
		" / ID: ",
		instance_id
	)

	return true


func set_equipment_instance_level(
	instance_id: int,
	new_level: int
) -> bool:
	for instance_data in owned_equipment_instances:
		if int(
			instance_data.get(
				"instance_id",
				-1
			)
		) != instance_id:
			continue

		var item_id: String = str(
			instance_data.get(
				"item_id",
				""
			)
		)

		var max_level: int = (
			ExpeditionEquipmentData
			.get_max_enhancement_level(
				item_id
			)
		)

		if new_level < 0 or new_level > max_level:
			return false

		instance_data["enhancement_level"] = (
			new_level
		)

		return true

	return false


func is_equipment_instance_data_valid(
	instance_data: Dictionary
) -> bool:
	if not instance_data.get(
		"instance_id"
	) is int:
		return false

	var instance_id: int = int(
		instance_data["instance_id"]
	)

	if instance_id <= 0:
		return false

	if not instance_data.get(
		"item_id"
	) is String:
		return false

	var item_id: String = str(
		instance_data["item_id"]
	)

	if not ExpeditionEquipmentData.has_equipment(
		item_id
	):
		return false

	if not instance_data.get(
		"enhancement_level"
	) is int:
		return false

	var level: int = int(
		instance_data["enhancement_level"]
	)

	var max_level: int = (
		ExpeditionEquipmentData
		.get_max_enhancement_level(
			item_id
		)
	)

	return (
		level >= 0
		and level <= max_level
	)

func migrate_legacy_equipment_inventory() -> void:
	var inventory_ids: Array = (
		inventory.keys()
	)

	for raw_item_id in inventory_ids:
		var item_id: String = str(
			raw_item_id
		)

		if not ExpeditionEquipmentData.has_equipment(
			item_id
		):
			continue

		var amount: int = get_item_count(
			item_id
		)

		if amount <= 0:
			inventory.erase(item_id)
			continue

		# 이전 도구 강화 데이터가 있다면 승계한다.
		var legacy_level: int = 0

		if tool_enhancement_levels.has(
			item_id
		):
			legacy_level = int(
				tool_enhancement_levels.get(
					item_id,
					0
				)
			)

		for _index in range(amount):
			var instance_id: int = (
				create_owned_equipment_instance(
					item_id,
					legacy_level
				)
			)

			if instance_id < 0:
				push_error(
					"[장비 이전] 인스턴스 생성 실패: "
					+ item_id
				)
				return

		# 장비는 이제 일반 수량 인벤토리에서 제거한다.
		inventory.erase(item_id)

		DebugLog.write(
			"[장비 이전] 일반 인벤토리 → 개별 장비 / ",
			item_id,
			" ×",
			amount
		)

# =========================
# 원정 재개 체크포인트
# =========================

func set_expedition_checkpoint(
	checkpoint_data: Dictionary
) -> void:
	expedition_checkpoint = (
		checkpoint_data.duplicate(true)
	)

	resume_scene_id = (
		RESUME_SCENE_EXPEDITION
	)


func clear_expedition_checkpoint() -> void:
	expedition_checkpoint.clear()

	resume_scene_id = (
		RESUME_SCENE_STORE
	)


func has_expedition_checkpoint() -> bool:
	return (
		resume_scene_id
		== RESUME_SCENE_EXPEDITION
		and not expedition_checkpoint.is_empty()
	)


#===============================
# 편의점 확장 단계
#===============================

func get_store_expansion_level() -> int:
	return clampi(
		store_expansion_level,
		StoreExpansionData.MIN_LEVEL,
		StoreExpansionData.MAX_LEVEL
	)


func get_store_size() -> Vector2i:
	return StoreExpansionData.get_store_size(
		get_store_expansion_level()
	)


func can_expand_store() -> bool:
	return StoreExpansionData.can_expand(
		get_store_expansion_level()
	)

func get_next_store_expansion_level() -> int:
	return StoreExpansionData.get_next_level(
		get_store_expansion_level()
	)


func get_next_store_size() -> Vector2i:
	return StoreExpansionData.get_next_store_size(
		get_store_expansion_level()
	)


func get_store_expansion_cost() -> int:
	return StoreExpansionData.get_expansion_cost(
		get_store_expansion_level()
	)


func can_afford_store_expansion() -> bool:
	if not can_expand_store():
		return false

	return can_afford(
		get_store_expansion_cost()
	)


# 소지금을 사용해 매장을 다음 단계로 확장한다.
func upgrade_store() -> bool:
	if not can_expand_store():
		push_warning(
			"[매장 확장] 이미 최대 단계입니다."
		)
		return false

	var expansion_cost: int = (
		get_store_expansion_cost()
	)

	if not can_afford(
		expansion_cost
	):
		push_warning(
			"[매장 확장] 소지금이 부족합니다. 필요: ",
			expansion_cost,
			"G / 보유: ",
			money,
			"G"
		)
		return false

	var previous_level: int = (
		get_store_expansion_level()
	)

	var new_level: int = (
		get_next_store_expansion_level()
	)

	if expansion_cost > 0:
		if not spend_money(
			expansion_cost
		):
			return false

	store_expansion_level = new_level

	var new_size: Vector2i = (
		get_store_size()
	)

	store_expansion_changed.emit(
		previous_level,
		new_level,
		new_size
	)

	DebugLog.write(
		"[매장 확장] 완료 / ",
		previous_level,
		"단계 → ",
		new_level,
		"단계 / 크기: ",
		new_size,
		" / 비용: ",
		expansion_cost,
		"G"
	)

	return true

func get_store_lot_type() -> String:
	return StoreLotData.normalize_lot_type(
		store_lot_type
	)


func get_production_room_expansion_level() -> int:
	return clampi(
		production_room_expansion_level,
		ProductionRoomExpansionData.MIN_LEVEL,
		ProductionRoomExpansionData.MAX_LEVEL
	)


func get_production_room_size() -> Vector2i:
	return ProductionRoomExpansionData.get_room_size(
		get_production_room_expansion_level()
	)


func can_expand_production_room() -> bool:
	return ProductionRoomExpansionData.can_expand(
		get_production_room_expansion_level()
	)


func get_next_production_room_level() -> int:
	return ProductionRoomExpansionData.get_next_level(
		get_production_room_expansion_level()
	)


func get_next_production_room_size() -> Vector2i:
	return ProductionRoomExpansionData.get_next_room_size(
		get_production_room_expansion_level()
	)


func get_production_room_expansion_cost() -> int:
	return ProductionRoomExpansionData.get_expansion_cost(
		get_production_room_expansion_level()
	)


func can_afford_production_room_expansion() -> bool:
	if not can_expand_production_room():
		return false

	return can_afford(
		get_production_room_expansion_cost()
	)


func upgrade_production_room() -> bool:
	if not can_expand_production_room():
		push_warning(
			"[생산실 확장] 이미 최대 단계입니다."
		)
		return false

	var expansion_cost: int = (
		get_production_room_expansion_cost()
	)

	if not can_afford(
		expansion_cost
	):
		push_warning(
			"[생산실 확장] 소지금 부족 / 필요: ",
			expansion_cost,
			"G / 보유: ",
			money,
			"G"
		)
		return false

	var previous_level: int = (
		get_production_room_expansion_level()
	)

	var new_level: int = (
		get_next_production_room_level()
	)

	if expansion_cost > 0:
		if not spend_money(
			expansion_cost
		):
			return false

	production_room_expansion_level = new_level

	var new_size: Vector2i = (
		get_production_room_size()
	)

	production_room_expansion_changed.emit(
		previous_level,
		new_level,
		new_size
	)

	DebugLog.write(
		"[생산실 확장] 완료 / ",
		previous_level,
		"단계 → ",
		new_level,
		"단계 / 크기: ",
		new_size,
		" / 비용: ",
		expansion_cost,
		"G"
	)

	return true

func get_warehouse_expansion_level() -> int:
	return clampi(
		warehouse_expansion_level,
		WarehouseExpansionData.MIN_LEVEL,
		WarehouseExpansionData.MAX_LEVEL
	)


func get_warehouse_size() -> Vector2i:
	return WarehouseExpansionData.get_warehouse_size(
		get_warehouse_expansion_level()
	)


func can_expand_warehouse() -> bool:
	return WarehouseExpansionData.can_expand(
		get_warehouse_expansion_level()
	)


func get_next_warehouse_level() -> int:
	return WarehouseExpansionData.get_next_level(
		get_warehouse_expansion_level()
	)


func get_next_warehouse_size() -> Vector2i:
	return WarehouseExpansionData.get_next_warehouse_size(
		get_warehouse_expansion_level()
	)


func get_warehouse_expansion_cost() -> int:
	return WarehouseExpansionData.get_expansion_cost(
		get_warehouse_expansion_level()
	)


func can_afford_warehouse_expansion() -> bool:
	if not can_expand_warehouse():
		return false

	return can_afford(
		get_warehouse_expansion_cost()
	)


func upgrade_warehouse() -> bool:
	if not can_expand_warehouse():
		push_warning(
			"[창고 확장] 이미 최대 단계입니다."
		)
		return false

	var expansion_cost: int = (
		get_warehouse_expansion_cost()
	)

	if not can_afford(
		expansion_cost
	):
		push_warning(
			"[창고 확장] 소지금 부족 / 필요: ",
			expansion_cost,
			"G / 보유: ",
			money,
			"G"
		)
		return false

	var previous_level: int = (
		get_warehouse_expansion_level()
	)

	var new_level: int = (
		get_next_warehouse_level()
	)

	if expansion_cost > 0:
		if not spend_money(
			expansion_cost
		):
			return false

	warehouse_expansion_level = new_level

	var new_size: Vector2i = (
		get_warehouse_size()
	)

	warehouse_expansion_changed.emit(
		previous_level,
		new_level,
		new_size
	)

	DebugLog.write(
		"[창고 확장] 완료 / ",
		previous_level,
		"단계 → ",
		new_level,
		"단계 / 크기: ",
		new_size,
		" / 비용: ",
		expansion_cost,
		"G"
	)

	return true
