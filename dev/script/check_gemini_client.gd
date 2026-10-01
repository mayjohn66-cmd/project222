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

	# CSV 정리
	var cleaned: String = load("res://dev/gemini/story_draft_generator.gd").clean_csv("```csv\nbeat_id,npc_id,conditions,gifts,repeat_days,lines\na_b,neighbor,day>=2,,0,안녕\n```\n")
	_check(cleaned == "beat_id,npc_id,conditions,gifts,repeat_days,lines\na_b,neighbor,day>=2,,0,안녕\n", "코드블록·중복 머리글 제거")

	print("CHECK_GEMINI_CLIENT failures=", failures)
	get_tree().quit(1 if failures > 0 else 0)
