extends Node
## 긴 글 Label 하나를 만들 때 비용이 설정(줄바꿈·크기 옵션)에 따라 얼마나 다른지 잰다(개발용, 화면 불필요).
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("run")

func ms(t0: int) -> float:
	return (Time.get_ticks_usec() - t0) / 1000.0

func run() -> void:
	GameState.initialize_new_game()
	var world = load("res://scenes/shop/main.tscn").instantiate()
	world.get_node("TutorialDirector").enabled = false
	add_child(world)
	for i in range(40): await get_tree().process_frame
	var menu: ManagementMenu = world.get_node("UI/ManagementMenu")
	menu.open_menu(ManagementMenu.MenuTab.HISTORY)
	await get_tree().process_frame
	menu._show_store_decoration_info()
	var text := ""
	for c in menu.history_list.get_children():
		if c is Label: text = (c as Label).text
	print("글 길이 %d자, %d줄" % [text.length(), text.count("\n") + 1])
	var host: Container = menu.history_list
	var variants := {
		"A 지금 방식(autowrap WORD_SMART + 가로 채움 + 20pt)": func(l: Label): l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; l.size_flags_horizontal = Control.SIZE_EXPAND_FILL,
		"B 줄바꿈 끔": func(l: Label): l.autowrap_mode = TextServer.AUTOWRAP_OFF,
		"C autowrap + 최소 폭 고정(480)": func(l: Label): l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; l.custom_minimum_size.x = 480,
		"D autowrap ARBITRARY": func(l: Label): l.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY; l.size_flags_horizontal = Control.SIZE_EXPAND_FILL,
	}
	for name in variants:
		var total := 0.0
		for i in range(6):
			var t := Time.get_ticks_usec()
			var l := Label.new()
			l.text = text
			l.add_theme_font_size_override("font_size", 20)
			variants[name].call(l)
			host.add_child(l)
			await get_tree().process_frame
			l.get_minimum_size()
			total += ms(t)
			host.remove_child(l)
			l.queue_free()
		print("  %-52s 평균 %.1fms" % [name, total / 6.0])
	# 줄을 나눠 Label 여러 개로(각각 한두 줄)
	var lines := text.split("\n")
	var total2 := 0.0
	for i in range(6):
		var t := Time.get_ticks_usec()
		var made: Array = []
		for ln in lines:
			var l := Label.new()
			l.text = ln
			l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			l.add_theme_font_size_override("font_size", 20)
			host.add_child(l)
			made.append(l)
		await get_tree().process_frame
		total2 += ms(t)
		for l in made:
			host.remove_child(l)
			l.queue_free()
	print("  %-52s 평균 %.1fms" % ["E 줄마다 Label(%d개, autowrap)" % lines.size(), total2 / 6.0])
	menu.close_menu()
	get_tree().quit()
