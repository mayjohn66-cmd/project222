extends Node
## 부탁 글 도구 실행기. 모드 3가지:
##   export   현재 원본의 글을 CSV로 내보낸다(기준 문장). --out <경로>
##   validate 글 CSV를 검사한다. --file <경로>
##   draft    제미나이에게 글을 새로 쓰게 하고 초안 CSV로 저장한다. [--kind resident_request|community_request|resident_greeting]
##   webprompt API 없이 제미나이 웹(구독)에 붙여 넣을 요청문을 파일로 만든다. draft 와 같은 --kind/--ids/--chunk. docs/drafts/story/web/prompt_*.txt
##   webimport 웹에서 받은 답을 파일로 저장해 두었다가 초안 CSV로 바꾸고 검사한다. --files 경로,경로
## 실행: godot --headless --path . res://dev/gemini/request_text.tscn -- --mode validate --file docs/drafts/story/<파일>.csv
## 기계 부분(id·재료·수량·보상)은 바꾸지 않는다. 규격: docs/스토리_작성_가이드.md 5.1

const Tools = preload("res://dev/gemini/request_text_tools.gd")
const GeminiClient = preload("res://dev/gemini/gemini_client.gd")
const StoryGen = preload("res://dev/gemini/story_draft_generator.gd")
const Profiles = preload("res://dev/gemini/character_profile_context.gd")
const FakeClient = preload("res://dev/gemini/fake_gemini_client.gd")

const OUT_DIR: String = "res://docs/drafts/story"

# 검사에서 오류나 수량 표현이 걸리면 그 내용을 제미나이에게 돌려보내 고치게 한다(최대 횟수).
const MAX_REPAIRS: int = 2

# 한 번에 제미나이에게 맡기는 항목 수. 작을수록 503(과부하)에 덜 걸리고 항목마다 구조가 달라진다.
# 바꾸려면 --chunk <수>.
const DEFAULT_CHUNK_SIZE: int = 2

const BASE_PROMPT: String = """너는 편의점 경영 + 판타지 원정 게임의 글 작가다. 이미 있는 항목의 "글"만 새로 쓴다. 설명·머리말·코드블록 표시 없이 CSV 행만 출력한다.
- 열: id, kind, title, summary, lines, completion 을 **탭 문자**로 구분한다(쉼표로 구분하지 않는다). 칸 안에는 쉼표를 써도 되지만 탭과 줄바꿈은 쓰지 않고, 따옴표로 감싸지 않는다. 비우는 칸은 탭 사이를 비워 둔다(칸 수는 항상 6개).
- 준 항목마다 정확히 한 행. id와 kind는 내가 준 그대로 쓴다. 새 id를 만들거나 빼지 않는다.
- kind별로 채울 열: resident_request = title, lines, completion / community_request = title, summary, completion / resident_greeting = lines 만. 나머지 열은 비운다.
- 개인 부탁: personal_request = title, summary, lines, completion. 창고에 물품을 준비한 뒤 게시판에서 직접 전달하는 안내를 유지한다.
- 우물 저녁 모임(service_text)의 화자와 장면 순서를 유지한다. 화자 이름은 화면에서 붙이므로 대사에 중복 쓰지 않고, 새 물품·돈·친밀도 지급을 약속하지 않는다.
- 추가 종류: resident_introduction / tutorial_dialogue = lines; trade_offer = title; tutorial_step = title, summary, lines, completion; service_text = 현재 행에서 채워진 글 열만. 기능 안내와 조작 키의 의미는 유지한다.
- lines와 completion의 여러 칸은 | 로 나눈다. 칸 수와 역할(예: 인사말은 아침·안부·하루 이야기·밤 순서)은 "현재 문장"과 같게 맞춘다.
- 칸(줄) 수는 "현재 문장"과 항상 같다. 부탁하는 말, 플레이어 행동 안내, 소문·마무리처럼 칸마다 맡은 역할을 하나도 빼지 않는다. 길이가 넘으면 칸을 지우지 말고 그 칸의 문장을 짧게 쓴다.
- 길이: title 20자 이내, summary 60자 이내, lines·completion 한 칸 45자 이내, lines는 6칸 이하.
- 쓰지 않는 말: 퀘스트, 의뢰, 보상, 레벨, 경험치, 미션, 임무, 스탯, 수락, 클리어. 사람이 하는 자연스러운 부탁으로 말한다.
- 수량·돈·평판 숫자는 쓰지 않는다(몇 개, 두 개 같은 표현도 금지). 필요한 재료 이름은 말해도 된다. 숫자는 게임 데이터가 정하므로 글이 틀려지지 않게 한다.
- 이미 게임 데이터에 있는 인물 이름만 쓰고 새 이름·지역은 만들지 않는다.
- 플레이어가 해야 할 행동(예: 창고에 준비한 뒤 다시 말을 걸기)은 "현재 문장"의 안내를 그대로 살린다. "내가 가지러 올게", "다시 와서 받아 갈게"처럼 플레이어가 기다리면 되는 것처럼 읽히는 말은 쓰지 않는다.
- 말투(반말/존댓말)는 "현재 문장"과 같게 하고, 한 문장 안에서 섞지 않는다.
- 같은 종류의 항목들이 모두 같은 구조(감탄 → 부탁 → 소문)로 시작하지 않게 한다. 현대적인 것에 놀라는 반응은 항목 중 일부에만 넣고 나머지는 부탁과 사정을 자연스럽게 말한다.
- 흔한 상투 표현을 피한다: "덕분에", "정말 고마워", "~로구나!", "~에게도 말해 줄게/소개해 줄게/추천해 줄게", 느낌표 연속. 감사는 그 사람이 처한 사정과 말버릇으로 다르게 표현한다(짧게 한마디, 퉁명스럽게, 걱정 섞어서 등).
- 항목에 "말하는 사람"과 "말버릇"이 있으면 그 사람의 목소리로 쓴다. 이름은 "말하는 사람"에 적힌 것만 쓰고, 말버릇을 대사마다 억지로 드러내지 않는다(광부는 짧게, 치료사는 조심스럽게처럼 문장 호흡으로 보여 준다).
- 같은 어구를 여러 항목에 되풀이하지 않는다. 항목마다 문장 길이와 마무리 방식을 다르게 한다."""


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
		"webprompt":
			_webprompt(sources)
		"webimport":
			_webimport(sources)
		"sync":
			await _sync(sources)
		"accept":
			_accept(sources)
		"rebase-state":
			_rebase_state(sources)
		"polish":
			await _polish(sources)
		"autopilot":
			await _autopilot()
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
	var made: Dictionary = await _make_draft(sources, targets)
	get_tree().quit(0 if bool(made["ok"]) else 1)


