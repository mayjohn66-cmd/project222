extends Node
## 주인공 초상화 연동: 14장이 모두 읽히고, 성별이 저장·불러오기를 거치며, 대화창이 성별에 맞는 초상화를 쓴다.
var checks := 0
var failures := 0
func check(ok: bool, text: String) -> void:
	checks += 1
	if ok: print("PASS: ", text)
	else:
		failures += 1
		push_error(text)
func _ready() -> void: call_deferred("run")
func run() -> void:
	var expressions := ["neutral", "smile", "flustered", "surprised", "worried", "tired", "determined"]
	for gender in PlayerProgress.GENDERS:
		for e in expressions:
			var tex: Texture2D = PlayerPortraits.find_for(gender, e)
			check(tex != null and tex.get_size() == Vector2(160, 192), "%s %s 초상화 160x192" % [gender, e])
	check(PlayerPortraits.find_for("male", "none") == PlayerPortraits.find_for("male", "neutral"), "없는 표정은 기본 표정으로")
	check(PlayerPortraits.find_for("alien") == null, "없는 성별은 null")
	GameState.initialize_new_game()
	check(PlayerProgress.player_gender == "male", "새 게임 기본은 남성")
	PlayerProgress.player_gender = "female"
	var data := PlayerProgress.to_save_data()
	PlayerProgress.reset()
	check(PlayerProgress.player_gender == "male", "초기화하면 기본값")
	PlayerProgress.load_save_data(data)
	check(PlayerProgress.player_gender == "female", "저장·불러오기 후 여성 유지")
	PlayerProgress.load_save_data({"player_gender": "x"})
	check(PlayerProgress.player_gender == "male", "잘못된 값은 기본값")
	PlayerProgress.load_save_data({})
	check(PlayerProgress.player_gender == "male", "옛 저장(성별 없음)은 남성")
	var panel = load("res://scenes/shop/main.tscn").instantiate()
	add_child(panel)
	for i in range(4): await get_tree().process_frame
	var dlg = panel.find_child("StoryDialoguePanel", true, false)
	if dlg == null:
		for n in panel.find_children("*", "", true, false):
			if n.get_script() != null and str(n.get_script().resource_path).ends_with("story_dialogue_panel.gd"):
				dlg = n
				break
	check(dlg != null, "대화창을 찾았다")
	if dlg != null:
		PlayerProgress.player_gender = "female"
		var lines: Array[String] = ["안녕."]
		dlg.start("나", null, lines)
		check(dlg.portrait.visible and dlg.portrait.texture == PlayerPortraits.find_for("female"), "플레이어 대사는 여성 초상화")
		dlg.start("타블렌", null, lines)
		check(dlg.portrait.texture != PlayerPortraits.find_for("female"), "NPC 대사는 NPC 초상화")
	print("checks=%d failures=%d" % [checks, failures])
	get_tree().quit(1 if failures > 0 else 0)
