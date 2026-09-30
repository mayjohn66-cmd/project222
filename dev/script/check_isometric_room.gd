extends Node

const GRID = preload("res://script/world/shared/isometric_grid.gd")
var failures: int = 0

func check(ok: bool, caption: String) -> void:
	if ok: print("PASS: ", caption)
	else:
		failures += 1
		push_error(caption)

func _ready() -> void:
	var floor_node = load("res://script/world/shop/floor.gd").new()
	for cell in [Vector2i.ZERO, Vector2i(3, 4), Vector2i(7, 7)]:
		var at: Vector2 = floor_node.grid_to_local(cell)
		check(at.is_equal_approx(GRID.project(Vector2(cell), Vector2(96, 48))), "same shop tile position " + str(cell))
		check(floor_node.local_to_grid(at) == cell, "shop grid round trip " + str(cell))
	floor_node.free()
	var model := ExpeditionRoomModel.new()
	var settings = load("res://scenes/expedition/rooms/default_room_settings.tres")
	model.setup(settings, settings.default_attack, 100, 100, 12, 3, {}, 1, false, "gather")
	model.obstacles.clear()
	for direction in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
		model.player_position = Vector2(4, 4)
		var before := GRID.project(model.player_position, Vector2(96, 48))
		model.step(0.1, GRID.screen_direction(direction, Vector2(96, 48)), false)
		var offset := GRID.project(model.player_position, Vector2(96, 48)) - before
		check(offset.normalized().is_equal_approx(direction), "movement follows screen " + str(direction))
	var view := ExpeditionRoomView.new()
	view.size = Vector2(1152, 648)
	view._layout_board()
	var corners := view._footprint(Rect2(0, 0, 8, 8))
	check(is_equal_approx(corners[1].x - corners[3].x, view.board.size.x), "8x8 diamond fits board width")
	check(is_equal_approx(corners[2].y - corners[0].y, view.board.size.y), "8x8 diamond fits board height")
	check(is_equal_approx(view.board.size.x / view.board.size.y, 2.0), "existing 2:1 floor perspective")
	add_child(view)
	view.set_physics_process(false)
	view.model = model
	for entry in [["move_left", Vector2.LEFT], ["move_right", Vector2.RIGHT], ["move_up", Vector2.UP], ["move_down", Vector2.DOWN]]:
		model.player_position = Vector2(4, 4)
		var before := view._point(model.player_position)
		Input.action_press(entry[0])
		view._physics_process(0.1)
		Input.action_release(entry[0])
		check((view._point(model.player_position) - before).normalized().is_equal_approx(entry[1]), "actual room input " + entry[0])
	view.queue_free()
	print("CHECK_ISOMETRIC_ROOM failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)