# 제미나이 웹(구독)용: API 를 부르지 않고 묶음마다 [지침]+[요청]을 한 파일로 만든다. 파일 내용을 웹 대화에 통째로 붙여 넣고,
# 답(코드블록 안의 탭 구분 행)을 복사해 docs/drafts/story/web/answer_N.txt 로 저장한 뒤 webimport 로 초안 CSV 를 만든다.
func _webprompt(sources: Dictionary) -> void:
	var only_kind: String = _arg("--kind")
	var system_prompt: String = StoryGen.append_world_setting(
		BASE_PROMPT,
		FileAccess.get_file_as_string(StoryGen.WORLD_SETTING_PATH) if FileAccess.file_exists(StoryGen.WORLD_SETTING_PATH) else ""
	)
	var only_ids: PackedStringArray = _arg("--ids").split(",", false)
	var chunk_size: int = maxi(1, int(_arg("--chunk")) if not _arg("--chunk").is_empty() else DEFAULT_CHUNK_SIZE)
	var stamp: String = Time.get_datetime_string_from_system().replace(":", "").replace("-", "").replace("T", "_")
	var count: int = 0

	for kind in Tools.KINDS:
		if not only_kind.is_empty() and only_kind != kind:
			continue

		var ids: Array = filter_ids(sources[kind].keys(), only_ids)

		if ids.is_empty():
			continue

		for chunk in chunk_ids(ids, chunk_size):
			var part: Dictionary = sources.duplicate()
			var subset: Dictionary = {}

			for id in chunk:
				subset[id] = sources[kind][id]

			part[kind] = subset
			count += 1
			var path: String = "%s/web/prompt_%s_%02d.txt" % [OUT_DIR, stamp, count]
			# 항목마다 채울 열을 현재 행에서 읽어 한 줄씩 적는다(웹 답이 제목/요약/대사 열을 서로 바꿔 쓰는 일을 막는다).
			var column_notes: PackedStringArray = []

			for id in chunk:
				var row: PackedStringArray = Tools.row_from_source(kind, sources[kind][id])
				var names: PackedStringArray = []

				for column_index in range(2, 6):
					if not str(row[column_index]).strip_edges().is_empty():
						var cell_text: String = str(row[column_index])
						var label: String = Tools.COLUMNS[column_index]
						names.append("%s(%d칸)" % [label, cell_text.split("|").size()] if label in ["lines", "completion"] else label)

				column_notes.append("- %s → 채울 열: %s (나머지 열은 비운다)" % [id, ", ".join(names)])

			var text: String = "아래 [지침]을 따라 [요청]의 항목만 쓴다. 답은 **코드블록 하나** 안에 탭으로 구분한 행만 넣고, 설명·머리말은 쓰지 않는다.\n\n[지침]\n%s\n\n[요청]\n%s\n\n[채울 열 — 반드시 지킨다]\n%s\n열 순서는 id, kind, title, summary, lines, completion 이고 항상 탭 5개(6칸)다. 단서(clue)·제목 행은 NPC 대사가 아니므로 lines 에 쓰지 않는다.\n" % [system_prompt, build_prompt(kind, part, sources), "\n".join(column_notes)]
			_write(path, text)
			print("[웹 요청] %s (%s %s)" % [path, kind, ", ".join(chunk)])

	if count == 0:
		print("[웹 요청] 대상 항목이 없습니다(--kind/--ids 확인).")
		get_tree().quit(1)
		return

	print("[웹 요청] 파일 %d개. 각 파일 내용을 제미나이 웹 대화에 붙여 넣고, 답의 코드블록을 복사해 같은 폴더에 answer_<번호>.txt 로 저장하세요. 그다음: run_request_text.bat webimport 파일1,파일2" % count)
	get_tree().quit(0)


func _webimport(sources: Dictionary) -> void:
	var files: PackedStringArray = _arg("--files").split(",", false)

	if files.is_empty():
		push_error("--files 경로,경로 가 필요합니다.")
		get_tree().quit(2)
		return

	var rows_text: PackedStringArray = []

	for file_path in files:
		var path: String = "res://" + file_path.strip_edges().trim_prefix("res://")

		if not FileAccess.file_exists(path):
			push_error("파일이 없습니다: " + path)
			get_tree().quit(2)
			return

		rows_text.append(fix_shifted_rows(parse_web_answer(FileAccess.get_file_as_string(path), sources), sources))

	var csv_text: String = Tools.csv_line(Tools.COLUMNS) + "\n" + "".join(rows_text)
	var stamp: String = Time.get_datetime_string_from_system().replace(":", "").replace("-", "").replace("T", "_")
	var out: String = "%s/requests_text_gemini_%s_web.csv" % [OUT_DIR, stamp]
	_write(out, csv_text)
	print("[웹 가져오기] 저장: ", out)
	var result: Dictionary = Tools.validate_file(out, sources)
	_print_result(out, result)
	get_tree().quit(0 if result["errors"].is_empty() else 1)


# 웹 대화의 답(머리말·코드블록 표시가 섞일 수 있음)에서 "아이디\t종류\t제목\t요약\t줄\t완료" 행만 골라 CSV 행으로 바꾼다.
# 끝의 빈 칸이 잘려도 6칸으로 채운다. 알려진 아이디로 시작하지 않는 줄은 무시하고, 탭이 없어 보이는 줄은 개수를 알려 준다.
static func parse_web_answer(text: String, sources: Dictionary) -> String:
	var known: Dictionary = {}

	for kind in Tools.KINDS:
		for id in sources[kind].keys():
			known[str(id)] = true

	var kept: PackedStringArray = []
	var ignored: int = 0

	for raw_line in text.replace("\r", "").split("\n"):
		var line: String = raw_line.strip_edges(true, false)

		if line.is_empty() or line.begins_with("```"):
			continue

		var cells: PackedStringArray = line.split("\t")
		var id: String = cells[0].strip_edges()

		if cells.size() == 1 or not known.has(id):
			if line.begins_with("act") or line.contains("service_text") or line.contains("_request"):
				ignored += 1

			continue

		while cells.size() < 6:
			cells.append("")

		if cells.size() > 6:
			# 칸 안에 탭이 섞였으면 뒤의 칸을 마지막 칸에 합친다.
			var tail: PackedStringArray = cells.slice(5)
			cells = cells.slice(0, 5)
			cells.append(" ".join(tail))

		for i in range(cells.size()):
			cells[i] = cells[i].strip_edges()

		kept.append(Tools.csv_line(cells))

	if ignored > 0:
		push_warning("[웹 가져오기] 탭으로 구분되지 않은 줄 %d개를 무시했습니다. 코드블록의 복사 버튼으로 복사했는지 확인하세요." % ignored)

	return "\n".join(kept) + "\n" if not kept.is_empty() else ""


