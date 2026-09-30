extends Node
func _ready() -> void:
	get_window().size = Vector2i(1152,648)
	var world = load("res://scenes/shop/main.tscn").instantiate()
	add_child(world)
	for i in range(6):
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
	var director = world.get_node("TutorialDirector")
	world.get_node("Actors/Player").global_position = director.npc.global_position + Vector2(40,30)
	director.try_interact()
	director.dialogue.typing_tween.kill()
	director.dialogue.text_label.visible_ratio = 1.0
	for i in range(4):
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
	var error := get_viewport().get_texture().get_image().save_png(OS.get_cmdline_user_args()[0])
	print("TUTORIAL_PREVIEW error=",error)
	get_tree().quit(0 if error == OK else 1)
