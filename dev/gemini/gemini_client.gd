extends Node
## Google AI Studio(Gemini API) 호출 클라이언트. 개발 도구용이며 게임 본편에서는 쓰지 않는다.
##
## API 키는 아래 순서로 찾는다(앞에서 찾으면 멈춘다). 키를 코드·씬·`project.godot`에 쓰지 않는다.
##   1. 환경 변수 GEMINI_API_KEY
##   2. 프로젝트 설정 `gemini/api_key` — 저장소에 올라가는 `project.godot`이 아니라,
##      올리지 않는 `override.cfg`(프로젝트 폴더, .gitignore 등록)에 적었을 때만 쓴다.
##   3. 사용자 폴더 파일 `user://gemini.cfg` 의 [gemini] api_key (저장소 밖)
## 모델은 환경 변수 GEMINI_MODEL, 없으면 DEFAULT_MODEL.
##
## 사용 예:
##   var client := GeminiClient.new()
##   add_child(client)
##   var result: Dictionary = await client.generate("프롬프트", "시스템 지침")
##   if result.ok: print(result.text) else: push_error(result.error)

const ENDPOINT: String = "https://generativelanguage.googleapis.com/v1beta/models/%s:generateContent"
# 2026-10-01 웹 검색 확인: 2.5 계열은 9/18부터 기존 사용자만 접근 가능, 새 프로젝트에는 3.8 Flash(또는 3.5 Flash-Lite) 권장.
# 모델 이름은 자주 바뀌므로 AI Studio에서 확인하고 GEMINI_MODEL 환경 변수로 바꾼다.
const DEFAULT_MODEL: String = "gemini-3.8-flash"
const ENV_KEY: String = "GEMINI_API_KEY"
const ENV_MODEL: String = "GEMINI_MODEL"
const SETTING_KEY: String = "gemini/api_key"
const USER_CONFIG: String = "user://gemini.cfg"
const TIMEOUT_SEC: float = 60.0

# 일시적 서버 오류(붐빔 503, 내부 오류 500, 한도 429)는 기다렸다가 다시 시도한다.
const MAX_ATTEMPTS: int = 6
const RETRY_BASE_SEC: float = 6.0     # 대기 = 6, 12, 24, 48, 96초(최대 약 3분)
const RETRYABLE_CODES: Array[int] = [429, 500, 502, 503, 504]
# 모든 시도가 실패하면 이 모델로 한 번 더 시도한다(비워 두면 사용 안 함). 예: setx GEMINI_FALLBACK_MODEL "모델이름"
const ENV_FALLBACK_MODEL: String = "GEMINI_FALLBACK_MODEL"


# 키를 찾는다. 없으면 빈 문자열. 반환값을 화면·로그에 출력하지 않는다.
static func find_api_key() -> String:
	var from_env: String = OS.get_environment(ENV_KEY).strip_edges()

	if not from_env.is_empty():
		return from_env

	if ProjectSettings.has_setting(SETTING_KEY):
		var from_setting: String = str(ProjectSettings.get_setting(SETTING_KEY)).strip_edges()

		if not from_setting.is_empty():
			return from_setting

	var config := ConfigFile.new()

	if config.load(USER_CONFIG) == OK:
		return str(config.get_value("gemini", "api_key", "")).strip_edges()

	return ""


static func find_model() -> String:
	var model: String = OS.get_environment(ENV_MODEL).strip_edges()
	return model if not model.is_empty() else DEFAULT_MODEL


# 요청 본문(JSON 문자열)을 만든다. 시험할 수 있게 정적 함수로 분리.
static func build_request_body(
	prompt: String,
	system_instruction: String = "",
	temperature: float = 0.8,
	json_output: bool = false
) -> String:
	var body: Dictionary = {
		"contents": [{"role": "user", "parts": [{"text": prompt}]}],
		"generationConfig": {"temperature": temperature},
	}

	if not system_instruction.is_empty():
		body["systemInstruction"] = {"parts": [{"text": system_instruction}]}

	if json_output:
		body["generationConfig"]["responseMimeType"] = "application/json"

	return JSON.stringify(body)


