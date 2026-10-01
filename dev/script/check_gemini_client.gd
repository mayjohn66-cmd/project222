extends Node
## GeminiClient / 스토리 초안 생성기의 오프라인 검사(네트워크·API 키 불필요).

const GeminiClient = preload("res://dev/gemini/gemini_client.gd")

var failures: int = 0


func _ready() -> void:
	call_deferred("_run")


func _check(ok: bool, text: String) -> void:
	if ok:
		print("PASS: ", text)
	else:
		failures += 1
		print("FAIL: ", text)


# 네트워크 없이 재시도 흐름을 시험하는 가짜 클라이언트: 정해 둔 결과를 순서대로 돌려준다.
class MockClient extends "res://dev/gemini/gemini_client.gd":
	var script_results: Array = []
	var calls: Array[String] = []

	func _request_once(model: String, _prompt: String, _system: String, _temp: float, _json: bool) -> Dictionary:
		calls.append(model)
		return script_results.pop_front() if not script_results.is_empty() else {"ok": false, "text": "", "error": "end", "finish_reason": "", "http_code": 500}


func _res_fail(code: int) -> Dictionary:
	return {"ok": false, "text": "", "error": "HTTP %d" % code, "finish_reason": "", "http_code": code}


func _res_ok() -> Dictionary:
	return {"ok": true, "text": "좋아요", "error": "", "finish_reason": "STOP", "http_code": 200}


