class_name StoreEventNextStepGuide
extends RefCounted
## Explain how to prepare an empty clue product; reading never learns or grants it.
const ENABLED := true

static func missing(item: String) -> String:
	if not ENABLED: return ""
	var learned := StoreEventPreparation.recipes(item)
	if not learned.is_empty():
		var opening := ProductNextStepGuidance.opening()
		if not opening.is_empty(): return opening
		if ShopSpaceProgression.active() and not ShopSpaceProgression.room_ready("production"):
			return UiText.t("store.preparation.production_room")
		return UiText.t("store.preparation.learned")
	RecipeUnlockData.ensure_loaded()
	ProductRecipeData.ensure_loaded()
	var craftable := false
	for recipe in ProductRecipeData.recipes.values():
		if str(recipe["result_item_id"]) != item: continue
		craftable = true
		var id := str(recipe["recipe_id"])
		var scroll := str(RecipeUnlockData.by_recipe.get(id,{}).get("scroll_item_id",""))
		if not PlayerProgress.is_recipe_learned(id) and not scroll.is_empty() and GameState.get_item_count(scroll) > 0:
			return UiText.f("store.preparation.owned_scroll",[ItemData.get_item_name(scroll)])
	return UiText.t("store.preparation.unavailable") if craftable else ""
