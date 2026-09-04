@tool
extends Node2D

@export var tile_width: float = 96.0
@export var tile_height: float = 48.0
@export var height: float = 75.0

var rotation_index: int = 0


func set_footprint(_size_x: int, _size_y: int):
	queue_redraw()


func set_rotation_index(value: int):
	rotation_index = value % 4
	queue_redraw()


func _draw():
	var point_a: Vector2
	var point_b: Vector2

	# 0도 / 180도
	if rotation_index % 2 == 0:
		point_a = Vector2(
			-tile_width * 0.25,
			-tile_height * 0.25
		)

		point_b = Vector2(
			tile_width * 0.25,
			tile_height * 0.25
		)

	# 90도 / 270도
	else:
		point_a = Vector2(
			tile_width * 0.25,
			-tile_height * 0.25
		)

		point_b = Vector2(
			-tile_width * 0.25,
			tile_height * 0.25
		)

	var up := Vector2(0, -height)

	var polygon := PackedVector2Array([
		point_a,
		point_b,
		point_b + up,
		point_a + up
	])

	draw_colored_polygon(
		polygon,
		Color(0.55, 0.35, 0.20)
	)

	var outline := PackedVector2Array([
		point_a,
		point_b,
		point_b + up,
		point_a + up,
		point_a
	])

	draw_polyline(
		outline,
		Color(0.2, 0.15, 0.1),
		2.0
	)
