extends Node

func _ready() -> void:
	get_window().size = Vector2i(1152, 648)
	var inst = load("res://scenes/expedition/expedition.tscn").instantiate()
	add_child(inst)
	await get_tree().process_frame
	inst.set_expedition_phase(inst.ExpeditionPhase.RUN)
	inst.expedition_map = ExpeditionMap.new()
	inst.expedition_room_controller.enter({"result_type": "battle", "target_id": "field_slime"}, "battle")
	inst.expedition_room_controller.view.set_physics_process(false)
	inst.expedition_room_controller.view.hp_label.text = "HP 100 / 100 · 찌르기 · 남은 적 2"
	inst.expedition_room_controller.view.hint_label.text = "몬스터를 처치하면 출구가 열립니다"
	for i in range(4):
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var target: String = OS.get_cmdline_user_args()[0] if not OS.get_cmdline_user_args().is_empty() else "user://direct_room.png"
	var error := image.save_png(target)
	print("[미리보기] ", target, " 결과=", error)
	get_tree().quit(0 if error == OK else 1)
