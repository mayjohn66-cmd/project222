extends RefCounted
## 부탁(주민 부탁·마을 부탁 게시판·주민 인사말)의 "글 부분" 도구 모음.
## 기계 부분(재료·수량·보상·landmark)은 건드리지 않고, 같은 id의 글만 CSV로 주고받는다.
## 규격과 분업: docs/스토리_작성_가이드.md 5.1

const COLUMNS: PackedStringArray = ["id", "kind", "title", "summary", "lines", "completion"]

const KIND_RESIDENT_REQUEST: String = "resident_request"   # 주민 부탁: title, lines(부탁 대사), completion(완료 대사)
const KIND_COMMUNITY_REQUEST: String = "community_request"  # 마을 게시판: title, summary, completion
const KIND_RESIDENT_GREETING: String = "resident_greeting"  # 주민 인사말: lines

const KIND_RESIDENT_INTRODUCTION := "resident_introduction"
const KIND_TRADE_OFFER := "trade_offer"
const KIND_TUTORIAL_STEP := "tutorial_step"
const KIND_TUTORIAL_DIALOGUE := "tutorial_dialogue"
const KIND_SERVICE_TEXT := "service_text"
const KIND_PERSONAL_REQUEST := "personal_request"
const KINDS: PackedStringArray = [KIND_RESIDENT_REQUEST, KIND_COMMUNITY_REQUEST, KIND_RESIDENT_GREETING, KIND_RESIDENT_INTRODUCTION, KIND_TRADE_OFFER, KIND_TUTORIAL_STEP, KIND_TUTORIAL_DIALOGUE, KIND_SERVICE_TEXT, KIND_PERSONAL_REQUEST]
const TextData = preload("res://script/data/production/request_text_data.gd")

# 원본(기계 부분이 들어 있는) 파일. 없는 파일은 건너뛴다.
const SOURCE_FILES: Dictionary = {
	"res://scenes/shop/requests/default_resident_requests.tres": KIND_RESIDENT_REQUEST,
	"res://scenes/shop/requests/default_community_requests.tres": KIND_COMMUNITY_REQUEST,
	"res://scenes/shop/requests/default_village_life.tres": KIND_RESIDENT_GREETING,
	"res://scenes/shop/requests/default_resident_story.tres": KIND_RESIDENT_REQUEST,
	"res://scenes/shop/requests/default_resident_trade.tres": KIND_TRADE_OFFER,
	"res://scenes/shop/tutorial/default_tutorial.tres": KIND_TUTORIAL_STEP,
	"res://scenes/shop/requests/default_personal_requests.tres": KIND_PERSONAL_REQUEST,
	"res://scenes/shop/requests/default_village_gathering.tres": KIND_SERVICE_TEXT,
	"res://scenes/shop/requests/default_lantern_wayfarer.tres": KIND_SERVICE_TEXT,
	"res://scenes/shop/requests/default_village_story.tres": KIND_SERVICE_TEXT,
	"res://scenes/shop/requests/default_village_market.tres": KIND_SERVICE_TEXT,
}


# 글이 들어가는 최종 위치(ChatGPT가 만들면 이쪽을 우선 사용). 없으면 기준 문장 파일을 쓴다.
const TEXT_PATH: String = "res://data/shop/requests/requests_text.csv"
const TEXT_FALLBACK_PATH: String = "res://docs/drafts/story/requests_text_baseline.csv"
# 글을 마지막으로 승인했을 때의 "기계 부분" 지문(id, kind, mech_hash). 이게 바뀌면 글을 다시 봐야 한다.
const STATE_PATH: String = "res://docs/drafts/story/requests_text_state.csv"

# 글에 해당하는 필드(이것들은 지문에 넣지 않는다. 나머지가 기계 부분이다).
const TEXT_FIELDS: PackedStringArray = ["title", "summary", "lines", "completion", "greetings", "name", "objective", "npc"]

const MAX_TITLE: int = 20
const MAX_SUMMARY: int = 60
const MAX_COMPLETION: int = 45
const MAX_LINE: int = 45
const MAX_LINES: int = 6

# 게임 용어는 대사에 쓰지 않는다(사람이 하는 부탁으로 말한다).
const FORBIDDEN_WORDS: PackedStringArray = ["퀘스트", "의뢰", "보상", "레벨", "경험치", "미션", "임무", "스탯", "수락", "클리어"]

# 수량·보상 숫자는 데이터가 정한다. 글에 쓰면 수치를 바꿀 때 글이 틀려진다.
const QUANTITY_PATTERN: String = "([0-9]+|한|두|세|네|다섯|여섯|일곱|여덟|아홉|열)\\s?(개|병|장|자루|묶음)"

