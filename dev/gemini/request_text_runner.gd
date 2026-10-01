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

const BASE_PROMPT: String = """너는 편의점 경영 + 판타지 원정 게임의 글 작가다. 이미 있는 항목의 "글"만 새로 쓴다. 설명·머리말·코드블록 표시 없이 CSV 행만 출력한다.
- 열: id,kind,title,summary,lines,completion (쉼표 구분. 칸 안에 쉼표가 있으면 그 칸 전체를 큰따옴표로 감싼다)
- 준 항목마다 정확히 한 행. id와 kind는 내가 준 그대로 쓴다. 새 id를 만들거나 빼지 않는다.
- kind별로 채울 열: resident_request = title, lines, completion / community_request = title, summary, completion / resident_greeting = lines 만. 나머지 열은 비운다.
- 추가 종류: resident_introduction / tutorial_dialogue = lines; trade_offer = title; tutorial_step = title, summary, lines, completion; service_text = 현재 행에서 채워진 글 열만. 기능 안내와 조작 키의 의미는 유지한다.
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
			await _draft(sources)
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


func _draft(sources: Dictionary) -> void:
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

		if sources[kind].is_empty():
			print("[부탁 글] %s: 원본이 없어 건너뜀" % kind)
			continue

		print("[부탁 글] %s %d개 요청 중 / 모델: %s" % [kind, sources[kind].size(), GeminiClient.find_model()])
		var result: Dictionary = await client.generate(build_prompt(kind, sources), system_prompt)

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
	_validate_saved(path, sources)


func _validate_saved(path: String, sources: Dictionary) -> void:
	var result: Dictionary = Tools.validate_file(path, sources)
	_print_result(path, result)
	get_tree().quit(1 if not result["errors"].is_empty() else 0)


# kind별 요청 글. 현재 문장(참고용)과 기계 정보 중 글에 도움이 되는 것만 준다.
static func build_prompt(kind: String, sources: Dictionary) -> String:
	var out: PackedStringArray = ["kind = %s 인 항목들의 글을 새로 쓴다. 항목마다 한 행." % kind, ""]
	var residents: Dictionary = sources.get(Tools.KIND_RESIDENT_GREETING, {})

	for id in sources[kind].keys():
		var d: Dictionary = sources[kind][id]
		var current: PackedStringArray = Tools.row_from_source(kind, d)
		var info: String = ""

		match kind:
			Tools.KIND_RESIDENT_INTRODUCTION:
				info = "인물: %s / 손님 유형: %s" % [d.get("npc",""), d.get("type","")]
			Tools.KIND_TRADE_OFFER:
				info = "건네는 재료: %s / 받는 재료: %s" % [_item_name(str(d.get("give",""))), _item_name(str(d.get("receive","")))]
			Tools.KIND_TUTORIAL_STEP:
				info = "안내 목표: %s" % d.get("goal","")
			Tools.KIND_TUTORIAL_DIALOGUE, Tools.KIND_SERVICE_TEXT:
				info = "기존 기능 안내를 유지하는 문장: " + id
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
