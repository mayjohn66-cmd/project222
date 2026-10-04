extends Node
func _ready() -> void:
	get_window().size = Vector2i(1152,648)
	var world = load("res://scenes/shop/main.tscn").instantiate()
	add_child(world)
	for i in range(6):
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
	var director = world.get_node("TutorialDirector")
	# 초반은 현지 안내 NPC 대신 플레이어의 상황 정리 독백이다.
	director.refresh()
	director.dialogue.typing_tween.kill()
	director.dialogue.text_label.visible_ratio = 1.0
	for i in range(4):
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
	var error := get_viewport().get_texture().get_image().save_png(OS.get_cmdline_user_args()[0])
	print("TUTORIAL_PREVIEW error=",error)
	get_tree().quit(0 if error == OK else 1)
