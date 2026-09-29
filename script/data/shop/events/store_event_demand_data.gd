class_name StoreEventDemandData
extends RefCounted


const CSV_PATH: String = (
	"res://data/shop/events/store_event_demands.csv"
)


static var demands_by_event: Dictionary = {}
static var _loaded: bool = false


# =========================================================
# 로드
# =========================================================

static func ensure_loaded() -> void:
	if _loaded:
		return

	_load_csv()
	_loaded = true

	print(
		"[StoreEventDemandData] 로드 완료 / 이벤트: ",
		demands_by_event.size()
	)


static func reload() -> void:
	demands_by_event.clear()
	_loaded = false

	ensure_loaded()


# =========================================================
# 이벤트별 수요 조회
# =========================================================

static func get_event_demand_entries(
	event_id: String,
	customer_type_id: String
) -> Array[Dictionary]:
	ensure_loaded()

	var result: Array[Dictionary] = []

	var entries: Array = demands_by_event.get(
		event_id,
		[]
	)

	for entry in entries:
		if not entry is Dictionary:
			continue

		var entry_customer_type_id: String = str(
			entry.get(
				"customer_type_id",
				""
			)
		)

		if (
			entry_customer_type_id != "any"
			and entry_customer_type_id
			!= customer_type_id
		):
			continue

		result.append(
			entry.duplicate(true)
		)

	return result


# =========================================================
# 현재 활성 이벤트의 수요 조회
# =========================================================

static func get_active_demand_entries(
	customer_type_id: String,
	total_day: int
) -> Array[Dictionary]:
	ensure_loaded()

	var result: Array[Dictionary] = []

	var active_events: Array[Dictionary] = (
		StoreEventData.get_active_events(
			total_day
		)
	)

	for event_data in active_events:
		var event_id: String = str(
			event_data.get(
				"event_id",
				""
			)
		)

		if event_id.is_empty():
			continue

		var event_entries: Array[Dictionary] = (
			get_event_demand_entries(
				event_id,
				customer_type_id
			)
		)

		for entry in event_entries:
			result.append(
				entry.duplicate(true)
			)

	return result


# =========================================================
# CSV 로드
# =========================================================

static func _load_csv() -> void:
	demands_by_event.clear()

	if not FileAccess.file_exists(
		CSV_PATH
	):
		push_error(
			"[StoreEventDemandData] CSV 없음: "
			+ CSV_PATH
		)

		return

	var file := FileAccess.open(
		CSV_PATH,
		FileAccess.READ
	)

	if file == null:
		push_error(
			"[StoreEventDemandData] CSV 열기 실패"
		)

		return

	var header: PackedStringArray = (
		file.get_csv_line()
	)

	var indexes: Dictionary = {}

	for index in range(header.size()):
		var column_name: String = (
			header[index].strip_edges()
		)

		indexes[column_name] = index

	var required_headers: Array[String] = [
		"event_id",
		"customer_type_id",
		"target_type",
		"target_id",
		"weight",
		"min_amount",
		"max_amount"
	]

	for column_name in required_headers:
		if indexes.has(column_name):
			continue

		push_error(
			"[StoreEventDemandData] CSV 열 없음: "
			+ column_name
		)

		return

	while (
		file.get_position()
		< file.get_length()
	):
		var row: PackedStringArray = (
			file.get_csv_line()
		)

		if row.is_empty():
			continue

		var event_id: String = CsvReader.get_cell(
			row,
			indexes,
			"event_id"
		)

		var customer_type_id: String = CsvReader.get_cell(
			row,
			indexes,
			"customer_type_id"
		)

		var target_type: String = CsvReader.get_cell(
			row,
			indexes,
			"target_type"
		)

		var target_id: String = CsvReader.get_cell(
			row,
			indexes,
			"target_id"
		)

		var weight: int = int(
			CsvReader.get_cell(
				row,
				indexes,
				"weight"
			)
		)

		var min_amount: int = int(
			CsvReader.get_cell(
				row,
				indexes,
				"min_amount"
			)
		)

		var max_amount: int = int(
			CsvReader.get_cell(
				row,
				indexes,
				"max_amount"
			)
		)

		if event_id.is_empty():
			continue

		if not StoreEventData.has_event(
			event_id
		):
			push_warning(
				"[StoreEventDemandData] 없는 이벤트: "
				+ event_id
			)

			continue

		if customer_type_id.is_empty():
			continue

		if (
			customer_type_id != "any"
			and not CustomerTypeData.has_customer_type(
				customer_type_id
			)
		):
			push_warning(
				"[StoreEventDemandData] 없는 손님 유형: "
				+ customer_type_id
			)

			continue

		if (
			target_type != "item"
			and target_type != "category"
		):
			push_warning(
				"[StoreEventDemandData] 잘못된 target_type: "
				+ target_type
			)

			continue

		if not _is_valid_target(
			target_type,
			target_id
		):
			push_warning(
				"[StoreEventDemandData] 사용할 수 없는 대상: "
				+ target_type
				+ " / "
				+ target_id
			)

			continue

		if weight <= 0:
			push_warning(
				"[StoreEventDemandData] 잘못된 가중치: "
				+ event_id
			)

			continue

		if (
			min_amount <= 0
			or max_amount < min_amount
		):
			push_warning(
				"[StoreEventDemandData] 잘못된 요구 수량: "
				+ event_id
			)

			continue

		if not demands_by_event.has(
			event_id
		):
			demands_by_event[event_id] = []

		demands_by_event[event_id].append(
			{
				"event_id": event_id,
				"customer_type_id": (
					customer_type_id
				),
				"target_type": target_type,
				"target_id": target_id,
				"weight": weight,
				"min_amount": min_amount,
				"max_amount": max_amount
			}
		)


# =========================================================
# 대상 검사
# =========================================================

static func _is_valid_target(
	target_type: String,
	target_id: String
) -> bool:
	if target_id.is_empty():
		return false

	if target_type == "item":
		return (
			ItemData.has_item(target_id)
			and ItemData.is_sellable(target_id)
		)

	if target_type == "category":
		var item_ids: Array[String] = (
			ItemData.get_items_by_category(
				target_id
			)
		)

		for item_id in item_ids:
			if ItemData.is_sellable(item_id):
				return true

	return false


# =========================================================
# CSV 셀 읽기
# =========================================================

