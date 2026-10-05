extends Node
## 책 펼침면과 탭 이동 책장 넘김 확인. 사용: godot --path . res://dev/spike3d/book_flip_shot.tscn -- <저장 폴더>

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("run")

func snap(dir: String, name: String) -> void:
	await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [dir, name])

func wait(sec: float) -> void:
	await get_tree().create_timer(sec, true, false, true).timeout

func run() -> void:
	var dir: String = OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "/tmp/book_flip"
	DirAccess.make_dir_recursive_absolute(dir)
	var world = load("res://scenes/shop/main.tscn").instantiate()
	world.get_node("TutorialDirector").enabled = false
	add_child(world)
	for i in 10: await get_tree().process_frame
	world.get_node("DayManager").hour_timer.stop()
	var mm = world.find_child("ManagementMenu", true, false)
	mm.open_menu(0)
	await wait(1.6)
	# 아이템 선택 → 오른쪽 쪽 상세
	var grid = mm.management_inventory.get_node("MainVBox/ItemScroll/ItemGrid")
	for c in grid.get_children():
		if c is ItemCard and c.item_id != "":
			c.pressed.emit()
			break
	await wait(0.3)
	await snap(dir, "a_detail")
	# 뒤쪽 탭(설계도)으로: 오른쪽 쪽이 왼쪽으로 넘어간다
	mm.select_tab(3)
	for i in range(7):
		await snap(dir, "b_fwd_%d" % i)
		await wait(0.07)
	await wait(0.6)
	await snap(dir, "c_blueprint")
	# 앞쪽 탭(인벤토리)으로: 왼쪽 쪽이 오른쪽으로 넘어간다
	mm.select_tab(0)
	for i in range(7):
		await snap(dir, "d_back_%d" % i)
		await wait(0.07)
	await wait(0.6)
	await snap(dir, "e_inventory")
	get_tree().quit()
