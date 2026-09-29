@tool
extends RefCounted

# 이미지가 없으면 null이 되고, draw_cell이 단색 칸으로 대신 그린다.
static var WOOD: Texture2D = ArtLoader.load_texture("res://art/world/cozy_v3/wood.png")
static var GRASS: Texture2D = ArtLoader.load_texture("res://art/world/cozy_v3/grass.png")
static var PAVING: Texture2D = ArtLoader.load_texture("res://art/world/cozy_v3/paving.png")
static var ROAD: Texture2D = ArtLoader.load_texture("res://art/world/cozy_v3/road.png")

const FALLBACK_COLOR := Color(0.45, 0.4, 0.35)

static func draw_cell(canvas: CanvasItem, center: Vector2, width: float, height: float, texture: Texture2D) -> void:
	var points := PackedVector2Array([
		center + Vector2(0, -height * 0.5),
		center + Vector2(width * 0.5, 0),
		center + Vector2(0, height * 0.5),
		center + Vector2(-width * 0.5, 0)])
	if texture == null:
		canvas.draw_polygon(points, PackedColorArray([FALLBACK_COLOR]))
		return
	# One material patch spans 2x2 cells, so its pixel clusters remain readable.
	var column: int = roundi(center.x / width + center.y / height)
	var row: int = roundi(center.y / height - center.x / width)
	var uv_origin := Vector2(posmod(column, 2), posmod(row, 2)) * 0.5
	canvas.draw_polygon(points, PackedColorArray([Color.WHITE]),
		PackedVector2Array([uv_origin, uv_origin + Vector2(0.5, 0), uv_origin + Vector2(0.5, 0.5), uv_origin + Vector2(0, 0.5)]), texture)
