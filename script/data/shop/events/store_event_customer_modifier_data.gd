class_name StoreEventCustomerModifierData
extends RefCounted


const CSV_PATH: String = (
	"res://data/shop/events/store_event_customer_modifiers.csv"
)


static var modifiers_by_event: Dictionary = {}
static var _loaded: bool = false


# =========================================================
# 로드
# =========================================================

static func ensure_loaded() -> void:
	if _loaded:
		return

	_load_csv()
	_loaded = true

	DebugLog.write(
		"[StoreEventCustomerModifierData] 로드 완료 / 이벤트: ",
		modifiers_by_event.size()
	)


static func reload() -> void:
	modifiers_by_event.clear()
	_loaded = false

	ensure_loaded()


# =========================================================
# 이벤트 하나의 배율
# =========================================================

static func get_event_weight_multiplier(
	event_id: String,
	customer_type_id: String
) -> float:
	ensure_loaded()

	var entries: Array = modifiers_by_event.get(
		event_id,
		[]
	)

	var result: float = 1.0

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

		result *= float(
			entry.get(
				"weight_multiplier",
				1.0
			)
		)

	return result


# =========================================================
# 현재 진행 중인 모든 이벤트의 배율
# =========================================================

static func get_active_weight_multiplier(
	customer_type_id: String,
	total_day: int
) -> float:
	ensure_loaded()

	var result: float = 1.0

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

		result *= get_event_weight_multiplier(
			event_id,
			customer_type_id
		)

	return result


# =========================================================
# CSV 로드
# =========================================================

static func _load_csv() -> void:
	modifiers_by_event.clear()

	if not FileAccess.file_exists(
		CSV_PATH
	):
		push_error(
			"[StoreEventCustomerModifierData] CSV 없음: "
			+ CSV_PATH
		)

		return

	var file := FileAccess.open(
		CSV_PATH,
		FileAccess.READ
	)

	if file == null:
		push_error(
			"[Store진행행동] CSV 열기 실패"
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
		"weight_multiplier"
	]

	for column_name in required_headers:
		if indexes.has(column_name):
			continue

		push_error(
			"[StoreEventCustomerModifierData] CSV 열 없음: "
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

		var weight_multiplier: float = float(
			CsvReader.get_cell(
				row,
				indexes,
				"weight_multiplier"
			)
		)

		if event_id.is_empty():
			continue

		if not StoreEventData.has_event(
			event_id
		):
			push_warning(
				"[StoreEventCustomerModifierData] 없는 이벤트: "
				+ event_id
			)

			continue

		if customer_type_id.is_empty():
			continue

		if (
			customer_type_id != "any"
			and not CustomerTypeData.has_customer_target(
				customer_type_id
			)
		):
			push_warning(
				"[StoreEventCustomerModifierData] 없는 손님 유형: "
				+ customer_type_id
			)

			continue

		if weight_multiplier <= 0.0:
			push_warning(
				"[StoreEventCustomerModifierData] 잘못된 배율: "
				+ event_id
				+ " / "
				+ customer_type_id
			)

			continue

		if not modifiers_by_event.has(
			event_id
		):
			modifiers_by_event[event_id] = []

		modifiers_by_event[event_id].append(
			{
				"event_id": event_id,
				"customer_type_id": (
					customer_type_id
				),
				"weight_multiplier": (
					weight_multiplier
				)
			}
		)


# =========================================================
# CSV 셀 읽기
# =========================================================

