class_name LanternWayfarerSettings
extends Resource

@export var prerequisite: String = "path_light"
@export var site_path: String = "VillageGathering/MarketLantern"
@export var fallback_path: String = "VillageGathering/VillageNoticeboard"
@export var start_hour: int = 18
@export var end_hour: int = 6
@export var return_days: int = 1
@export var interaction_distance: float = 72.0
@export var npc_name: String = "불빛을 따라온 길손"
@export var customer_type: String = "backpacker"
@export var customer_group: String = "traveler"
@export var reputation: int = 1
@export var gifts: Array[Dictionary] = []
@export var choices: Array[Dictionary] = []
@export var moments: Array[Dictionary] = []
