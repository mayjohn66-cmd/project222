@tool
extends Node2D
## 진열대의 칸 크기·회전·쌓임 값을 담는 노드. 그림은 3D 거울(StoreView3D)이 이 값을 읽어 그린다(2D 그리기는 제거됨).

@export var tile_width: float = 96.0
@export var tile_height: float = 48.0
@export var footprint_x: int = 1:
	set(value):
		footprint_x = max(1, value)

@export var footprint_y: int = 1:
	set(value):
		footprint_y = max(1, value)

@export var furniture_height: float = 22.0

var stack_level: int = 1
var rotation_index: int = 0


func set_footprint(size_x: int, size_y: int):
	footprint_x = max(1, size_x)
	footprint_y = max(1, size_y)


func set_stack_level(value: int):
	stack_level = clampi(value, 1, 3)


func set_rotation_index(value: int):
	rotation_index = posmod(value, 4)


# 칸 좌표(x, y)를 이 노드 기준 화면 좌표로(상호작용 거리 계산 등에서 쓴다).
func grid_point(x: float, y: float) -> Vector2:
	return Vector2(
		(x - y) * tile_width * 0.5,
		(x + y) * tile_height * 0.5
	)
