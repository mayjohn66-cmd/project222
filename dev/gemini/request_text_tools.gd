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

# 글이 들어가는 최종 위치(ChatGPT가 만들면 이쪽을 우선 사용). 없으면 기준 문장 파일을 쓴다.
const TEXT_PATH: String = "res://data/shop/requests/requests_text.csv"
const TEXT_FALLBACK_PATH: String = "res://docs/drafts/story/requests_text_baseline.csv"
# 글을 마지막으로 승인했을 때의 "기계 부분" 지문(id, kind, mech_hash). 이게 바뀌면 글을 다시 봐야 한다.
const STATE_PATH: String = "res://docs/drafts/story/requests_text_state.csv"

# 글에 해당하는 필드(이것들은 지문에 넣지 않는다. 나머지가 기계 부분이다).
const TEXT_FIELDS: PackedStringArray = ["title", "summary", "lines", "completion", "greetings", "name"]

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


# ---------- 동기화: 새 항목·기계 부분이 바뀐 항목 찾기 ----------
# 기계 부분 지문: 글 필드를 뺀 나머지를 키 순서대로 문자열로 만들어 md5.
static func fingerprint(data: Dictionary) -> String:
	var mech: Dictionary = {}

	for key in data.keys():
		if not TEXT_FIELDS.has(str(key)):
			mech[key] = data[key]

	return JSON.stringify(mech, "", true).md5_text()


static func text_path() -> String:
	return TEXT_PATH if FileAccess.file_exists(TEXT_PATH) else TEXT_FALLBACK_PATH


# 글 CSV → {"kind:id": 행}
static func load_text_rows(path: String) -> Dictionary:
	var result: Dictionary = {}
	var file := FileAccess.open(path, FileAccess.READ)

	if file == null:
		return result

	file.get_csv_line()

	while not file.eof_reached():
		var row: PackedStringArray = file.get_csv_line()

		if row.size() == COLUMNS.size():
			result[row[1] + ":" + row[0]] = row

	file.close()
	return result


# 상태 CSV → {"kind:id": 지문}
static func load_state(path: String = STATE_PATH) -> Dictionary:
	var result: Dictionary = {}
	var file := FileAccess.open(path, FileAccess.READ)

	if file == null:
		return result

	file.get_csv_line()

	while not file.eof_reached():
		var row: PackedStringArray = file.get_csv_line()

		if row.size() == 3:
			result[row[1] + ":" + row[0]] = row[2]

	file.close()
	return result


# 반환: {"new": {kind: {id: dict}}, "changed": {...}, "orphan": [글만 있고 원본이 없는 "kind:id"]}
# new = 글이 없는 항목, changed = 글은 있지만 승인 뒤에 기계 부분이 바뀐 항목.
# 상태 파일에 없는 기존 글은 "승인된 것"으로 보고 지금 지문을 기준으로 삼는다(처음 한 번은 바뀌지 않은 것으로 취급).
static func find_todo(sources: Dictionary, texts: Dictionary, state: Dictionary) -> Dictionary:
	var result: Dictionary = {"new": {}, "changed": {}, "orphan": []}

	for kind in KINDS:
		result["new"][kind] = {}
		result["changed"][kind] = {}

		for id in sources[kind].keys():
			var key: String = kind + ":" + id

			if not texts.has(key):
				result["new"][kind][id] = sources[kind][id]
			elif state.has(key) and state[key] != fingerprint(sources[kind][id]):
				result["changed"][kind][id] = sources[kind][id]

	for key in texts.keys():
		var parts: PackedStringArray = str(key).split(":", true, 1)

		if parts.size() == 2 and sources.has(parts[0]) and not sources[parts[0]].is_empty() and not sources[parts[0]].has(parts[1]):
			result["orphan"].append(key)

	return result


static func count_targets(targets: Dictionary) -> int:
	var n: int = 0

	for kind in targets.keys():
		n += targets[kind].size()

	return n


# 초안 행들을 글 CSV에 합친다(같은 kind·id는 덮어쓰고 새 id는 추가). 합친 CSV 텍스트와 새 상태를 돌려준다.
static func merge_draft(texts: Dictionary, draft_rows: Array, sources: Dictionary, state: Dictionary) -> Dictionary:
	var merged: Dictionary = texts.duplicate()
	var new_state: Dictionary = state.duplicate()

	for row in draft_rows:
		var key: String = str(row[1]) + ":" + str(row[0])
		merged[key] = row

		if sources.has(row[1]) and sources[row[1]].has(row[0]):
			new_state[key] = fingerprint(sources[row[1]][row[0]])

	# 모든 항목 상태도 채워 둔다(처음 승인할 때 기존 글의 기준을 잡는다).
	for kind in KINDS:
		for id in sources[kind].keys():
			var k: String = kind + ":" + id

			if merged.has(k) and not new_state.has(k):
				new_state[k] = fingerprint(sources[kind][id])

	var lines: PackedStringArray = [csv_line(COLUMNS)]
	var state_lines: PackedStringArray = [csv_line(PackedStringArray(["id", "kind", "mech_hash"]))]
	var keys: Array = merged.keys()
	keys.sort()

	for key in keys:
		lines.append(csv_line(merged[key]))

	var state_keys: Array = new_state.keys()
	state_keys.sort()

	for key in state_keys:
		var parts: PackedStringArray = str(key).split(":", true, 1)
		state_lines.append(csv_line(PackedStringArray([parts[1], parts[0], new_state[key]])))

	return {"csv": "\n".join(lines) + "\n", "state_csv": "\n".join(state_lines) + "\n"}
