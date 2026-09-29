class_name FurnitureFootprint
extends RefCounted

static func polygon(size: Vector2i, depth: float, rotation: int, tile: Vector2) -> PackedVector2Array:
	var lo := Vector2(-0.5,-0.5)
	var hi := Vector2(size) - Vector2(0.5,0.5)
	# The solid occupies one edge-aligned half, not a strip centered in the tile.
	if depth < 1.0:
		match posmod(rotation,4):
			0: hi.y = lo.y + depth
			1: hi.x = lo.x + depth
			2: lo.y = hi.y - depth
			3: lo.x = hi.x - depth
	var result := PackedVector2Array()
	for p in [lo,Vector2(hi.x,lo.y),hi,Vector2(lo.x,hi.y)]:
		result.append(Vector2((p.x-p.y)*tile.x*0.5,(p.x+p.y)*tile.y*0.5))
	return result
