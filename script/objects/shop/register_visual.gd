@tool
extends Node2D
## 계산대의 칸 크기·회전 값을 담는 노드. 그림은 3D 거울(StoreView3D)이 이 값을 읽어 그린다(2D 그리기는 제거됨).

var rotation_index: int = 0

@export var tile_width: float = 96.0
@export var tile_height: float = 48.0
@export var footprint_x: int = 2:
	set(value):
		footprint_x = max(1, value)

@export var footprint_y: int = 1:
	set(value):
		footprint_y = max(1, value)

@export var furniture_height: float = 24.0


func set_rotation_index(value: int) -> void:
	rotation_index = posmod(value, 4)


func set_footprint(size_x: int, size_y: int):
	footprint_x = max(1, size_x)
	footprint_y = max(1, size_y)
