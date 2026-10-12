class_name UiText
extends RefCounted
## 화면에 나오는 짧은 안내 문구를 코드 밖(data/ui/ui_text.csv)에서 가져온다.
## 키는 "화면.부분.이름" 형식. 값에 %s·%d 가 있으면 f() 로 채운다.
## 새 UI 문구는 코드에 직접 쓰지 않고 여기에 추가한다. 기존 문구는 손댈 때 하나씩 옮긴다(진행 상황: tools/code/ui_text_scan.py).
const CSV_PATH := "res://data/ui/ui_text.csv"
static var _rows: Dictionary = {}
static var _loaded := false

static func reload() -> void:
	_rows.clear()
	_loaded = true
	var file := FileAccess.open(CSV_PATH, FileAccess.READ)
	if file == null:
		push_warning("[UiText] 파일을 읽을 수 없습니다: " + CSV_PATH)
		return
	file.get_csv_line() # 머리글
	while not file.eof_reached():
		var cells := file.get_csv_line()
		if cells.size() < 2 or cells[0].strip_edges().is_empty(): continue
		if _rows.has(cells[0]):
			push_warning("[UiText] 중복 키를 건너뜁니다: " + cells[0])
			continue
		_rows[cells[0]] = cells[1].replace("\\n", "\n")

static func t(key: String, fallback: String = "") -> String:
	if not _loaded: reload()
	if _rows.has(key): return str(_rows[key])
	push_warning("[UiText] 없는 키: " + key)
	return fallback if not fallback.is_empty() else key

static func f(key: String, args: Array) -> String:
	return t(key) % args

static func has_key(key: String) -> bool:
	if not _loaded: reload()
	return _rows.has(key)
