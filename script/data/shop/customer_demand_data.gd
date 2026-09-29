class_name CustomerDemandData
extends RefCounted

const CSV_PATH: String = (
	"res://data/shop/catalogs/customer_demands.csv"
)

static var demands_by_type: Dictionary = {}
static var _loaded: bool = false


static func ensure_loaded() -> void:
	if _loaded:
		return

	_load_csv()
	_loaded = true

	print(
		"[CustomerDemandData] 로드 완료 / 손님 종류: ",
		demands_by_type.size()
	)


static func reload() -> void:
	demands_by_type.clear()
	_loaded = false
	ensure_loaded()


static func get_random_wanted_item(
	customer_type_id: String
) -> String:
	var request: Dictionary = (
		get_random_wanted_request(
			customer_type_id,
			GameState.total_day
		)
	)

	return str(
		request.get(
			"item_id",
			""
		)
	)


static func get_random_wanted_request(
	customer_type_id: String,
	total_day: int
) -> Dictionary:
	ensure_loaded()

	var combined_entries: Array[Dictionary] = []

	# =====================================================
	# 손님 유형의 기본 수요
	# =====================================================

	var base_entries: Array = demands_by_type.get(
		customer_type_id,
		[]
	)

	for raw_entry in base_entries:
		if not raw_entry is Dictionary:
			continue

		var base_entry: Dictionary = (
			raw_entry.duplicate(true)
		)

		# 현재 기본 수요는 항상 1개
		base_entry["min_amount"] = 1
		base_entry["max_amount"] = 1
		base_entry["event_id"] = ""

		combined_entries.append(
			base_entry
		)

	# =====================================================
	# 현재 활성 이벤트의 추가 수요
	# =====================================================

	var event_entries: Array[Dictionary] = (
		StoreEventDemandData.get_active_demand_entries(
			customer_type_id,
			total_day
		)
	)

	for event_entry in event_entries:
		combined_entries.append(
			event_entry.duplicate(true)
		)

	# =====================================================
	# 실제 선택 가능한 후보 구성
	# =====================================================

	var candidates: Array[Dictionary] = []
	var total_weight: int = 0

	for entry in combined_entries:
		var item_ids: Array[String] = (
			_get_candidate_items(
				entry
			)
		)

		if item_ids.is_empty():
			continue

		var weight: int = int(
			entry.get(
				"weight",
				0
			)
		)

		if weight <= 0:
			continue

		var min_amount: int = maxi(
			int(
				entry.get(
					"min_amount",
					1
				)
			),
			1
		)

		var max_amount: int = maxi(
			int(
				entry.get(
					"max_amount",
					min_amount
				)
			),
			min_amount
		)

		candidates.append(
			{
				"weight": weight,
				"item_ids": item_ids,
				"min_amount": min_amount,
				"max_amount": max_amount,
				"event_id": str(
					entry.get(
						"event_id",
						""
					)
				)
			}
		)

		total_weight += weight

	if candidates.is_empty():
		return {}

	if total_weight <= 0:
		return {}

	# =====================================================
	# 가중치 추첨
	# =====================================================

	var roll: int = randi_range(
		1,
		total_weight
	)

	var accumulated: int = 0

	for candidate in candidates:
		accumulated += int(
			candidate.get(
				"weight",
				0
			)
		)

		if roll > accumulated:
			continue

		var item_ids: Array = candidate.get(
			"item_ids",
			[]
		)

		if item_ids.is_empty():
			return {}

		var item_id: String = str(
			item_ids.pick_random()
		)

		var min_amount: int = int(
			candidate.get(
				"min_amount",
				1
			)
		)

		var max_amount: int = int(
			candidate.get(
				"max_amount",
				min_amount
			)
		)

		var amount: int = randi_range(
			min_amount,
			max_amount
		)

		return {
			"item_id": item_id,
			"amount": amount,
			"event_id": str(
				candidate.get(
					"event_id",
					""
				)
			)
		}

	return {}


static func _get_candidate_items(
	entry: Dictionary
) -> Array[String]:
	var result: Array[String] = []

	var target_type: String = str(
		entry.get("target_type", "")
	)

	var target_id: String = str(
		entry.get("target_id", "")
	)

	if target_type == "item":
		if (
			ItemData.has_item(target_id)
			and ItemData.is_sellable(target_id)
		):
			result.append(target_id)

		return result

	if target_type == "category":
		var category_items: Array[String] = (
			ItemData.get_items_by_category(
				target_id
			)
		)

		for item_id in category_items:
			if ItemData.is_sellable(item_id):
				result.append(item_id)

	return result


static func _load_csv() -> void:
	demands_by_type.clear()

	if not FileAccess.file_exists(CSV_PATH):
		push_error(
			"[CustomerDemandData] CSV 없음: "
			+ CSV_PATH
		)
		return

	var file := FileAccess.open(
		CSV_PATH,
		FileAccess.READ
	)

	if file == null:
		push_error(
			"[CustomerDemandData] CSV 열기 실패"
		)
		return

	var header: PackedStringArray = (
		file.get_csv_line()
	)

	var indexes: Dictionary = {}

	for index in range(header.size()):
		indexes[
			header[index].strip_edges()
		] = index

	var required_headers: Array[String] = [
		"customer_type_id",
		"target_type",
		"target_id",
		"weight"
	]

	for column_name in required_headers:
		if not indexes.has(column_name):
			push_error(
				"[CustomerDemandData] CSV 열 없음: "
				+ column_name
			)
			return

	while file.get_position() < file.get_length():
		var row: PackedStringArray = (
			file.get_csv_line()
		)

		if row.is_empty():
			continue

		var customer_type_id: String = (
			_get_cell(
				row,
				indexes,
				"customer_type_id"
			)
		)

		var target_type: String = (
			_get_cell(
				row,
				indexes,
				"target_type"
			)
		)

		var target_id: String = (
			_get_cell(
				row,
				indexes,
				"target_id"
			)
		)

		var weight: int = int(
			_get_cell(
				row,
				indexes,
				"weight"
			)
		)

		if (
			customer_type_id.is_empty()
			or target_id.is_empty()
			or weight <= 0
		):
			continue

		if (
			target_type != "category"
			and target_type != "item"
		):
			push_warning(
				"[CustomerDemandData] 잘못된 target_type: "
				+ target_type
			)
			continue

		if not demands_by_type.has(
			customer_type_id
		):
			demands_by_type[customer_type_id] = []

		demands_by_type[
			customer_type_id
		].append(
			{
				"target_type": target_type,
				"target_id": target_id,
				"weight": weight
			}
		)


static func _get_cell(
	row: PackedStringArray,
	indexes: Dictionary,
	column_name: String
) -> String:
	if not indexes.has(column_name):
		return ""

	var index: int = int(
		indexes[column_name]
	)

	if index < 0 or index >= row.size():
		return ""

	return row[index].strip_edges()
