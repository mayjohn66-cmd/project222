extends Node2D

## Diagnostic grid drawn above world objects, using the same cell geometry as
## world_tile_art.gd. It does not change the terrain or collision shapes.
var terrain

func _draw() -> void:
	if terrain == null:
		return
	var outlined: Dictionary = {}
	for cell in terrain.get_connected_map_cells():
		if outlined.has(cell):
			continue
		outlined[cell] = true
		var center: Vector2 = terrain.grid_to_local(cell)
		var half_width: float = terrain.tile_width * 0.5
		var half_height: float = terrain.tile_height * 0.5
		var outline := PackedVector2Array([
			center + Vector2(0, -half_height),
			center + Vector2(half_width, 0),
			center + Vector2(0, half_height),
			center + Vector2(-half_width, 0),
			center + Vector2(0, -half_height)
		])
		draw_polyline(outline, Color(0.02, 0.13, 0.15, 0.55), 3.0, true)
		draw_polyline(outline, Color(0.37, 0.95, 0.88, 0.82), 1.5, true)
