class_name VillageLifeSettings
extends Resource

@export var residents: Array[Dictionary] = []
@export var friendship_thresholds: PackedInt32Array = PackedInt32Array([1, 3, 7])
@export var friendship_names: PackedStringArray = PackedStringArray(["알아가는 이웃", "반가운 이웃", "가까운 이웃"])
@export var well_item: String = "water"
@export var well_amount: int = 1
@export var interaction_distance: float = 64.0
@export var walk_speed: float = 70.0
@export var resident_radius: float = 12.0
@export var route_retry_seconds: float = 3.0
