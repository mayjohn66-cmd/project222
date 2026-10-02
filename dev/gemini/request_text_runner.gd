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
		"sync":
			await _sync(sources)
		"accept":
			_accept(sources)
		"rebase-state":
			_rebase_state(sources)
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

			rows_text.append(clean_rows(str(result["text"])))

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

		var repaired: String = clean_rows(str(fixed["text"]))

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
static func build_prompt(kind: String, targets: Dictionary, sources: Dictionary = {}) -> String:
	var out: PackedStringArray = ["kind = %s 인 항목들의 글을 새로 쓴다. 항목마다 한 행." % kind, ""]
	var residents: Dictionary = (sources if not sources.is_empty() else targets).get(Tools.KIND_RESIDENT_GREETING, {})
	var voices: Dictionary = Tools.load_voices()

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
			Tools.KIND_RESIDENT_INTRODUCTION:
				info = "인물: %s / 손님 유형: %s" % [d.get("npc",""), d.get("type","")]
			Tools.KIND_TRADE_OFFER:
				info = "건네는 재료: %s / 받는 재료: %s" % [_item_name(str(d.get("give",""))), _item_name(str(d.get("receive","")))]
			Tools.KIND_TUTORIAL_STEP:
				info = "안내 목표: %s" % d.get("goal","")
			Tools.KIND_TUTORIAL_DIALOGUE, Tools.KIND_SERVICE_TEXT:
				info = "기존 기능 안내를 유지하는 문장: " + id
				if d.has("speaker"):
					var speaker := str(d["speaker"])
					info = "우물 곁 저녁 모임 / 말하는 사람: %s / 준비한 빵과 물을 함께 나눔 / 새 물품이나 돈을 약속하지 않음 / 화자 이름은 대사에 쓰지 않음" % ("장면 서술" if speaker.is_empty() else str(residents.get(speaker, {}).get("name", speaker)))
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

		var voice: Dictionary = voices.get(id, {})

		if not voice.is_empty():
			info += " / 말하는 사람: %s / 말버릇: %s" % [voice["name"], voice["voice"]]

		out.append("id=%s | %s" % [id, info])
		out.append("현재 문장(참고, 같은 칸 수와 역할로 새로 쓴다): " + "\t".join(current))
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
