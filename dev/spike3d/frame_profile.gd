extends Node
## 스크립트가 한 프레임에 쓰는 CPU 시간을 잰다(개발용, 화면 불필요).
## 방법: 가장 먼저 도는 노드(우선순위 -100000)와 가장 나중에 도는 노드(+100000)의 _process 로 한 프레임의 처리 구간을 감싸 그 사이 시간을 잰다.
## 프레임 사이 시간은 헤드리스가 프레임을 144fps 근처로 맞추느라 기다리는 시간이 섞여 쓸 수 없다.
## 사용: godot --headless --path . res://dev/spike3d/frame_profile.tscn -- [프레임 수 기본 300]
## 보는 것: 한 프레임 _process 구간의 CPU 시간, 스크립트(노드 그룹)별로 끄면 줄어드는 시간, StoreView3D 단계별 시간, 노드 수.
class Clock extends RefCounted:
	var start_us := 0
	var spent: Array = []

class Starter extends Node:
	var clock: Clock
	func _ready() -> void:
		process_mode = Node.PROCESS_MODE_ALWAYS
		process_priority = -100000
	func _process(_d: float) -> void:
		clock.start_us = Time.get_ticks_usec()

class Ender extends Node:
	var clock: Clock
	func _ready() -> void:
		process_mode = Node.PROCESS_MODE_ALWAYS
		process_priority = 100000
	func _process(_d: float) -> void:
		clock.spent.append((Time.get_ticks_usec() - clock.start_us) / 1000000.0)

var clock := Clock.new()

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("run")

func mean(values: Array) -> float:
	var sum := 0.0
	for v in values: sum += float(v)
	return sum / maxf(values.size(), 1)

func stat(values: Array) -> String:
	if values.is_empty(): return "-"
	var s: Array = values.duplicate()
	s.sort()
	return "평균 %.2fms · 중앙 %.2fms · 95%% %.2fms · 최대 %.2fms" % [mean(s) * 1000.0, float(s[s.size() / 2]) * 1000.0, float(s[int(s.size() * 0.95)]) * 1000.0, float(s[-1]) * 1000.0]

func sample(frames: int) -> Array:
	clock.spent.clear()
	while clock.spent.size() < frames:
		await get_tree().process_frame
	return clock.spent.duplicate()

func run() -> void:
	var args := OS.get_cmdline_user_args()
	var frames: int = int(args[0]) if args.size() > 0 else 300
	GameState.initialize_new_game()
	var starter := Starter.new()
	starter.clock = clock
	add_child(starter)
	var ender := Ender.new()
	ender.clock = clock
	add_child(ender)
	var world = load("res://scenes/shop/main.tscn").instantiate()
	world.get_node("TutorialDirector").enabled = false
	add_child(world)
	for i in range(60): await get_tree().process_frame
	var view: StoreView3D = world.get_node("StoreView3D")
	# 부하 상황: 인자 두 번째가 load 이면 가게를 열고 손님을 한꺼번에 들여보낸다
	if args.size() > 1 and args[1] == "load":
		var layout: Array[Dictionary] = [{"build_id":"door","anchor":Vector2i(0,4),"rotation_index":3},{"build_id":"register","anchor":Vector2i(4,3),"rotation_index":0},{"build_id":"shelf_1x1","anchor":Vector2i(2,2),"rotation_index":0}]
		world.get_node("BuildManager")._restore_current_area_layout(layout)
		for i in range(10): await get_tree().process_frame
		var spawner = world.get_node("CustomerSpawner")
		spawner.set_shop_open(true)
		for i in range(14):
			spawner.spawn_customer()
			for k in range(6): await get_tree().process_frame
		for i in range(240): await get_tree().process_frame
		print("부하 상황: 손님 %d명, 직원 %d명" % [get_tree().get_nodes_in_group("customer").size(), get_tree().get_nodes_in_group("worker").size()])
	var all: Array = await sample(frames)
	print("노드 %d개 · 오브젝트 %d개 · 고아 노드 %d개" % [int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)), int(Performance.get_monitor(Performance.OBJECT_COUNT)), int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))])
	print("한 프레임 _process 구간 CPU 시간: ", stat(all))
	# 스크립트별: 같은 스크립트를 쓰는 노드의 _process 를 한꺼번에 끄고 평균이 얼마나 줄어드는지
	var groups := {}
	for n in world.find_children("*", "", true, false):
		if n.is_processing():
			var sc = n.get_script()
			var key: String = str(sc.resource_path) if sc != null else n.get_class()
			if not groups.has(key): groups[key] = []
			groups[key].append(n)
	var base: float = mean(await sample(120))
	var rows: Array = []
	for key in groups:
		for n in groups[key]: n.set_process(false)
		await get_tree().process_frame
		var without: float = mean(await sample(80))
		for n in groups[key]:
			if is_instance_valid(n): n.set_process(true)
		rows.append({"key": key, "count": groups[key].size(), "saved": base - without})
	rows.sort_custom(func(a, b): return a["saved"] > b["saved"])
	print("기준 평균 %.2fms. _process 를 끄면 줄어드는 시간(상위):" % (base * 1000.0))
	for r in rows.slice(0, 12):
		print("  %6.2fms  %s (노드 %d개)" % [float(r["saved"]) * 1000.0, str(r["key"]).replace("res://script/", ""), int(r["count"])])
	var steps := {
		"_sync_walls": func(): view._sync_walls(),
		"_sync_furniture": func(): view._sync_furniture(),
		"_sync_actors": func(): view._sync_actors(0.016),
		"_sort_and_update": func(): view._sort_and_update(),
	}
	for name in steps:
		var times: Array = []
		for i in range(120):
			var t0 := Time.get_ticks_usec()
			steps[name].call()
			times.append((Time.get_ticks_usec() - t0) / 1000000.0)
		print("  StoreView3D.%-18s %s" % [name, stat(times)])
	var counts := {}
	for n in world.find_children("*", "", true, false):
		counts[n.get_class()] = int(counts.get(n.get_class(), 0)) + 1
	var keys := counts.keys()
	keys.sort_custom(func(a, b): return counts[a] > counts[b])
	var line := ""
	for k in keys.slice(0, 8): line += "%s=%d  " % [k, counts[k]]
	print("노드 종류: ", line)
	get_tree().quit()
