extends Node
## 부탁 글 도구 검사: 원본 읽기, 검사 규칙, 프롬프트 조립, CSV 내보내기 형식.

const Tools = preload("res://dev/gemini/request_text_tools.gd")
const Runner = preload("res://dev/gemini/request_text_runner.gd")

var failures: int = 0


func _ready() -> void:
	call_deferred("_run")


func _check(ok: bool, text: String) -> void:
	if ok:
		print("PASS: ", text)
	else:
		failures += 1
		print("FAIL: ", text)


func _row(values: Array) -> PackedStringArray:
	return PackedStringArray(values)


func _known() -> Dictionary:
	return {
		Tools.KIND_RESIDENT_REQUEST: {"neighbor_bread": {"id": "neighbor_bread", "npc": "이웃 주민", "item": "bread", "title": "t", "lines": ["a"], "completion": ["b"]}},
		Tools.KIND_COMMUNITY_REQUEST: {"path_light": {"id": "path_light", "resident": "naru", "title": "t", "summary": "s", "requirements": [{"item": "dry_branch", "amount": 5}], "landmark_name": "길목 등불", "completion": "c"}},
		Tools.KIND_RESIDENT_GREETING: {"naru": {"id": "naru", "name": "행상인 나루", "type": "peddler", "gift": "bread", "greetings": ["x"]}},
	}


