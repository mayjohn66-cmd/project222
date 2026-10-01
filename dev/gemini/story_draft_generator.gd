extends Node
## 스토리 초안 생성 파이프라인(개발 도구). 주제를 받아 제미나이에게 장면 CSV 행을 쓰게 하고
## `docs/drafts/story/story_beats_gemini_<시각>.csv`로 저장한다. data/ 는 건드리지 않는다.
##
## 실행(프로젝트 폴더에서, 환경 변수 GEMINI_API_KEY 설정 후):
##   godot --headless --path . res://dev/gemini/story_draft.tscn -- --topic "첫 원정을 앞둔 날 이웃의 응원"
## 저장 뒤 반드시: python tools/validate_story.py . <저장된 파일>
## 형식과 규칙의 근거: docs/스토리_작성_가이드.md

const OUT_DIR: String = "res://docs/drafts/story"
const HEADER: String = "beat_id,npc_id,conditions,gifts,repeat_days,lines"

const SYSTEM_PROMPT: String = """너는 편의점 경영 + 판타지 원정 게임의 스토리 작가다. 규칙에 맞는 장면 CSV 행만 출력한다(설명·머리말·코드블록 표시 없음).
- 열: beat_id,npc_id,conditions,gifts,repeat_days,lines (쉼표 구분. 칸 안에 쉼표가 있으면 그 칸 전체를 큰따옴표로 감싼다)
- npc_id는 neighbor 만 사용한다.
- conditions는 ;로 이어 쓰고 다음만 사용한다: day>=N, expedition_done, money<N, item_below:아이템아이디:N, furniture_missing:가구아이디, product_stock_empty
- gifts는 종류:아이디:수량을 ;로 이어 쓴다. 종류는 item, furniture, money. 아이디는 아래 목록에 있는 것만 쓴다. 없으면 빈 칸.
- repeat_days는 숫자(0 = 한 번만).
- lines는 | 로 나누고 한 칸 40자 이내, 6칸 이하. 따뜻하고 짧은 이웃 말투.
- 게임 수치(골드, 확률, 공격력)를 대사에 쓰지 않는다. 포션은 원정에서 쓰지 않는다. 세계관·지역 이름을 새로 만들지 않는다.
- 장면 하나당 한 줄. beat_id는 소문자·숫자·밑줄만, 서로 달라야 한다."""


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var topic: String = _get_arg("--topic")
	var count: String = _get_arg("--count")

	if topic.is_empty():
		push_error("주제가 없습니다. 예: -- --topic \"첫 원정을 앞둔 날 이웃의 응원\" [--count 3]")
		get_tree().quit(2)
		return

	var scene_count: int = int(count) if not count.is_empty() else 3
	var prompt: String = _build_prompt(topic, scene_count)

	var client := GeminiClient.new()
	add_child(client)
	print("[스토리] 제미나이 호출 중 / 모델: ", GeminiClient.find_model())
	var result: Dictionary = await client.generate(prompt, SYSTEM_PROMPT)

	if not bool(result["ok"]):
		push_error("[스토리] 실패: " + str(result["error"]))
		get_tree().quit(1)
		return

	var csv_text: String = clean_csv(str(result["text"]))
	var path: String = _save(csv_text)
	print("[스토리] 저장: ", path)
	print("[스토리] 다음 단계: python tools/validate_story.py . ", path.replace("res://", ""))
	get_tree().quit(0)


func _build_prompt(topic: String, scene_count: int) -> String:
	return "장면 주제: %s\n장면 수: %d\n쓸 수 있는 아이템 아이디: %s\n쓸 수 있는 가구 아이디: %s\n" % [
		topic,
		scene_count,
		", ".join(_sellable_item_ids()),
		", ".join(_furniture_ids()),
	]


func _sellable_item_ids() -> Array[String]:
	var result: Array[String] = []

	for item_id in ItemData.items.keys():
		result.append(str(item_id))

	return result


func _furniture_ids() -> Array[String]:
	var result: Array[String] = []

	for data in FurnitureData.get_all_furniture():
		result.append(str(data["id"]))

	return result


# 코드블록 표시와 머리말(헤더 줄)을 정리해 "머리글 + 행"만 남긴다.
static func clean_csv(text: String) -> String:
	var lines: PackedStringArray = []

	for raw_line in text.split("\n"):
		var line: String = raw_line.strip_edges()

		if line.is_empty() or line.begins_with("```"):
			continue

		if line.begins_with("beat_id,"):
			continue

		lines.append(line)

	return HEADER + "\n" + "\n".join(lines) + "\n"


func _save(csv_text: String) -> String:
	var stamp: String = Time.get_datetime_string_from_system().replace(":", "").replace("-", "").replace("T", "_")
	var path: String = "%s/story_beats_gemini_%s.csv" % [OUT_DIR, stamp]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var file := FileAccess.open(path, FileAccess.WRITE)

	if file == null:
		push_error("저장 실패: " + path)
		get_tree().quit(1)
		return path

	file.store_string(csv_text)
	file.close()
	return path


func _get_arg(name: String) -> String:
	var args: PackedStringArray = OS.get_cmdline_user_args()

	for i in args.size():
		if args[i] == name and i + 1 < args.size():
			return args[i + 1]

	return ""
