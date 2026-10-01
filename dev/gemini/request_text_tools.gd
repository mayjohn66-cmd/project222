extends RefCounted
## 부탁(주민 부탁·마을 부탁 게시판·주민 인사말)의 "글 부분" 도구 모음.
## 기계 부분(재료·수량·보상·landmark)은 건드리지 않고, 같은 id의 글만 CSV로 주고받는다.
## 규격과 분업: docs/스토리_작성_가이드.md 5.1

const COLUMNS: PackedStringArray = ["id", "kind", "title", "summary", "lines", "completion"]

const KIND_RESIDENT_REQUEST: String = "resident_request"   # 주민 부탁: title, lines(부탁 대사), completion(완료 대사)
const KIND_COMMUNITY_REQUEST: String = "community_request"  # 마을 게시판: title, summary, completion
const KIND_RESIDENT_GREETING: String = "resident_greeting"  # 주민 인사말: lines

const KINDS: PackedStringArray = [KIND_RESIDENT_REQUEST, KIND_COMMUNITY_REQUEST, KIND_RESIDENT_GREETING]

# 원본(기계 부분이 들어 있는) 파일. 없는 파일은 건너뛴다.
const SOURCE_FILES: Dictionary = {
	"res://scenes/shop/requests/default_resident_requests.tres": KIND_RESIDENT_REQUEST,
	"res://scenes/shop/requests/default_community_requests.tres": KIND_COMMUNITY_REQUEST,
	"res://scenes/shop/requests/default_village_life.tres": KIND_RESIDENT_GREETING,
}

const MAX_TITLE: int = 20
const MAX_SUMMARY: int = 60
const MAX_COMPLETION: int = 45
const MAX_LINE: int = 45
const MAX_LINES: int = 6

# 게임 용어는 대사에 쓰지 않는다(사람이 하는 부탁으로 말한다).
const FORBIDDEN_WORDS: PackedStringArray = ["퀘스트", "의뢰", "보상", "레벨", "경험치", "미션", "임무", "스탯", "수락", "클리어"]

# 수량·보상 숫자는 데이터가 정한다. 글에 쓰면 수치를 바꿀 때 글이 틀려진다.
const QUANTITY_PATTERN: String = "([0-9]+|한|두|세|네|다섯|여섯|일곱|여덟|아홉|열)\\s?(개|병|장|자루|묶음)"


# ---------- 원본 읽기 ----------
# `.tres`의 한 줄 항목({"id":...},)은 JSON 모양이라 스크립트 없이 그대로 읽는다.
# 반환: {kind: {id: 항목 Dictionary}}
static func load_sources() -> Dictionary:
	var result: Dictionary = {}

	for kind in KINDS:
		result[kind] = {}

	for path in SOURCE_FILES.keys():
		if not FileAccess.file_exists(path):
			continue

		var kind: String = SOURCE_FILES[path]

		for raw_line in FileAccess.get_file_as_string(path).split("\n"):
			var line: String = raw_line.strip_edges().trim_suffix(",")

			if not line.begins_with("{\"id\""):
				continue

			var json := JSON.new()

			if json.parse(line) != OK or typeof(json.data) != TYPE_DICTIONARY:
				continue

			result[kind][str(json.data["id"])] = json.data

	return result


# 원본 항목 → 글 행(PackedStringArray, COLUMNS 순서). 기준 문장 내보내기에 쓴다.
static func row_from_source(kind: String, data: Dictionary) -> PackedStringArray:
	var title: String = ""
	var summary: String = ""
	var lines: String = ""
	var completion: String = ""

	match kind:
		KIND_RESIDENT_REQUEST:
			title = str(data.get("title", ""))
			lines = "|".join(PackedStringArray(data.get("lines", [])))
			completion = "|".join(PackedStringArray(data.get("completion", [])))
		KIND_COMMUNITY_REQUEST:
			title = str(data.get("title", ""))
			summary = str(data.get("summary", ""))
			completion = str(data.get("completion", ""))
		KIND_RESIDENT_GREETING:
			lines = "|".join(PackedStringArray(data.get("greetings", [])))

	return PackedStringArray([str(data["id"]), kind, title, summary, lines, completion])


static func csv_line(values: PackedStringArray) -> String:
	var parts: PackedStringArray = []

	for v in values:
		if v.contains(",") or v.contains("\"") or v.contains("\n"):
			parts.append("\"" + v.replace("\"", "\"\"") + "\"")
		else:
			parts.append(v)

	return ",".join(parts)


