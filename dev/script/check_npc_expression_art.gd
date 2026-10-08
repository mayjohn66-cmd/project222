extends Node
## NPC 표정 그림: art/npc/expr 에 들어온 파일이 160x192 로 읽히고, 대화창이 그 표정을 쓴다.
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
	GameState.initialize_new_game()
	var world = load("res://scenes/shop/main.tscn").instantiate()
	add_child(world)
	for i in range(4): await get_tree().process_frame
	var dlg = null
	for n in world.find_children("*", "", true, false):
		if n.get_script() != null and str(n.get_script().resource_path).ends_with("story_dialogue_panel.gd"):
			dlg = n
			break
	check(dlg != null, "대화창을 찾았다")
	var base: Texture2D = NpcPortraits.find("타블렌")
	var roster := {"타블렌": "naru", "코르빈": "doyun", "이세르": "sora", "오렐": "neighbor_bread", "피니아": "child_berries", "라슈": "traveler_water", "엘미": "gatherer_herbs", "바르크": "miner_ore", "세이나": "healer_moss", "델빈": "delvin"}
	for who in roster:
		check(NpcPortraits.npc_id_of(who) == roster[who], "%s → %s" % [who, roster[who]])
		var base_who: Texture2D = NpcPortraits.find(who)
		for e in ["smile", "surprised", "worried", "flustered"]:
			var tex: Texture2D = NpcPortraits.find_expression(who, e)
			check(tex != null and tex.get_size() == Vector2(160, 192), "%s %s 160x192" % [who, e])
			check(tex != base_who, "%s %s 는 기본 초상화와 다른 그림" % [who, e])
	check(NpcPortraits.find_expression("타블렌", "tired") == null, "그림이 없는 표정(tired)은 null → 기본 초상화")
	if dlg != null:
		var lines: Array[String] = ["{놀람}앗!", "그냥 말", "{피곤}휴우."]
		dlg.start("행상인 타블렌", null, lines)
		check(dlg.portrait.texture == NpcPortraits.find_expression("타블렌", "surprised"), "{놀람} 줄은 놀람 그림")
		dlg.text_label.visible_ratio = 1.0
		dlg._advance()
		check(dlg.portrait.texture == base, "표시 없는 줄은 기본 초상화")
		dlg.text_label.visible_ratio = 1.0
		dlg._advance()
		check(dlg.portrait.texture == base, "그림이 없는 표정은 기본 초상화로")
		dlg.close()
	print("checks=%d failures=%d" % [checks, failures])
	get_tree().quit(1 if failures > 0 else 0)
