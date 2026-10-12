class_name DialogueMarks
extends RefCounted


# 대사 한 줄 앞에 붙는 표시를 읽는다. 순서는 상관없고 표시는 겹쳐 쓸 수 있다.
#   *문장        서술(행동 묘사). 이름 없이 괄호로 흐리게 보인다.
#   {놀람}문장    주인공 초상화 표정. 표정 이름은 data/story/portrait_expressions.csv (영문 id도 된다).
#   >문장        NPC 장면 안에서 이 줄만 주인공이 말한다(이름·초상화가 주인공으로 바뀐다).
#   예) "*{피곤}눈꺼풀이 무겁다."  "{걱정}이 세계에서도 음식은 상할 텐데…"  ">{미소}좋아, 같이 해 보자."
# 모르는 {이름}은 표시로 보지 않고 글에 그대로 남긴다({item} 같은 자리표시자와 겹치지 않게).
# 표정은 주인공(화자 "나")의 줄에만 쓰인다. NPC 초상화는 한 장뿐이라 표정 표시는 무시한다.

const DATA_PATH: String = "res://data/story/portrait_expressions.csv"
const NARRATION_MARK: String = "*"
const PLAYER_MARK: String = ">"

static var _ids: Dictionary = {}   # 태그 또는 id -> expression_id
static var _loaded: bool = false


# {narration: bool, player: bool, expression: String(없으면 ""), text: String}
static func parse(line: String) -> Dictionary:
	var text: String = line.strip_edges()
	var narration: bool = false
	var player: bool = false
	var expression: String = ""

	while true:
		if text.begins_with(NARRATION_MARK):
			narration = true
			text = text.substr(1).strip_edges()
		elif text.begins_with(PLAYER_MARK):
			player = true
			text = text.substr(1).strip_edges()
		elif text.begins_with("{") and text.contains("}"):
			var close: int = text.find("}")
			var id: String = resolve(text.substr(1, close - 1).strip_edges())

			# 아는 표정 이름만 표시로 읽는다. {item} 같은 글자 자리표시자는 그대로 둔다.
			if id.is_empty():
				break

			expression = id
			text = text.substr(close + 1).strip_edges()
		else:
			break

	return {"narration": narration, "player": player, "expression": expression, "text": text}


# 표정 태그(한글)나 id(영문)를 expression_id 로. 모르는 표정이면 "".
static func resolve(tag: String) -> String:
	if not _loaded:
		_load()

	return str(_ids.get(tag, ""))


# 글 점검기용: 표시를 뗀 화면 글자.
static func plain_text(line: String) -> String:
	return str(parse(line)["text"])


static func _load() -> void:
	_loaded = true
	_ids.clear()
	var file := FileAccess.open(DATA_PATH, FileAccess.READ)

	if file == null:
		push_warning("[DialogueMarks] 파일 없음: " + DATA_PATH)
		return

	var header: PackedStringArray = file.get_csv_line()
	var indexes: Dictionary = {}

	for i in range(header.size()):
		indexes[header[i].strip_edges()] = i

	while not file.eof_reached():
		var row: PackedStringArray = file.get_csv_line()
		var tag: String = CsvReader.get_cell(row, indexes, "tag")
		var id: String = CsvReader.get_cell(row, indexes, "expression_id")

		if tag.is_empty() or id.is_empty():
			continue

		_ids[tag] = id
		_ids[id] = id
