extends Node
## 실제 클릭으로 진열대/팝업을 조작하고 배경 HUD·입력의 복귀를 확인한다.
var checks := 0
var failures := 0
var world: Node
var panel: Control

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func frames(count := 8) -> void:
	for i in range(count): await get_tree().process_frame

func click_at(point: Vector2) -> void:
	for down in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = down
		get_viewport().push_input(event, true)
	await frames()

func click(button: Button) -> void:
	await click_at(button.get_global_rect().get_center())

func key_action(action: String) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	get_viewport().push_input(event, true)
	await frames()

func snapshot(label: String) -> void:
	if DisplayServer.get_name() == "headless": return
	for arg in OS.get_cmdline_user_args():
		if not arg.begins_with("--shelf-capture="): continue
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(arg.trim_prefix("--shelf-capture=") + "-" + label + ".png")

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	run.call_deferred()

func run() -> void:
	check(OS.get_user_data_dir().contains("foodbag_checks"), "isolated test saves")
	GameState.initialize_new_game()
	world = load("res://scenes/shop/main.tscn").instantiate()
	world.get_node("TutorialDirector").enabled = false
	add_child(world)
	await frames()
	var manager = world.get_node("DayManager")
	manager.hour_timer.stop()
	world.get_node("QuestVisitDirector").set_process(false)
	var player = world.get_node("Actors/Player")
	var shelf = load("res://scenes/shop/objects/shelf.tscn").instantiate()
	world.add_child(shelf)
	shelf.slots = [{"item_id":"water", "stock":0, "capacity":10}, {"item_id":"bread", "stock":0, "capacity":10}]
	panel = world.get_node("UI/ShelfPanel")
	var hud: Control = world.get_node("UI/HUD")
	var menu = world.get_node("UI/GameMenu")
	var bag: Control = world.get_node("UI/BuildQuickSlotBar")
	var menu_point: Vector2 = menu.menu_button.get_global_rect().get_center()
	var original_hud := hud.visible
	var original_menu: bool = menu.visible
	var original_bag := bag.visible
	var original_movement: bool = player.is_physics_processing()
	await snapshot("before")
	panel.open(shelf, player)
	await frames()
	check(not hud.visible and not menu.visible and not bag.visible, "shelf hides HUD and background menus")
	check(not player.is_physics_processing() and player.velocity == Vector2.ZERO, "movement stops while shelf is open")
	check(not get_tree().paused, "shop time and workers are not paused by priority change")
	check(world.get_node("WorldInteractions").blocked(), "background interaction hints and actions are blocked")
	await snapshot("window")
	await click_at(menu_point)
	check(not menu.menu_open and panel.visible, "background menu click does not pass through")
	await key_action("management_menu")
	check(not world.get_node("UI/ManagementMenu").visible, "management shortcut does not open another book")
	await click(panel.material_tab_button)
	check(panel.selected_category == ItemData.CATEGORY_MATERIAL, "shelf categories receive real clicks above input backdrop")
	await click(panel.food_tab_button)
	await click(panel.shelf_slot_grid.get_child(0))
	check(panel.slot_action_panel.visible and panel.slot_action_panel.z_index > panel.z_index, "item actions show above shelf")
	check(get_viewport().get_visible_rect().encloses(panel.action_close_button.get_global_rect()), "item menu close button fits inside the screen")
	await snapshot("actions")
	await click(panel.restock_button)
	check(panel.restock_panel.visible and panel.restock_panel.z_index > panel.slot_action_panel.z_index, "amount picker shows above item actions")
	await click(panel.material_tab_button)
	check(panel.selected_category == ItemData.CATEGORY_FOOD, "amount picker blocks clicks on underlying shelf tabs")
	await snapshot("amount")
	await key_action("ui_cancel")
	check(panel.visible and not panel.restock_panel.visible, "Escape closes only the amount picker")
	await click(panel.shelf_slot_grid.get_child(0))
	await key_action("ui_cancel")
	check(panel.visible and not panel.slot_action_panel.visible, "second Escape closes only item actions")
	await click(panel.shelf_slot_grid.get_child(0))
	await click(panel.restock_button)
	var water_before := GameState.get_item_count("water")
	await click(panel.restock_confirm_button)
	check(shelf.get_item_stock("water") == 1 and GameState.get_item_count("water") == water_before - 1, "real confirm click transfers goods exactly once")
	await click(panel.close_button)
	check(not panel.visible and hud.visible == original_hud and menu.visible == original_menu and bag.visible == original_bag, "close restores previous HUD and menu visibility")
	check(player.is_physics_processing() == original_movement, "close restores previous movement processing")
	await snapshot("closed")
	# 영업 마감은 선반보다 우선되어 마감 화면을 가리지 않아야 한다.
	panel.open(shelf, player)
	world.get_node("UI/DaySummaryCenter").show()
	await frames()
	check(not panel.visible and hud.visible == original_hud, "day summary supersedes shelf and restores background state")
	world.get_node("UI/DaySummaryCenter").hide()
	# Originally hidden/disabled states must remain so after reopening.
	hud.hide()
	player.set_physics_process(false)
	panel.open(shelf, player)
	await frames()
	await key_action("ui_cancel")
	check(not panel.visible and not hud.visible and not player.is_physics_processing(), "Escape preserves originally hidden and disabled states")
	print("SHELF_WINDOW_PRIORITY checks=%d failures=%d" % [checks, failures])
	get_tree().quit(1 if failures else 0)
