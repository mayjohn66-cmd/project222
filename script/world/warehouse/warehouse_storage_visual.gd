@tool
extends Node2D
## 창고 선반의 칸 크기·회전 값을 담는 노드. 그림은 3D 거울(StoreView3D)이 이 값을 읽어 그린다(2D 그리기는 제거됨).

@export var tile_width: float = 96.0
@export var tile_height: float = 48.0
@export var visual_height: float = 36.0

var footprint_width: int = 2
var footprint_height: int = 1
var rotation_index: int = 0


func set_footprint(width: int, height: int) -> void:
	footprint_width = maxi(width, 1)
	footprint_height = maxi(height, 1)


func set_rotation_index(value: int) -> void:
	rotation_index = posmod(value, 4)