func _new_client() -> Node:
	var client: Node = FakeClient.new() if OS.get_environment("STORY_FAKE_GEMINI") == "1" else GeminiClient.new()
	add_child(client)
	return client


# 대상 항목의 글 초안을 만들어 저장하고 검사·자동 수정까지 한다. 종료하지 않는다.
# 반환: {ok(오류 없음), path, result(검사 결과), made(제미나이 호출 성공 여부)}
func _make_draft(sources: Dictionary, targets: Dictionary) -> Dictionary:
	var only_kind: String = _arg("--kind")
	var client: Node = _new_client()
	var system_prompt: String = StoryGen.append_world_setting(
		BASE_PROMPT,
		FileAccess.get_file_as_string(StoryGen.WORLD_SETTING_PATH) if FileAccess.file_exists(StoryGen.WORLD_SETTING_PATH) else ""
	)
	var only_ids: PackedStringArray = _arg("--ids").split(",", false)
	var rows_text: PackedStringArray = []
	var failed_ids: Array[String] = []
	var chunk_size: int = maxi(1, int(_arg("--chunk")) if not _arg("--chunk").is_empty() else DEFAULT_CHUNK_SIZE)

	for kind in Tools.KINDS:
		if not only_kind.is_empty() and only_kind != kind:
			continue

		if targets[kind].is_empty():
			print("[부탁 글] %s: 대상이 없어 건너뜀" % kind)
			continue

		var ids: Array = filter_ids(targets[kind].keys(), only_ids)

		if ids.is_empty():
			print("[부탁 글] %s: --ids 에 해당하는 항목이 없어 건너뜀" % kind)
			continue

		var chunks: Array = chunk_ids(ids, chunk_size)
		print("[부탁 글] %s %d개를 %d묶음으로 나눠 요청 / 모델: %s" % [kind, ids.size(), chunks.size(), GeminiClient.find_model()])

		for i in range(chunks.size()):
			var part: Dictionary = targets.duplicate()
			var subset: Dictionary = {}

			for id in chunks[i]:
				subset[id] = targets[kind][id]

			part[kind] = subset
			print("[부탁 글] %s 묶음 %d/%d: %s" % [kind, i + 1, chunks.size(), ", ".join(chunks[i])])
			var result: Dictionary = await client.generate(build_prompt(kind, part, sources), system_prompt)

			if not bool(result["ok"]):
				push_error("[부탁 글] 묶음 실패(%s %d/%d): %s" % [kind, i + 1, chunks.size(), str(result["error"])])
				failed_ids.append_array(chunks[i])
				continue

			rows_text.append(fix_shifted_rows(clean_rows(str(result["text"])), sources))

	if rows_text.is_empty():
		_print_usage(client)
		client.queue_free()
		return {"ok": false, "path": "", "result": {}, "made": false}

	var csv_text: String = Tools.csv_line(Tools.COLUMNS) + "\n" + "".join(rows_text)
	var stamp: String = Time.get_datetime_string_from_system().replace(":", "").replace("-", "").replace("T", "_")
	var path: String = "%s/requests_text_gemini_%s.csv" % [OUT_DIR, stamp]
	_write(path, csv_text)
	print("[부탁 글] 저장: ", path)

	# 검사 → 문제가 있으면 제미나이에게 돌려보내 고치게 한다.
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

		var repaired: String = fix_shifted_rows(clean_rows(str(fixed["text"])), sources)

		if repaired.is_empty():
			break

		csv_text = Tools.csv_line(Tools.COLUMNS) + "\n" + repaired
		_write(path, csv_text)
		result = Tools.validate_file(path, sources)

	_print_result(path, result)

	if not failed_ids.is_empty():
		print("[부탁 글] 실패한 항목(초안에 없음, 나중에 다시 실행): ", ", ".join(failed_ids))

	_print_usage(client)
	client.queue_free()
	return {"ok": result["errors"].is_empty() and failed_ids.is_empty(), "path": path, "result": result, "made": true}


# --ids 로 고른 id만 남긴다(비어 있으면 전부).
static func filter_ids(ids: Array, only: PackedStringArray) -> Array:
	if only.is_empty():
		return ids

	var out: Array = []

	for id in ids:
		if only.has(str(id)):
			out.append(id)

	return out


# id 목록을 size개씩 묶는다.
static func chunk_ids(ids: Array, size: int) -> Array:
	var out: Array = []
	var step: int = maxi(1, size)

	for i in range(0, ids.size(), step):
		out.append(ids.slice(i, i + step))

	return out


# 고치게 할 문제: 모든 오류와, 글이 틀려지기 쉬운 수량 표현 주의.
static func _repairable(result: Dictionary) -> Array[String]:
	var problems: Array[String] = []

	for e in result["errors"]:
		problems.append(str(e))

	for w in result["warns"]:
		if str(w).contains("수량 표현") or str(w).contains("한 칸이") or str(w).contains("상투 표현") or str(w).contains("반복 어구") or str(w).contains("줄 수가 현재와 다름") or str(w).contains("행동 안내가 없음"):
			problems.append(str(w))

	return problems


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
const POLISH_PROMPT: String = """
[지금은 다듬기 단계] 아래 "다듬을 초안"은 가벼운 모델이 쓴 초안이다. 이것을 사람이 쓴 것처럼 다듬는다.
- 초안이 이미 자연스러운 줄은 그대로 둔다. 어색한 표현, 상투적인 말, 말투가 섞인 곳, 인물 말버릇과 안 맞는 곳만 고친다.
- id, title, 칸 수, 칸별 역할(부탁 / 플레이어 행동 안내 / 소문 / 마무리)은 바꾸지 않는다. 플레이어 행동 안내("다시 말을 걸...")는 반드시 남긴다.
- 한 칸의 길이 제한과 금지어, 수량 표현 금지는 그대로 지킨다."""

