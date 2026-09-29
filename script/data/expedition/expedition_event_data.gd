class_name ExpeditionEventData
extends RefCounted


const EVENT_CSV_PATH: String = (
	"res://data/expedition/expedition_events.csv"
)

const LOOT_CSV_PATH: String = (
	"res://data/expedition/expedition_loot.csv"
)


static var events: Array[Dictionary] = []
static var loot_entries: Array[Dictionary] = []

static var _loaded: bool = false


# =========================
# 외부 사용
# =========================

static func ensure_loaded() -> void:
	if _loaded:
		return

	_load_events()
	_load_loot()

	_loaded = true

	print(
		"[ExpeditionEventData] 로드 완료 / 이벤트: ",
		events.size(),
		" / 전리품 데이터: ",
		loot_entries.size()
	)

static func reload() -> void:
	events.clear()
	loot_entries.clear()

	_loaded = false

	ensure_loaded()


static func get_events_by_node_type(
	region_id: String,
	node_type: String,
	current_day: int
) -> Array[Dictionary]:
	ensure_loaded()

	var result: Array[Dictionary] = []

	for event in events:
		var event_region_id: String = str(
			event.get(
				"region_id",
				""
			)
		)

		var event_node_type: String = str(
			event.get(
				"node_type",
				""
			)
		)

		if event_region_id != region_id:
			continue

		if event_node_type != node_type:
			continue

		var day_filter: String = str(
			event.get(
				"day_filter",
				""
			)
		)

		if not _matches_day_filter(
			day_filter,
			current_day
		):
			continue

		result.append(
			event.duplicate(true)
		)

	return result


static func get_loot_entries(
	table_id: String
) -> Array[Dictionary]:
	ensure_loaded()

	var result: Array[Dictionary] = []

	var target_table_id: String = (
		table_id.strip_edges()
	)

	for entry in loot_entries:
		var entry_table_id: String = str(
			entry.get(
				"table_id",
				""
			)
		).strip_edges()

		if entry_table_id == target_table_id:
			result.append(
				entry.duplicate(true)
			)

	return result


# =========================
# 이벤트 CSV
# =========================

static func _load_events() -> void:
	events.clear()

	if not FileAccess.file_exists(
		EVENT_CSV_PATH
	):
		push_error(
			"[ExpeditionEventData] 이벤트 CSV 없음: "
			+ EVENT_CSV_PATH
		)
		return

	var file := FileAccess.open(
		EVENT_CSV_PATH,
		FileAccess.READ
	)

	if file == null:
		push_error(
			"[ExpeditionEventData] 이벤트 CSV 열기 실패"
		)
		return

	var header: PackedStringArray = (
		file.get_csv_line()
	)

	var indexes := _make_header_indexes(
		header
	)

	var required_headers: Array[String] = [
		"event_id",
		"node_type",
		"weight",
		"message",
		"result_type",
		"target_id",
		"value"
	]

	if not _validate_headers(
		indexes,
		required_headers,
		EVENT_CSV_PATH
	):
		return

	while file.get_position() < file.get_length():
		var row: PackedStringArray = (
			file.get_csv_line()
		)

		if row.is_empty():
			continue

		var event_id := _get_cell(
			row,
			indexes,
			"event_id"
		)

		if event_id.is_empty():
			continue

		events.append(
			{
				"event_id": event_id,

				"region_id": _get_cell(
					row,
					indexes,
					"region_id"
				),

				"node_type": _get_cell(
					row,
					indexes,
					"node_type"
				),

				"weight": int(
					_get_cell(
						row,
						indexes,
						"weight"
					)
				),

				"message": _get_cell(
					row,
					indexes,
					"message"
				),

				"result_type": _get_cell(
					row,
					indexes,
					"result_type"
				),

				"target_id": _get_cell(
					row,
					indexes,
					"target_id"
				),

				"value": int(
					_get_cell(
						row,
						indexes,
						"value"
					)
				),

				"day_filter": _get_cell(
					row,
					indexes,
					"day_filter"
				).strip_edges().to_lower(),

			}
		)

