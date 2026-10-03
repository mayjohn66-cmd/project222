class_name VillageStorySettings
extends Resource

@export var giver: String = "sora"
@export var after_request: String = "sora_well_notes"
@export var after_event: String = "village_event:lantern_wayfarer:done"
@export var after_gathering: bool = true
@export var participants: Array[String] = ["naru", "doyun"]
@export var reputation: int = 1
@export var gifts: Array[Dictionary] = []
@export var choices: Array[Dictionary] = []
@export var moments: Array[Dictionary] = []