# AI가 쓴 티가 나는 상투 표현. 쓰면 "주의"로 알리고 자동 수정 때 다시 쓰게 한다. 새로 눈에 띄는 표현은 여기에 더한다.
const CLICHE_PHRASES: PackedStringArray = ["덕분에", "정말 고마", "로구나", "말해 둘게", "말해 줄게", "소개해 줄게", "추천해 줄게", "소문도 내", "참 독특", "!!"]

# 인물별 이름·말버릇. id(요청·인사·소개 id)로 찾는다. 열: id,name,voice
const VOICES_PATH: String = "res://docs/drafts/story/character_voices.csv"
# 공통 인물 기준은 그대로 두고, 새 콘텐츠별 말투는 별도 파일에서 보완한다.
const CONTENT_VOICES_PATH: String = "res://docs/drafts/story/content_voices.csv"

# 여러 항목에서 같은 어구(어절 2개)가 이만큼 반복되면 주의한다. 플레이어 행동 안내("말을 걸") 칸은 세지 않는다.
const REPEAT_ROWS: int = 3


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
			if path.ends_with("default_resident_story.tres"):
				if line.begins_with("introductions ="): kind = KIND_RESIDENT_INTRODUCTION
				if line.begins_with("settlement_requests ="): kind = KIND_RESIDENT_REQUEST
				if line.begins_with("landmarks ="): kind = KIND_SERVICE_TEXT

			if not line.begins_with("{"):
				continue

			var json := JSON.new()

			if json.parse(line) != OK or typeof(json.data) != TYPE_DICTIONARY:
				continue

			var data: Dictionary = json.data
			var id := str(data.get("id", data.get("type", data.get("request", ""))))
			if not data.has("id") and kind == KIND_RESIDENT_REQUEST: continue
			if id.is_empty(): continue
			if kind == KIND_SERVICE_TEXT and not data.has("id"): id = "landmark_" + id
			data["id"] = id
			result[kind][id] = TextData.enrich(data,kind)
	for id in ["trade_panel", "smithy_panel", "trade_first_greeting"]:
		result[KIND_SERVICE_TEXT][id] = {"id":id}
	for id in ["checkout_intro", "checkout_checkout", "checkout_finished"]:
		result[KIND_TUTORIAL_DIALOGUE][id] = {"id":id}

	return result


# 원본 항목 → 글 행(PackedStringArray, COLUMNS 순서). 기준 문장 내보내기에 쓴다.
static func row_from_source(kind: String, data: Dictionary) -> PackedStringArray:
	var title: String = ""
	var summary: String = ""
	var lines: String = ""
	var completion: String = ""

	match kind:
		KIND_PERSONAL_REQUEST, KIND_RESIDENT_INTRODUCTION, KIND_TRADE_OFFER, KIND_TUTORIAL_STEP, KIND_TUTORIAL_DIALOGUE, KIND_SERVICE_TEXT:
			var prose := TextData.entry(kind, str(data["id"]))
			return PackedStringArray([str(data["id"]),kind,str(prose.get("title","")),str(prose.get("summary","")),str(prose.get("lines","")),str(prose.get("completion",""))])
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


# 반환: {id: {name, voice}}. 파일이 없으면 빈 Dictionary.
static func load_voices(path: String = VOICES_PATH) -> Dictionary:
	var voices: Dictionary = {}

	if not FileAccess.file_exists(path):
		return load_voices(CONTENT_VOICES_PATH) if path == VOICES_PATH else voices

	var file := FileAccess.open(path, FileAccess.READ)
	file.get_csv_line()

	while not file.eof_reached():
		var row: PackedStringArray = file.get_csv_line()

		if row.size() >= 3 and not row[0].strip_edges().is_empty():
			voices[row[0].strip_edges()] = {"name": row[1], "voice": row[2]}

	file.close()
	if path == VOICES_PATH:
		voices.merge(load_voices(CONTENT_VOICES_PATH), true)
	return voices


# 모델이 lines 칸을 비우고 대사 전체를 completion 칸에 넣은 행을 바로잡는다(연속된 빈 칸 탭을 세지 못해 생기는 실수).
# 현재 글의 대사 줄 수(L)와 마무리 줄 수(C)를 알고, 비어 있는 lines 와 L+C 칸짜리 completion 이 맞아떨어질 때만 나눈다.
static func fix_shifted_lines(cells: PackedStringArray, known: Dictionary) -> PackedStringArray:
	if cells.size() != COLUMNS.size() or not cells[4].strip_edges().is_empty():
		return cells

	var kind: String = cells[1].strip_edges()
	var id: String = cells[0].strip_edges()

	if not known.get(kind, {}).has(id):
		return cells

	var current: PackedStringArray = row_from_source(kind, known[kind][id])
	var want_lines: int = current[4].split("|", false).size()
	var want_done: int = current[5].split("|", false).size()
	var parts: PackedStringArray = cells[5].split("|", false)

	if want_lines <= 0 or parts.size() != want_lines + want_done:
		return cells

	var fixed: PackedStringArray = cells.duplicate()
	fixed[4] = "|".join(parts.slice(0, want_lines))
	fixed[5] = "|".join(parts.slice(want_lines))
	return fixed


