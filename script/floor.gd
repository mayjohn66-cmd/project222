@tool
extends Node2D

@export var columns: int = 10:
	set(value):
		columns = value
		queue_redraw()

@export var rows: int = 8:
	set(value):
		rows = value
		queue_redraw()

@export var tile_width: float = 96.0:
	set(value):
		tile_width = value
		queue_redraw()

@export var tile_height: float = 48.0:
	set(value):
		tile_height = value
		queue_redraw()


func _draw():
	for row in range(rows):
		for column in range(columns):
			var center := Vector2(
				(column - row) * tile_width * 0.5,
				(column + row) * tile_height * 0.5
			)

			var diamond := PackedVector2Array([
				center + Vector2(0, -tile_height * 0.5),
				center + Vector2(tile_width * 0.5, 0),
				center + Vector2(0, tile_height * 0.5),
				center + Vector2(-tile_width * 0.5, 0)
			])

			draw_colored_polygon(
				diamond,
				Color(0.35, 0.38, 0.35)
			)

			var outline := PackedVector2Array([
				diamond[0],
				diamond[1],
				diamond[2],
				diamond[3],
				diamond[0]
			])

			draw_polyline(
				outline,
				Color(0.6, 0.6, 0.6),
				1.0
			)


func grid_to_local(cell: Vector2i) -> Vector2:
	return Vector2(
		(cell.x - cell.y) * tile_width * 0.5,
		(cell.x + cell.y) * tile_height * 0.5
	)

func local_to_grid(pos: Vector2) -> Vector2i:
	var column := pos.x / tile_width + pos.y / tile_height
	var row := pos.y / tile_height - pos.x / tile_width

	return Vector2i(
		roundi(column),
		roundi(row)
	)


func is_cell_inside(cell: Vector2i) -> bool:
	return (
		cell.x >= 0
		and cell.x < columns
		and cell.y >= 0
		and cell.y < rows
	)
