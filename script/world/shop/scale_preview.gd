extends "res://script/world/shop/world_art_preview.gd"

func _place_samples() -> void:
	super._place_samples()
	var player = $Actors/Player
	var camera = $Actors/Player/Camera2D
	var center: Vector2 = $Floor.to_global($Floor.grid_to_local(Vector2i(4,4)))
	camera.top_level = true
	camera.global_position = center
	var counter = $Objects.get_children().filter(func(n): return n.get_meta("build_id", "") == "register")[0]
	var behind: bool = "--behind" in OS.get_cmdline_user_args()
	player.global_position = counter.global_position + (Vector2(0,-16) if behind else Vector2(24,72))
	player.set_physics_process(false)
	assert($Actors.y_sort_enabled)
	assert(player.get_node("AnimatedSprite2D").position.y == -32)
	assert(counter.get_node("Visual").furniture_height == 24)
	print("SCALE_AND_SORT_OK: player ", "behind" if behind else "in front", " of counter")