static func get_random_event(
	region_id: String,
	node_type: String,
	current_day: int,
	allow_heal_event: bool = true
) -> Dictionary:
	var candidates: Array[Dictionary] = (
		get_events_by_node_type(
			region_id,
			node_type,
			current_day
		)
	)

	if candidates.is_empty():
		push_warning(
			"[ExpeditionEventData] 이벤트 없음"
			+ " / 지역: "
			+ region_id
			+ " / 노드: "
			+ node_type
		)

		return {}

	var selectable: Array[Dictionary] = []

	for event in candidates:
		var weight: int = int(
			event.get(
				"weight",
				0
			)
		)

		if weight <= 0:
			continue

		var result_type: String = str(
			event.get(
				"result_type",
				""
			)
		)

		if (
			not allow_heal_event
			and result_type == "heal"
		):
			continue

		selectable.append(event)

	# 회복 이벤트밖에 없다면 기존 후보를 사용
	if selectable.is_empty():
		for event in candidates:
			if int(event.get("weight", 0)) > 0:
				selectable.append(event)

	if selectable.is_empty():
		push_warning(
			"[ExpeditionEventData] 추첨 가능한 이벤트 없음"
			+ " / 지역: "
			+ region_id
			+ " / 노드: "
			+ node_type
		)

		return {}

	var total_weight: int = 0

	for event in selectable:
		total_weight += int(
			event.get(
				"weight",
				0
			)
		)

	var roll: int = randi_range(
		1,
		total_weight
	)

	var accumulated: int = 0

	for event in selectable:
		accumulated += int(
			event.get(
				"weight",
				0
			)
		)

		if roll <= accumulated:
			return event.duplicate(true)

	return {}

static func _load_loot() -> void:
	loot_entries.clear()

	if not FileAccess.file_exists(
		LOOT_CSV_PATH
	):
		push_error(
			"[ExpeditionEventData] 전리품 CSV 없음: "
			+ LOOT_CSV_PATH
		)
		return

	var file := FileAccess.open(
		LOOT_CSV_PATH,
		FileAccess.READ
	)

	if file == null:
		push_error(
			"[ExpeditionEventData] 전리품 CSV 열기 실패"
		)
		return

	var header: PackedStringArray = (
		file.get_csv_line()
	)

	var indexes := _make_header_indexes(
		header
	)

	var required_headers: Array[String] = [
		"table_id",
		"item_id",
		"weight",
		"min_amount",
		"max_amount"
	]

	if not _validate_headers(
		indexes,
		required_headers,
		LOOT_CSV_PATH
	):
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

		var table_id: String = _get_cell(
			row,
			indexes,
			"table_id"
		).strip_edges()

		var item_id: String = _get_cell(
			row,
			indexes,
			"item_id"
		).strip_edges()

		if table_id.is_empty():
			continue

		if item_id.is_empty():
			continue

		if not ItemData.has_item(
			item_id
		):
			push_warning(
				"[ExpeditionEventData] 없는 아이템: "
				+ item_id
			)
			continue

		var entry: Dictionary = {
			"table_id": table_id,

			"item_id": item_id,

			"weight": int(
				_get_cell(
					row,
					indexes,
					"weight"
				)
			),

			"min_amount": int(
				_get_cell(
					row,
					indexes,
					"min_amount"
				)
			),

			"max_amount": int(
				_get_cell(
					row,
					indexes,
					"max_amount"
				)
			)
		}

		loot_entries.append(
			entry
		)


# =========================
# CSV 공통 처리
# =========================

static func _make_header_indexes(
	header: PackedStringArray
) -> Dictionary:
	var result: Dictionary = {}

	for i in range(header.size()):
		var column_name := (
			header[i].strip_edges()
		)

		result[column_name] = i

	return result


static func _validate_headers(
	indexes: Dictionary,
	required_headers: Array[String],
	path: String
) -> bool:
	for header_name in required_headers:
		if not indexes.has(
			header_name
		):
			push_error(
				"[ExpeditionEventData] CSV 열 없음: "
				+ header_name
				+ " / "
				+ path
			)
			return false

	return true


static func _get_cell(
	row: PackedStringArray,
	indexes: Dictionary,
	column_name: String
) -> String:
	if not indexes.has(
		column_name
	):
		return ""

	var index: int = int(
		indexes[column_name]
	)

	if index < 0:
		return ""

	if index >= row.size():
		return ""

	return row[index].strip_edges()

