extends Node2D

func _ready() -> void:
	call_deferred("preview")

func preview() -> void:
	$DayManager/HourTimer.stop()
	var builder = $BuildManager
	builder._set_build_area(true)
	builder.floor = $ProductionRoom
	builder.objects = $ProductionRoom/Objects
	for sample in [["drink_machine",Vector2i(2,1),0],["magic_oven",Vector2i(2,4),0]]:
		GameState.add_furniture(sample[0],1)
		builder.build_selection_state.restore_selection(builder.get_catalog_index_from_build_id(sample[0]),sample[2])
		var object = builder.build_placement_service.place_furniture(sample[0],sample[1])
		assert(object!=null)
		assert(object.get_node("Visual").facility_id==sample[0])
		assert(object.get_node("Collision").polygon.size()==4)
	builder.clear_build_selection()
	$Actors/Player.global_position = $ProductionRoom.to_global($ProductionRoom.grid_to_local(Vector2i(3,3)))
	$Actors/Player/Camera2D.zoom = Vector2.ONE
	print("PRODUCTION_ROOM_OK: facilities installed via placement service in production room")
