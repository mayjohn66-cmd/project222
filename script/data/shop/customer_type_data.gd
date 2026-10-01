class_name CustomerTypeData
extends RefCounted


# 손님은 두 단계로 나뉜다.
#   대분류(customer_groups.csv): 모험가·광부처럼 큰 무리. 계절과 시간대에 따라 오는 비율이 달라진다.
#   소분류(customer_types.csv): 대분류 안의 종류(궁수·도적·전사 등). 원하는 품목 가중치를 갖는다
#     (customer_demands.csv, 대분류의 수요를 바탕으로 소분류가 덮어쓰거나 추가).
#     계절·시간대는 우선 대분류에서만 정하고, 특정 소분류만 season_weights/period_weights 열에 따로 적는다.
# 방문 손님은 "대분류 뽑기(계절·시간대·이벤트·치장) → 소분류 뽑기" 순서로 정해진다.
# 손님 한 명의 customer_type_id는 소분류 ID이고, 대분류는 group_id로 얻는다.

const GROUPS_CSV_PATH: String = (
	"res://data/shop/catalogs/customer_groups.csv"
)

const CSV_PATH: String = (
	"res://data/shop/catalogs/customer_types.csv"
)

static var customer_groups: Dictionary = {}
static var customer_types: Dictionary = {}
static var _loaded: bool = false


static func ensure_loaded() -> void:
	if _loaded:
		return

	_load_groups_csv()
	_load_csv()
	_loaded = true

	DebugLog.write(
		"[CustomerTypeData] 로드 완료 / 대분류: ",
		customer_groups.size(),
		" / 소분류: ",
		customer_types.size()
	)


static func reload() -> void:
	customer_groups.clear()
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


# 이벤트·치장 효과의 대상이 될 수 있는 ID인지(대분류 또는 소분류).
static func has_customer_target(
	target_id: String
) -> bool:
	ensure_loaded()

	return (
		customer_groups.has(target_id)
		or customer_types.has(target_id)
	)


# 소분류 ID로 대분류 ID를 얻는다. 이미 대분류 ID이면 그대로 돌려준다.
static func get_group_id(
	customer_type_id: String
) -> String:
	ensure_loaded()

	if customer_types.has(customer_type_id):
		return str(
			customer_types[customer_type_id].get(
				"group_id",
				""
			)
		)

	if customer_groups.has(customer_type_id):
		return customer_type_id

	return ""


# period: "morning" / "day" / "evening" / "night". 비우면 시간대를 보지 않는다.
static func get_random_customer_type(
	total_day: int = -1,
	decoration_bonuses: Dictionary = {},
	period: String = ""
) -> Dictionary:
	ensure_loaded()

	if customer_groups.is_empty() or customer_types.is_empty():
		return {}

	var target_day: int = total_day

	if target_day < 1:
		target_day = GameState.total_day

	var season_id: String = CalendarData.get_season_id(
		target_day
	)

	# 1단계: 대분류
	var group_candidates: Array[Dictionary] = []

	for group_data in customer_groups.values():
		var group_id: String = str(
			group_data.get("group_id", "")
		)

		var weight: float = _get_effective_weight(
			float(group_data.get("weight", 0)),
			group_id,
			target_day,
			decoration_bonuses
		)

		weight *= get_group_season_multiplier(
			group_data,
			season_id
		)

		if period != "":
			weight *= get_group_period_multiplier(
				group_data,
				period
			)

		if weight > 0.0:
			group_candidates.append({
				"data": group_data,
				"weight": weight
			})

	var selected_group: Dictionary = _pick_weighted(
		group_candidates
	)

	if selected_group.is_empty():
		return {}

	var selected_group_id: String = str(
		selected_group.get("group_id", "")
	)

	# 2단계: 그 대분류 안의 소분류
	var type_candidates: Array[Dictionary] = []

	for type_data in customer_types.values():
		if not ResidentRequestFlow.customer_available(str(type_data.get("customer_type_id", ""))):
			continue
		if str(type_data.get("group_id", "")) != selected_group_id:
			continue

		var type_weight: float = _get_effective_weight(
			float(type_data.get("weight", 0)),
			str(type_data.get("customer_type_id", "")),
			target_day,
			decoration_bonuses
		)

		# 소분류의 계절·시간대 배수는 특정 손님만 따로 조절할 때 쓴다(비워 두면 1.0).
		type_weight *= get_group_season_multiplier(
			type_data,
			season_id
		)

		if period != "":
			type_weight *= get_group_period_multiplier(
				type_data,
				period
			)

		if type_weight > 0.0:
			type_candidates.append({
				"data": type_data,
				"weight": type_weight
			})

	return _pick_weighted(
		type_candidates
	).duplicate(true)


