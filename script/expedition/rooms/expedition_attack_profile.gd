class_name ExpeditionAttackProfile
extends Resource

# 장비가 기본 공격을 바꾸는 계약. 별도 스킬/조작을 추가하지 않는다.
enum Method { MELEE, PROJECTILE }
@export var equipment_id: String = ""
@export var display_name: String = "기본 공격"
@export var method: Method = Method.MELEE
@export_range(0.1, 3.0) var cooldown: float = 0.4
@export_range(0.1, 8.0) var reach: float = 1.35
@export_range(10.0, 360.0) var arc_degrees: float = 80.0
@export_range(1, 10) var max_targets: int = 1
@export_range(0.0, 2.0) var knockback: float = 0.0
@export_range(0.0, 1.0) var heal_fraction: float = 0.0
@export_range(1.0, 20.0) var projectile_speed: float = 8.0