# 초안 파일을 본 모델로 다듬어 <이름>_polished.csv 로 저장한다. 기본 모델 gemini-3.8-flash(--model 또는 GEMINI_POLISH_MODEL 로 바꿈), 예비 모델 없이 호출한다.
#   --file <초안 경로> [--chunk N(기본 5)] [--model 이름]
func _polish(sources: Dictionary) -> void:
	var path: String = _arg("--file")

	if path.is_empty():
		push_error("--file 이 필요합니다.")
		get_tree().quit(2)
		return

	var full: String = "res://" + path.trim_prefix("res://")

	if not FileAccess.file_exists(full):
		push_error("파일이 없습니다: " + full)
		get_tree().quit(2)
		return

	var file := FileAccess.open(full, FileAccess.READ)
	file.get_csv_line()
	var by_kind: Dictionary = {}
	var order: Array = []

	while not file.eof_reached():
		var row: PackedStringArray = file.get_csv_line()

		if row.size() != Tools.COLUMNS.size():
			continue

		var kind: String = row[1].strip_edges()

		if not by_kind.has(kind):
			by_kind[kind] = {}

		by_kind[kind][row[0].strip_edges()] = row
		order.append([kind, row[0].strip_edges()])

	file.close()

	var model: String = _arg("--model")

	if model.is_empty():
		model = OS.get_environment("GEMINI_POLISH_MODEL").strip_edges()

	if model.is_empty():
		model = "gemini-3.8-flash"

	var client: Node = _new_client()
	client.model_override = model
	client.allow_fallback = false
	var system_prompt: String = StoryGen.append_world_setting(
		BASE_PROMPT + "\n" + POLISH_PROMPT,
		FileAccess.get_file_as_string(StoryGen.WORLD_SETTING_PATH) if FileAccess.file_exists(StoryGen.WORLD_SETTING_PATH) else ""
	)
	var chunk_size: int = maxi(1, int(_arg("--chunk")) if not _arg("--chunk").is_empty() else 5)
	var polished: Dictionary = {}
	var failed: Array = []
	print("[다듬기] 초안 %d행을 %s 로 다듬습니다(묶음 %d개씩)" % [order.size(), model, chunk_size])

	for kind in Tools.KINDS:
		if not by_kind.has(kind):
			continue

		var targets: Dictionary = {}

		for k in Tools.KINDS:
			targets[k] = {}

		var ids: Array = []

		for id in by_kind[kind].keys():
			if sources.get(kind, {}).has(id):
				targets[kind][id] = sources[kind][id]
				ids.append(id)

		for chunk in chunk_ids(ids, chunk_size):
			var part: Dictionary = targets.duplicate()
			part[kind] = {}
			var draft_rows: Dictionary = {}

			for id in chunk:
				part[kind][id] = targets[kind][id]
				draft_rows[id] = by_kind[kind][id]

			print("[다듬기] %s: %s" % [kind, ", ".join(chunk)])
			var result: Dictionary = await client.generate(build_prompt(kind, part, sources, draft_rows), system_prompt)

			if not bool(result["ok"]):
				push_error("[다듬기] 실패(%s): %s" % [", ".join(chunk), str(result["error"])])
				failed.append_array(chunk)
				continue

			for line in fix_shifted_rows(clean_rows(str(result["text"])), sources).split("\n", false):
				var cells: PackedStringArray = Tools.parse_csv_line(line)

				if cells.size() == Tools.COLUMNS.size() and by_kind[kind].has(cells[0].strip_edges()):
					polished[kind + ":" + cells[0].strip_edges()] = cells

	# 다듬기에 실패했거나 빠진 행은 초안 그대로 둔다.
	var out_lines: PackedStringArray = [Tools.csv_line(Tools.COLUMNS)]
	var kept: int = 0

	for pair in order:
		var key: String = pair[0] + ":" + pair[1]

		if polished.has(key):
			out_lines.append(Tools.csv_line(polished[key]))
		else:
			out_lines.append(Tools.csv_line(by_kind[pair[0]][pair[1]]))
			kept += 1

	var out_path: String = full.trim_suffix(".csv") + "_polished.csv"
	_write(out_path, "\n".join(out_lines) + "\n")
	print("[다듬기] 저장: ", out_path, " (다듬은 행 %d, 초안 그대로 %d)" % [polished.size(), kept])
	var check: Dictionary = Tools.validate_file(out_path, sources)
	_print_result(out_path, check)
	_print_usage(client)
	client.queue_free()
	get_tree().quit(0 if check["errors"].is_empty() and failed.is_empty() else 1)


# 글이 있는 모든 항목의 상태를 지금 데이터 기준으로 다시 잡는다(글은 바꾸지 않는다). 인물 이름 교체 같은 변경 뒤에 쓴다.
func _rebase_state(sources: Dictionary) -> void:
	var texts: Dictionary = Tools.load_text_rows(Tools.text_path())
	_write(Tools.STATE_PATH, Tools.rebase_state_csv(texts, sources))
	var todo: Dictionary = Tools.find_todo(sources, texts, Tools.load_state())
	print("[부탁 글] 상태를 다시 잡았습니다: %s (글 %d행). 새 항목 %d건, 바뀐 항목 %d건" % [Tools.STATE_PATH.trim_prefix("res://"), texts.size(), Tools.count_targets(todo["new"]), Tools.count_targets(todo["changed"])])
	get_tree().quit(0)


func _accept(sources: Dictionary) -> void:
	var path: String = _arg("--file")

	if path.is_empty():
		push_error("--file 이 필요합니다.")
		get_tree().quit(2)
		return

	var done: Dictionary = _accept_file(sources, "res://" + path.trim_prefix("res://"), _arg("--into"))
	get_tree().quit(0 if bool(done["ok"]) else 1)


# 초안 파일을 글 CSV에 합친다. 오류가 있는 초안은 합치지 않는다. 반환: {ok, target, rows}
func _accept_file(sources: Dictionary, full_path: String, into: String = "") -> Dictionary:
	var check: Dictionary = Tools.validate_file(full_path, sources)

	if not check["errors"].is_empty():
		_print_result(full_path, check)
		push_error("오류가 있는 초안은 합칠 수 없습니다.")
		return {"ok": false, "target": "", "rows": 0}

	var file := FileAccess.open(full_path, FileAccess.READ)
	file.get_csv_line()
	var rows: Array = []

	while not file.eof_reached():
		var row: PackedStringArray = file.get_csv_line()

		if row.size() == Tools.COLUMNS.size():
			rows.append(row)

	file.close()
	var out: Dictionary = Tools.merge_draft(Tools.load_text_rows(Tools.text_path()), rows, sources, Tools.load_state())
	var target: String = Tools.text_path() if into.is_empty() else "res://" + into.trim_prefix("res://")
	_write(target, out["csv"])
	_write(Tools.STATE_PATH, out["state_csv"])
	print("[부탁 글] %d행을 합쳤습니다: %s (상태: %s)" % [rows.size(), target.trim_prefix("res://"), Tools.STATE_PATH.trim_prefix("res://")])
	return {"ok": true, "target": target, "rows": rows.size()}