static func _matches_day_filter(
	day_filter: String,
	current_day: int
) -> bool:
	if day_filter.is_empty():
		return true

	if day_filter == "any":
		return true

	if day_filter == "saturday":
		return current_day == 6

	if day_filter == "sunday":
		return current_day == 7

	return false

static func get_missing_event_node_types(
	region_id: String,
	node_types: Array[String],
	current_day: int
) -> Array[String]:
	var missing: Array[String] = []

	for node_type in node_types:
		var candidates: Array[Dictionary] = (
			get_events_by_node_type(
				region_id,
				node_type,
				current_day
			)
		)

		var has_available_event: bool = false

		for event in candidates:
			if int(event.get("weight", 0)) > 0:
				has_available_event = true
				break

		if not has_available_event:
			if not missing.has(node_type):
				missing.append(node_type)

	return missing

static func _is_valid_loot_table(
	table_id: String
) -> bool:
	if table_id.is_empty():
		return false

	var entries: Array[Dictionary] = (
		get_loot_entries(table_id)
	)

	var has_positive_entry: bool = false

	for entry in entries:
		var weight: int = int(
			entry.get("weight", 0)
		)

		if weight <= 0:
			continue

		has_positive_entry = true

		var item_id: String = str(
			entry.get("item_id", "")
		)

		var min_amount: int = int(
			entry.get("min_amount", 0)
		)

		var max_amount: int = int(
			entry.get("max_amount", 0)
		)

		if not ItemData.has_item(item_id):
			return false

		if not ItemData.can_store_in_expedition_bag(
			item_id
		):
			return false

		if min_amount <= 0:
			return false

		if max_amount < min_amount:
			return false

	return has_positive_entry

static func get_invalid_region_event_ids(
	region_id: String,
	node_types: Array[String],
	current_day: int
) -> Array[String]:
	var invalid_event_ids: Array[String] = []

	for node_type in node_types:
		var candidates: Array[Dictionary] = (
			get_events_by_node_type(
				region_id,
				node_type,
				current_day
			)
		)

		for event in candidates:
			if int(event.get("weight", 0)) <= 0:
				continue

			var event_id: String = str(
				event.get("event_id", "")
			)

			var message: String = str(
				event.get("message", "")
			)

			var result_type: String = str(
				event.get("result_type", "")
			)

			var target_id: String = str(
				event.get("target_id", "")
			)

			var value: int = int(
				event.get("value", 0)
			)

			var valid: bool = (
				not event_id.is_empty()
				and not message.is_empty()
			)

			if valid:
				match result_type:
					"battle":
						valid = (
							not target_id.is_empty()
							and not EnemyData.get_enemy(
								target_id
							).is_empty()
						)

					"loot":
						valid = _is_valid_loot_table(
							target_id
						)

					"heal":
						valid = value > 0

					"none":
						valid = true

					_:
						valid = false

			if not valid:
				if event_id.is_empty():
					event_id = (
						region_id
						+ "/"
						+ node_type
						+ "/ID 없음"
					)

				if not invalid_event_ids.has(event_id):
					invalid_event_ids.append(event_id)

	return invalid_event_ids

static func get_random_loot(
	table_id: String
) -> Dictionary:
	var candidates: Array[Dictionary] = (
		get_loot_entries(
			table_id
		)
	)

	if candidates.is_empty():
		push_warning(
			"[ExpeditionEventData] 전리품 테이블 없음: "
			+ table_id
		)
		return {}

	var total_weight: int = 0

	for entry in candidates:
		total_weight += max(
			0,
			int(
				entry.get(
					"weight",
					0
				)
			)
		)

	if total_weight <= 0:
		push_warning(
			"[ExpeditionEventData] 전리품 가중치 합계가 0: "
			+ table_id
		)
		return {}

	var roll: int = randi_range(
		1,
		total_weight
	)

	var accumulated: int = 0

	for entry in candidates:
		accumulated += max(
			0,
			int(
				entry.get(
					"weight",
					0
				)
			)
		)

		if roll <= accumulated:
			return entry.duplicate(true)

	return {}