# 한 줄 CSV를 칸으로 나눈다(큰따옴표 안의 쉼표와 ""를 처리).
static func parse_csv_line(line: String) -> PackedStringArray:
	var cells: PackedStringArray = []
	var cur: String = ""
	var quoted: bool = false
	var i: int = 0

	while i < line.length():
		var c: String = line[i]

		if quoted:
			if c == "\"" and i + 1 < line.length() and line[i + 1] == "\"":
				cur += "\""
				i += 1
			elif c == "\"":
				quoted = false
			else:
				cur += c
		elif c == "\"":
			quoted = true
		elif c == ",":
			cells.append(cur)
			cur = ""
		else:
			cur += c

		i += 1

	cells.append(cur)
	return cells


# 제미나이가 비워야 할 칸을 통째로 빼먹어 한 칸 모자란 행을 바로잡는다(resident_request: summary, community_request: lines).
# 다른 경우(칸이 더 많거나 종류를 모를 때)는 건드리지 않고 검사가 오류로 알리게 둔다.
static func fix_missing_empty_cell(cells: PackedStringArray) -> PackedStringArray:
	if cells.size() != COLUMNS.size() - 1:
		return cells

	var fixed: PackedStringArray = cells.duplicate()

	match cells[1].strip_edges():
		KIND_RESIDENT_REQUEST:
			fixed.insert(3, "")
		KIND_COMMUNITY_REQUEST:
			fixed.insert(4, "")
		_:
			return cells

	return fixed


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
	var gram_rows: Dictionary = {}

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
			KIND_PERSONAL_REQUEST:
				_need(errors, tag, "title", title, MAX_TITLE)
				_need(errors, tag, "summary", summary, MAX_SUMMARY)
				_need_lines(errors, warns, tag, lines)
				_need(errors, tag, "completion", completion, MAX_COMPLETION)
				if not "|".join(lines).contains("게시판") or not "|".join(lines).contains("전달"):
					warns.append("%s 플레이어 행동 안내가 없음: 창고에 준비한 뒤 게시판에서 직접 전달하도록 안내하세요" % tag)
			KIND_RESIDENT_INTRODUCTION, KIND_TUTORIAL_DIALOGUE:
				_need_lines(errors,warns,tag,lines)
			KIND_TRADE_OFFER:
				_need(errors,tag,"title",title,MAX_TITLE)
			KIND_TUTORIAL_STEP:
				_need(errors,tag,"title",title,MAX_TITLE)
				_need(errors,tag,"summary",summary,120)
				_need_lines(errors,warns,tag,lines)
			KIND_SERVICE_TEXT:
				if title.is_empty() and summary.is_empty() and lines.is_empty(): errors.append("%s 안내 글이 비어 있음" % tag)
			KIND_RESIDENT_REQUEST:
				_need(errors, tag, "title", title, MAX_TITLE)
				_need_lines(errors, warns, tag, lines)

				if not summary.is_empty():
					errors.append("%s resident_request는 summary가 비어야 함" % tag)

				if not "|".join(lines).contains("말을 걸"):
					warns.append("%s 플레이어 행동 안내가 없음: 창고에 준비한 뒤 '다시 말을 걸어 줘'로 안내하세요" % tag)
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

		# 대사·마무리 줄 수는 현재 문장과 같아야 한다(칸이 하나 사라지면 부탁 내용이 통째로 빠질 수 있다).
		if known.get(kind, {}).has(id):
			var current: PackedStringArray = row_from_source(kind, known[kind][id])
			var cur_lines: int = current[4].split("|", false).size()
			var cur_done: int = current[5].split("|", false).size()

			if cur_lines > 0 and cur_lines != lines.size():
				warns.append("%s 대사 줄 수가 현재와 다름(현재 %d줄, 초안 %d줄): 부탁 내용이 빠지지 않았는지 확인하세요" % [tag, cur_lines, lines.size()])

			if cur_done > 0 and cur_done != completion.split("|", false).size():
				warns.append("%s 마무리 줄 수가 현재와 다름(현재 %d줄, 초안 %d줄)" % [tag, cur_done, completion.split("|", false).size()])

		for phrase in CLICHE_PHRASES:
			if all_text.contains(phrase):
				warns.append("%s 상투 표현 '%s' 이 있음: 인물 사정에 맞는 다른 말로 바꾸세요" % [tag, phrase])

		for cell in _flavor_cells(lines, completion):
			for gram in _bigrams(cell):
				if not gram_rows.has(gram):
					gram_rows[gram] = {}

				gram_rows[gram][id] = true

		var q := quantity.search(all_text)

		if q != null:
			warns.append("%s 수량 표현 '%s' 이 있음: 수치를 바꾸면 글이 틀려지므로 수량은 쓰지 마세요" % [tag, q.get_string()])

	for gram in gram_rows.keys():
		if gram_rows[gram].size() >= REPEAT_ROWS:
			warns.append("반복 어구 '%s' 이 %d개 항목에 나옴(%s): 항목마다 다르게 쓰세요" % [gram, gram_rows[gram].size(), ", ".join(gram_rows[gram].keys())])

	return {"errors": errors, "warns": warns, "rows": rows.size()}


