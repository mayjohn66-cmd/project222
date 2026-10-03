class_name VillageSmithyFlow
extends RefCounted

const SITE := "VillageBlacksmith/Smithy"
const INTERACTION_DISTANCE := 112.0
const REQUEST_ID := "open_smithy"

static func available() -> bool:
	return CommunityRequestFlow.board_available() and CommunityRequestFlow.done(REQUEST_ID)

static func recipes() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for recipe in RecipeData.get_all_recipes():
		var entry := recipe.duplicate(true)
		entry["id"] = str(recipe["recipe_id"])
		entry["title"] = ItemData.get_item_name(str(recipe["result_item_id"]))
		result.append(entry)
	return result

static func blocked_reason(id: String) -> String:
	if not available(): return "대장간을 여는 공동 부탁을 먼저 완료하세요."
	if not RecipeData.has_recipe(id): return "제작법을 확인할 수 없습니다."
	if not RecipeUnlockData.is_recipe_available(id): return "원정에서 제작 두루마리를 얻어 먼저 배우세요."
	if not RecipeData.can_craft(id): return "창고에 필요한 재료가 부족합니다."
	return ""

static func craft(id: String) -> Dictionary:
	if not blocked_reason(id).is_empty(): return {}
	var recipe := RecipeData.get_recipe(id)
	if not RecipeData.craft(id): return {}
	return {"item":str(recipe["result_item_id"]), "amount":int(recipe["result_amount"])}