# ---------- 자동 순환 ----------
# 정해진 간격으로: 원본 가져오기 → 새·바뀐 항목 찾기 → 제미나이가 쓰기 → 검사 통과하면(옵션) 합치고 커밋·푸시.
# 안전장치: feature/story-script 브랜치에서만 돌고, 커밋은 글 파일 3개만 지정해서 하며, 푸시는 같은 브랜치로만 한다.
#   --interval N      순환 간격(초, 기본 600)
#   --once            한 번만 하고 끝
#   --auto-accept     검사를 통과한 초안을 사람 확인 없이 글 CSV에 합치고 커밋한다(기본: 초안만 만들고 알림)
#   --no-push         커밋만 하고 푸시하지 않음
#   --source-branch B 순환 때마다 origin/B 를 이 브랜치에 병합해 새 원본(ChatGPT 작업)을 가져온다(환경 변수 STORY_SOURCE_BRANCH 도 가능)
const STORY_BRANCH: String = "feature/story-script"

var _drafted_signature: String = ""


func _git(args: Array) -> Dictionary:
	var output: Array = []
	var full_args: Array = ["-C", ProjectSettings.globalize_path("res://")]
	full_args.append_array(args)
	var code: int = OS.execute("git", full_args, output, true)
	return {"code": code, "out": "".join(PackedStringArray(output)).strip_edges()}


func _autopilot() -> void:
	var branch: Dictionary = _git(["rev-parse", "--abbrev-ref", "HEAD"])

	if branch["out"] != STORY_BRANCH:
		push_error("자동 순환은 %s 브랜치에서만 돕니다(지금: %s). 스토리 전용 폴더에서 실행하세요." % [STORY_BRANCH, branch["out"]])
		get_tree().quit(2)
		return

	var interval: float = float(_arg("--interval")) if not _arg("--interval").is_empty() else 600.0
	var once: bool = _flag("--once")
	print("[자동 순환] 시작: 간격 %.0f초, 자동 합치기 %s, 푸시 %s%s" % [interval, "켬" if _flag("--auto-accept") else "끔(초안만)", "끔" if _flag("--no-push") else "켬", " (한 번만)" if once else ""])

	while true:
		await _autopilot_round()

		if once:
			break

		print("[자동 순환] %.0f초 뒤 다시 확인합니다. 멈추려면 Ctrl+C" % interval)
		await get_tree().create_timer(interval).timeout

	get_tree().quit(0)


# 풀리지 않은 병합(충돌) 상태가 남아 있으면 되돌린다. 이 폴더는 자동 순환 전용이라 병합 취소는 안전하다.
# 반환: true = 깨끗함(계속 진행), false = 직접 확인이 필요함(이번 순환 건너뜀)
func _ensure_clean_merge_state() -> bool:
	var unmerged: Dictionary = _git(["diff", "--name-only", "--diff-filter=U"])

	if str(unmerged["out"]).is_empty():
		return true

	print("[자동 순환] 풀리지 않은 병합 충돌이 남아 있습니다: ", str(unmerged["out"]).replace("\n", ", "))
	var abort: Dictionary = _git(["merge", "--abort"])
	var after: Dictionary = _git(["diff", "--name-only", "--diff-filter=U"])

	if str(after["out"]).is_empty():
		print("[자동 순환] 병합을 취소해 원래 상태로 되돌렸습니다.")
		return true

	# 병합이 진행 중이 아닌데 충돌 흔적만 남은 경우(MERGE_HEAD 없음): 병합 취소와 같은 효과의 reset --merge.
	# 커밋하지 않은 다른 변경은 지우지 않는다.
	var reset: Dictionary = _git(["reset", "--merge"])
	after = _git(["diff", "--name-only", "--diff-filter=U"])

	if str(after["out"]).is_empty():
		print("[자동 순환] 남은 충돌 흔적을 정리했습니다(git reset --merge).")
		return true

	print("[자동 순환] 자동으로 되돌리지 못했습니다(%s / %s). 이 폴더(스토리 전용)에서 아래를 직접 실행하세요:" % [str(abort["out"]).left(80), str(reset["out"]).left(80)])
	print("    git status                     (무엇이 충돌인지 확인)")
	print("    git merge --abort              (병합 중이면 취소)")
	print("    git reset --hard origin/feature/story-script   (그래도 안 되면 원격 상태로 맞춤. 올리지 않은 변경은 사라짐)")
	return false