func _run() -> void:
	var header := Tools.COLUMNS

	# 원본 읽기(현재 저장소에 있는 파일만)
	var sources: Dictionary = Tools.load_sources()
	_check(sources[Tools.KIND_RESIDENT_REQUEST].has("neighbor_bread"), "주민 부탁 원본 읽기(.tres 한 줄 JSON)")
	_check(str(sources[Tools.KIND_RESIDENT_REQUEST]["neighbor_bread"]["item"]) == "bread", "원본의 기계 필드 보존")

	# 정상 행
	var good := [
		_row(["neighbor_bread", "resident_request", "이웃의 아침 식사", "", "빵이 좀 필요한데, 구해 줄 수 있어?|준비되면 다시 말해 줘.", "고마워, 덕분에 살았어!"]),
		_row(["path_light", "community_request", "길목의 작은 등불", "노점 앞길을 밝힐 불빛을 모읍니다.", "", "길목에 등불이 켜졌습니다."]),
		_row(["naru", "resident_greeting", "", "", "나루가 노점 앞에서 손을 흔들었습니다.|나루와 안부를 나눴습니다.", ""]),
	]
	var r1 := Tools.validate_rows(header, good, _known(), "good.csv")
	_check(r1["errors"].is_empty(), "정상 행은 오류 없음")

	# 나쁜 행들
	var bad_id := Tools.validate_rows(header, [_row(["new_one", "resident_request", "제목", "", "대사", ""])], _known())
	_check(not bad_id["errors"].is_empty() and "원본에 없는 id" in str(bad_id["errors"]), "새 id는 오류(제미나이는 id를 만들 수 없음)")
	var forbidden := Tools.validate_rows(header, [_row(["neighbor_bread", "resident_request", "퀘스트 안내", "", "보상을 줄게", ""])], _known())
	_check("퀘스트" in str(forbidden["errors"]) and "보상" in str(forbidden["errors"]), "게임 용어 금지어 오류")
	var qty := Tools.validate_rows(header, [_row(["neighbor_bread", "resident_request", "빵", "", "빵 두 개를 부탁해.", ""])], _known())
	_check(qty["errors"].is_empty() and "수량 표현" in str(qty["warns"]), "수량 표현은 주의")
	var digit := Tools.validate_rows(header, [_row(["neighbor_bread", "resident_request", "빵", "", "빵 3개 필요해.", ""])], _known())
	_check("수량 표현" in str(digit["warns"]), "숫자 수량도 주의")
	var long_title := Tools.validate_rows(header, [_row(["neighbor_bread", "resident_request", "아주아주아주아주아주아주아주 긴 제목입니다", "", "대사", ""])], _known())
	_check("title가" in str(long_title["errors"]), "제목 길이 초과 오류")
	var wrong_cols := Tools.validate_rows(header, [_row(["neighbor_bread", "resident_request", "제목"])], _known())
	_check("칸 수" in str(wrong_cols["errors"]), "칸 수 오류")
	var wrong_kind := Tools.validate_rows(header, [_row(["x", "quest", "", "", "", ""])], _known())
	_check("kind는" in str(wrong_kind["errors"]), "kind 오류")
	var dup := Tools.validate_rows(header, [good[0], good[0]], _known())
	_check("두 번" in str(dup["errors"]), "중복 id 오류")
	var wrong_fields := Tools.validate_rows(header, [_row(["naru", "resident_greeting", "제목", "", "인사", ""])], _known())
	_check("lines만" in str(wrong_fields["errors"]), "인사말에 title을 쓰면 오류")
	var no_source := Tools.validate_rows(header, [good[1]], {Tools.KIND_RESIDENT_REQUEST: {}, Tools.KIND_COMMUNITY_REQUEST: {}, Tools.KIND_RESIDENT_GREETING: {}})
	_check("원본 파일이 없어" in str(no_source["warns"]), "원본 파일이 없으면 주의로 알림")
	var wrong_header := Tools.validate_rows(PackedStringArray(["id", "kind"]), [], _known())
	_check(not wrong_header["errors"].is_empty(), "머리글 오류")

	# 내보내기 형식 왕복(쉼표·따옴표가 있는 칸)
	var tricky := Tools.csv_line(PackedStringArray(["a", "b", "안녕, \"친구\"", "", "x", ""]))
	_check(tricky == 'a,b,"안녕, ""친구""",,x,', "csv 따옴표 처리")

	# 프롬프트 조립: 기계 정보는 주되 수치(수량·보상)는 주지 않는다.
	var prompt: String = Runner.build_prompt(Tools.KIND_RESIDENT_REQUEST, _known())
	_check("id=neighbor_bread" in prompt and "이웃 주민" in prompt, "프롬프트에 id와 인물")
	_check(not ("money" in prompt) and not ("reputation" in prompt), "프롬프트에 보상 수치 없음")
	var gprompt: String = Runner.build_prompt(Tools.KIND_RESIDENT_GREETING, _known())
	_check("행상인 나루" in gprompt, "인사말 프롬프트에 주민 이름")
	var cprompt: String = Runner.build_prompt(Tools.KIND_COMMUNITY_REQUEST, _known())
	_check("행상인 나루" in cprompt and "길목 등불" in cprompt, "게시판 프롬프트에 주민 이름과 완성 장소")
	_check(Runner.clean_rows("```csv\nid,kind,title,summary,lines,completion\na,b,c,,d,e\n```\n") == "a,b,c,,d,e\n", "코드블록·머리글 제거")
	_check(Runner.BASE_PROMPT.contains("새 id를 만들거나 빼지 않는다"), "기본 지침에 id 고정 규칙")
	_check(Runner.BASE_PROMPT.contains("다시 말을 걸기") and Runner.BASE_PROMPT.contains("가지러 올게"), "기본 지침에 플레이어 행동 유지 규칙")
	_check(Runner.BASE_PROMPT.contains("말투(반말/존댓말)"), "기본 지침에 말투 일관 규칙")
	_check(Runner.BASE_PROMPT.contains("상투 표현") and Runner.BASE_PROMPT.contains("되풀이하지"), "기본 지침에 상투·반복 금지 규칙")
	var slop_header: PackedStringArray = Tools.COLUMNS
	var slop_rows: Array = []

	for n in ["a", "b", "c"]:
		slop_rows.append(PackedStringArray([n, "resident_request", "제목", "", "첫 줄 입니다|창고에 두고 다시 말을 걸어 줘", "무사히 끝났어 덕분에 편해졌어. 오늘 밤은 푹 자겠다"]))

	var slop: Dictionary = Tools.validate_rows(slop_header, slop_rows, {}, "slop")
	var slop_text: String = "\n".join(PackedStringArray(slop["warns"]))
	_check(slop_text.contains("상투 표현 '덕분에'"), "상투 표현을 주의로 알림")
	_check(slop_text.contains("반복 어구 '오늘 밤은'"), "여러 항목의 반복 어구를 주의로 알림")
	_check(not slop_text.contains("말을 걸"), "행동 안내 칸은 반복 검사에서 제외")
	_check(Runner._repairable(slop).size() >= 3, "상투·반복 주의는 자동 수정 대상")
	var chunks: Array = Runner.chunk_ids(["a", "b", "c", "d", "e"], 2)
	_check(chunks.size() == 3 and chunks[0] == ["a", "b"] and chunks[2] == ["e"], "항목을 2개씩 묶음")
	_check(Runner.chunk_ids([], 2).is_empty() and Runner.chunk_ids(["a"], 0).size() == 1, "빈 목록·0 크기 처리")

	# 수정 요청 조립
	var result := {"errors": ["a.csv:2 [x] lines 한 칸이 48자(최대 45)"], "warns": ["a.csv:3 [y] 수량 표현 '한 병' 이 있음", "a.csv:4 [z] completion 한 칸이 46자(권장 45 이하)", "a.csv:5 [w] 원본 파일이 없어 id를 확인하지 못함"]}
	var problems: Array[String] = Runner._repairable(result)
	_check(problems.size() == 3, "고칠 문제: 오류 전부 + 수량·길이 주의, 그 밖의 주의는 제외")
	var repair: String = Runner.build_repair_prompt("id,kind\nx,y\n", problems)
	_check("48자" in repair and "한 병" in repair and "id,kind" in repair, "수정 요청에 문제와 현재 CSV가 들어감")
	_check(Runner._repairable({"errors": [], "warns": ["a [x] 돈 선물"]}).is_empty(), "문제 없으면 수정 요청 안 함")

	# ---- 동기화: 새 항목·바뀐 항목 탐지 ----
	var src := {
		Tools.KIND_RESIDENT_REQUEST: {
			"a": {"id": "a", "npc": "이웃", "item": "bread", "amount": 2, "title": "t", "lines": ["x"]},
			"b": {"id": "b", "npc": "광부", "item": "iron_ore", "amount": 3, "title": "t2", "lines": ["y"]},
			"c": {"id": "c", "npc": "새 주민", "item": "water", "amount": 1},
		},
		Tools.KIND_COMMUNITY_REQUEST: {},
		Tools.KIND_RESIDENT_GREETING: {},
	}
	_check(Tools.fingerprint(src[Tools.KIND_RESIDENT_REQUEST]["a"]) == Tools.fingerprint({"id": "a", "npc": "이웃", "item": "bread", "amount": 2, "title": "완전히 다른 제목", "lines": ["다른 대사"]}), "글 필드가 바뀌어도 기계 지문은 같다")
	_check(Tools.fingerprint(src[Tools.KIND_RESIDENT_REQUEST]["a"]) != Tools.fingerprint({"id": "a", "npc": "이웃", "item": "bread", "amount": 3, "title": "t", "lines": ["x"]}), "수량이 바뀌면 지문이 달라진다")
	var texts := {
		"resident_request:a": PackedStringArray(["a", "resident_request", "t", "", "x", ""]),
		"resident_request:b": PackedStringArray(["b", "resident_request", "t2", "", "y", ""]),
		"resident_request:gone": PackedStringArray(["gone", "resident_request", "t3", "", "z", ""]),
	}
	var state := {
		"resident_request:a": Tools.fingerprint(src[Tools.KIND_RESIDENT_REQUEST]["a"]),
		"resident_request:b": "old-hash",
	}
	var todo := Tools.find_todo(src, texts, state)
	_check(todo["new"][Tools.KIND_RESIDENT_REQUEST].has("c") and todo["new"][Tools.KIND_RESIDENT_REQUEST].size() == 1, "글이 없는 c는 새 항목")
	_check(todo["changed"][Tools.KIND_RESIDENT_REQUEST].has("b") and todo["changed"][Tools.KIND_RESIDENT_REQUEST].size() == 1, "지문이 달라진 b는 바뀐 항목")
	_check(not todo["changed"][Tools.KIND_RESIDENT_REQUEST].has("a"), "지문이 같은 a는 할 일 없음")
	_check(todo["orphan"] == ["resident_request:gone"], "원본이 사라진 글을 알려 줌")
	_check(Tools.count_targets(todo["new"]) == 1, "새 항목 개수")
	# 상태가 비어 있으면(처음) 글이 있는 항목은 바뀐 것으로 보지 않는다.
	var first := Tools.find_todo(src, texts, {})
	_check(Tools.count_targets(first["changed"]) == 0 and Tools.count_targets(first["new"]) == 1, "상태가 없으면 기존 글은 승인된 것으로 간주")
	# 합치기: 초안이 기존 글을 덮어쓰고 새 id를 추가하며 상태를 갱신한다.
	var merged := Tools.merge_draft(texts, [PackedStringArray(["b", "resident_request", "새 제목", "", "새 대사", ""]), PackedStringArray(["c", "resident_request", "c 제목", "", "c 대사", ""])], src, state)
	_check("새 제목" in merged["csv"] and "c 제목" in merged["csv"] and not ("t2" in merged["csv"]), "합치면 덮어쓰고 추가한다")
	_check(merged["csv"].begins_with("id,kind,title,summary,lines,completion\n"), "합친 CSV 머리글")
	_check(merged["state_csv"].contains(Tools.fingerprint(src[Tools.KIND_RESIDENT_REQUEST]["b"])), "합친 항목의 상태 지문 갱신")
	_check(merged["state_csv"].contains(Tools.fingerprint(src[Tools.KIND_RESIDENT_REQUEST]["c"])), "새 항목 상태 지문 추가")

	print("CHECK_REQUEST_TEXT failures=", failures)
	get_tree().quit(1 if failures > 0 else 0)
