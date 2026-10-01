class_name IsometricGrid
extends RefCounted

# 상점과 원정이 같은 바닥 좌표와 화면 비율을 사용한다.
static func project(cell: Vector2, tile_size: Vector2) -> Vector2:
	return Vector2((cell.x - cell.y) * tile_size.x * 0.5,
		(cell.x + cell.y) * tile_size.y * 0.5)

static func unproject(position: Vector2, tile_size: Vector2) -> Vector2:
	return Vector2(position.x / tile_size.x + position.y / tile_size.y,
		position.y / tile_size.y - position.x / tile_size.x)

static func screen_direction(direction: Vector2, tile_size: Vector2) -> Vector2:
	return unproject(direction, tile_size).normalized() if direction != Vector2.ZERO else Vector2.ZERO
