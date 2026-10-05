extends Node
## UI 현황 점검: 주요 화면을 열어 PNG 로 저장한다.  사용: godot --path . res://dev/spike3d/ui_audit_shot.tscn -- <저장 폴더>

func shot(dir: String, name: String, frames: int = 20) -> void:
	for i in frames: await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [dir, name])
	print("저장: ", name)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("run")

func run() -> void:
	var dir: String = OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "/tmp/ui_audit"
	DirAccess.make_dir_recursive_absolute(dir)
	var title = load("res://scenes/core/title/title_screen.tscn").instantiate()
	add_child(title)
	await shot(dir, "01_title", 30)
	title.queue_free()
	var world = load("res://scenes/shop/main.tscn").instantiate()
	world.get_node("TutorialDirector").enabled = false
	add_child(world)
	for i in 10: await get_tree().process_frame
	world.get_node("DayManager").hour_timer.stop()
	await shot(dir, "02_store_hud", 30)
	var ui = world.get_node("StoreUI") if world.has_node("StoreUI") else null
	var layer = get_tree().get_first_node_in_group("store_ui")
	var mm = world.find_child("ManagementMenu", true, false)
	var gm = world.find_child("GameMenu", true, false)
	if gm:
		gm.toggle_main_menu()
		await shot(dir, "03_game_menu", 40)
		gm.toggle_main_menu()
	if mm:
		for tab in range(0, 5):
			mm.visible = false
			mm.open_menu(tab)
			await shot(dir, "04_management_tab%d" % tab, 20)
		mm.close_menu()
	get_tree().quit()
