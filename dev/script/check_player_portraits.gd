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
	# 대사 표시(서술 *, 표정 {이름})
	var m: Dictionary = DialogueMarks.parse("*{피곤}눈꺼풀이 무겁다.")
	check(m["narration"] and m["expression"] == "tired" and m["text"] == "눈꺼풀이 무겁다.", "서술+표정 표시를 함께 읽는다")
	m = DialogueMarks.parse("{surprised}{놀람}아야!")
	check(not m["narration"] and m["expression"] == "surprised" and m["text"] == "아야!", "영문 id·겹친 표시")
	m = DialogueMarks.parse("{item} 챙겼어.")
	check(m["expression"] == "" and m["text"] == "{item} 챙겼어.", "자리표시자 {item}은 글에 그대로 남는다")
	m = DialogueMarks.parse("그냥 대사")
	check(m["expression"] == "" and m["text"] == "그냥 대사" and not m["narration"], "표시 없는 줄은 그대로")
	check(DialogueMarks.resolve("없는표정") == "", "모르는 표정은 빈 값")
	if dlg != null:
		PlayerProgress.player_gender = "male"
		var tagged: Array[String] = ["{놀람}앗!", "그냥 말", "*{피곤}한숨."]
		dlg.start("나", null, tagged)
		check(dlg.portrait.texture == PlayerPortraits.find_for("male", "surprised") and dlg.text_label.text == "앗!", "첫 줄은 놀람 표정·표시는 글에서 빠진다")
		dlg.text_label.visible_ratio = 1.0
		dlg._advance()
		check(dlg.portrait.texture == PlayerPortraits.find_for("male", "neutral"), "표시 없는 줄은 기본 표정으로 돌아간다")
		dlg.text_label.visible_ratio = 1.0
		dlg._advance()
		check(dlg.portrait.texture == PlayerPortraits.find_for("male", "tired") and dlg.text_label.text == "(한숨.)", "서술 줄도 표정이 붙는다")
		dlg.start("타블렌", null, tagged)
		check(dlg.portrait.texture != PlayerPortraits.find_for("male", "surprised"), "NPC 줄은 주인공 표정을 쓰지 않는다")
		# NPC 표정: 그림 파일이 없으면 기본 초상화를 쓴다(그림이 오면 art/npc/expr/<npc_id>_<표정>.png)
		check(NpcPortraits.npc_id_of("행상인 타블렌") == "naru" and NpcPortraits.npc_id_of("낯선 사람") == "", "화자 이름 → npc_id")
		var base_naru: Texture2D = NpcPortraits.find("타블렌")
		var expr_lines: Array[String] = ["{놀람}앗!", "그냥 말"]
		dlg.start("타블렌", null, expr_lines)
		var has_file: bool = NpcPortraits.find_expression("타블렌", "surprised") != null
		check(dlg.portrait.texture == (NpcPortraits.find_expression("타블렌", "surprised") if has_file else base_naru), "NPC 표정 파일이 없으면 기본 초상화")
		check(NpcPortraits.find_expression("타블렌", "neutral") == null and NpcPortraits.find_expression("타블렌", "") == null, "기본 표정은 별도 파일을 찾지 않는다")
		dlg.close()
	# 데이터에 쓴 모든 표시는 유효한 표정이어야 한다
	var csv := FileAccess.open("res://data/shop/requests/requests_text.csv", FileAccess.READ)
	var bad := 0
	var tagged_count := 0
	csv.get_csv_line()
	while not csv.eof_reached():
		var row := csv.get_csv_line()
		if row.size() < 6: continue
		for cell in [row[4], row[5]]:
			for l in str(cell).split("|", false):
				var t := l.strip_edges().trim_prefix("*")
				if t.begins_with("{"):
					var inner := t.substr(1, maxi(t.find("}") - 1, 0))
					if str(DialogueMarks.parse(l)["expression"]).is_empty():
						# {item} 같은 영문 자리표시자는 표시가 아니다. 한글 이름인데 모르면 오타다.
						if inner.to_ascii_buffer().size() != inner.to_utf8_buffer().size(): bad += 1; push_error("알 수 없는 표정: " + l)
					else:
						tagged_count += 1
	check(bad == 0 and tagged_count > 20, "대사 데이터의 표정 표시 %d개가 모두 유효" % tagged_count)
	print("checks=%d failures=%d" % [checks, failures])
	get_tree().quit(1 if failures > 0 else 0)
