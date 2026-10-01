extends Node

func _ready() -> void:
	get_window().size = Vector2i(1152,648)
	var world = load("res://scenes/shop/main.tscn").instantiate()
	add_child(world)
	for i in range(6): await get_tree().process_frame
	for step in TutorialDirector.SETTINGS.steps:
		PlayerProgress.record_story_beat("tutorial_step:" + str(step["id"]) + ":done", GameState.total_day)
	PlayerProgress.record_story_beat(CheckoutTutorial.BEAT_ID, GameState.total_day)
	for entry in VillageLifeFlow.SETTINGS.residents:
		PlayerProgress.record_story_beat(ResidentRequestFlow.PREFIX + str(entry["request"]) + ":done", GameState.total_day)
	VillageSettlement.apply_world(world)
	for i in range(6): await get_tree().physics_frame
	var life: VillageLifeDirector = world.get_node("VillageLifeDirector")
	life.refresh()
	var npc: VillageResident = life.residents["naru"]
	var player = world.get_node("Actors/Player")
	player.set_physics_process(false)
	player.global_position = npc.global_position + Vector2(40, 25)
	var camera := Camera2D.new()
	world.add_child(camera)
	camera.global_position = npc.global_position + Vector2(30,-100)
	camera.zoom = Vector2(1,1)
	camera.make_current()
	for i in range(6): await get_tree().process_frame
	var args := OS.get_cmdline_user_args()
	if args.size() > 1 and args[1] == "dialogue": life.try_interact()
	for i in range(4):
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
	if life.talking:
		if life.dialogue.typing_tween != null: life.dialogue.typing_tween.kill()
		life.dialogue.text_label.visible_ratio = 1
	await RenderingServer.frame_post_draw
	var error := get_viewport().get_texture().get_image().save_png(args[0])
	print("VILLAGE_LIFE_PREVIEW error=", error)
	get_tree().quit(0 if error == OK else 1)
