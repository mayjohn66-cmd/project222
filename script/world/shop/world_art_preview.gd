extends Node2D

# Runs the real shop scene with an unsaved demonstration layout.
func _ready() -> void:
	call_deferred("_place_samples")

func _place_samples() -> void:
	$DayManager/HourTimer.stop()
	var builder = $BuildManager
	var samples = [
		["shelf_2x1", Vector2i(2, 2), 0],
		["shelf_2x1", Vector2i(2, 4), 0],
		["shelf_1x1", Vector2i(6, 2), 0],
		["register", Vector2i(6, 5), 0],
		["door", Vector2i(4, 0), 0]]
	for sample in samples:
		var id: String = sample[0]
		GameState.add_furniture(id, 1)
		builder.build_selection_state.restore_selection(builder.get_catalog_index_from_build_id(id), sample[2])
		var object = builder.build_placement_service.place_furniture(id, sample[1])
		assert(object != null, "Preview furniture placement failed: " + id)
		if id == "shelf_1x1":
			object.stack_level = 2
			object.update_visual()
			object.update_stock_label()
	builder.clear_build_selection()
	$Actors/Player.global_position = $Floor.to_global($Floor.grid_to_local(Vector2i(4, 4)))
	$Actors/Player/Camera2D.zoom = Vector2.ONE
	print("WORLD_ART_PREVIEW_OK: real shop scene with unsaved demonstration furniture")
