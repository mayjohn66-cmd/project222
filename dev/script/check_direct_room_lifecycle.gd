extends Node

var failures: Array[String] = []

func expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)

func make_host():
	var inst = load("res://scenes/expedition/expedition.tscn").instantiate()
	add_child(inst)
	await get_tree().process_frame
	inst.expedition_map = ExpeditionMap.new()
	inst.set_expedition_phase(inst.ExpeditionPhase.RUN)
	return inst

func _ready() -> void:
	var inst = await make_host()
	var controller: ExpeditionRoomController = inst.expedition_room_controller
	expect(inst.can_save_expedition_checkpoint(), "지도에서는 저장 가능")
	controller.enter({"result_type": "battle", "target_id": "field_slime"}, "battle")
	expect(not inst.can_save_expedition_checkpoint(), "방 진행 중 저장 금지")
	var before := controller.model.player_position
	Input.action_press("move_up")
	for i in range(12): await get_tree().physics_frame
	Input.action_release("move_up")
	expect(controller.model.player_position.y < before.y, "화면의 이동 입력 연결")
	expect(not inst.get_node("PreparationVillage").clock_hud.visible, "방 안에서는 준비 시계 숨김")
	inst.game_menu.menu_open = true
	before = controller.model.player_position
	var elapsed_before: float = controller.model.elapsed
	Input.action_press("move_up")
	for i in range(12): await get_tree().physics_frame
	Input.action_release("move_up")
	expect(controller.model.player_position == before and controller.model.elapsed == elapsed_before, "메뉴 중 방 전투/이동 정지")
	inst.game_menu.menu_open = false
	controller.view.attack_button.button_down.emit()
	expect(controller.model.attack_remaining > 0, "화면 공격 버튼 연결")
	controller._retreat()
	expect(inst.current_end_reason == inst.ExpeditionEndReason.RETREAT and inst.current_expedition_phase == inst.ExpeditionPhase.RESULT, "전투 중 철수 가능")
	inst.queue_free()
	await get_tree().process_frame

	inst = await make_host()
	controller = inst.expedition_room_controller
	controller.enter({"result_type": "loot", "target_id": "treasure_basic"}, "treasure")
	controller.view.set_physics_process(false)
	controller.model.player_position = controller.model.object_position
	controller.view.interact_button.pressed.emit()
	controller.model.step(1.0, Vector2.ZERO, false)
	expect(controller.pending_loot.size() == 1, "상자 보상은 상호작용 후 한 번만 생성")
	controller._retreat()
	expect(inst.loot_panel.visible and inst.current_expedition_phase == inst.ExpeditionPhase.RUN, "보상 있는 철수는 가방 정리부터")
	inst.expedition_bag_controller.finish_loot_organization()
	expect(inst.current_expedition_phase == inst.ExpeditionPhase.RESULT and inst.current_end_reason == inst.ExpeditionEndReason.RETREAT, "가방 정리 후 철수 결과")
	inst.queue_free()
	await get_tree().process_frame

	inst = await make_host()
	controller = inst.expedition_room_controller
	controller.enter({"result_type": "battle", "target_id": "field_slime"}, "battle")
	controller.view.set_physics_process(false)
	controller.model.player_hp = 1
	controller.model.player_position = controller.model.enemies[0]["position"]
	controller.model.step(0.01, Vector2.ZERO, false)
	controller.model.step(1.0, Vector2.ZERO, false)
	expect(inst.current_expedition_phase == inst.ExpeditionPhase.RESULT and inst.current_end_reason == inst.ExpeditionEndReason.DEFEAT, "HP 소진 시 패배 결과")
	inst.queue_free()
	await get_tree().process_frame
	print("[방 흐름 검사] 실패 ", failures.size())
	get_tree().quit(0 if failures.is_empty() else 1)
