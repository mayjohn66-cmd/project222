class_name ExpeditionContentSettings
extends Resource
@export var enemy_profiles: Array[Dictionary] = []
@export var gathering_encounters: Array[Dictionary] = []
@export var region_profiles: Array[Dictionary] = []

func region_profile(id: String) -> Dictionary:
	for entry in region_profiles:
		if str(entry["id"]) == id: return entry
	return {}

func enemy_profile(id: String) -> Dictionary:
	for entry in enemy_profiles:
		if str(entry["id"]) == id: return entry
	return {}

func gathering(event_id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for entry in gathering_encounters:
		if str(entry["id"]) == event_id:
			for site in entry["sites"]: result.append(site.duplicate(true))
	return result
