extends Node

var failures := 0
var clicked := false

func check(condition: bool, message: String) -> void:
	if condition: return
	failures += 1
	push_error(message)

func settle() -> void:
	for i in range(6): await get_tree().process_frame

func _ready() -> void:
	var expedition = load("res://scenes/expedition/expedition.tscn").instantiate()
	add_child(expedition)
	await settle()
	var panel: PanelContainer = expedition.result_panel
	var button: Button = expedition.result_confirm_button
	var scroll: ScrollContainer = panel.get_node("VBoxContainer/ResultScroll")
	button.pressed.disconnect(expedition.confirm_result_phase)
	button.pressed.connect(func(): clicked = true)
	var contents := "지역의 보스를 처치했습니다!\n\n[자동 보관할 아이템]\n"
	for i in range(50): contents += "숲에서 모은 재료 %d ×13\n" % i
	contents += "\n[가방에 유지할 아이템]\n낡은 검 ×1\n빵 굽기 레시피 ×1\n확인하면 자동 보관됩니다."
	expedition.result_info_label.text = contents
	expedition.set_expedition_phase(expedition.ExpeditionPhase.RESULT)
	for dimensions in [Vector2i(1152,648), Vector2i(593,523), Vector2i(800,450)]:
		get_window().size = dimensions
		await settle()
		var viewport := get_viewport().get_visible_rect()
		check(viewport.encloses(panel.get_global_rect()), "결과창이 화면을 벗어남: " + str(dimensions))
		check(panel.get_global_rect().encloses(button.get_global_rect()), "복귀 버튼이 창 밖으로 밀려남")
		check(not scroll.get_global_rect().intersects(button.get_global_rect()), "내용이 복귀 버튼과 겹침")
		check(scroll.get_v_scroll_bar().max_value > scroll.size.y, "긴 내용 스크롤 없음")
		scroll.scroll_vertical = 100000
		await settle()
		check(scroll.scroll_vertical > 0, "마지막 보상까지 스크롤 불가")
		clicked = false
		for down in [true, false]:
			var event := InputEventMouseButton.new()
			event.position = button.get_global_rect().get_center()
			event.button_index = MOUSE_BUTTON_LEFT
			event.pressed = down
			get_viewport().push_input(event, true)
		await settle()
		check(clicked, "실제 마우스 입력으로 복귀 버튼 클릭 불가")
		panel.hide()
		panel.show()
		await settle()
		check(scroll.scroll_vertical == 0, "다시 열 때 스크롤 초기화 실패")
		var args := OS.get_cmdline_user_args()
		if not args.is_empty() and dimensions == Vector2i(593,523):
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(args[0])
	expedition.result_info_label.text = "원정에서 철수했습니다.\n획득한 물품 없음"
	await settle()
	check(panel.get_global_rect().encloses(button.get_global_rect()), "짧은 결과 버튼 배치 실패")
	print("RESULT_LAYOUT_CHECK failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)
