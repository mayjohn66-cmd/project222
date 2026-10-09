extends Node
## 주인공을 실제로 걷게 하면서 스프라이트 상태를 프레임마다 기록해 "떨림" 원인을 잰다(개발용, 화면 불필요).
## 사용: godot --headless --path . res://dev/spike3d/sprite_jitter_probe.tscn
## 보는 것: 방향 그림 바뀜 횟수, 걷기↔정지 바뀜 횟수, 걷기 프레임 번호가 거꾸로 가는 횟수, 화면 이동량의 흔들림.
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("run")

func run() -> void:
	GameState.initialize_new_game()
	var world = load("res://scenes/shop/main.tscn").instantiate()
	world.get_node("TutorialDirector").enabled = false
	add_child(world)
	for i in range(40): await get_tree().process_frame
	var view: StoreView3D = world.get_node("StoreView3D")
	var player = view.player
	print("shrink=", view.shrink, " player=", player.name, " sprite=", view._actors.get(player.get_instance_id(), {}).get("sprite_key", "?"))
	for route in [["move_right"], ["move_down"], ["move_right", "move_down"], ["move_left", "move_up"]]:
		var log: Array[Dictionary] = []
		for a in route: Input.action_press(a)
		for i in range(150):
			await get_tree().physics_frame
			await get_tree().process_frame
			var e: Dictionary = view._actors.get(player.get_instance_id(), {})
			if e.is_empty(): continue
			var f = e["figure"]
			log.append({"dir": str(f.get("direction")), "walk": bool(f.walking), "frame": int(f.get("frame_index") if f.get("frame_index") != null else -9), "x": player.global_position.x, "y": player.global_position.y, "yaw": float(f.facing_yaw_deg)})
		for a in route: Input.action_release(a)
		await get_tree().create_timer(0.3).timeout
		_report(route, log)
	get_tree().quit()

func _report(route: Array, log: Array[Dictionary]) -> void:
	var dir_changes := 0
	var walk_toggles := 0
	var backward := 0
	var steps: Array[float] = []
	for i in range(1, log.size()):
		var a: Dictionary = log[i - 1]
		var b: Dictionary = log[i]
		if a["dir"] != b["dir"]: dir_changes += 1
		if a["walk"] != b["walk"]: walk_toggles += 1
		if a["walk"] and b["walk"] and a["frame"] >= 0 and b["frame"] >= 0 and b["frame"] != a["frame"]:
			var d := (int(b["frame"]) - int(a["frame"]) + 8) % 8
			if d > 4: backward += 1
		steps.append(Vector2(float(b["x"]) - float(a["x"]), float(b["y"]) - float(a["y"])).length())
	var mean := 0.0
	for s in steps: mean += s
	mean /= maxf(steps.size(), 1)
	var variance := 0.0
	for s in steps: variance += (s - mean) * (s - mean)
	var sd := sqrt(variance / maxf(steps.size(), 1))
	var moving_steps: Array[float] = steps.filter(func(s): return s > 0.1)
	print("route=%s frames=%d 방향바뀜=%d 걷기정지바뀜=%d 프레임역행=%d 이동량 평균=%.2f 표준편차=%.2f (변동계수 %.2f)" % [str(route), log.size(), dir_changes, walk_toggles, backward, mean, sd, sd / maxf(mean, 0.0001)])
