extends Node
## 화면 갱신(프레임)이 물리 갱신(초당 60)보다 잦을 때(고주사율 모니터) 걷기 그림이 어떻게 바뀌는지 잰다(개발용, 화면 불필요).
## 사용: godot --headless --path . res://dev/spike3d/sprite_refresh_probe.tscn -- <초당 화면 프레임 수, 기본 144>
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("run")

func run() -> void:
	var args := OS.get_cmdline_user_args()
	var fps: int = int(args[0]) if args.size() > 0 else 144
	GameState.initialize_new_game()
	var world = load("res://scenes/shop/main.tscn").instantiate()
	world.get_node("TutorialDirector").enabled = false
	add_child(world)
	for i in range(40): await get_tree().process_frame
	var view: StoreView3D = world.get_node("StoreView3D")
	var player = view.player
	Engine.max_fps = fps
	Input.action_press("move_right")
	var changes := 0
	var toggles := 0
	var idle_frames := 0
	var total := 0
	var last_frame := -99
	var last_walk := false
	var start := Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < 3000:
		await get_tree().process_frame
		var e: Dictionary = view._actors.get(player.get_instance_id(), {})
		if e.is_empty(): continue
		var f = e["figure"]
		total += 1
		var fr := int(f.get("frame_index"))
		if fr != last_frame: changes += 1
		last_frame = fr
		if bool(f.walking) != last_walk: toggles += 1
		last_walk = bool(f.walking)
		if fr == -1: idle_frames += 1
	Input.action_release("move_right")
	var secs := (Time.get_ticks_msec() - start) / 1000.0
	print("화면 %d fps 요청 → 실제 표시 프레임 %d개/%.1f초(%.0f fps): 그림 바뀜 %.0f회/초, 걷기↔정지 전환 %.0f회/초, 정지 그림으로 보인 프레임 %.0f%%" % [fps, total, secs, total / secs, changes / secs, toggles / secs, 100.0 * idle_frames / maxf(total, 1)])
	get_tree().quit()
