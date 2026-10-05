extends Node
## 관리 창 책 여닫기 연출 확인: 열기 → 펼침 직후 → 닫기 도중의 화면을 시간 간격으로 저장한다.  사용: godot --path . res://dev/spike3d/book_anim_shot.tscn -- <저장 폴더>

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("run")

func snap(dir: String, name: String) -> void:
	await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [dir, name])

func wait(sec: float) -> void:
	await get_tree().create_timer(sec, true, false, true).timeout

func run() -> void:
	var dir: String = OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "/tmp/book_anim"
	DirAccess.make_dir_recursive_absolute(dir)
	var world = load("res://scenes/shop/main.tscn").instantiate()
	world.get_node("TutorialDirector").enabled = false
	add_child(world)
	for i in 10: await get_tree().process_frame
	world.get_node("DayManager").hour_timer.stop()
	var mm = world.find_child("ManagementMenu", true, false)
	mm.open_menu(0)
	var t := 0.0
	for i in range(8):
		await snap(dir, "open_%d" % i)
		await wait(0.12)
	await wait(0.6)
	await snap(dir, "open_done")
	mm.close_menu()
	for i in range(5):
		await snap(dir, "close_%d" % i)
		await wait(0.1)
	await wait(0.5)
	print("닫힘 후 visible=", mm.visible)
	mm.open_menu(0)
	await wait(1.2)
	await snap(dir, "reopen_done")
	get_tree().quit()