func _autopilot_round() -> void:
	print("[자동 순환] --- %s ---" % Time.get_datetime_string_from_system())

	if not _ensure_clean_merge_state():
		return

	var fetch: Dictionary = _git(["fetch", "origin"])

	if int(fetch["code"]) != 0:
		print("[자동 순환] git fetch 실패: ", fetch["out"])
		return

	var pull: Dictionary = _git(["merge", "--ff-only", "origin/" + STORY_BRANCH])

	if int(pull["code"]) != 0 and not str(pull["out"]).contains("up to date") and not str(pull["out"]).contains("Already"):
		print("[자동 순환] 스토리 브랜치를 최신으로 맞추지 못했습니다(직접 확인 필요): ", pull["out"])

	var source: String = _arg("--source-branch")

	if source.is_empty():
		source = OS.get_environment("STORY_SOURCE_BRANCH")

	if not source.is_empty():
		var merge: Dictionary = _git(["merge", "--no-edit", "origin/" + source])

		if int(merge["code"]) != 0:
			_git(["merge", "--abort"])
			print("[자동 순환] origin/%s 병합이 충돌해 취소했습니다. 이번 순환은 건너뜁니다." % source)
			print("    충돌 내용: ", str(merge["out"]).replace("\n", " / ").left(300))
			return

	var sources: Dictionary = Tools.load_sources()
	var todo: Dictionary = Tools.find_todo(sources, Tools.load_text_rows(Tools.text_path()), Tools.load_state())
	var new_count: int = Tools.count_targets(todo["new"])
	var changed_count: int = Tools.count_targets(todo["changed"])

	if new_count + changed_count == 0:
		print("[자동 순환] 할 일이 없습니다.")
		_drafted_signature = ""
		return

	var targets: Dictionary = {}
	var signature_parts: PackedStringArray = []

	for kind in Tools.KINDS:
		targets[kind] = {}
		targets[kind].merge(todo["new"][kind])
		targets[kind].merge(todo["changed"][kind])

		for id in targets[kind].keys():
			signature_parts.append(kind + ":" + id + ":" + Tools.fingerprint(targets[kind][id]))

	var signature: String = ",".join(signature_parts)
	print("[자동 순환] 새 항목 %d건, 바뀐 항목 %d건" % [new_count, changed_count])

	if signature == _drafted_signature:
		print("[자동 순환] 같은 항목의 초안을 이미 만들었습니다(사람의 확인을 기다리는 중). 건너뜁니다.")
		return

	var made: Dictionary = await _make_draft(sources, targets)

	if not bool(made["made"]):
		print("[자동 순환] 제미나이 호출이 실패했습니다. 다음 순환에 다시 시도합니다.")
		return

	_drafted_signature = signature

	if not bool(made["ok"]):
		print("[자동 순환] 검사 오류가 남아 있어 합치지 않았습니다. 초안을 직접 확인하세요: ", made["path"])
		return

	if not _flag("--auto-accept"):
		print("[자동 순환] 초안이 준비됐습니다(검사 통과). 읽어 본 뒤 합치세요: run_request_text.bat accept %s" % str(made["path"]).trim_prefix("res://"))
		return

	var done: Dictionary = _accept_file(sources, str(made["path"]))

	if not bool(done["ok"]):
		return

	var files: Array = [str(done["target"]).trim_prefix("res://"), Tools.STATE_PATH.trim_prefix("res://"), str(made["path"]).trim_prefix("res://")]
	var add_args: Array = ["add", "--"]
	add_args.append_array(files)
	_git(add_args)
	var commit_args: Array = ["commit", "-m", "[docs] 자동 동기화: 제미나이 글 %d건(검사 통과)" % int(done["rows"]), "--"]
	commit_args.append_array(files)
	var commit: Dictionary = _git(commit_args)
	print("[자동 순환] 커밋: ", str(commit["out"]).left(160))

	if _flag("--no-push") or int(commit["code"]) != 0:
		return

	var push: Dictionary = _git(["push", "origin", STORY_BRANCH])
	print("[자동 순환] 푸시 ", "성공" if int(push["code"]) == 0 else "실패: " + str(push["out"]).left(200))
	_drafted_signature = ""


func _flag(name: String) -> bool:
	return OS.get_cmdline_user_args().has(name)


static func build_repair_prompt(csv_text: String, problems: Array[String]) -> String:
	return "아래 표(탭으로 구분)는 검사에서 다음 문제가 나왔다. 문제가 있는 행의 글만 규칙에 맞게 고쳐서, 모든 행을 같은 형식(탭 구분)으로 다시 출력한다(머리글 줄 없이 행만). id와 kind와 칸 수는 그대로 둔다. 글자 수 제한은 한 칸의 문장을 짧게 줄여서 지킨다(한 칸에 공백 포함). 글자 수를 맞추려고 칸(줄)을 지우거나 합치지 않는다. 칸 수와 칸별 역할은 그대로 둔다.\n\n문제:\n- %s\n\n현재 표:\n%s" % ["\n- ".join(problems), csv_to_tsv(csv_text)]