# 기본 가중치에 이벤트 배수와 치장 보너스를 곱한다(유효하지 않으면 0).
static func _get_effective_weight(
	base_weight: float,
	target_id: String,
	total_day: int,
	decoration_bonuses: Dictionary
) -> float:
	if (
		target_id.is_empty()
		or not is_finite(base_weight)
		or base_weight <= 0.0
	):
		return 0.0

	var event_multiplier: float = (
		StoreEventCustomerModifierData
		.get_active_weight_multiplier(
			target_id,
			total_day
		)
	)

	if not is_finite(event_multiplier) or event_multiplier <= 0.0:
		return 0.0

	# 0.20이면 가중치 +20%
	var decoration_bonus: float = float(
		decoration_bonuses.get(target_id, 0.0)
	)

	if not is_finite(decoration_bonus):
		decoration_bonus = 0.0

	decoration_bonus = maxf(decoration_bonus, 0.0)

	var result: float = (
		base_weight
		* event_multiplier
		* (1.0 + decoration_bonus)
	)

	return result if is_finite(result) else 0.0


static func _pick_weighted(
	candidates: Array[Dictionary]
) -> Dictionary:
	var total_weight: float = 0.0

	for candidate in candidates:
		total_weight += float(candidate["weight"])

	if candidates.is_empty() or total_weight <= 0.0:
		return {}

	var roll: float = randf() * total_weight
	var accumulated: float = 0.0

	for candidate in candidates:
		accumulated += float(candidate["weight"])

		if roll < accumulated:
			return candidate["data"]

	# 부동소수점 오차로 마지막 후보를 지나친 경우
	return candidates[candidates.size() - 1]["data"]


static func get_group_season_multiplier(
	group_data: Dictionary,
	season_id: String
) -> float:
	var weights: Dictionary = group_data.get(
		"season_weights",
		{}
	)

	return float(weights.get(season_id, 1.0))


static func get_group_period_multiplier(
	group_data: Dictionary,
	period: String
) -> float:
	var weights: Dictionary = group_data.get(
		"period_weights",
		{}
	)

	return float(weights.get(period, 1.0))


static func get_all_customer_groups() -> Array[Dictionary]:
	ensure_loaded()

	var result: Array[Dictionary] = []

	for data in customer_groups.values():
		result.append(
			data.duplicate(true)
		)

	return result


static func get_customer_group(
	group_id: String
) -> Dictionary:
	ensure_loaded()

	if not customer_groups.has(group_id):
		return {}

	return customer_groups[group_id].duplicate(true)


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


# 소분류 이름을 돌려준다. 대분류 ID(치장·이벤트 대상)도 이름으로 바꿔 준다.
static func get_display_name(
	customer_type_id: String
) -> String:
	var data: Dictionary = (
		get_customer_type(customer_type_id)
	)

	if data.is_empty():
		data = get_customer_group(customer_type_id)

	if data.is_empty():
		return customer_type_id

	return str(
		data.get(
			"display_name",
			customer_type_id
		)
	)


