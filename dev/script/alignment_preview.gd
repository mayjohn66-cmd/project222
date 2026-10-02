extends Node2D

func _ready() -> void:
	call_deferred("_setup")

func _setup() -> void:
	$DayManager/HourTimer.stop()
	$Actors/Player.global_position = $Floor.to_global($Floor.grid_to_local(Vector2i(4, 4)))
	$Actors/Player/Camera2D.zoom = Vector2.ONE
	var builder = $BuildManager
	builder.start_build_mode()
	builder.build_selection_state.restore_selection(builder.get_catalog_index_from_build_id("register"), 0)
	builder.create_preview()
	builder.update_preview_size()
	var visual = builder.build_preview_controller.get_preview().get_node("Visual")
	var rect: Rect2 = visual.get_art_rect()
	assert(rect.position.x == -48.0 and rect.end.x == 96.0)
	assert(rect.end.y == 48.0)
	print("ALIGNMENT_OK: 2x1 bounds remain [-48,96], front y=48 when flipped")