# kind별 요청 글. 현재 문장(참고용)과 기계 정보 중 글에 도움이 되는 것만 준다.
static func build_prompt(kind: String, targets: Dictionary, sources: Dictionary = {}, drafts: Dictionary = {}) -> String:
	var head: String = "kind = %s 인 항목들의 글을 새로 쓴다. 항목마다 한 행." % kind

	if not drafts.is_empty():
		head = "kind = %s 인 항목들의 초안을 다듬는다. 항목마다 한 행. 초안의 뜻·칸 수·칸별 역할·id·title 은 그대로 두고 문장만 고친다." % kind

	var out: PackedStringArray = [head, ""]
	var residents: Dictionary = (sources if not sources.is_empty() else targets).get(Tools.KIND_RESIDENT_GREETING, {})
	var voices: Dictionary = Tools.load_voices()
	var profiles: Dictionary = Profiles.load_profiles()

	for id in targets[kind].keys():
		var d: Dictionary = targets[kind][id]
		var current: PackedStringArray = Tools.row_from_source(kind, d)
		var info: String = ""

		match kind:
			Tools.KIND_PERSONAL_REQUEST:
				var resident: Dictionary = residents.get(str(d.get("resident", "")), {})
				var items: PackedStringArray = []
				for requirement in d.get("requirements", []):
					items.append(_item_name(str(requirement["item"])))
				info = "인물: %s / 필요한 물건: %s / 정착 뒤 안부를 나눈 이웃의 개인 부탁 / 기한 없음 / 창고 준비 후 게시판에서 직접 전달" % [resident.get("name", d.get("resident", "")), "·".join(items)]
				if d.has("stockpile_season"):
					info += " / 제안 계절: " + str(d["stockpile_season"]) + " / 지난 계절에만 원정에서 얻는 재료를 오래 보관해 전달 / 제안을 맡은 뒤 계절이 바뀌어도 유지 / 대금·평판은 UI에 표시하며 숫자는 대사에 넣지 않음 / 서리 얼음은 상온 다음 아침에 물이 됨: 냉동함에 넣었다가 전달할 날 꺼냄 / 새순·물박하는 채집 계절이 지난 아침에 시들고 냉장·냉동 보관 가능 / 식물 부탁은 베이킹 작업대에서 가공한 말린 봄 새순·말린 물박하를 요구 / 주민은 보존 경험을 말하며 설비 설치·버튼 조작은 플레이어 UI에 맡김 / 무료 재료 없음"
				var after := str(d.get("after", ""))
				if not after.is_empty():
					info += " / 앞선 개인 부탁: " + Tools.row_from_source(Tools.KIND_PERSONAL_REQUEST, {"id":after})[2]
				if bool(d.get("after_gathering",false)):
					info += " / 우물 곁 첫 저녁 모임 뒤 이웃이 된 관계의 후속 이야기 / 새 건물·장비·책 지급이나 별도 기능을 약속하지 않음"
				if bool(d.get("after_market", false)):
					info += " / 첫 장터를 함께 마친 다음 날 이후 / 배운 레시피의 완제품을 전달하고 주민에게 E로 후일담을 끝까지 듣기 / 후일담에 추가 답례 없음"
				if d.has("after_craft"):
					info += " / 교류로 배운 상품의 생활 사용 / 해당 제품 이야기의 시제품 나눔 완료 다음 날 이후 / 기존 제조법 완제품만 전달, 맡은 뒤 재제작 필수 아님 / 상품 대금과 작은 사례비는 전달 최초1회, 가격·수량은 UI / 전달 다음 날 주민 E 사용 후일담 완독, 추가 답례·능력치·실제 사용 연출·손님 해금 없음"
				if d.has("recipe"):
					info += " / 기존 레시피: " + _item_name(str(d["recipe"]))
				if bool(d.get("after_rest", false)):
					info += " / 길목 쉼터 첫 모임을 끝까지 함께한 다음 날 이후 / 앞선 먹거리 부탁의 후일담도 완독 / 원정 재료를 창고에 준비해 게시판에서 전달하고 주민에게 E로 후일담 듣기 / 가방·장비·날씨·능력치 변경 없음 / 추가 답례 없음"
				if d.has("after_store_event"):
					info += " / 매장 행사에서 이어지는 부탁 / " + str(d.get("context", "")) + " / 행사 기간의 전체 매장 판매 기록이며 행사 수요 구매나 구매자 신원을 특정하지 않음 / 행사 종료 후 기한 없이 준비 / 후일담에 추가 답례 없음"
			Tools.KIND_RESIDENT_INTRODUCTION:
				info = "인물: %s / 손님 유형: %s" % [d.get("npc",""), d.get("type","")]
			Tools.KIND_TRADE_OFFER:
				info = "건네는 재료: %s / 받는 재료: %s" % [_item_name(str(d.get("give",""))), _item_name(str(d.get("receive","")))]
			Tools.KIND_TUTORIAL_STEP:
				info = "안내 목표: %s / 화자: %s / 장면: %s / 조작 키는 summary의 UI 안내에 유지, 현지인 대사로 이동하지 않음" % [d.get("goal",""), d.get("npc",""), d.get("stage","")]
			Tools.KIND_TUTORIAL_DIALOGUE, Tools.KIND_SERVICE_TEXT:
				info = "기존 기능 안내를 유지하는 문장: " + id
				if d.has("stage"):
					info = "마을 이야기·이벤트 / 말하는 사람: %s / 장면: %s / 새 정착·구매·해금을 약속하지 않음" % [d.get("npc", ""), d["stage"]]
				if id.begins_with("craft_"):
					info = "교류로 제품 발전 / 화자: %s / 장면: %s / 소개 완독 시 실제 제조법 학습, 소개 후 제작 수령과 창고 시제품이 필요, 최종 완독 때 시제품 소비·평판 최초 1회 / 현지인은 현지 재료·음식을 설명, 처음 편의점 빵·생수의 재현 지식은 플레이어 / 조작·수량은 UI, 새 시설·돈·무료 완제품 약속 없음" % [d.get("npc", ""),d.get("stage", "")]
				if id.begins_with("regular_"):
					info = "실제 구매로 시작하는 단골 이야기 / 화자: %s / 장면: %s / 상품/수량/재료/답례는 UI, 새 고유 이름·자동 판매·실제 동료 등장·판매 보장·추가 답례 약속 없음 / introduction→실제 재구매→부탁→최종 완독→다음 날 후일담, 기간 제한 없음" % [d.get("npc",""),d.get("stage","")]
				if id.begins_with("weather_"):
					info = "날씨에서 이어진 실제 구매 / 화자: %s / 장면: %s / 날씨·계절은 최초 소개 조건, 소개 후에는 변화해도 계속 / 진열 상품을 대표 손님이 실제 구매한 다음 날 E 최종 완독에 재료 답례·평판 최초1회 / 직접 전달·무료 상품·자동 판매·가격 상승·기간 제한·새 시설/고유 이름 없음 / 현재 날씨 단정 없이 지난 구매 회상, 수량·가격은 UI" % [d.get("npc",""),d.get("stage","")]
				if id.begins_with("expansion_"):
					info = "마을의 여덟 콘텐츠 묶음 / 화자: %s / 실제 단계: %s / 기존 service_text, 수량·날짜·조작은 UI / 단계·대금 지급 시점·실제 제작/채집·참가자 도착 조건을 유지 / 새 고유 이름·미구현 건물·자동 판매·추가 지급·회복/능력치 효과를 약속하지 않음" % [d.get("npc", ""),d.get("stage", "")]
				if id.begins_with("workshop_afterglow_"):
					info = "교류로 배운 상품의 사용 후일담 / 화자: %s / 장면: %s / 게시판에서 완제품 전달 다음 날 이후 주민 E 완독으로 수첩 기억 / 상품 대금·작은 사례비는 이전 전달 때 이미 지급, 추가 지급 없음 / 현재 날씨 단정·새 이름/건물/무료 물품/회복/능력치/판매 보장 없음 / 수량·가격·조작은 UI" % [d.get("npc", ""),d.get("stage", "")]
				if id.begins_with("prologue_"):
					info = "튜토리얼 전 플레이어 독백 / 화자: 나 / 장면: %s / 익숙한 가게에서 낯선 풍경 발견→함께 온 가게 확인→가게 정리 결심 / 아직 첫 손님·현지 화폐·물물교환·원정을 만나지 않았음 / 전이 원인·신·사고·고유 이름·세계의 확정 법칙·새 장비/재료 지급 없음 / 마지막 완독 후 기존 튜토리얼, 현실 지도/연출 영상을 약속하지 않음" % d.get("stage","")
				if id.begins_with("contact_"):
					info = "원정에서 만난 사람 / 화자: %s / 장면: %s / 실제 비전투 물음표 방에서 접근 E 완독→다음 날 마을에서 창고 재료 직접 전달→최초 답례→다른 날 실제 가게 결제→다음 날 후일담 / 기간·계절 제한 없음, 원정 가방 소비·전투 구출·무료 상품·새 고유 이름/시설/기능 약속 없음 / 조작·수량·상품 가격은 UI" % [d.get("npc",""),d.get("stage","")]
				if id.begins_with("preserve_"):
					info = "처음 만난 계절 재료의 보존 체험 / 화자: %s / 장면: %s / 소개 완독 후 실제 보관 입고→다음 날 이후 출고 또는 실제 베이킹 생산 수령 / 생재료(cold)와 가공품(dry) 경로의 서술 구분 / 두 방법 중 하나만 필요, 기한·계절 제한 없음·손실 강제 없음 / 일반 창고 시료를 주민 E로 직접 전달, 최종 완독 최초1회 소비·작은 재료 답례·평판 / 현지인은 보존 경험, 현대 설비 설치/키/수량은 UI / 무료 설비·새 고객·실제 음용/회복 없음" % [d.get("npc", ""),d.get("stage", "")]
				if kind == Tools.KIND_TUTORIAL_DIALOGUE:
					info = "초반 현지 손님의 실제 구매 / " + ("원정 원재료를 다시 구매" if id.begins_with("raw_") else "함께 온 가게 식품을 처음 구매") + " / 조작·매출 기록·현대 기기 설명은 UI와 플레이어 몫 / 연습용 물건이나 추가 선물 없음"
				if id == "arrival_peddler_return":
					info = "이전에 실제 식품과 검·갑옷을 바꾼 타블렌의 재방문 / 처음 만나는 자기소개 금지 / 주민 부탁·정착은 기존 조건 유지"
				if d.has("event_id") and d.has("context"):
					info = "매장 행사 / 장면: %s / %s / 날짜·배율·판매 보장 안내 금지 / {item}이 있다면 유지 / 없는 날씨·인파·오브젝트 연출 추가 금지" % [d["stage"], d["context"]]
				if d.has("speaker") and not d.has("stage"):
					var speaker := str(d["speaker"])
					info = "우물 곁 저녁 모임 / 말하는 사람: %s / 준비한 빵과 물을 함께 나눔 / 새 물품이나 돈을 약속하지 않음 / 화자 이름은 대사에 쓰지 않음" % ("장면 서술" if speaker.is_empty() else str(residents.get(speaker, {}).get("name", speaker)))
			Tools.KIND_RESIDENT_REQUEST:
				info = "인물: %s / 필요한 재료: %s" % [d.get("npc", ""), _item_name(str(d.get("item", "")))]
			Tools.KIND_COMMUNITY_REQUEST:
				if bool(d.get("after_afterglow", false)):
					info += "첫 장터 뒤 먹거리 후일담 세 개를 듣고 다음 날부터 준비 / 재료는 게시판에서 전달 / 다음 오후 새 벤치에 모여 쉬기 / 반복 보상·체력 회복 없음 / "
				var names: PackedStringArray = []

				for req in d.get("requirements", []):
					names.append(_item_name(str(req.get("item", ""))))

				var resident: Dictionary = residents.get(str(d.get("resident", "")), {})
				info += "부탁하는 주민: %s / 필요한 재료: %s / 완성되는 곳: %s" % [resident.get("name", d.get("resident", "")), ", ".join(names), d.get("landmark_name", "")]
			Tools.KIND_RESIDENT_GREETING:
				info = "이름: %s / 직업: %s / 건네는 물건: %s" % [d.get("name", ""), d.get("type", ""), _item_name(str(d.get("gift", "")))]

		var voice: Dictionary = voices.get(id, {})

		if not voice.is_empty():
			info += " / 말하는 사람: %s / 말버릇: %s" % [voice["name"], voice["voice"]]

		out.append("id=%s | %s" % [id, info])
		var profile := Profiles.for_speaker(profiles, str(voice.get("name", d.get("npc", d.get("name", "")))), str(id))
		if not profile.is_empty():
			out.append(profile)
		out.append("현재 문장(참고, 같은 칸 수와 역할로 새로 쓴다): " + "\t".join(current))

		if drafts.has(id):
			out.append("다듬을 초안: " + "\t".join(drafts[id]))
		out.append("")

	return "\n".join(out)


