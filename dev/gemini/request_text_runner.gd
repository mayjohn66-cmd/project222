extends Node
## 부탁 글 도구 실행기. 모드 3가지:
##   export   현재 원본의 글을 CSV로 내보낸다(기준 문장). --out <경로>
##   validate 글 CSV를 검사한다. --file <경로>
##   draft    제미나이에게 글을 새로 쓰게 하고 초안 CSV로 저장한다. [--kind resident_request|community_request|resident_greeting]
## 실행: godot --headless --path . res://dev/gemini/request_text.tscn -- --mode validate --file docs/drafts/story/<파일>.csv
## 기계 부분(id·재료·수량·보상)은 바꾸지 않는다. 규격: docs/스토리_작성_가이드.md 5.1

const Tools = preload("res://dev/gemini/request_text_tools.gd")
const GeminiClient = preload("res://dev/gemini/gemini_client.gd")
const StoryGen = preload("res://dev/gemini/story_draft_generator.gd")

const OUT_DIR: String = "res://docs/drafts/story"

# 검사에서 오류나 수량 표현이 걸리면 그 내용을 제미나이에게 돌려보내 고치게 한다(최대 횟수).
const MAX_REPAIRS: int = 2

const BASE_PROMPT: String = """너는 편의점 경영 + 판타지 원정 게임의 글 작가다. 이미 있는 항목의 "글"만 새로 쓴다. 설명·머리말·코드블록 표시 없이 CSV 행만 출력한다.
- 열: id,kind,title,summary,lines,completion (쉼표 구분. 칸 안에 쉼표가 있으면 그 칸 전체를 큰따옴표로 감싼다)
- 준 항목마다 정확히 한 행. id와 kind는 내가 준 그대로 쓴다. 새 id를 만들거나 빼지 않는다.
- kind별로 채울 열: resident_request = title, lines, completion / community_request = title, summary, completion / resident_greeting = lines 만. 나머지 열은 비운다.
- lines와 completion의 여러 칸은 | 로 나눈다. 칸 수와 역할(예: 인사말은 아침·안부·하루 이야기·밤 순서)은 "현재 문장"과 같게 맞춘다.
- 길이: title 20자 이내, summary 60자 이내, lines·completion 한 칸 45자 이내, lines는 6칸 이하.
- 쓰지 않는 말: 퀘스트, 의뢰, 보상, 레벨, 경험치, 미션, 임무, 스탯, 수락, 클리어. 사람이 하는 자연스러운 부탁으로 말한다.
- 수량·돈·평판 숫자는 쓰지 않는다(몇 개, 두 개 같은 표현도 금지). 필요한 재료 이름은 말해도 된다. 숫자는 게임 데이터가 정하므로 글이 틀려지지 않게 한다.
- 이미 게임 데이터에 있는 인물 이름만 쓰고 새 이름·지역은 만들지 않는다."""


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var mode: String = _arg("--mode")
	var sources: Dictionary = Tools.load_sources()

	match mode:
		"export":
			_export(sources)
		"validate":
			_validate(sources)
		"draft":
			await _draft(sources, sources)
		"sync":
			await _sync(sources)
		"accept":
			_accept(sources)
		_:
			push_error("--mode 는 export, validate, draft 중 하나입니다.")
			get_tree().quit(2)


func _export(sources: Dictionary) -> void:
	var out: String = _arg("--out")

	if out.is_empty():
		out = "docs/drafts/story/requests_text_baseline.csv"

	var lines: PackedStringArray = [Tools.csv_line(Tools.COLUMNS)]
	var count: int = 0

	for kind in Tools.KINDS:
		for id in sources[kind].keys():
			lines.append(Tools.csv_line(Tools.row_from_source(kind, sources[kind][id])))
			count += 1

	_write("res://" + out.trim_prefix("res://"), "\n".join(lines) + "\n")
	print("[부탁 글] 기준 문장 %d행 저장: %s" % [count, out])
	get_tree().quit(0)


func _validate(sources: Dictionary) -> void:
	var path: String = _arg("--file")

	if path.is_empty():
		push_error("--file 이 필요합니다.")
		get_tree().quit(2)
		return

	var result: Dictionary = Tools.validate_file("res://" + path.trim_prefix("res://"), sources)
	_print_result(path, result)
	get_tree().quit(1 if not result["errors"].is_empty() else 0)


