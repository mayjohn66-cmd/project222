class_name StoreEventData
extends RefCounted


const CSV_PATH: String = (
	"res://data/shop/events/store_events.csv"
)


static var events: Dictionary = {}
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
		"[StoreEventData] 로드 완료 / 이벤트: ",
		events.size()
	)


static func reload() -> void:
	events.clear()
	_loaded = false

	ensure_loaded()


# =========================================================
# 기본 조회
# =========================================================

static func has_event(
	event_id: String
) -> bool:
	ensure_loaded()

	return events.has(
		event_id
	)


static func get_event(
	event_id: String
) -> Dictionary:
	ensure_loaded()

	if not events.has(event_id):
		return {}

	return events[event_id].duplicate(true)


static func get_all_events() -> Array[Dictionary]:
	ensure_loaded()

	var result: Array[Dictionary] = []

	for event in events.values():
		result.append(
			event.duplicate(true)
		)

	return result


# =========================================================
# 발견 가능 이벤트
# =========================================================

static func get_discoverable_events(
	total_day: int,
	customer_type_id: String
) -> Array[Dictionary]:
	ensure_loaded()

	var result: Array[Dictionary] = []

	for event in events.values():
		var event_id: String = str(
			event.get(
				"event_id",
				""
			)
		)

		if event_id.is_empty():
			continue

		# 이미 발견한 이벤트는 다시 나오지 않음
		if GameState.has_discovered_store_event(
			event_id
		):
			continue

		var discovery_start_day: int = int(
			event.get(
				"discovery_start_day",
				0
			)
		)

		var discovery_end_day: int = int(
			event.get(
				"discovery_end_day",
				0
			)
		)

		if total_day < discovery_start_day:
			continue

		if total_day > discovery_end_day:
			continue

		var rumor_customer_type_id: String = str(
			event.get(
				"rumor_customer_type_id",
				""
			)
		)

		# 비어 있거나 any이면 모든 손님 유형 허용
		if (
			not rumor_customer_type_id.is_empty()
			and rumor_customer_type_id != "any"
			and rumor_customer_type_id
			!= customer_type_id
		):
			continue

		result.append(
			event.duplicate(true)
		)

	return result


# =========================================================
# 현재 진행 중인 이벤트
# =========================================================

static func get_active_events(
	total_day: int
) -> Array[Dictionary]:
	ensure_loaded()

	var result: Array[Dictionary] = []

	for event in events.values():
		var start_day: int = int(
			event.get(
				"start_day",
				0
			)
		)

		var end_day: int = int(
			event.get(
				"end_day",
				0
			)
		)

		if total_day < start_day:
			continue

		if total_day > end_day:
			continue

		result.append(
			event.duplicate(true)
		)

	return result


static func is_event_active(
	event_id: String,
	total_day: int
) -> bool:
	var event: Dictionary = get_event(
		event_id
	)

	if event.is_empty():
		return false

	var start_day: int = int(
		event.get(
			"start_day",
			0
		)
	)

	var end_day: int = int(
		event.get(
			"end_day",
			0
		)
	)

	return (
		total_day >= start_day
		and total_day <= end_day
	)


# =========================================================
# CSV 로드
# =========================================================

static func _load_csv() -> void:
	events.clear()

	if not FileAccess.file_exists(
		CSV_PATH
	):
		push_error(
			"[StoreEventData] CSV 없음: "
			+ CSV_PATH
		)

		return

	var file := FileAccess.open(
		CSV_PATH,
		FileAccess.READ
	)

	if file == null:
		push_error(
			"[StoreEventData] CSV 열기 실패"
		)

		return

	var header: PackedStringArray = (
		file.get_csv_line()
	)

	var indexes: Dictionary = {}

	for i in range(header.size()):
		var column_name: String = (
			header[i].strip_edges()
		)

		indexes[column_name] = i

	var required_headers: Array[String] = [
		"event_id",
		"title",
		"discovery_start_day",
		"discovery_end_day",
		"start_day",
		"end_day",
		"rumor_customer_type_id",
		"dialogue_id",
		"description"
	]

	for column_name in required_headers:
		if indexes.has(column_name):
			continue

		push_error(
			"[StoreEventData] CSV 열 없음: "
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

		if event_id.is_empty():
			continue

		if events.has(event_id):
			push_warning(
				"[StoreEventData] 중복 이벤트 ID: "
				+ event_id
			)

			continue

		var discovery_start_day: int = int(
			CsvReader.get_cell(
				row,
				indexes,
				"discovery_start_day"
			)
		)

		var discovery_end_day: int = int(
			CsvReader.get_cell(
				row,
				indexes,
				"discovery_end_day"
			)
		)

		var start_day: int = int(
			CsvReader.get_cell(
				row,
				indexes,
				"start_day"
			)
		)

		var end_day: int = int(
			CsvReader.get_cell(
				row,
				indexes,
				"end_day"
			)
		)

		if (
			discovery_start_day < 1
			or discovery_end_day
			< discovery_start_day
			or start_day
			<= discovery_end_day
			or end_day < start_day
		):
			push_warning(
				"[StoreEventData] 잘못된 날짜 설정: "
				+ event_id
			)

			continue

		events[event_id] = {
			"event_id": event_id,

			"title": CsvReader.get_cell(
				row,
				indexes,
				"title"
			),

			"discovery_start_day": (
				discovery_start_day
			),

			"discovery_end_day": (
				discovery_end_day
			),

			"start_day": start_day,
			"end_day": end_day,

			"rumor_customer_type_id": (
				CsvReader.get_cell(
					row,
					indexes,
					"rumor_customer_type_id"
				)
			),

			"dialogue_id": CsvReader.get_cell(
				row,
				indexes,
				"dialogue_id"
			),

			"description": CsvReader.get_cell(
				row,
				indexes,
				"description"
			)
		}


# =========================================================
# CSV 셀 읽기
# =========================================================

