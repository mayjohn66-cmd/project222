@tool
extends Node2D
## 제작 시설의 종류·칸 크기·회전 값을 담는 노드. 그림은 3D 거울(StoreView3D)이 이 값을 읽어 그린다(2D 그리기는 제거됨).

var facility_id: String = "drink_machine"
var footprint := Vector2i.ONE
var rotation_index: int = 0


func set_footprint(x: int, y: int) -> void:
	footprint = Vector2i(x, y)


func set_rotation_index(value: int) -> void:
	rotation_index = posmod(value, 4)


func configure(id: String) -> void:
	facility_id = id
