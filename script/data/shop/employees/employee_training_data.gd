class_name EmployeeTrainingData
extends RefCounted

const DATA_PATH: String = "res://data/shop/employees/employee_training.csv"

const STAT_IDS: Array[String] = [
	"checkout",
	"restock",
	"movement",
	"service"
]

static var training: Dictionary = {}
static var _loaded: bool = false


static func ensure_loaded() -> void:
	if _loaded:
		return

	var file := FileAccess.open(DATA_PATH, FileAccess.READ)

	if file == null:
		push_error("[직원 교육] CSV 열기 실패: " + DATA_PATH)
		return

	var header: PackedStringArray = file.get_csv_line()

	if (
		header.size() != 4
		or header[0].strip_edges() != "stat_id"
		or header[1].strip_edges() != "level"
		or header[2].strip_edges() != "value"
		or header[3].strip_edges() != "upgrade_cost"
	):
		file.close()
		push_error("[직원 교육] CSV 헤더 오류")
		return

	var loaded_data: Dictionary = {}
	var line_number: int = 1

	while file.get_position() < file.get_length():
		var row: PackedStringArray = file.get_csv_line()
		line_number += 1

		if row.is_empty():
			continue

		if row.size() == 1 and row[0].strip_edges().is_empty():
			continue

		if row.size() != 4:
			file.close()
			push_error("[직원 교육] 열 수 오류 / 줄: " + str(line_number))
			return

		var stat_id: String = row[0].strip_edges()
		var level_text: String = row[1].strip_edges()
		var value_text: String = row[2].strip_edges()
		var cost_text: String = row[3].strip_edges()

		if (
			not STAT_IDS.has(stat_id)
			or not level_text.is_valid_int()
			or not value_text.is_valid_float()
			or not cost_text.is_valid_int()
		):
			file.close()
			push_error("[직원 교육] 값 형식 오류 / 줄: " + str(line_number))
			return

		var level: int = int(level_text)
		var value: float = float(value_text)
		var cost: int = int(cost_text)

		var valid: bool = (
			level >= 0
			and cost >= 0
			and is_finite(value)
		)

		if stat_id == "service":
			valid = valid and value >= 0.0 and value <= 1.0
		else:
			valid = valid and value >= 1.0

		if not valid:
			file.close()
			push_error("[직원 교육] 값 범위 오류 / 줄: " + str(line_number))
			return

		if not loaded_data.has(stat_id):
			loaded_data[stat_id] = {}

		var levels: Dictionary = loaded_data[stat_id]

		if levels.has(level):
			file.close()
			push_error("[직원 교육] 중복 단계 / 줄: " + str(line_number))
			return

		levels[level] = {
			"value": value,
			"upgrade_cost": cost
		}

	file.close()

	# 모든 능력이 0레벨부터 연속으로 정의되어 있어야 함
	for stat_id in STAT_IDS:
		if not loaded_data.has(stat_id):
			push_error("[직원 교육] 능력 데이터 없음: " + stat_id)
			return

		var levels: Dictionary = loaded_data[stat_id]
		var previous_value: float = -1.0

		for level in range(levels.size()):
			if not levels.has(level):
				push_error("[직원 교육] 단계 누락: " + stat_id)
				return

			var entry: Dictionary = levels[level]
			var value: float = float(entry["value"])

			if value < previous_value:
				push_error("[직원 교육] 상위 단계 능력 감소: " + stat_id)
				return

			previous_value = value

	training = loaded_data
	_loaded = true


static func get_level_data(
	stat_id: String,
	level: int
) -> Dictionary:
	ensure_loaded()

	if not training.has(stat_id):
		return {}

	var levels: Dictionary = training[stat_id]

	if not levels.has(level):
		return {}

	return levels[level].duplicate(true)


static func create_default_levels() -> Dictionary:
	return {
		"checkout": 0,
		"restock": 0,
		"movement": 0,
		"service": 0
	}


static func is_levels_valid(levels: Dictionary) -> bool:
	if levels.size() != STAT_IDS.size():
		return false

	for stat_id in STAT_IDS:
		if not levels.get(stat_id) is int:
			return false

		if get_level_data(stat_id, int(levels[stat_id])).is_empty():
			return false

	return true
