extends Node

func _ready() -> void:
	get_window().size = Vector2i(1152,648)
	var world = load("res://scenes/shop/main.tscn").instantiate()
	add_child(world)
	for i in range(6): await get_tree().process_frame
	for step in TutorialDirector.SETTINGS.steps:
		PlayerProgress.record_story_beat("tutorial_step:" + str(step["id"]) + ":done", GameState.total_day)
	PlayerProgress.record_story_beat(CheckoutTutorial.BEAT_ID, GameState.total_day)
	world.get_node("TutorialDirector").refresh()
	var args := OS.get_cmdline_user_args()
	var grown: bool = args.size() > 1 and args[1] == "grown"
	if grown:
		for request in ResidentStoryFlow.SETTINGS.settlement_requests:
			PlayerProgress.record_story_beat(ResidentRequestFlow.PREFIX + str(request["id"]) + ":done", GameState.total_day)
	VillageSettlement.apply_world(world)
	world.get_node("UI").hide()
	var camera := Camera2D.new()
	world.add_child(camera)
	var bounds := Rect2(world.get_node("Floor").global_position, Vector2.ONE)
	for landmark in ResidentStoryFlow.SETTINGS.landmarks:
		var site := VillageSettlement.find_site(world, str(landmark["path"]))
		if site != null: bounds = bounds.expand(site.global_position)
	bounds = bounds.grow(280.0)
	camera.global_position = bounds.get_center()
	var scale := minf(1000.0 / bounds.size.x, 560.0 / bounds.size.y)
	camera.zoom = Vector2.ONE * scale
	camera.make_current()
	for i in range(4):
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
	var error := get_viewport().get_texture().get_image().save_png(args[0])
	print("SETTLEMENT_PREVIEW error=",error)
	get_tree().quit(0 if error == OK else 1)
