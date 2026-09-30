class_name ShopSpeedController
extends Node


# 상점 씬이 열려 있는 동안 설정의 게임 속도를 Engine.time_scale에 적용한다.
# 씬을 떠날 때(원정, 타이틀) 1배로 되돌려 원정 조작에는 영향이 없다.


func _ready() -> void:
	add_to_group(GameSpeed.LISTENER_GROUP)
	on_game_speed_changed()


func _exit_tree() -> void:
	Engine.time_scale = 1.0


func on_game_speed_changed() -> void:
	Engine.time_scale = GameSpeed.get_current()