func _draft(sources: Dictionary, targets: Dictionary) -> void:
	var only_kind: String = _arg("--kind")
	var client := GeminiClient.new()
	add_child(client)
	var system_prompt: String = StoryGen.append_world_setting(
		BASE_PROMPT,
		FileAccess.get_file_as_string(StoryGen.WORLD_SETTING_PATH) if FileAccess.file_exists(StoryGen.WORLD_SETTING_PATH) else ""
	)
	var rows_text: PackedStringArray = []

	for kind in Tools.KINDS:
		if not only_kind.is_empty() and only_kind != kind:
			continue

		if targets[kind].is_empty():
			print("[부탁 글] %s: 대상이 없어 건너뜀" % kind)
			continue

		print("[부탁 글] %s %d개 요청 중 / 모델: %s" % [kind, targets[kind].size(), GeminiClient.find_model()])
		var result: Dictionary = await client.generate(build_prompt(kind, targets, sources), system_prompt)

		if not bool(result["ok"]):
			push_error("[부탁 글] 실패(%s): %s" % [kind, str(result["error"])])
			get_tree().quit(1)
			return

		rows_text.append(clean_rows(str(result["text"])))

	var csv_text: String = Tools.csv_line(Tools.COLUMNS) + "\n" + "".join(rows_text)
	var stamp: String = Time.get_datetime_string_from_system().replace(":", "").replace("-", "").replace("T", "_")
	var path: String = "%s/requests_text_gemini_%s.csv" % [OUT_DIR, stamp]
	_write(path, csv_text)
	print("[부탁 글] 저장: ", path)

	# 검사 → 문제가 있으면 제미나이에게 고치게 한다.
	var result: Dictionary = Tools.validate_file(path, sources)

	for round in range(1, MAX_REPAIRS + 1):
		var problems: Array[String] = _repairable(result)

		if problems.is_empty():
			break

		print("[부탁 글] 검사 문제 %d건을 제미나이에게 돌려보내 고칩니다 (%d/%d)" % [problems.size(), round, MAX_REPAIRS])
		var fixed: Dictionary = await client.generate(build_repair_prompt(csv_text, problems), system_prompt)

		if not bool(fixed["ok"]):
			print("[부탁 글] 수정 요청 실패: ", fixed["error"], " — 현재 초안을 그대로 둡니다.")
			break

		var repaired: String = clean_rows(str(fixed["text"]))

		if repaired.is_empty():
			break

		csv_text = Tools.csv_line(Tools.COLUMNS) + "\n" + repaired
		_write(path, csv_text)
		result = Tools.validate_file(path, sources)

	_print_result(path, result)
	get_tree().quit(1 if not result["errors"].is_empty() else 0)


# 글이 없거나(새 항목) 기계 부분이 바뀐 항목을 찾아 보여 주고, --dry 가 아니면 그 항목만 제미나이에게 쓰게 한다.
func _sync(sources: Dictionary) -> void:
	var texts: Dictionary = Tools.load_text_rows(Tools.text_path())
	var todo: Dictionary = Tools.find_todo(sources, texts, Tools.load_state())
	var new_count: int = Tools.count_targets(todo["new"])
	var changed_count: int = Tools.count_targets(todo["changed"])
	print("[부탁 글 동기화] 글 파일: %s (글 %d행)" % [Tools.text_path().trim_prefix("res://"), texts.size()])
	print("[부탁 글 동기화] 글이 없는 새 항목 %d건, 기계 부분이 바뀐 항목 %d건" % [new_count, changed_count])

	for group in ["new", "changed"]:
		for kind in Tools.KINDS:
			for id in todo[group][kind].keys():
				print("  - %s %s: %s" % ["새" if group == "new" else "바뀜", kind, id])

	for key in todo["orphan"]:
		print("  - 원본이 사라진 글(확인 필요): ", key)

	if new_count + changed_count == 0:
		print("[부탁 글 동기화] 할 일이 없습니다.")
		get_tree().quit(0)
		return

	if _flag("--dry"):
		print("[부탁 글 동기화] --dry: 제미나이를 부르지 않았습니다.")
		get_tree().quit(0)
		return

	var targets: Dictionary = {}

	for kind in Tools.KINDS:
		targets[kind] = {}
		targets[kind].merge(todo["new"][kind])
		targets[kind].merge(todo["changed"][kind])

	await _draft(sources, targets)


# 검토를 끝낸 초안을 글 CSV에 합치고, 기계 부분 지문(상태)을 갱신한다. 사용자가 승인한 뒤에만 쓴다.
func _accept(sources: Dictionary) -> void:
	var path: String = _arg("--file")

	if path.is_empty():
		push_error("--file 이 필요합니다.")
		get_tree().quit(2)
		return

	var full: String = "res://" + path.trim_prefix("res://")
	var check: Dictionary = Tools.validate_file(full, sources)

	if not check["errors"].is_empty():
		_print_result(path, check)
		push_error("오류가 있는 초안은 합칠 수 없습니다.")
		get_tree().quit(1)
		return

	var file := FileAccess.open(full, FileAccess.READ)
	file.get_csv_line()
	var rows: Array = []

	while not file.eof_reached():
		var row: PackedStringArray = file.get_csv_line()

		if row.size() == Tools.COLUMNS.size():
			rows.append(row)

	file.close()
	var out: Dictionary = Tools.merge_draft(Tools.load_text_rows(Tools.text_path()), rows, sources, Tools.load_state())
	var target: String = _arg("--into")

	if target.is_empty():
		target = Tools.text_path()
	else:
		target = "res://" + target.trim_prefix("res://")

	_write(target, out["csv"])
	_write(Tools.STATE_PATH, out["state_csv"])
	print("[부탁 글] %d행을 합쳤습니다: %s (상태: %s)" % [rows.size(), target.trim_prefix("res://"), Tools.STATE_PATH.trim_prefix("res://")])
	get_tree().quit(0)


