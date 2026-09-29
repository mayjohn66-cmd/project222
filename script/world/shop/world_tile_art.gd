@tool
extends RefCounted

const WOOD = preload("res://art/world/cozy_v3/wood.png")
const GRASS = preload("res://art/world/cozy_v3/grass.png")
const PAVING = preload("res://art/world/cozy_v3/paving.png")
const ROAD = preload("res://art/world/cozy_v3/road.png")

static func draw_cell(canvas: CanvasItem, center: Vector2, width: float, height: float, texture: Texture2D) -> void:
	var points := PackedVector2Array([
		center + Vector2(0, -height * 0.5),
		center + Vector2(width * 0.5, 0),
		center + Vector2(0, height * 0.5),
		center + Vector2(-width * 0.5, 0)])
	# One material patch spans 2x2 cells, so its pixel clusters remain readable.
	var column: int = roundi(center.x / width + center.y / height)
	var row: int = roundi(center.y / height - center.x / width)
	var uv_origin := Vector2(posmod(column, 2), posmod(row, 2)) * 0.5
	canvas.draw_polygon(points, PackedColorArray([Color.WHITE]),
		PackedVector2Array([uv_origin, uv_origin + Vector2(0.5, 0), uv_origin + Vector2(0.5, 0.5), uv_origin + Vector2(0, 0.5)]), texture)