# ---------- 검사 ----------
# known: load_sources() 결과 형식. 반환: {errors, warns, rows}
static func validate_rows(header: PackedStringArray, rows: Array, known: Dictionary, tag_name: String = "csv") -> Dictionary:
	var errors: Array[String] = []
	var warns: Array[String] = []

	if header != COLUMNS:
		errors.append("열 이름이 %s 와 다릅니다: %s" % [str(COLUMNS), str(header)])

	var seen: Dictionary = {}
	var quantity := RegEx.create_from_string(QUANTITY_PATTERN)

	for index in rows.size():
		var row: PackedStringArray = rows[index]
		var tag: String = "%s:%d" % [tag_name, index + 2]

		if row.size() != COLUMNS.size():
			errors.append("%s 칸 수가 %d개(필요 %d개). 쉼표가 있는 칸은 큰따옴표로 감싸세요" % [tag, row.size(), COLUMNS.size()])
			continue

		var id: String = row[0].strip_edges()
		var kind: String = row[1].strip_edges()
		var title: String = row[2]
		var summary: String = row[3]
		var lines: PackedStringArray = row[4].split("|", false)
		var completion: String = row[5]
		tag += " [%s]" % id

		if not KINDS.has(kind):
			errors.append("%s kind는 %s 중 하나" % [tag, str(KINDS)])
			continue

		var key: String = kind + ":" + id

		if seen.has(key):
			errors.append("%s 같은 kind·id가 두 번 나옴" % tag)

		seen[key] = true

		if known.get(kind, {}).is_empty():
			warns.append("%s 원본 파일이 없어 id를 확인하지 못함(kind: %s)" % [tag, kind])
		elif not known[kind].has(id):
			errors.append("%s 원본에 없는 id입니다. 제미나이는 새 id를 만들 수 없습니다" % tag)

		match kind:
			KIND_RESIDENT_REQUEST:
				_need(errors, tag, "title", title, MAX_TITLE)
				_need_lines(errors, warns, tag, lines)

				if not summary.is_empty():
					errors.append("%s resident_request는 summary가 비어야 함" % tag)
			KIND_COMMUNITY_REQUEST:
				_need(errors, tag, "title", title, MAX_TITLE)
				_need(errors, tag, "summary", summary, MAX_SUMMARY)

				if not lines.is_empty():
					errors.append("%s community_request는 lines가 비어야 함" % tag)
			KIND_RESIDENT_GREETING:
				_need_lines(errors, warns, tag, lines)

				if not title.is_empty() or not summary.is_empty() or not completion.is_empty():
					errors.append("%s resident_greeting은 lines만 씀" % tag)

		if completion.length() > MAX_COMPLETION * MAX_LINES:
			warns.append("%s completion이 너무 김" % tag)

		for part in completion.split("|", false):
			if part.length() > MAX_COMPLETION:
				warns.append("%s completion 한 칸이 %d자(권장 %d 이하)" % [tag, part.length(), MAX_COMPLETION])

		var all_text: String = " ".join([title, summary, "|".join(lines), completion])

		for word in FORBIDDEN_WORDS:
			if all_text.contains(word):
				errors.append("%s 게임 용어 '%s' 사용 금지(사람의 부탁으로 말하세요)" % [tag, word])

		var q := quantity.search(all_text)

		if q != null:
			warns.append("%s 수량 표현 '%s' 이 있음: 수치를 바꾸면 글이 틀려지므로 수량은 쓰지 마세요" % [tag, q.get_string()])

	return {"errors": errors, "warns": warns, "rows": rows.size()}


static func _need(errors: Array[String], tag: String, field: String, value: String, max_len: int) -> void:
	if value.strip_edges().is_empty():
		errors.append("%s %s가 비어 있음" % [tag, field])
	elif value.length() > max_len:
		errors.append("%s %s가 %d자(최대 %d)" % [tag, field, value.length(), max_len])


static func _need_lines(errors: Array[String], warns: Array[String], tag: String, lines: PackedStringArray) -> void:
	if lines.is_empty():
		errors.append("%s lines가 비어 있음" % tag)
		return

	if lines.size() > MAX_LINES:
		warns.append("%s lines가 %d칸(권장 %d 이하)" % [tag, lines.size(), MAX_LINES])

	for x in lines:
		if x.strip_edges().is_empty():
			errors.append("%s lines에 빈 칸이 있음" % tag)
		elif x.length() > MAX_LINE:
			errors.append("%s lines 한 칸이 %d자(최대 %d)" % [tag, x.length(), MAX_LINE])


static func validate_file(path: String, known: Dictionary) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)

	if file == null:
		return {"errors": ["파일을 열 수 없음: " + path], "warns": [], "rows": 0}

	var header: PackedStringArray = file.get_csv_line()
	var rows: Array = []

	while not file.eof_reached():
		var line: PackedStringArray = file.get_csv_line()

		if line.size() == 1 and line[0].strip_edges().is_empty():
			continue

		rows.append(line)

	file.close()
	return validate_rows(header, rows, known, path.get_file())
