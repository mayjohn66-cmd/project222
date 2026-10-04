@tool
extends Node2D
## 문의 종류·회전 값을 담는 노드. 그림은 3D 거울(StoreView3D)이 이 값을 읽어 그린다(2D 그리기는 제거됨).

@export_enum("entrance", "warehouse", "production") var door_kind: String = "entrance"
@export var tile_width: float = 96.0
@export var tile_height: float = 48.0
@export var art_is_frontal: bool = true
@export var door_width: float = 52.0
@export var door_height: float = 110.0
@export var art_scale: float = 1.2
@export var show_outline: bool = false
@export var art_offset: Vector2 = Vector2.ZERO

var rotation_index: int = 0


func set_footprint(_size_x: int, _size_y: int):
	pass


func set_rotation_index(value: int):
	rotation_index = value % 4
