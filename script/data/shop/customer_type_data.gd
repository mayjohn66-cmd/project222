class_name CustomerTypeData
extends RefCounted

const CSV_PATH: String = (
	"res://data/shop/catalogs/customer_types.csv"
)

static var customer_types: Dictionary = {}
static var _loaded: bool = false


static func ensure_loaded() -> void:
	if _loaded:
		return

	_load_csv()
	_loaded = true

	DebugLog.write(
		"[CustomerTypeData] 로드 완료 / 손님 종류: ",
		customer_types.size()
	)


static func reload() -> void:
	customer_types.clear()
	_loaded = false
	ensure_loaded()


static func has_customer_type(
	customer_type_id: String
) -> bool:
	ensure_loaded()

	return customer_types.has(
		customer_type_id
	)


static func get_random_customer_type(
	total_day: int = -1,
	decoration_bonuses: Dictionary = {}
) -> Dictionary:
	ensure_loaded()

	if customer_types.is_empty():
		return {}

	var target_day: int = total_day

	if target_day < 1:
		target_day = GameState.total_day

	var candidates: Array[Dictionary] = []
	var total_weight: float = 0.0

	for data in customer_types.values():
		var customer_type_id: String = str(
			data.get("customer_type_id", "")
		)

		if customer_type_id.is_empty():
			continue

		var base_weight: float = float(
			data.get("weight", 0)
		)

		if not is_finite(base_weight) or base_weight <= 0.0:
			continue

		var event_multiplier: float = (
			StoreEventCustomerModifierData
			.get_active_weight_multiplier(
				customer_type_id,
				target_day
			)
		)

		if (
			not is_finite(event_multiplier)
			or event_multiplier <= 0.0
		):
			continue

		# 해당 손님 유형을 대상으로 하는 치장 효과
		# 0.20이면 가중치 +20%
		var decoration_bonus: float = float(
			decoration_bonuses.get(customer_type_id, 0.0)
		)

		if not is_finite(decoration_bonus):
			decoration_bonus = 0.0

		decoration_bonus = maxf(decoration_bonus, 0.0)

		var effective_weight: float = (
			base_weight
			* event_multiplier
			* (1.0 + decoration_bonus)
		)

		if (
			not is_finite(effective_weight)
			or effective_weight <= 0.0
		):
			continue

		candidates.append({
			"data": data,
			"effective_weight": effective_weight
		})

		total_weight += effective_weight

	if (
		candidates.is_empty()
		or not is_finite(total_weight)
		or total_weight <= 0.0
	):
		return {}

	var roll: float = randf() * total_weight
	var accumulated: float = 0.0

	for candidate in candidates:
		accumulated += float(
			candidate["effective_weight"]
		)

		if roll < accumulated:
			var selected_data: Dictionary = candidate["data"]
			return selected_data.duplicate(true)

	# 부동소수점 오차로 마지막 후보를 지나친 경우
	var last_candidate: Dictionary = candidates[
		candidates.size() - 1
	]
	var last_data: Dictionary = last_candidate["data"]

	return last_data.duplicate(true)


static func get_all_customer_types() -> Array[Dictionary]:
	ensure_loaded()

	var result: Array[Dictionary] = []

	for data in customer_types.values():
		result.append(
			data.duplicate(true)
		)

	return result

static func get_customer_type(
	customer_type_id: String
) -> Dictionary:
	ensure_loaded()

	if not customer_types.has(customer_type_id):
		return {}

	return customer_types[customer_type_id].duplicate(true)


static func get_display_name(
	customer_type_id: String
) -> String:
	var data: Dictionary = (
		get_customer_type(customer_type_id)
	)

	if data.is_empty():
		return customer_type_id

	return str(
		data.get(
			"display_name",
			customer_type_id
		)
	)


static func _load_csv() -> void:
	customer_types.clear()

	if not FileAccess.file_exists(
		CSV_PATH
	):
		push_error(
			"[CustomerTypeData] CSV 없음: "
			+ CSV_PATH
		)
		return

	var file := FileAccess.open(
		CSV_PATH,
		FileAccess.READ
	)

	if file == null:
		push_error(
			"[CustomerTypeData] CSV 열기 실패"
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
		"display_name",
		"weight",
		"description"
	]

	for column_name in required_headers:
		if indexes.has(column_name):
			continue

		push_error(
			"[CustomerTypeData] CSV 열 없음: "
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

		var customer_type_id: String = (
			CsvReader.get_cell(
				row,
				indexes,
				"customer_type_id"
			)
		)

		if customer_type_id.is_empty():
			continue

		if customer_types.has(
			customer_type_id
		):
			push_warning(
				"[CustomerTypeData] 중복 ID: "
				+ customer_type_id
			)
			continue

		var display_name: String = (
			CsvReader.get_cell(
				row,
				indexes,
				"display_name"
			)
		)

		var weight: int = int(
			CsvReader.get_cell(
				row,
				indexes,
				"weight"
			)
		)

		if display_name.is_empty():
			push_warning(
				"[CustomerTypeData] 이름 없음: "
				+ customer_type_id
			)
			continue

		if weight <= 0:
			push_warning(
				"[CustomerTypeData] 잘못된 가중치: "
				+ customer_type_id
			)
			continue

		customer_types[customer_type_id] = {
			"customer_type_id": customer_type_id,
			"display_name": display_name,
			"weight": weight,
			"description": CsvReader.get_cell(
				row,
				indexes,
				"description"
			)
		}


