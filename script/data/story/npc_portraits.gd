class_name NpcPortraits
extends RefCounted


# 대화 화자 이름으로 NPC 초상화를 찾는다. 값은 data/story/npc_portraits.csv 에 있다(코드에 박지 않음).
# 화자 이름에 keyword 가 들어 있으면 그 초상화를 쓴다("행상인 타블렌", "타블렌" 모두 타블렌).

const DATA_PATH: String = "res://data/story/npc_portraits.csv"
const PLACEHOLDER_PATH: String = "res://art/npc/npc_placeholder.png"

static var _rows: Array[Dictionary] = []
static var _loaded: bool = false


# 넘겨받은 초상화가 없거나 임시 그림이면 화자 이름으로 찾은 초상화를, 아니면 그대로 돌려준다.
static func resolve(speaker: String, given: Texture2D) -> Texture2D:
	if given != null and given.resource_path != PLACEHOLDER_PATH:
		return given

	var found: Texture2D = find(speaker)
	return found if found != null else given


# 화자 이름에 맞는 초상화. 없으면 null.
static func find(speaker: String) -> Texture2D:
	if not _loaded:
		_load()

	for row in _rows:
		if speaker.contains(str(row["keyword"])):
			var path: String = str(row["portrait_path"])
			if ResourceLoader.exists(path):
				return load(path) as Texture2D

	return null


static func _load() -> void:
	_loaded = true
	_rows.clear()
	var file := FileAccess.open(DATA_PATH, FileAccess.READ)

	if file == null:
		push_warning("[NpcPortraits] 파일 없음: " + DATA_PATH)
		return

	var header: PackedStringArray = file.get_csv_line()
	var indexes: Dictionary = {}

	for i in range(header.size()):
		indexes[header[i].strip_edges()] = i

	while not file.eof_reached():
		var row: PackedStringArray = file.get_csv_line()
		var keyword: String = CsvReader.get_cell(row, indexes, "keyword")

		if keyword.is_empty():
			continue

		_rows.append({
			"keyword": keyword,
			"portrait_path": CsvReader.get_cell(row, indexes, "portrait_path"),
		})
