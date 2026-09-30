class_name StoryData
extends RefCounted


# 스토리 NPC와 개입 장면(비트)을 CSV에서 읽는다.
# 비트는 조건이 맞으면 NPC가 가게에 찾아와 대화하고 선물을 주는 한 장면이다.
#   conditions: 세미콜론으로 이어진 조건. 모두 맞아야 한다. (StoryConditions 참고)
#   gifts: "종류:아이디:수량"을 세미콜론으로 이어 씀. 종류는 furniture / item / money.
#   repeat_days: 0이면 한 번만, 그 외에는 마지막 발생 후 그 일수가 지나야 다시 발생.
#   lines: 대사. 세로줄(|)로 나눈다.

const NPCS_PATH: String = "res://data/story/story_npcs.csv"
const BEATS_PATH: String = "res://data/story/story_beats.csv"

static var npcs: Dictionary = {}
static var beats: Array[Dictionary] = []
static var _loaded: bool = false


static func ensure_loaded() -> void:
	if _loaded:
		return

	_loaded = true
	_load_npcs()
	_load_beats()


static func reload() -> void:
	npcs.clear()
	beats.clear()
	_loaded = false
	ensure_loaded()


static func get_npc(
	npc_id: String
) -> Dictionary:
	ensure_loaded()

	return npcs.get(
		npc_id,
		{}
	)


static func get_beats() -> Array[Dictionary]:
	ensure_loaded()

	return beats


static func _open_with_header(
	path: String,
	required: Array[String]
) -> Array:
	var file := FileAccess.open(
		path,
		FileAccess.READ
	)

	if file == null:
		push_error(
			"[스토리] CSV 열기 실패: " + path
		)
		return []

	var header: PackedStringArray = file.get_csv_line()
	var indexes: Dictionary = {}

	for i in range(header.size()):
		indexes[header[i].strip_edges()] = i

	for column_name in required:
		if not indexes.has(column_name):
			push_error(
				"[스토리] CSV 열 없음: " + column_name + " / " + path
			)
			file.close()
			return []

	return [file, indexes]


static func _load_npcs() -> void:
	var opened: Array = _open_with_header(
		NPCS_PATH,
		["npc_id", "name", "portrait_path"]
	)

	if opened.is_empty():
		return

	var file: FileAccess = opened[0]
	var indexes: Dictionary = opened[1]

	while file.get_position() < file.get_length():
		var row: PackedStringArray = file.get_csv_line()

		var npc_id: String = CsvReader.get_cell(
			row, indexes, "npc_id"
		)

		if npc_id.is_empty():
			continue

		npcs[npc_id] = {
			"npc_id": npc_id,
			"name": CsvReader.get_cell(row, indexes, "name"),
			"portrait_path": CsvReader.get_cell(
				row, indexes, "portrait_path"
			)
		}

	file.close()


static func _load_beats() -> void:
	var opened: Array = _open_with_header(
		BEATS_PATH,
		["beat_id", "npc_id", "conditions", "gifts", "repeat_days", "lines"]
	)

	if opened.is_empty():
		return

	var file: FileAccess = opened[0]
	var indexes: Dictionary = opened[1]

	while file.get_position() < file.get_length():
		var row: PackedStringArray = file.get_csv_line()

		var beat_id: String = CsvReader.get_cell(
			row, indexes, "beat_id"
		)

		if beat_id.is_empty():
			continue

		var conditions: Array[String] = []

		for text in CsvReader.get_cell(
			row, indexes, "conditions"
		).split(";", false):
			conditions.append(text.strip_edges())

		var gifts: Array[Dictionary] = []

		for text in CsvReader.get_cell(
			row, indexes, "gifts"
		).split(";", false):
			var parts: PackedStringArray = text.strip_edges().split(":")

			if parts.size() < 3:
				push_warning(
					"[스토리] 잘못된 선물 표기: " + text
				)
				continue

			gifts.append(
				{
					"type": parts[0],
					"id": parts[1],
					"amount": maxi(int(parts[2]), 1)
				}
			)

		var lines: Array[String] = []

		for text in CsvReader.get_cell(
			row, indexes, "lines"
		).split("|", false):
			lines.append(text.strip_edges())

		var repeat_text: String = CsvReader.get_cell(
			row, indexes, "repeat_days"
		)

		beats.append(
			{
				"beat_id": beat_id,
				"npc_id": CsvReader.get_cell(row, indexes, "npc_id"),
				"conditions": conditions,
				"gifts": gifts,
				"repeat_days": int(repeat_text) if repeat_text.is_valid_int() else 0,
				"lines": lines
			}
		)

	file.close()
