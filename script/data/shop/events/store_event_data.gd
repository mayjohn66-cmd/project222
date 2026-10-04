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
			StoreEventSchedule.occurrence(event, GameState.total_day)
		)

	return result


# =========================================================
# 발견 가능 이벤트
# =========================================================

static func get_event_occurrence(event_id: String, total_day: int) -> Dictionary:
	var event := get_event(event_id)
	return {} if event.is_empty() else StoreEventSchedule.occurrence(event, total_day)

static func is_discovered_for_occurrence(event_id: String, total_day: int) -> bool:
	var event := get_event(event_id)
	return not event.is_empty() and StoreEventSchedule.heard(event, total_day, GameState.get_store_event_discovery_day(event_id))

static func can_share_event(event_id: String, total_day: int) -> bool:
	var event := get_event_occurrence(event_id, total_day)
	return not event.is_empty() and total_day >= int(event["discovery_start_day"]) and total_day <= int(event["end_day"]) and not is_discovered_for_occurrence(event_id, total_day)

static func discover_event(event_id: String, total_day: int) -> bool:
	if total_day != GameState.total_day or not can_share_event(event_id, total_day): return false
	if not GameState.has_discovered_store_event(event_id): return GameState.discover_store_event(event_id)
	# 기존 저장 형식은 id -> 최근 소문 일자. 새 회차만 날짜를 갱신하고 같은 신호를 사용한다.
	GameState.discovered_store_events[event_id] = total_day
	GameState.store_event_discovered.emit(event_id, total_day)
	return true

static func get_discoverable_events(total_day: int, customer_type_id: String) -> Array[Dictionary]:
	ensure_loaded()
	var result: Array[Dictionary] = []
	for raw_event in events.values():
		var event := StoreEventSchedule.occurrence(raw_event, total_day)
		if is_discovered_for_occurrence(str(event["event_id"]), total_day): continue
		if total_day < int(event["discovery_start_day"]) or total_day > int(event["discovery_end_day"]): continue
		var owner := str(event.get("rumor_customer_type_id", ""))
		if not owner.is_empty() and owner != "any" and owner != customer_type_id and owner != CustomerTypeData.get_group_id(customer_type_id): continue
		result.append(event)
	return result

static func get_active_events(total_day: int) -> Array[Dictionary]:
	ensure_loaded()
	var result: Array[Dictionary] = []
	for event in events.values():
		if StoreEventSchedule.active(event, total_day): result.append(StoreEventSchedule.occurrence(event, total_day))
	return result

static func is_event_active(event_id: String, total_day: int) -> bool:
	var event := get_event(event_id)
	return not event.is_empty() and StoreEventSchedule.active(event, total_day)


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

		var event_kind := CsvReader.get_cell(row, indexes, "event_kind")
		if event_kind.is_empty(): event_kind = "common"
		var season_id := CsvReader.get_cell(row, indexes, "season_id")
		var repeat_days := int(CsvReader.get_cell(row, indexes, "repeat_days"))
		if not StoreEventSchedule.valid({"event_kind":event_kind, "season_id":season_id, "repeat_days":repeat_days, "discovery_start_day":discovery_start_day, "discovery_end_day":discovery_end_day, "start_day":start_day, "end_day":end_day}):
			push_warning("[StoreEventData] 잘못된 종류/주기/날짜 설정: " + event_id)
			continue

		events[event_id] = {
			"event_id": event_id,
			"event_kind": event_kind,
			"season_id": season_id,
			"repeat_days": repeat_days,

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

