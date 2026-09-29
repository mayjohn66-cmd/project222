class_name ExpeditionMapData
extends RefCounted


const CSV_PATH: String = (
	"res://data/expedition/expedition_map_nodes.csv"
)

const REGIONS_CSV_PATH: String = (
	"res://data/expedition/expedition_regions.csv"
)

static var regions: Dictionary = {}
static var _regions_loaded: bool = false


static var node_entries: Array[Dictionary] = []
static var _loaded: bool = false


# =========================
# 로드
# =========================

static func ensure_loaded() -> void:
	if _loaded:
		return

	_load_csv()

	_loaded = true

	print(
		"[ExpeditionMapData] 로드 완료 / 노드 데이터: ",
		node_entries.size()
	)


static func reload() -> void:
	node_entries.clear()
	_loaded = false

	regions.clear()
	_regions_loaded = false

	ensure_loaded()


# =========================
# 지역별 랜덤 노드
# =========================

static func get_random_node_type(
	region_id: String
) -> String:
	ensure_loaded()

	var candidates: Array[Dictionary] = []

	for entry in node_entries:
		var entry_region_id: String = str(
			entry.get(
				"region_id",
				""
			)
		)

		if entry_region_id == region_id:
			candidates.append(
				entry
			)

	if candidates.is_empty():
		push_warning(
			"[ExpeditionMapData] 지역 데이터 없음: "
			+ region_id
		)

		return "battle"

	var total_weight: int = 0

	for entry in candidates:
		var weight: int = int(
			entry.get(
				"weight",
				0
			)
		)

		if weight > 0:
			total_weight += weight

	if total_weight <= 0:
		push_warning(
			"[ExpeditionMapData] 가중치 합계가 0: "
			+ region_id
		)

		return "battle"

	var roll: int = randi_range(
		1,
		total_weight
	)

	var accumulated: int = 0

	for entry in candidates:
		var weight: int = int(
			entry.get(
				"weight",
				0
			)
		)

		if weight <= 0:
			continue

		accumulated += weight

		if roll <= accumulated:
			return str(
				entry.get(
					"node_type",
					"battle"
				)
			)

	return "battle"


# =========================
# CSV 로드
# =========================

static func _load_csv() -> void:
	node_entries.clear()

	if not FileAccess.file_exists(
		CSV_PATH
	):
		push_error(
			"[ExpeditionMapData] CSV 파일 없음: "
			+ CSV_PATH
		)

		return

	var file := FileAccess.open(
		CSV_PATH,
		FileAccess.READ
	)

	if file == null:
		push_error(
			"[ExpeditionMapData] CSV 열기 실패"
		)

		return

	var header: PackedStringArray = (
		file.get_csv_line()
	)

	var indexes: Dictionary = {}

	for i in range(
		header.size()
	):
		var column_name: String = (
			header[i].strip_edges()
		)

		indexes[column_name] = i

	if not indexes.has(
		"region_id"
	):
		push_error(
			"[ExpeditionMapData] region_id 열 없음"
		)

		return

	if not indexes.has(
		"node_type"
	):
		push_error(
			"[ExpeditionMapData] node_type 열 없음"
		)

		return

	if not indexes.has(
		"weight"
	):
		push_error(
			"[ExpeditionMapData] weight 열 없음"
		)

		return

	while (
		file.get_position()
		< file.get_length()
	):
		var row: PackedStringArray = (
			file.get_csv_line()
		)

		if row.size() == 0:
			continue

		var region_id: String = _get_cell(
			row,
			indexes,
			"region_id"
		)

		var node_type: String = _get_cell(
			row,
			indexes,
			"node_type"
		)

		var weight_text: String = _get_cell(
			row,
			indexes,
			"weight"
		)

		if region_id.is_empty():
			continue

		if node_type.is_empty():
			continue

		if weight_text.is_empty():
			continue

		var weight: int = int(
			weight_text
		)

		# 0은 테스트할 때 사용할 수 있으므로
		# 음수만 제외
		if weight < 0:
			continue

		node_entries.append(
			{
				"region_id": region_id,
				"node_type": node_type,
				"weight": weight
			}
		)


# =========================
# CSV 셀 읽기
# =========================

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

# =========================
# 지역 정보
# =========================

