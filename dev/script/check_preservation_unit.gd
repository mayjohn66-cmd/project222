extends Node
## 냉장함·냉동함 가구: 설치(무료), 월드 상호작용으로 보관 창 열기, 넣기·꺼내기, 보존 규칙 확인.
var checks := 0
var failures := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("FAIL: " + message)

func settle() -> void:
	for i in range(4): await get_tree().process_frame

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("run")

func run() -> void:
	var world = load("res://scenes/shop/main.tscn").instantiate()
	world.get_node("TutorialDirector").enabled = false
	add_child(world)
	await settle()
	world.get_node("DayManager").hour_timer.stop()
	for worker in get_tree().get_nodes_in_group("worker"): worker.queue_free()
	var manager = world.get_node("BuildManager")
	var player: Node2D = world.get_node("Actors/Player")
	player.set_physics_process(false)
	PreservationService.settle()
	check(not PreservationService.installed("fridge"), "fridge not installed at start")
	for id in ["fridge_unit", "freezer_unit"]:
		GameState.add_furniture(id, 1)
		manager.build_selection_state.restore_selection(manager.furniture_catalog.find(id), 0)
		var anchor := Vector2i(3, 3) if id == "fridge_unit" else Vector2i(6, 3)
		check(manager.can_place(anchor), "can place " + id)
		var f = manager.build_placement_service.place_furniture(id, anchor)
		check(is_instance_valid(f) and f.is_in_group("preservation_unit"), "placed in group: " + id)
		check(f.unit_id() == id.trim_suffix("_unit"), "unit id: " + id)
		player.global_position = f.global_position + Vector2(0, 20)
		await settle()
		var money := GameState.money
		check(player.try_interact_with_preservation_unit(), "interaction opens: " + id)
		await settle()
		var panel: PreservationPanel = player.get_node_or_null("PreservationWorldPanel")
		check(panel != null and panel.visible, "panel visible: " + id)
		check(PreservationService.installed(id.trim_suffix("_unit")) and GameState.money == money, "free install: " + id)
		panel.hide()
	GameState.add_item("spring_bud", 2)
	check(PreservationService.deposit("fridge", "spring_bud", 2) == 2, "deposit")
	check(PreservationService.deposit("fridge", "winter_frost", 1) == 0, "fridge rejects ice")
	check(PreservationService.withdraw("freezer", "spring_bud", 1) == 0, "freezer empty")
	check(PreservationService.withdraw("fridge", "spring_bud", 2) == 2, "withdraw")
	print("CHECK_PRESERVATION_UNIT checks=%d failures=%d" % [checks, failures])
	get_tree().quit(1 if failures > 0 else 0)
