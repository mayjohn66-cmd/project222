extends Node
## 닉네임: 정리 규칙, 저장·불러오기, 새 게임 초기화 뒤에도 유지되는 입력 순서를 확인한다.
var checks := 0
var failures := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("FAIL: " + message)

func _ready() -> void:
	call_deferred("run")

func run() -> void:
	check(PlayerProgress.clean_player_name("  민수  ") == "민수", "공백 제거")
	check(PlayerProgress.clean_player_name("가나다라마바사아자차") == "가나다라마바사아", "최대 8자")
	check(PlayerProgress.clean_player_name("   ") == "", "공백만이면 빈 이름")
	PlayerProgress.reset()
	check(PlayerProgress.display_player_name() == "점장", "이름 없으면 기본 호칭")
	PlayerProgress.player_name = "민수"
	var saved := PlayerProgress.to_save_data()
	check(saved["player_name"] == "민수", "저장 데이터에 이름")
	PlayerProgress.reset()
	check(PlayerProgress.player_name == "", "reset 이 이름을 비움")
	PlayerProgress.load_save_data(saved)
	check(PlayerProgress.player_name == "민수" and PlayerProgress.display_player_name() == "민수", "불러오면 이름 복원")
	PlayerProgress.load_save_data({})
	check(PlayerProgress.player_name == "", "옛 저장(이름 없음)은 빈 이름")
	# 타이틀 화면: 이름 대화상자가 있고, 비어 있으면 시작 버튼이 막힌다
	var title = load("res://scenes/core/title/title_screen.tscn").instantiate()
	add_child(title)
	await get_tree().process_frame
	check(title.nickname_dialog != null and title.nickname_edit != null, "타이틀에 이름 대화상자")
	title._ask_nickname()
	await get_tree().process_frame
	check(title.nickname_dialog.visible and title.nickname_dialog.get_ok_button().disabled, "빈 이름이면 시작 버튼 비활성")
	title.nickname_edit.text = "  하나  "
	title._on_nickname_changed(title.nickname_edit.text)
	check(not title.nickname_dialog.get_ok_button().disabled, "이름을 쓰면 버튼 활성")
	print("CHECK_NICKNAME checks=%d failures=%d" % [checks, failures])
	get_tree().quit(1 if failures > 0 else 0)