static func _load_regions() -> bool:
	var file := FileAccess.open(
		REGIONS_CSV_PATH,
		FileAccess.READ
	)

	if file == null:
		push_error(
			"[원정 지역] CSV 열기 실패: "
			+ REGIONS_CSV_PATH
		)
		return false

	var header: PackedStringArray = file.get_csv_line()
	var indexes: Dictionary = {}

	for i in range(header.size()):
		indexes[header[i].strip_edges()] = i

	var required_headers: Array[String] = [
		"region_id",
		"name",
		"difficulty",
		"description",
		"entry_item_id",
		"entry_amount",
		"consume_on_entry"
	]

	for column_name in required_headers:
		if not indexes.has(column_name):
			push_error(
				"[원정 지역] CSV 열 없음: " + column_name
			)
			file.close()
			return false

	var loaded_regions: Dictionary = {}

	while file.get_position() < file.get_length():
		var row: PackedStringArray = file.get_csv_line()

		var region_id: String = _get_cell(
			row, indexes, "region_id"
		)

		if region_id.is_empty():
			continue

		var region_name: String = _get_cell(
			row, indexes, "name"
		)

		var item_id: String = _get_cell(
			row, indexes, "entry_item_id"
		)

		var amount_text: String = _get_cell(
			row, indexes, "entry_amount"
		)

		var consume_text: String = _get_cell(
			row, indexes, "consume_on_entry"
		).to_lower()

		if (
			loaded_regions.has(region_id)
			or region_name.is_empty()
			or not amount_text.is_valid_int()
			or (
				consume_text != "true"
				and consume_text != "false"
			)
		):
			push_error(
				"[원정 지역] 잘못된 지역 데이터: "
				+ region_id
			)
			file.close()
			return false

		var amount: int = int(amount_text)
		var consume: bool = consume_text == "true"

		if item_id.is_empty():
			if amount != 0 or consume:
				push_error(
					"[원정 지역] 입장 아이템 없는 지역의 설정 오류: "
					+ region_id
				)
				file.close()
				return false
		else:
			if not ItemData.has_item(item_id) or amount <= 0:
				push_error(
					"[원정 지역] 잘못된 입장 아이템 또는 수량: "
					+ region_id
				)
				file.close()
				return false

		loaded_regions[region_id] = {
			"region_id": region_id,

			"name": region_name,

			"difficulty": _get_cell(
				row,
				indexes,
				"difficulty"
			),

			"description": _get_cell(
				row,
				indexes,
				"description"
			),

			"entry_item_id": item_id,

			"entry_amount": amount,

			"consume_on_entry": consume
		}

	file.close()

	regions = loaded_regions
	return true


static func get_region_data(region_id: String) -> Dictionary:
	if not _regions_loaded:
		_regions_loaded = _load_regions()

	if not _regions_loaded or not regions.has(region_id):
		return {}

	return regions[region_id].duplicate(true)


# =========================
# 入장 조건 검사 — 수량 변경 없음
# =========================

static func can_enter_region(region_id: String) -> bool:
	var data: Dictionary = get_region_data(region_id)

	if data.is_empty():
		return false

	var item_id: String = str(data["entry_item_id"])

	if item_id.is_empty():
		return true

	return (
		GameState.get_item_count(item_id)
		>= int(data["entry_amount"])
	)


# =========================
# 출발 시 입장 아이템 처리
# =========================

static func try_pay_entry_cost(region_id: String) -> bool:
	if not can_enter_region(region_id):
		return false

	var data: Dictionary = get_region_data(region_id)

	if not bool(data["consume_on_entry"]):
		return true

	var item_id: String = str(data["entry_item_id"])
	var amount: int = int(data["entry_amount"])

	var removed: int = GameState.remove_item(
		item_id,
		amount
	)

	if removed != amount:
		if removed > 0:
			GameState.add_item(item_id, removed)

		return false

	return true

static func has_valid_region_nodes(
	region_id: String
) -> bool:
	ensure_loaded()

	if get_region_data(region_id).is_empty():
		return false

	var allowed_types: Array[String] = [
		"battle",
		"gather",
		"unknown",
		"treasure"
	]

	var total_weight: int = 0

	for entry in node_entries:
		if str(entry.get("region_id", "")) != region_id:
			continue

		var weight: int = int(
			entry.get("weight", 0)
		)

		if weight <= 0:
			continue

		var node_type: String = str(
			entry.get("node_type", "")
		)

		if not allowed_types.has(node_type):
			push_error(
				"[원정 맵] 잘못된 랜덤 노드 종류: "
				+ region_id
				+ " / "
				+ node_type
			)
			return false

		total_weight += weight

	return total_weight > 0

static func get_required_event_node_types(
	region_id: String
) -> Array[String]:
	ensure_loaded()

	var result: Array[String] = []

	for entry in node_entries:
		if str(entry.get("region_id", "")) != region_id:
			continue

		if int(entry.get("weight", 0)) <= 0:
			continue

		var node_type: String = str(
			entry.get("node_type", "")
		)

		if node_type.is_empty():
			continue

		if not result.has(node_type):
			result.append(node_type)

	if not result.has("boss"):
		result.append("boss")

	return result

static func get_node_type_rates(
	region_id: String
) -> Dictionary:
	ensure_loaded()

	var weights: Dictionary = {}
	var total_weight: int = 0

	for entry in node_entries:
		if str(entry.get("region_id", "")) != region_id:
			continue

		var weight: int = int(
			entry.get("weight", 0)
		)

		if weight <= 0:
			continue

		var node_type: String = str(
			entry.get("node_type", "")
		)

		if node_type.is_empty():
			continue

		weights[node_type] = (
			int(weights.get(node_type, 0))
			+ weight
		)

		total_weight += weight

	if total_weight <= 0:
		return {}

	var rates: Dictionary = {}

	for raw_node_type in weights.keys():
		var node_type: String = str(
			raw_node_type
		)

		rates[node_type] = (
			float(weights[node_type])
			/ float(total_weight)
			* 100.0
		)

	return rates
