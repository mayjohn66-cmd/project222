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

	DebugLog.write(
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


# stocked_item_ids: 지금 진열대에 재고가 있는 품목. 카테고리 안에서 이 품목들이
# 더 자주 뽑힌다(GameConfig.DEMAND_STOCKED_WEIGHT_MULT). 비워 두면 재고를 보지 않는다.
static func get_random_wanted_request(
	customer_type_id: String,
	total_day: int,
	stocked_item_ids: Array = []
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
	var total_weight: float = 0.0

	for entry in combined_entries:
		var item_ids: Array[String] = (
			_get_candidate_items(
				entry
			)
		)

		if item_ids.is_empty():
			continue

		var weight: float = float(
			entry.get(
				"weight",
				0
			)
		)

		# 특정 품목을 원하는 행은 지금 재고가 있으면 조금 더 자주 나온다.
		if (
			str(entry.get("target_type", "")) == "item"
			and stocked_item_ids.has(
				str(entry.get("target_id", ""))
			)
		):
			weight *= GameConfig.DEMAND_STOCKED_ENTRY_WEIGHT_MULT

		if weight <= 0.0:
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

	if total_weight <= 0.0:
		return {}

	# =====================================================
	# 가중치 추첨
	# =====================================================

	var roll: float = randf() * total_weight

	var accumulated: float = 0.0

	for candidate in candidates:
		accumulated += float(
			candidate.get(
				"weight",
				0.0
			)
		)

		if roll >= accumulated:
			continue

		var item_ids: Array = candidate.get(
			"item_ids",
			[]
		)

		if item_ids.is_empty():
			return {}

		var item_id: String = _pick_weighted_item(
			item_ids,
			stocked_item_ids
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


# 품목별 가중치로 하나를 뽑는다. 희귀할수록 가볍고, 진열대에 재고가 있으면 무겁다.
static func _pick_weighted_item(
	item_ids: Array,
	stocked_item_ids: Array
) -> String:
	var weights: Array[float] = []
	var total: float = 0.0

	for raw_id in item_ids:
		var item_id: String = str(raw_id)

		var weight: float = float(
			GameConfig.DEMAND_RARITY_WEIGHTS.get(
				ItemData.get_rarity(item_id),
				100.0
			)
		)

		if stocked_item_ids.has(item_id):
			weight *= GameConfig.DEMAND_STOCKED_WEIGHT_MULT

		weights.append(weight)
		total += weight

	if total <= 0.0:
		return str(item_ids.pick_random())

	var roll: float = randf() * total

	for index in range(item_ids.size()):
		roll -= weights[index]

		if roll < 0.0:
			return str(item_ids[index])

	return str(item_ids[item_ids.size() - 1])


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
			CsvReader.get_cell(
				row,
				indexes,
				"customer_type_id"
			)
		)

		var target_type: String = (
			CsvReader.get_cell(
				row,
				indexes,
				"target_type"
			)
		)

		var target_id: String = (
			CsvReader.get_cell(
				row,
				indexes,
				"target_id"
			)
		)

		var weight: int = int(
			CsvReader.get_cell(
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


