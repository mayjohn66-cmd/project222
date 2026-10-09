extends Node
## 게임을 켜는 데 걸리는 시간과 관리 책을 열고 탭을 넘길 때 걸리는 시간을 잰다(개발용, 화면 불필요, GDScript·노드 생성 비용만).
## 사용: godot --headless --path . res://dev/spike3d/load_profile.tscn
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("run")

func ms(t0: int) -> float:
	return (Time.get_ticks_usec() - t0) / 1000.0

func run() -> void:
	var t := Time.get_ticks_usec()
	GameState.initialize_new_game()
	print("새 게임 초기화: %.0fms" % ms(t))
	t = Time.get_ticks_usec()
	var packed: PackedScene = load("res://scenes/shop/main.tscn")
	print("main.tscn 읽기: %.0fms" % ms(t))
	t = Time.get_ticks_usec()
	var world = packed.instantiate()
	print("인스턴스 만들기: %.0fms" % ms(t))
	world.get_node("TutorialDirector").enabled = false
	t = Time.get_ticks_usec()
	add_child(world)
	await get_tree().process_frame
	print("트리에 넣고 첫 프레임: %.0fms" % ms(t))
	t = Time.get_ticks_usec()
	for i in range(30): await get_tree().process_frame
	print("이후 30프레임 합계: %.0fms" % ms(t))
	print("노드 %d개 · 오브젝트 %d개 · 정적 메모리 %.1fMB" % [int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)), int(Performance.get_monitor(Performance.OBJECT_COUNT)), Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0])
	var menu: ManagementMenu = world.get_node("UI/ManagementMenu")
	t = Time.get_ticks_usec()
	menu.open_menu(ManagementMenu.MenuTab.INVENTORY)
	await get_tree().process_frame
	print("관리 책 열기(인벤토리): %.0fms" % ms(t))
	for name in ["PRODUCTION", "EMPLOYEE", "BLUEPRINT", "CONSTRUCTION", "SCHEDULE", "HISTORY", "INVENTORY"]:
		if not ManagementMenu.MenuTab.has(name): continue
		var best := 1e9
		var total := 0.0
		for i in range(5):
			t = Time.get_ticks_usec()
			menu.select_tab(ManagementMenu.MenuTab[name])
			var d := ms(t)
			total += d
			best = minf(best, d)
			await get_tree().process_frame
		print("  탭 %-12s 평균 %.1fms · 최소 %.1fms" % [name, total / 5.0, best])
	t = Time.get_ticks_usec()
	for i in range(20):
		menu.refresh_schedule()
	print("일정 탭 새로고침 20회: 평균 %.2fms" % (ms(t) / 20.0))
	# 탭 전환 비용을 나눠 본다: 내용 새로고침 / 책 배치(PRESENTATION.apply_tab)
	var parts := {
		"기록 새로고침(refresh_shop_history)": func(): menu.refresh_shop_history(),
		"일정 새로고침(refresh_schedule)": func(): menu.refresh_schedule(),
		"설계도 새로고침(blueprint.refresh_view)": func(): menu.blueprint_content.refresh_view(),
		"생산 새로고침(production.refresh_view)": func(): menu.management_production.refresh_view(),
		"인벤토리 새로고침(refresh_inventory)": func(): menu.management_inventory.refresh_inventory(),
		"책 배치(PRESENTATION.apply_tab)": func(): menu.PRESENTATION.apply_tab(menu),
	}
	for name in parts:
		var total := 0.0
		for i in range(5):
			t = Time.get_ticks_usec()
			parts[name].call()
			total += ms(t)
			await get_tree().process_frame
		print("  %-44s 평균 %.1fms" % [name, total / 5.0])
	var inner := {
		"  ActFourBookView.refresh_button": func(): ActFourBookView.refresh_button(menu),
		"  refresh_common_info": func(): menu.refresh_common_info(),
		"  _show_basic_store_info": func(): menu._show_basic_store_info(),
		"  _show_detailed_store_info": func(): menu._show_detailed_store_info(),
		"  _show_sales_trend": func(): menu._show_sales_trend(),
		"  _refresh_daily_history_list": func(): menu._refresh_daily_history_list(),
	}
	for name in inner:
		for child in menu.history_list.get_children():
			menu.history_list.remove_child(child)
			child.queue_free()
		var total := 0.0
		for i in range(3):
			t = Time.get_ticks_usec()
			inner[name].call()
			total += ms(t)
			for child in menu.history_list.get_children():
				menu.history_list.remove_child(child)
				child.queue_free()
			await get_tree().process_frame
		print("   %-40s 평균 %.1fms" % [name, total / 3.0])
	var player_node = world.get_node("Actors/Player")
	var probes := {
		"  _show_store_decoration_info": func(): menu._show_store_decoration_info(),
		"  ResidentRequestFlow.reputation()": func(): ResidentRequestFlow.reputation(),
		"  DecorationEffectService.visit_bonus": func(): DecorationEffectService.get_reputation_visit_bonus(3.0),
		"  player.get_daily_shop_stats()": func(): player_node.call("get_daily_shop_stats"),
		"  CalendarData.get_display_date": func(): CalendarData.get_display_date(GameState.total_day),
		"  _add_store_info_text(Label 만들기)": func(): menu._add_store_info_text("x\ny\nz"),
	}
	for name in probes:
		var total := 0.0
		for i in range(10):
			t = Time.get_ticks_usec()
			probes[name].call()
			total += ms(t)
		for child in menu.history_list.get_children():
			menu.history_list.remove_child(child)
			child.queue_free()
		print("    %-44s 평균 %.2fms" % [name, total / 10.0])
	menu.close_menu()
	get_tree().quit()