# 반복 검사 대상 칸: 플레이어에게 할 일을 안내하는 칸("말을 걸")은 같은 말이 맞으므로 뺀다.
static func _flavor_cells(lines: PackedStringArray, completion: String) -> PackedStringArray:
	var cells: PackedStringArray = []

	for cell in lines:
		if not cell.contains("말을 걸") and not (cell.contains("게시판") and cell.contains("전달")):
			cells.append(cell)

	for cell in completion.split("|", false):
		cells.append(cell)

	return cells


# 문장부호를 뺀 어절 2개씩의 묶음. 같은 항목 안의 중복은 한 번만 센다.
static func _bigrams(text: String) -> PackedStringArray:
	var clean: String = text
	for mark in [".", ",", "!", "?", "~", "…", "\"", "'"]:
		clean = clean.replace(mark, " ")

	var words: PackedStringArray = clean.split(" ", false)
	var out: PackedStringArray = []

	for i in range(words.size() - 1):
		out.append(words[i] + " " + words[i + 1])

	return out


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

		var kind_sources: Dictionary = sources.get(kind, {})

		for id in kind_sources.keys():
			var key: String = kind + ":" + id

			if not texts.has(key):
				result["new"][kind][id] = kind_sources[id]
			elif state.has(key) and state[key] != fingerprint(kind_sources[id]):
				result["changed"][kind][id] = kind_sources[id]

	for key in texts.keys():
		var parts: PackedStringArray = str(key).split(":", true, 1)

		if parts.size() == 2 and not sources.get(parts[0], {}).is_empty() and not sources[parts[0]].has(parts[1]):
			result["orphan"].append(key)

	return result


static func count_targets(targets: Dictionary) -> int:
	var n: int = 0

	for kind in targets.keys():
		n += targets[kind].size()

	return n


# 초안 행들을 글 CSV에 합친다(같은 kind·id는 덮어쓰고 새 id는 추가). 합친 CSV 텍스트와 새 상태를 돌려준다.
# 지금 글이 있는 모든 항목의 상태를 현재 기계 부분 기준으로 다시 잡는다("지금 글이 현재 데이터를 반영한다"고 선언).
# 인물 이름 교체처럼 글에 영향이 없는 변경 뒤에 쓴다. 반환: 상태 CSV 글.
static func rebase_state_csv(texts: Dictionary, sources: Dictionary) -> String:
	var state: Dictionary = {}

	for kind in KINDS:
		for id in sources.get(kind, {}).keys():
			var k: String = kind + ":" + id

			if texts.has(k):
				state[k] = fingerprint(sources[kind][id])

	var lines: PackedStringArray = [csv_line(PackedStringArray(["id", "kind", "mech_hash"]))]
	var keys: Array = state.keys()
	keys.sort()

	for key in keys:
		var parts: PackedStringArray = str(key).split(":", true, 1)
		lines.append(csv_line(PackedStringArray([parts[1], parts[0], state[key]])))

	return "\n".join(lines) + "\n"


static func merge_draft(texts: Dictionary, draft_rows: Array, sources: Dictionary, state: Dictionary) -> Dictionary:
	var merged: Dictionary = texts.duplicate()
	var new_state: Dictionary = state.duplicate()

	for row in draft_rows:
		var key: String = str(row[1]) + ":" + str(row[0])
		merged[key] = row

		if sources.get(row[1], {}).has(row[0]):
			new_state[key] = fingerprint(sources[row[1]][row[0]])

	# 모든 항목 상태도 채워 둔다(처음 승인할 때 기존 글의 기준을 잡는다).
	for kind in KINDS:
		var kind_sources: Dictionary = sources.get(kind, {})

		for id in kind_sources.keys():
			var k: String = kind + ":" + id

			if merged.has(k) and not new_state.has(k):
				new_state[k] = fingerprint(kind_sources[id])

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