func _run() -> void:
	# 요청 본문
	var body: Dictionary = JSON.parse_string(GeminiClient.build_request_body("안녕", "너는 작가다", 0.5, false))
	_check(body["contents"][0]["parts"][0]["text"] == "안녕", "요청 본문에 프롬프트")
	_check(body["systemInstruction"]["parts"][0]["text"] == "너는 작가다", "시스템 지침 포함")
	_check(is_equal_approx(float(body["generationConfig"]["temperature"]), 0.5), "temperature")
	_check(not body["generationConfig"].has("responseMimeType"), "JSON 모드 꺼짐")
	var no_system: Dictionary = JSON.parse_string(GeminiClient.build_request_body("a"))
	_check(not no_system.has("systemInstruction"), "시스템 지침 없으면 생략")
	var json_body: Dictionary = JSON.parse_string(GeminiClient.build_request_body("a", "", 0.8, true))
	_check(json_body["generationConfig"]["responseMimeType"] == "application/json", "JSON 모드")

	# 응답 해석
	var good := '{"candidates":[{"content":{"parts":[{"text":"가"},{"text":"나"}]},"finishReason":"STOP"}]}'
	var r1 := GeminiClient.parse_response(200, good)
	_check(r1["ok"] and r1["text"] == "가나" and r1["finish_reason"] == "STOP", "정상 응답 이어 붙임")
	var r2 := GeminiClient.parse_response(429, '{"error":{"message":"quota"}}')
	_check(not r2["ok"] and "quota" in r2["error"] and "429" in r2["error"], "HTTP 오류 메시지")
	var r3 := GeminiClient.parse_response(200, '{"promptFeedback":{"blockReason":"SAFETY"}}')
	_check(not r3["ok"] and "SAFETY" in r3["error"], "차단 사유")
	var r4 := GeminiClient.parse_response(200, '{"candidates":[]}')
	_check(not r4["ok"], "후보 없음")
	var r5 := GeminiClient.parse_response(200, "not json")
	_check(not r5["ok"], "JSON 아님")
	var r6 := GeminiClient.parse_response(200, '{"candidates":[{"content":{"parts":[]},"finishReason":"MAX_TOKENS"}]}')
	_check(not r6["ok"] and "MAX_TOKENS" in r6["error"], "빈 글")

	# 키 찾기(환경 변수 우선, 값은 출력하지 않는다)
	OS.set_environment(GeminiClient.ENV_KEY, "")
	var before := GeminiClient.find_api_key()
	OS.set_environment(GeminiClient.ENV_KEY, "test-key-123")
	_check(GeminiClient.find_api_key() == "test-key-123", "환경 변수 키 읽기")
	OS.set_environment(GeminiClient.ENV_KEY, "")
	_check(GeminiClient.find_api_key() == before, "환경 변수 비우면 다른 곳 확인")
	OS.set_environment(GeminiClient.ENV_MODEL, "")
	_check(GeminiClient.find_model() == GeminiClient.DEFAULT_MODEL, "기본 모델")
	OS.set_environment(GeminiClient.ENV_MODEL, "my-model")
	_check(GeminiClient.find_model() == "my-model", "환경 변수 모델")
	OS.set_environment(GeminiClient.ENV_MODEL, "")

	# 키 없을 때 호출은 네트워크에 나가지 않고 안내 메시지를 돌려준다.
	if GeminiClient.find_api_key().is_empty():
		var client := GeminiClient.new()
		add_child(client)
		var r7: Dictionary = await client.generate("x")
		_check(not r7["ok"] and "GEMINI_API_KEY" in r7["error"], "키 없으면 안내 오류(요청 안 보냄)")

	# 시스템 프롬프트 조립(세계관 설정 문서 반영)
	var gen = load("res://dev/gemini/story_draft_generator.gd")
	var setting_text := FileAccess.get_file_as_string("res://docs/drafts/story/world_setting.md")
	var full: String = gen.build_system_prompt(setting_text)
	_check("이세계 숲 한가운데" in full and "24시 편의점" in full, "세계관 배경이 시스템 프롬프트에 들어감")
	_check("1줄 이상" in full and "자동문" in full, "NPC 반응 지침이 들어감")
	_check(not ("상태: 🟡" in full) and not ("이 파일의 내용은" in full), "안내용 인용문은 제외")
	_check("beat_id,npc_id" in full and "neighbor" in full, "기본 지침도 그대로 유지")
	_check(gen.build_system_prompt("") == gen.SYSTEM_PROMPT, "설정 문서가 없으면 기본 지침만")

	# 재시도 규칙
	_check(GeminiClient.is_retryable(503) and GeminiClient.is_retryable(429) and GeminiClient.is_retryable(500), "503·429·500은 재시도")
	_check(not GeminiClient.is_retryable(404) and not GeminiClient.is_retryable(403) and not GeminiClient.is_retryable(200), "404·403은 재시도 안 함")
	_check(is_equal_approx(GeminiClient.retry_delay_sec(1), 4.0) and is_equal_approx(GeminiClient.retry_delay_sec(3), 16.0), "대기 4, 8, 16초")
	var r8 := GeminiClient.parse_response(503, '{"error":{"message":"high demand"}}')
	_check(not r8["ok"] and int(r8["http_code"]) == 503, "오류 결과에 http_code 포함")

	# 재시도 흐름(가짜 클라이언트, 대기 시간 0)
	OS.set_environment("GEMINI_MODEL", "main-model")
	OS.set_environment("GEMINI_FALLBACK_MODEL", "")
	var m1 := MockClient.new()
	add_child(m1)
	m1.retry_wait_scale = 0.0
	m1.script_results = [_res_fail(503), _res_fail(503), _res_ok()]
	var g1: Dictionary = await m1.generate("x")
	_check(g1["ok"] and m1.calls.size() == 3, "503 두 번 뒤 성공(호출 3회)")
	var m2 := MockClient.new()
	add_child(m2)
	m2.retry_wait_scale = 0.0
	m2.script_results = [_res_fail(404)]
	var g2: Dictionary = await m2.generate("x")
	_check(not g2["ok"] and m2.calls.size() == 1, "404는 재시도 없이 바로 실패(호출 1회)")
	var m3 := MockClient.new()
	add_child(m3)
	m3.retry_wait_scale = 0.0
	m3.script_results = [_res_fail(503), _res_fail(503), _res_fail(503), _res_fail(503), _res_fail(503)]
	var g3: Dictionary = await m3.generate("x")
	_check(not g3["ok"] and m3.calls.size() == GeminiClient.MAX_ATTEMPTS, "계속 503이면 최대 횟수에서 멈춤")
	OS.set_environment("GEMINI_FALLBACK_MODEL", "backup-model")
	var m4 := MockClient.new()
	add_child(m4)
	m4.retry_wait_scale = 0.0
	m4.script_results = [_res_fail(503), _res_fail(503), _res_fail(503), _res_fail(503), _res_fail(503), _res_ok()]
	var g4: Dictionary = await m4.generate("x")
	_check(g4["ok"] and m4.calls.size() == 6 and m4.calls[5] == "backup-model" and m4.calls[0] == "main-model", "예비 모델로 넘어가 성공")
	OS.set_environment("GEMINI_FALLBACK_MODEL", "")
	OS.set_environment("GEMINI_MODEL", "")

	# CSV 정리
	var cleaned: String = load("res://dev/gemini/story_draft_generator.gd").clean_csv("```csv\nbeat_id,npc_id,conditions,gifts,repeat_days,lines\na_b,neighbor,day>=2,,0,안녕\n```\n")
	_check(cleaned == "beat_id,npc_id,conditions,gifts,repeat_days,lines\na_b,neighbor,day>=2,,0,안녕\n", "코드블록·중복 머리글 제거")

	print("CHECK_GEMINI_CLIENT failures=", failures)
	get_tree().quit(1 if failures > 0 else 0)
