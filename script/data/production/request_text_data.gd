class_name RequestTextData
extends RefCounted
## Content prose is keyed by kind/id. Gameplay values remain in settings Resources.
const CSV_PATH := "res://data/shop/requests/requests_text.csv"
const COLUMNS: PackedStringArray = ["id", "kind", "title", "summary", "lines", "completion"]
static var _rows: Dictionary = {}
static var _loaded := false

static func read_file(path: String) -> Dictionary:
	var result: Dictionary = {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_warning("[부탁 글] 파일을 읽을 수 없습니다: " + path)
		return result
	if file.get_csv_line() != COLUMNS:
		push_warning("[부탁 글] CSV 열 이름이 다릅니다: " + path)
		return result
	while not file.eof_reached():
		var cells := file.get_csv_line()
		if cells.size() == 1 and cells[0].strip_edges().is_empty(): continue
		if cells.size() != COLUMNS.size() or cells[0].is_empty() or cells[1].is_empty():
			push_warning("[부탁 글] 잘못된 CSV 행을 건너뜁니다: " + path)
			continue
		var key := cells[1] + ":" + cells[0]
		if result.has(key):
			push_warning("[부탁 글] 중복 kind/id를 건너뜁니다: " + key)
			continue
		var entry: Dictionary = {}
		for i in COLUMNS.size(): entry[COLUMNS[i]] = cells[i]
		result[key] = entry
	return result

static func reload() -> void:
	_rows = read_file(CSV_PATH)
	_loaded = true

static func entry(kind: String, id: String) -> Dictionary:
	if not _loaded: reload()
	return _rows.get(kind + ":" + id, {}).duplicate(true)

static func text(kind: String, id: String, field: String, fallback: String = "") -> String:
	var value := str(entry(kind, id).get(field, ""))
	return fallback if value.is_empty() else value

static func lines(kind: String, id: String, field: String = "lines") -> Array[String]:
	var result: Array[String] = []
	for part in text(kind, id, field).split("|", false): result.append(part)
	if result.is_empty(): result.append("이야기를 준비하고 있어요.")
	return result

static func enrich(data: Dictionary, kind: String) -> Dictionary:
	var result := data.duplicate(true)
	var id := str(data.get("id", data.get("type", "")))
	match kind:
		"resident_request", "tutorial_step":
			result["title"] = text(kind,id,"title",str(data.get("title",id)))
			result["lines"] = lines(kind,id)
			result["completion"] = lines(kind,id,"completion")
			if kind == "tutorial_step": result["objective"] = text(kind,id,"summary","안내 인물과 이야기해 보세요.")
		"resident_introduction": result["lines"] = lines(kind,id)
		"resident_greeting":
			var greetings := lines(kind,id)
			while greetings.size() < 4: greetings.append(greetings.back())
			result["greetings"] = greetings
		"community_request":
			result["title"] = text(kind,id,"title",str(data.get("title",id)))
			result["summary"] = text(kind,id,"summary","이웃의 부탁을 준비하고 있어요.")
			result["completion"] = text(kind,id,"completion","이웃과 함께 준비를 마쳤습니다.")
		"trade_offer": result["title"] = text(kind,id,"title",str(data.get("title",id)))
	return result

static func enrich_all(data: Array[Dictionary], kind: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for item in data: result.append(enrich(item,kind))
	return result
