extends Node
## 스토리 초안 검사기(Godot판). tools/validate_story.py 와 같은 검사를 파이썬 없이 한다.
##
## 실행: godot --headless --path . res://dev/gemini/validate_story.tscn -- --file docs/drafts/story/<파일>.csv
## 파일을 안 주면 data/story/story_beats.csv 를 검사한다. 오류가 있으면 종료 코드 1.

const COLUMNS: PackedStringArray = ["beat_id", "npc_id", "conditions", "gifts", "repeat_days", "lines"]
const MAX_LINE_CHARS: int = 40
const MAX_LINES: int = 6
const MAX_GIFT_QTY: int = 20


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var path: String = _get_arg("--file")

	if path.is_empty():
		path = "data/story/story_beats.csv"

	var result: Dictionary = validate_file("res://" + path.trim_prefix("res://"))
	print("검사 대상: ", path, " (", result["rows"], "개 장면)")

	for w in result["warns"]:
		print("주의: ", w)

	for e in result["errors"]:
		print("오류: ", e)

	print("오류 %d개, 주의 %d개" % [result["errors"].size(), result["warns"].size()])
	get_tree().quit(1 if not result["errors"].is_empty() else 0)


static func _get_arg(name: String) -> String:
	var args: PackedStringArray = OS.get_cmdline_user_args()

	for i in args.size():
		if args[i] == name and i + 1 < args.size():
			return args[i + 1]

	return ""


# 검사 본체(시험할 수 있게 정적). 아이템·가구·NPC 아이디 집합을 받아서 검사한다.
static func validate_rows(
	header: PackedStringArray,
	rows: Array,
	items: Dictionary,
	furniture: Dictionary,
	npcs: Dictionary,
	tag_name: String = "csv"
) -> Dictionary:
	var errors: Array[String] = []
	var warns: Array[String] = []

	if header != COLUMNS:
		errors.append("열 이름이 %s 와 다릅니다: %s" % [str(COLUMNS), str(header)])

	var seen: Dictionary = {}
	var id_regex := RegEx.create_from_string("^[a-z0-9_]+$")

	for index in rows.size():
		var row: PackedStringArray = rows[index]
		var n: int = index + 2
		var bid: String = row[0].strip_edges() if row.size() > 0 else ""
		var tag: String = "%s:%d [%s]" % [tag_name, n, bid]

		if row.size() != COLUMNS.size():
			errors.append("%s 칸 수가 %d개(필요 %d개). 대사 안 쉼표는 칸 전체를 큰따옴표로 감싸야 함" % [tag, row.size(), COLUMNS.size()])
			continue

		if id_regex.search(bid) == null:
			errors.append("%s beat_id는 소문자·숫자·밑줄만" % tag)

		if seen.has(bid):
			errors.append("%s beat_id 중복" % tag)

		seen[bid] = true

		if not npcs.has(row[1].strip_edges()):
			errors.append("%s 없는 npc_id: %s" % [tag, row[1]])

		var conditions: String = row[2].strip_edges()

		for c in conditions.split(";", false):
			var why: String = check_condition(c.strip_edges(), items, furniture)

			if not why.is_empty():
				errors.append("%s 조건 '%s': %s" % [tag, c, why])

		if conditions.is_empty():
			warns.append("%s 조건이 없어 항상 나올 수 있음" % tag)

		for g in row[3].strip_edges().split(";", false):
			var parts: PackedStringArray = g.strip_edges().split(":")

			if parts.size() != 3 or not parts[2].is_valid_int():
				errors.append("%s 선물 형식 '종류:아이디:수량' 아님: %s" % [tag, g])
				continue

			var kind: String = parts[0]
			var gid: String = parts[1]
			var qty: int = int(parts[2])

			if kind == "item" and not items.has(gid):
				errors.append("%s 없는 아이템 선물: %s" % [tag, gid])
			elif kind == "furniture" and not furniture.has(gid):
				errors.append("%s 없는 가구 선물: %s" % [tag, gid])
			elif kind != "item" and kind != "furniture" and kind != "money":
				errors.append("%s 선물 종류는 item/furniture/money: %s" % [tag, kind])

			if qty > MAX_GIFT_QTY and kind != "money":
				warns.append("%s 선물 수량이 많음(%d): 밸런스 확인" % [tag, qty])

			if kind == "money":
				warns.append("%s 돈 선물(%d): 밸런스는 Claude 확인 필요" % [tag, qty])

		if not row[4].strip_edges().is_valid_int():
			errors.append("%s repeat_days는 숫자(0 = 한 번만)" % tag)

		var lines: PackedStringArray = row[5].split("|")
		var empty_line: bool = false

		for x in lines:
			if x.strip_edges().is_empty():
				empty_line = true

		if empty_line:
			errors.append("%s 대사가 비었거나 빈 칸이 있음" % tag)

		if lines.size() > MAX_LINES:
			warns.append("%s 대사 %d줄(권장 %d 이하)" % [tag, lines.size(), MAX_LINES])

		for x in lines:
			if x.length() > MAX_LINE_CHARS:
				warns.append("%s 대사 한 칸이 %d자(권장 %d 이하): %s..." % [tag, x.length(), MAX_LINE_CHARS, x.substr(0, 20)])

	return {"errors": errors, "warns": warns, "rows": rows.size()}


# 알 수 없거나 틀린 조건이면 이유를, 맞으면 빈 문자열을 돌려준다.
static func check_condition(c: String, items: Dictionary, furniture: Dictionary) -> String:
	if RegEx.create_from_string("^day>=\\d+$").search(c) != null:
		return ""

	if c == "expedition_done" or c == "product_stock_empty":
		return ""

	if RegEx.create_from_string("^money<\\d+$").search(c) != null:
		return ""

	var m := RegEx.create_from_string("^item_below:([a-z0-9_]+):(\\d+)$").search(c)

	if m != null:
		return "" if items.has(m.get_string(1)) else "없는 아이템 " + m.get_string(1)

	m = RegEx.create_from_string("^furniture_missing:([a-z0-9_]+)$").search(c)

	if m != null:
		return "" if furniture.has(m.get_string(1)) else "없는 가구 " + m.get_string(1)

	return "알 수 없는 조건(게임에서 항상 거짓)"


static func validate_file(path: String) -> Dictionary:
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

	var items: Dictionary = {}

	for item_id in ItemData.items.keys():
		items[str(item_id)] = true

	var furniture: Dictionary = {}

	for data in FurnitureData.get_all_furniture():
		furniture[str(data["id"])] = true

	var npcs: Dictionary = {}
	var npc_file := FileAccess.open("res://data/story/story_npcs.csv", FileAccess.READ)

	if npc_file != null:
		npc_file.get_csv_line()

		while not npc_file.eof_reached():
			var npc_line: PackedStringArray = npc_file.get_csv_line()

			if npc_line.size() > 0 and not npc_line[0].is_empty():
				npcs[npc_line[0]] = true

	return validate_rows(header, rows, items, furniture, npcs, path.get_file())
