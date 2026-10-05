extends Node
## 3D 책 위에서 마우스 입력이 UI 로 전달되는지 확인(포스트잇 클릭 → 탭 전환, 책 바깥 클릭 → 닫기). 사용: godot --path . res://dev/spike3d/book_click_shot.tscn -- <저장 폴더>

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("run")

func wait(sec: float) -> void:
	await get_tree().create_timer(sec, true, false, true).timeout

func click(pos: Vector2) -> void:
	var move := InputEventMouseMotion.new()
	move.position = pos
	move.global_position = pos
	Input.parse_input_event(move)
	await wait(0.1)
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = pos
	down.global_position = pos
	Input.parse_input_event(down)
	await wait(0.05)
	var up := down.duplicate()
	up.pressed = false
	Input.parse_input_event(up)
	await wait(0.1)

func run() -> void:
	var dir: String = OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "/tmp/book_click"
	DirAccess.make_dir_recursive_absolute(dir)
	var world = load("res://scenes/shop/main.tscn").instantiate()
	world.get_node("TutorialDirector").enabled = false
	add_child(world)
	for i in 10: await get_tree().process_frame
	world.get_node("DayManager").hour_timer.stop()
	var mm = world.find_child("ManagementMenu", true, false)
	mm.open_menu(0)
	await wait(1.6)
	var stage = mm.get_meta("book_stage")
	var nav = mm.get_node("DimBackground/CenterContainer/MainPanel/MainVBox/Body/Navigation")
	var b: Control = nav.get_child(5)
	var p: Vector2 = b.get_global_rect().get_center() + stage._offset
	print("클릭 전 탭=", mm.current_tab)
	await click(p)
	await wait(1.5)
	print("클릭 후 탭=", mm.current_tab, " (기대 5)")
	get_viewport().get_texture().get_image().save_png(dir + "/after_click.png")
	# 앞 탭 포스트잇은 왼쪽 가장자리에 있다: 그중 인벤토리(0)를 눌러 돌아간다
	var items: Array = stage.left_flags.items
	print("왼쪽 포스트잇 수=", items.size(), " (기대 5)")
	await click((items[0]["rect"] as Rect2).get_center())
	await wait(1.5)
	print("왼쪽 클릭 후 탭=", mm.current_tab, " (기대 0)")
	get_viewport().get_texture().get_image().save_png(dir + "/after_back.png")
	await click(Vector2(5, 5))
	await wait(1.2)
	print("바깥 클릭 후 visible=", mm.visible, " (기대 false)")
	get_tree().quit()
