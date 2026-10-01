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
	var director = world.get_node("ResidentRequestDirector")
	ResidentRequestFlow.accept(ResidentRequestFlow.current())
	director.refresh()
	world.get_node("Actors/Player").global_position = director.npc.global_position + Vector2(30,20)
	for i in range(4):
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
	var error := get_viewport().get_texture().get_image().save_png(OS.get_cmdline_user_args()[0])
	print("REQUEST_PREVIEW error=",error)
	get_tree().quit(0 if error == OK else 1)