# 응답 본문을 해석한다. 반환: {ok, text, error, finish_reason}
static func parse_response(http_code: int, body_text: String) -> Dictionary:
	var json := JSON.new()

	if json.parse(body_text) != OK or typeof(json.data) != TYPE_DICTIONARY:
		return _fail("응답을 JSON으로 읽을 수 없음(HTTP %d)" % http_code)

	var data: Dictionary = json.data

	if http_code != 200:
		var message: String = "HTTP %d" % http_code

		if data.has("error") and typeof(data["error"]) == TYPE_DICTIONARY:
			message += ": " + str(data["error"].get("message", ""))

		return _fail(message, http_code)

	var feedback: Dictionary = data.get("promptFeedback", {})

	if feedback.has("blockReason"):
		return _fail("요청이 차단됨: " + str(feedback["blockReason"]))

	var candidates: Array = data.get("candidates", [])

	if candidates.is_empty():
		return _fail("응답에 candidates가 없음")

	var candidate: Dictionary = candidates[0]
	var finish: String = str(candidate.get("finishReason", ""))
	var parts: Array = candidate.get("content", {}).get("parts", [])
	var text: String = ""

	for part in parts:
		if typeof(part) == TYPE_DICTIONARY and part.has("text"):
			text += str(part["text"])

	if text.is_empty():
		return _fail("응답 글이 비어 있음(finishReason: %s)" % finish)

	return {"ok": true, "text": text, "error": "", "finish_reason": finish, "http_code": 200}


static func _fail(message: String, http_code: int = 0) -> Dictionary:
	return {"ok": false, "text": "", "error": message, "finish_reason": "", "http_code": http_code}


static func is_retryable(http_code: int) -> bool:
	return RETRYABLE_CODES.has(http_code)


# attempt = 1부터. 1회 실패 뒤 6초, 그다음 12, 24, 48, 96초.
static func retry_delay_sec(attempt: int) -> float:
	return RETRY_BASE_SEC * pow(2.0, float(maxi(attempt - 1, 0)))


static func find_fallback_model() -> String:
	return OS.get_environment(ENV_FALLBACK_MODEL).strip_edges()


# Gemini 호출. await 로 기다린다. 일시적 오류(503 등)는 자동으로 기다렸다가 다시 시도한다.
# 키는 요청 헤더로만 보내고(주소에 붙이지 않음) 로그에 남기지 않는다.
func generate(
	prompt: String,
	system_instruction: String = "",
	temperature: float = 0.8,
	json_output: bool = false
) -> Dictionary:
	var model: String = find_model()
	var result: Dictionary = await _generate_with_retry(model, prompt, system_instruction, temperature, json_output)
	var fallback: String = find_fallback_model()

	if (
		not bool(result["ok"])
		and is_retryable(int(result.get("http_code", 0)))
		and not fallback.is_empty()
		and fallback != model
	):
		print("[제미나이] %s 가 계속 실패해 예비 모델 %s 로 시도합니다." % [model, fallback])
		result = await _generate_with_retry(fallback, prompt, system_instruction, temperature, json_output)

	return result


# 시험용: 재시도 대기 시간 배율(1.0 = 실제 시간).
var retry_wait_scale: float = 1.0


func _generate_with_retry(
	model: String,
	prompt: String,
	system_instruction: String,
	temperature: float,
	json_output: bool
) -> Dictionary:
	var result: Dictionary = {}

	for attempt in range(1, MAX_ATTEMPTS + 1):
		result = await _request_once(model, prompt, system_instruction, temperature, json_output)

		if bool(result["ok"]) or not is_retryable(int(result.get("http_code", 0))):
			return result

		if attempt < MAX_ATTEMPTS:
			var wait: float = retry_delay_sec(attempt) * retry_wait_scale
			print("[제미나이] %s (시도 %d/%d). %.0f초 뒤 다시 시도합니다." % [result["error"], attempt, MAX_ATTEMPTS, wait])
			await get_tree().create_timer(wait).timeout

	return result


func _request_once(
	model: String,
	prompt: String,
	system_instruction: String,
	temperature: float,
	json_output: bool
) -> Dictionary:
	var key: String = find_api_key()

	if key.is_empty():
		return _fail(
			"API 키가 없습니다. 환경 변수 %s 를 설정하세요(키를 파일·채팅에 붙이지 마세요)." % ENV_KEY
		)

	var request := HTTPRequest.new()
	request.timeout = TIMEOUT_SEC
	add_child(request)

	var headers: PackedStringArray = [
		"Content-Type: application/json",
		"x-goog-api-key: " + key,
	]
	var error: int = request.request(
		ENDPOINT % model,
		headers,
		HTTPClient.METHOD_POST,
		build_request_body(prompt, system_instruction, temperature, json_output)
	)

	if error != OK:
		request.queue_free()
		return _fail("요청을 보내지 못함(코드 %d)" % error)

	var response: Array = await request.request_completed
	request.queue_free()

	var result_code: int = int(response[0])
	var http_code: int = int(response[1])
	var body_text: String = (response[3] as PackedByteArray).get_string_from_utf8()

	if result_code != HTTPRequest.RESULT_SUCCESS:
		return _fail("네트워크 오류(코드 %d). 연결과 방화벽을 확인하세요." % result_code)

	return parse_response(http_code, body_text)
