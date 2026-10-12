extends Node
## Silver 전환 후 실제 창·대사·날짜·금액 글씨가 영역을 벗어나지 않는지 검사한다.
var checks := 0
var failures := 0
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	run.call_deferred()
func frames(count: int = 12) -> void:
	for index in count: await get_tree().process_frame
func run() -> void:
	check(OS.get_user_data_dir().contains("foodbag_checks"), "isolated UI test saves")
	check(FileAccess.get_sha256("res://art/fonts/Silver.ttf") == "5bbbcd90b9f3ed71f8e15816fc114cbfefe9dfa29e5aacab31fe3f49fe1d1c89", "original Silver unchanged")
	check(UiTypography.FONT is FontVariation and UiTypography.FONT.base_font.get_font_name() == "Silver", "Silver metrics wrapper")
	check(UiTypography.FONT.get_height(UiTypography.DEFAULT_SIZE) < UiTypography.FONT.base_font.get_height(UiTypography.DEFAULT_SIZE), "excess line padding reduced")
	get_tree().current_scene = null
	get_tree().change_scene_to_file("res://scenes/core/title/title_screen.tscn")
	await frames()
	var title = get_tree().current_scene
	title.new_game_button.pressed.emit()
	await frames()
	check(title.nickname_dialog.visible, "name dialog opens")
	check(title.nickname_dialog.get_contents_minimum_size().y <= 600, "name dialog content fits")
	check(title.nickname_dialog.get_theme_stylebox("panel").bg_color.get_luminance() > 0.7, "readable name panel background")
	title.nickname_edit.text = "글씨점검"
	title.nickname_dialog.confirmed.emit()
	title.nickname_dialog.hide()
	await frames(60)
	var world = get_tree().current_scene
	var tutorial = world.get_node("TutorialDirector")
	tutorial.enabled = false
	tutorial.dialogue.close()
	var dialogue := StoryDialoguePanel.new()
	world.add_child(dialogue)
	await frames()
	var long_lines: Array[String] = ["타블렌의 부탁을 듣고 검과 갑옷을 장착한 뒤 출발 지점으로 가세요. 원정에서 얻은 재료는 가게로 가져와 진열할 수 있습니다. 돌아오면 타블렌에게 보고하고, 필요한 물품은 창고에서 꺼내 준비하세요."]
	var hud: Control = world.get_node("UI/HUD")
	var old_money: int = GameState.money
	for resolution in [Vector2i(1152,648), Vector2i(800,600)]:
		get_window().size = resolution
		await frames()
		dialogue.start("나", null, long_lines)
		if dialogue.typing_tween != null: dialogue.typing_tween.kill()
		dialogue.text_label.visible_ratio = 1.0
		await frames()
		check(dialogue.text_label.get_line_count() >= 2, "long dialogue wraps")
		check(dialogue.text_label.get_combined_minimum_size().y <= dialogue.text_label.size.y + 0.5, "dialogue lines fit")
		check(dialogue.root.get_child(0).get_global_rect().encloses(dialogue.text_label.get_global_rect()), "dialogue inside panel")
		check(dialogue.root.get_child(0).get_global_rect().encloses(dialogue.hint_label.get_global_rect()), "continue hint inside panel")
		dialogue.close()
		for value in [0,999999999,999999999999]:
			GameState.money = value
			hud._update_money_digits()
			await frames()
			for card in hud.money_digits.get_children():
				check(hud.get_node("MoneyPaper").get_global_rect().encloses(card.get_global_rect()), "money card stays inside frame")
				check(hud.get_node("MoneyPaper").get_global_rect().encloses(card.get_child(1).get_global_rect()), "money label stays inside frame")
		for pair in [["DatePaper","DayLabel"],["TimePaper","TimeLabel"]]:
			check(hud.get_node(pair[0]).get_global_rect().encloses(hud.get_node(pair[1]).get_global_rect()), "clock text fits " + pair[1])
	GameState.money = old_money
	print("SILVER_UI_TYPOGRAPHY checks=%d failures=%d" % [checks,failures])
	get_tree().quit(1 if failures else 0)
