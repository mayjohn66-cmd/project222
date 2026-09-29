class_name ExpeditionGatheringData
extends RefCounted


const DATA_PATH: String = (
	"res://data/expedition/expedition_gathering_rules.csv"
)


static var rules: Dictionary = {}
static var _loaded: bool = false


static func ensure_loaded() -> void:
	if _loaded:
		return

	load_data()


static func load_data() -> void:
	rules.clear()
	_loaded = false

	if not FileAccess.file_exists(DATA_PATH):
		push_error(
			"[ExpeditionGatheringData] 파일 없음: "
			+ DATA_PATH
		)
		return

	var file := FileAccess.open(
		DATA_PATH,
		FileAccess.READ
	)

	if file == null:
		push_error(
			"[ExpeditionGatheringData] 파일 열기 실패"
		)
		return

	if file.eof_reached():
		file.close()
		push_error(
			"[ExpeditionGatheringData] CSV가 비어 있습니다."
		)
		return

	var header: PackedStringArray = (
		file.get_csv_line()
	)

	var indexes: Dictionary = {}

	for index in range(header.size()):
		var column_name: String = str(
			header[index]
		).strip_edges()

		if not column_name.is_empty():
			indexes[column_name] = index

	var required_headers: Array[String] = [
		"loot_table_id",
		"tool_effect_id",
		"no_tool_success_rate",
		"tool_success_rate",
		"tool_bonus_amount",
		"enhancement_bonus_per_level",
		"tool_required"
	]

	for column in required_headers:
		if indexes.has(column):
			continue

		file.close()

		push_error(
			"[ExpeditionGatheringData] CSV 열 없음: "
			+ column
		)
		return

	var loaded_rules: Dictionary = {}
	var line_number: int = 1

	while file.get_position() < file.get_length():
		var row: PackedStringArray = (
			file.get_csv_line()
		)

		line_number += 1

		if _is_empty_row(row):
			continue

		var table_id: String = CsvReader.get_cell(
			row,
			indexes,
			"loot_table_id"
		)

		var tool_effect_id: String = CsvReader.get_cell(
			row,
			indexes,
			"tool_effect_id"
		)

		var no_tool_rate_text: String = CsvReader.get_cell(
			row,
			indexes,
			"no_tool_success_rate"
		)

		var tool_rate_text: String = CsvReader.get_cell(
			row,
			indexes,
			"tool_success_rate"
		)

		var tool_bonus_text: String = CsvReader.get_cell(
			row,
			indexes,
			"tool_bonus_amount"
		)

		var level_bonus_text: String = CsvReader.get_cell(
			row,
			indexes,
			"enhancement_bonus_per_level"
		)

		var required_text: String = CsvReader.get_cell(
			row,
			indexes,
			"tool_required"
		).to_lower()

		if table_id.is_empty():
			file.close()
			push_error(
				"[채집 규칙] 테이블 ID 없음 / 줄: "
				+ str(line_number)
			)
			return

		if loaded_rules.has(table_id):
			file.close()
			push_error(
				"[채집 규칙] 중복 테이블 ID: "
				+ table_id
			)
			return

		if tool_effect_id.is_empty():
			file.close()
			push_error(
				"[채집 규칙] 도구 효과 ID 없음: "
				+ table_id
			)
			return

		if (
			not no_tool_rate_text.is_valid_float()
			or not tool_rate_text.is_valid_float()
		):
			file.close()
			push_error(
				"[채집 규칙] 성공률 형식 오류: "
				+ table_id
			)
			return

		var no_tool_rate: float = float(
			no_tool_rate_text
		)

		var tool_rate: float = float(
			tool_rate_text
		)

		if (
			not is_finite(no_tool_rate)
			or not is_finite(tool_rate)
			or no_tool_rate < 0.0
			or no_tool_rate > 1.0
			or tool_rate < 0.0
			or tool_rate > 1.0
		):
			file.close()
			push_error(
				"[채집 규칙] 성공률 범위 오류: "
				+ table_id
			)
			return

		if (
			not tool_bonus_text.is_valid_int()
			or not level_bonus_text.is_valid_int()
		):
			file.close()
			push_error(
				"[채집 규칙] 추가 획득량 형식 오류: "
				+ table_id
			)
			return

		var tool_bonus_amount: int = int(
			tool_bonus_text
		)

		var level_bonus: int = int(
			level_bonus_text
		)

		if (
			tool_bonus_amount < 0
			or level_bonus < 0
		):
			file.close()
			push_error(
				"[채집 규칙] 추가 획득량 범위 오류: "
				+ table_id
			)
			return

		if (
			required_text != "true"
			and required_text != "false"
		):
			file.close()
			push_error(
				"[채집 규칙] tool_required 형식 오류: "
				+ table_id
			)
			return

		loaded_rules[table_id] = {
			"loot_table_id": table_id,
			"tool_effect_id": tool_effect_id,
			"no_tool_success_rate": no_tool_rate,
			"tool_success_rate": tool_rate,
			"tool_bonus_amount": tool_bonus_amount,
			"enhancement_bonus_per_level": level_bonus,
			"tool_required": (
				required_text == "true"
			)
		}

	file.close()

	rules = loaded_rules
	_loaded = true

	print(
		"[ExpeditionGatheringData] 로드 완료"
		+ " / 채집 규칙: ",
		rules.size()
	)


static func has_rule(
	loot_table_id: String
) -> bool:
	ensure_loaded()

	return rules.has(
		loot_table_id
	)


static func get_rule(
	loot_table_id: String
) -> Dictionary:
	ensure_loaded()

	if not rules.has(loot_table_id):
		return {}

	return rules[
		loot_table_id
	].duplicate(true)


static func get_all_rules() -> Array[Dictionary]:
	ensure_loaded()

	var result: Array[Dictionary] = []

	for rule in rules.values():
		result.append(
			rule.duplicate(true)
		)

	return result


static func _is_empty_row(
	row: PackedStringArray
) -> bool:
	if row.is_empty():
		return true

	for cell in row:
		if not str(cell).strip_edges().is_empty():
			return false

	return true
