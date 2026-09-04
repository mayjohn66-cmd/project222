@tool
extends Node2D

@export var tile_width: float = 96.0:
	set(value):
		tile_width = value
		queue_redraw()

@export var tile_height: float = 48.0:
	set(value):
		tile_height = value
		queue_redraw()

@export var footprint_x: int = 2:
	set(value):
		footprint_x = max(1, value)
		queue_redraw()

@export var footprint_y: int = 1:
	set(value):
		footprint_y = max(1, value)
		queue_redraw()

@export var furniture_height: float = 24.0:
	set(value):
		furniture_height = value
		queue_redraw()


func set_footprint(size_x: int, size_y: int):
	footprint_x = max(1, size_x)
	footprint_y = max(1, size_y)
	queue_redraw()


func grid_point(x: float, y: float) -> Vector2:
	return Vector2(
		(x - y) * tile_width * 0.5,
		(x + y) * tile_height * 0.5
	)


func _draw():
	var min_x := -0.5
	var min_y := -0.5

	var max_x := footprint_x - 0.5
	var max_y := footprint_y - 0.5

	var back := grid_point(min_x, min_y)
	var right := grid_point(max_x, min_y)
	var front := grid_point(max_x, max_y)
	var left := grid_point(min_x, max_y)

	var up := Vector2(0, -furniture_height)

	var back_top := back + up
	var right_top := right + up
	var front_top := front + up
	var left_top := left + up

	# 왼쪽 면
	draw_colored_polygon(
		PackedVector2Array([
			left,
			front,
			front_top,
			left_top
		]),
		Color(0.38, 0.40, 0.42)
	)

	# 오른쪽 면
	draw_colored_polygon(
		PackedVector2Array([
			front,
			right,
			right_top,
			front_top
		]),
		Color(0.28, 0.30, 0.32)
	)

	# 윗면
	draw_colored_polygon(
		PackedVector2Array([
			back_top,
			right_top,
			front_top,
			left_top
		]),
		Color(0.58, 0.60, 0.62)
	)
