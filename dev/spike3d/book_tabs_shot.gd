extends Node
## 관리 창 각 탭의 펼침면 배치 확인(선택·하위 탭 포함). 사용: godot --path . res://dev/spike3d/book_tabs_shot.tscn -- <저장 폴더>

func _ready() -> void:
	ManagementMenu.PRESENTATION.animations_enabled = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("run")

func snap(dir: String, name: String) -> void:
	for i in 6: await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [dir, name])

func run() -> void:
	var dir: String = OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "/tmp/book_tabs"
	DirAccess.make_dir_recursive_absolute(dir)
	var world = load("res://scenes/shop/main.tscn").instantiate()
	world.get_node("TutorialDirector").enabled = false
	add_child(world)
	for i in 10: await get_tree().process_frame
	world.get_node("DayManager").hour_timer.stop()
	var mm = world.find_child("ManagementMenu", true, false)
	GameState.add_furniture("fridge_unit", 1)
	GameState.add_furniture("modern_shelf_2x1", 1)
	mm.open_menu(0)
	mm.management_inventory.select_inventory_group("furniture")
	await snap(dir, "0_inventory_furniture")
	for c in mm.management_inventory.get_node("MainVBox/ItemScroll/ItemGrid").get_children():
		if c is ItemCard and c.entry_type == "furniture":
			c.pressed.emit()
			break
	await snap(dir, "0b_inventory_furniture_selected")
	mm.select_tab(3)
	await snap(dir, "1_blueprint")
	mm.blueprint_content._select_furniture("modern_shelf_2x1")
	await snap(dir, "2_blueprint_selected")
	mm.select_tab(1)
	var prod = mm.management_production
	prod._select_production_tab(false)
	await snap(dir, "3_production_recipe")
	mm.select_tab(6)
	await snap(dir, "4_info_basic")
	mm.info_tab_bar.get_node("DetailInfoButton").pressed.emit()
	await snap(dir, "5_info_detail")
	mm.info_tab_bar.get_node("SalesTrendButton").pressed.emit()
	await snap(dir, "6_info_sales")
	mm.info_tab_bar.get_node("ExtraRecordButton").pressed.emit()
	await snap(dir, "7_info_extra")
	mm.select_tab(5)
	await snap(dir, "8_schedule")
	mm.select_tab(2)
	await snap(dir, "9_employee")
	get_tree().quit()
