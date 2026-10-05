extends Node
## 행사 장식 확인: 행사가 진행되는 날짜를 골라 매장 화면을 저장한다.  사용: godot --path . res://dev/spike3d/event_decor_shot.tscn -- <저장 폴더>

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("run")

func run() -> void:
	var dir: String = OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "/tmp/event_decor"
	DirAccess.make_dir_recursive_absolute(dir)
	var world = load("res://scenes/shop/main.tscn").instantiate()
	world.get_node("TutorialDirector").enabled = false
	add_child(world)

	for i in 10: await get_tree().process_frame

	world.get_node("DayManager").hour_timer.stop()
	var seen: Dictionary = {}

	for day in range(1, 130):
		var ids: Array = []
		for ev in StoreEventData.get_active_events(day): ids.append(str(ev["event_id"]))
		ids.sort()
		var sig := ",".join(ids)
		if ids.is_empty() or seen.has(sig): continue
		seen[sig] = true
		GameState.total_day = day
		for i in 40: await get_tree().process_frame
		var img := get_viewport().get_texture().get_image()
		img.save_png("%s/day_%03d_%s.png" % [dir, day, ids[0]])
		print("저장: day ", day, " ", sig)

	get_tree().quit()
