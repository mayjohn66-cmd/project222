class_name PlayerPortraits
extends RefCounted


# 주인공(남·여) 대화 초상화. 값은 data/story/player_portraits.csv 에 있다(코드에 박지 않음).
# 성별은 PlayerProgress.player_gender 에 저장된다. 표정이 없으면 기본 표정(neutral)을 쓴다.

const DATA_PATH: String = "res://data/story/player_portraits.csv"
const DEFAULT_EXPRESSION: String = "neutral"

static var _paths: Dictionary = {}   # "gender:expression" -> portrait_path
static var _loaded: bool = false


# 현재 선택한 성별의 초상화. 없으면 null.
static func find(expression: String = DEFAULT_EXPRESSION) -> Texture2D:
	return find_for(PlayerProgress.player_gender, expression)


static func find_for(gender: String, expression: String = DEFAULT_EXPRESSION) -> Texture2D:
	if not _loaded:
		_load()

	for key in [gender + ":" + expression, gender + ":" + DEFAULT_EXPRESSION]:
		var path: String = str(_paths.get(key, ""))

		if not path.is_empty() and ResourceLoader.exists(path):
			return load(path) as Texture2D

	return null


static func _load() -> void:
	_loaded = true
	_paths.clear()
	var file := FileAccess.open(DATA_PATH, FileAccess.READ)

	if file == null:
		push_warning("[PlayerPortraits] 파일 없음: " + DATA_PATH)
		return

	var header: PackedStringArray = file.get_csv_line()
	var indexes: Dictionary = {}

	for i in range(header.size()):
		indexes[header[i].strip_edges()] = i

	while not file.eof_reached():
		var row: PackedStringArray = file.get_csv_line()
		var gender: String = CsvReader.get_cell(row, indexes, "gender")

		if gender.is_empty():
			continue

		var expression: String = CsvReader.get_cell(row, indexes, "expression")
		_paths[gender + ":" + expression] = CsvReader.get_cell(row, indexes, "portrait_path")
