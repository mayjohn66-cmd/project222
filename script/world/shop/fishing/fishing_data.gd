class_name FishingData
extends RefCounted
const PATH := "res://data/fishing/fishing_content.json"
static var _data: Dictionary = {}
static func data() -> Dictionary:
	if _data.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		if parsed is Dictionary: _data = parsed
	return _data
static func entries(kind: String) -> Array:
	return data().get(kind, [])
static func entry(id: String) -> Dictionary:
	for kind in ["locations", "tools", "fish", "goods", "progression", "recipes", "requests", "events", "store_events"]:
		for value in entries(kind):
			if str(value["id"]) == id: return value
	return {}
static func fish(id: String) -> bool:
	return group("fish_any_fresh").has(id)
static func group(id: String) -> Array:
	return data().get("ingredient_groups", {}).get(id, [])
static func variant(id: String) -> Dictionary:
	return data().get("recipe_variants", {}).get(id, {})
static func recipe_name(recipe: Dictionary) -> String:
	var value := ItemData.get_item_name(str(recipe.get("result_item_id", "")))
	var choice := str(variant(str(recipe.get("recipe_id", ""))).get("fish", ""))
	return value + (" · " + ItemData.get_item_name(choice) if not choice.is_empty() else "")