func _flag(name: String) -> bool:
	return OS.get_cmdline_user_args().has(name)


# 고치게 할 문제: 모든 오류와, 글이 틀려지기 쉬운 수량 표현 주의.
static func _repairable(result: Dictionary) -> Array[String]:
	var problems: Array[String] = []

	for e in result["errors"]:
		problems.append(str(e))

	for w in result["warns"]:
		if str(w).contains("수량 표현") or str(w).contains("한 칸이"):
			problems.append(str(w))

	return problems


static func build_repair_prompt(csv_text: String, problems: Array[String]) -> String:
	return "아래 CSV는 검사에서 다음 문제가 나왔다. 문제가 있는 행의 글만 규칙에 맞게 고쳐서, 모든 행을 같은 형식의 CSV로 다시 출력한다(머리글 줄 없이 행만). id와 kind와 칸 수는 그대로 둔다. 글자 수 제한을 꼭 지킨다(한 칸에 공백 포함).\n\n문제:\n- %s\n\n현재 CSV:\n%s" % ["\n- ".join(problems), csv_text]


# kind별 요청 글. 현재 문장(참고용)과 기계 정보 중 글에 도움이 되는 것만 준다.
static func build_prompt(kind: String, targets: Dictionary, sources: Dictionary = {}) -> String:
	var out: PackedStringArray = ["kind = %s 인 항목들의 글을 새로 쓴다. 항목마다 한 행." % kind, ""]
	var residents: Dictionary = (sources if not sources.is_empty() else targets).get(Tools.KIND_RESIDENT_GREETING, {})

	for id in targets[kind].keys():
		var d: Dictionary = targets[kind][id]
		var current: PackedStringArray = Tools.row_from_source(kind, d)
		var info: String = ""

		match kind:
			Tools.KIND_RESIDENT_REQUEST:
				info = "인물: %s / 필요한 재료: %s" % [d.get("npc", ""), _item_name(str(d.get("item", "")))]
			Tools.KIND_COMMUNITY_REQUEST:
				var names: PackedStringArray = []

				for req in d.get("requirements", []):
					names.append(_item_name(str(req.get("item", ""))))

				var resident: Dictionary = residents.get(str(d.get("resident", "")), {})
				info = "부탁하는 주민: %s / 필요한 재료: %s / 완성되는 곳: %s" % [resident.get("name", d.get("resident", "")), ", ".join(names), d.get("landmark_name", "")]
			Tools.KIND_RESIDENT_GREETING:
				info = "이름: %s / 직업: %s / 건네는 물건: %s" % [d.get("name", ""), d.get("type", ""), _item_name(str(d.get("gift", "")))]

		out.append("id=%s | %s" % [id, info])
		out.append("현재 문장(참고, 같은 칸 수와 역할로 새로 쓴다): " + Tools.csv_line(current))
		out.append("")

	return "\n".join(out)


static func _item_name(item_id: String) -> String:
	if item_id.is_empty():
		return ""

	return ItemData.get_item_name(item_id) if ItemData.has_item(item_id) else item_id


# 코드블록 표시와 머리글 줄을 지운 CSV 행들(끝에 줄바꿈 포함).
static func clean_rows(text: String) -> String:
	var kept: PackedStringArray = []

	for raw_line in text.split("\n"):
		var line: String = raw_line.strip_edges()

		if line.is_empty() or line.begins_with("```") or line.begins_with("id,kind"):
			continue

		kept.append(line)

	return "\n".join(kept) + "\n" if not kept.is_empty() else ""


func _print_result(path: String, result: Dictionary) -> void:
	print("검사 대상: ", path, " (", result["rows"], "행)")

	for w in result["warns"]:
		print("주의: ", w)

	for e in result["errors"]:
		print("오류: ", e)

	print("오류 %d개, 주의 %d개" % [result["errors"].size(), result["warns"].size()])


func _write(path: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var file := FileAccess.open(path, FileAccess.WRITE)

	if file == null:
		push_error("저장 실패: " + path)
		return

	file.store_string(text)
	file.close()


func _arg(name: String) -> String:
	var args: PackedStringArray = OS.get_cmdline_user_args()

	for i in args.size():
		if args[i] == name and i + 1 < args.size():
			return args[i + 1]

	return ""