static func _item_name(item_id: String) -> String:
	if item_id.is_empty():
		return ""

	return ItemData.get_item_name(item_id) if ItemData.has_item(item_id) else item_id


# 코드블록 표시와 머리글 줄을 지운 CSV 행들(끝에 줄바꿈 포함).
# CSV 글을 탭으로 구분한 줄로 바꾼다(제미나이에게 보여 줄 때 쓴다. 칸 안의 쉼표가 헷갈리지 않게).
static func csv_to_tsv(csv_text: String) -> String:
	var out: PackedStringArray = []

	for line in csv_text.split("\n"):
		if line.strip_edges().is_empty():
			continue

		out.append("\t".join(Tools.parse_csv_line(line.strip_edges())))

	return "\n".join(out)


# 줄 단위로 fix_shifted_lines 를 적용한다.
static func fix_shifted_rows(text: String, sources: Dictionary) -> String:
	var out: PackedStringArray = []

	for line in text.split("\n", false):
		var cells: PackedStringArray = Tools.parse_csv_line(line)
		var fixed: PackedStringArray = Tools.fix_shifted_lines(cells, sources)
		out.append(Tools.csv_line(fixed) if fixed != cells else line)

	return "\n".join(out) + "\n" if not out.is_empty() else ""


static func clean_rows(text: String) -> String:
	var kept: PackedStringArray = []

	for raw_line in text.split("\n"):
		var line: String = raw_line.strip_edges()

		if line.is_empty() or line.begins_with("```") or line.begins_with("id,kind"):
			continue

		# 탭으로 구분한 줄(요청한 형식)이면 칸을 나눠 CSV로 바꾼다. 아니면 CSV로 읽는다.
		var is_tsv: bool = line.contains("\t")
		var cells: PackedStringArray = line.split("\t") if is_tsv else Tools.parse_csv_line(line)

		if is_tsv and cells.size() >= 1 and cells[0].strip_edges() == "id" and cells.size() > 1 and cells[1].strip_edges() == "kind":
			continue

		var fixed: PackedStringArray = Tools.fix_missing_empty_cell(cells)

		for i in range(fixed.size()):
			fixed[i] = fixed[i].strip_edges()

		kept.append(Tools.csv_line(fixed) if (is_tsv or fixed.size() != cells.size()) else line)

	return "\n".join(kept) + "\n" if not kept.is_empty() else ""


# 이번 실행에서 구글에 보낸 요청 횟수(실패·재시도 포함). 무료 한도는 요청 횟수로 세므로 참고용.
func _print_usage(client: Node) -> void:
	if client.has_method("request_summary") and not str(client.request_summary()).is_empty():
		print("[제미나이] 이번 실행의 요청 횟수: ", client.request_summary(), " (무료 한도는 모델마다 하루 20회 안팎이며, 실패한 재시도도 세어질 수 있음)")


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
