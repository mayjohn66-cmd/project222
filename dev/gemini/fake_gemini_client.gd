extends "res://dev/gemini/gemini_client.gd"
## 시험용 가짜 제미나이: 네트워크·키 없이, 프롬프트에 든 id마다 규칙에 맞는 임시 글을 돌려준다.
## 환경 변수 STORY_FAKE_GEMINI=1 이면 부탁 글 도구가 진짜 대신 이것을 쓴다(자동 순환 시험용).


func generate(
	prompt: String,
	_system_instruction: String = "",
	_temperature: float = 0.8,
	_json_output: bool = false
) -> Dictionary:
	var kind: String = ""
	var rows: PackedStringArray = []

	for line in prompt.split("\n"):
		if line.begins_with("kind = "):
			kind = line.substr(7).split(" ")[0]
		elif line.begins_with("id="):
			var id: String = line.substr(3).split(" ")[0]

			match kind:
				"resident_request":
					rows.append("%s,%s,임시 부탁 제목,,\"도와줄 수 있을까?|준비되면 다시 말해 줘.\",고마워 덕분이야." % [id, kind])
				"community_request":
					rows.append("%s,%s,임시 게시판 제목,임시 요약 문장입니다.,,임시 완료 문장입니다." % [id, kind])
				"resident_greeting":
					rows.append("%s,%s,,,\"아침 인사를 나눴습니다.|안부를 나눴습니다.\"," % [id, kind])

	return {"ok": true, "text": "\n".join(rows), "error": "", "finish_reason": "STOP", "http_code": 200}
