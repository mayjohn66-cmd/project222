extends Node

func _ready() -> void:
	get_window().size = Vector2i(1152,648)
	var args := OS.get_cmdline_user_args()
	var mode := args[0] if not args.is_empty() else "gather"
	var inst = load("res://scenes/expedition/expedition.tscn").instantiate()
	add_child(inst)
	await get_tree().process_frame
	inst.set_expedition_phase(inst.ExpeditionPhase.RUN)
	inst.expedition_map = ExpeditionMap.new()
	var controller: ExpeditionRoomController = inst.expedition_room_controller
	if mode == "battle":
		controller.enter({"result_type":"battle", "target_id":"forest_thornling"},"battle")
	else:
		controller.enter({"event_id":"forest_gather_choice", "result_type":"loot", "target_id":"forest_gather"},"gather")
		controller.model.player_position = Vector2(2.5,4.3)
	controller.view.set_physics_process(false)
	controller.view._physics_process(0)
	for i in range(4):
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
	var target: String = args[1] if args.size() > 1 else "user://content_" + mode + ".png"
	var error := get_viewport().get_texture().get_image().save_png(target)
	print("CONTENT_PREVIEW ", target, " error=", error)
	get_tree().quit(0 if error == OK else 1)