# "spring:1.4|winter:0.6" 형식을 {"spring": 1.4, "winter": 0.6}으로 바꾼다.
# 적히지 않은 키는 기본값 1.0으로 취급한다.
static func parse_weight_map(
	text: String
) -> Dictionary:
	var result: Dictionary = {}

	for part in text.split("|", false):
		var pair: PackedStringArray = part.split(":")

		if pair.size() != 2:
			push_warning(
				"[CustomerTypeData] 잘못된 가중치 형식: " + part
			)
			continue

		var key: String = pair[0].strip_edges()
		var value_text: String = pair[1].strip_edges()

		if key.is_empty() or not value_text.is_valid_float():
			push_warning(
				"[CustomerTypeData] 잘못된 가중치 형식: " + part
			)
			continue

		result[key] = maxf(float(value_text), 0.0)

	return result


static func _open_csv(
	path: String,
	required_headers: Array[String]
) -> Array:
	if not FileAccess.file_exists(path):
		push_error(
			"[CustomerTypeData] CSV 없음: " + path
		)
		return []

	var file := FileAccess.open(
		path,
		FileAccess.READ
	)

	if file == null:
		push_error(
			"[CustomerTypeData] CSV 열기 실패: " + path
		)
		return []

	var header: PackedStringArray = (
		file.get_csv_line()
	)

	var indexes: Dictionary = {}

	for index in range(header.size()):
		indexes[
			header[index].strip_edges()
		] = index

	for column_name in required_headers:
		if indexes.has(column_name):
			continue

		push_error(
			"[CustomerTypeData] CSV 열 없음: "
			+ column_name
			+ " / "
			+ path
		)
		return []

	return [file, indexes]


static func _load_groups_csv() -> void:
	customer_groups.clear()

	var opened: Array = _open_csv(
		GROUPS_CSV_PATH,
		["group_id", "display_name", "weight"]
	)

	if opened.is_empty():
		return

	var file: FileAccess = opened[0]
	var indexes: Dictionary = opened[1]

	while (
		file.get_position()
		< file.get_length()
	):
		var row: PackedStringArray = (
			file.get_csv_line()
		)

		if row.is_empty():
			continue

		var group_id: String = CsvReader.get_cell(
			row,
			indexes,
			"group_id"
		)

		if group_id.is_empty():
			continue

		if customer_groups.has(group_id):
			push_warning(
				"[CustomerTypeData] 중복 대분류 ID: " + group_id
			)
			continue

		var display_name: String = CsvReader.get_cell(
			row,
			indexes,
			"display_name"
		)

		var weight: int = int(
			CsvReader.get_cell(
				row,
				indexes,
				"weight"
			)
		)

		if display_name.is_empty() or weight <= 0:
			push_warning(
				"[CustomerTypeData] 대분류 데이터 오류: " + group_id
			)
			continue

		customer_groups[group_id] = {
			"group_id": group_id,
			"display_name": display_name,
			"weight": weight,
			"description": CsvReader.get_cell(
				row,
				indexes,
				"description"
			),
			"season_weights": parse_weight_map(
				CsvReader.get_cell(
					row,
					indexes,
					"season_weights"
				)
			),
			"period_weights": parse_weight_map(
				CsvReader.get_cell(
					row,
					indexes,
					"period_weights"
				)
			)
		}


static func _load_csv() -> void:
	customer_types.clear()

	var opened: Array = _open_csv(
		CSV_PATH,
		[
			"customer_type_id",
			"display_name",
			"group_id",
			"weight",
			"description"
		]
	)

	if opened.is_empty():
		return

	var file: FileAccess = opened[0]
	var indexes: Dictionary = opened[1]

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

		if (
			customer_types.has(customer_type_id)
			or customer_groups.has(customer_type_id)
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

		var group_id: String = (
			CsvReader.get_cell(
				row,
				indexes,
				"group_id"
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

		if not customer_groups.has(group_id):
			push_warning(
				"[CustomerTypeData] 대분류를 찾을 수 없음: "
				+ customer_type_id
				+ " → "
				+ group_id
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
			"group_id": group_id,
			"weight": weight,
			"description": CsvReader.get_cell(
				row,
				indexes,
				"description"
			),
			"season_weights": parse_weight_map(
				CsvReader.get_cell(
					row,
					indexes,
					"season_weights"
				)
			),
			"period_weights": parse_weight_map(
				CsvReader.get_cell(
					row,
					indexes,
					"period_weights"
				)
			)
		}
