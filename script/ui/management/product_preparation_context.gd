class_name ProductPreparationContext
extends RefCounted
# Only heard/accepted records enter this index. No future quest or demand forecasts.
static func notes() -> Dictionary:
	var result := {}
	if PlayerProgress.story_beat_days.has("tutorial_step:production:intro") and not PlayerProgress.story_beat_days.has("tutorial_event:produced_bread"):
		_add(result,"camp_bread","첫 제작 · 타블렌에게 배운 현지식 빵")
	for entry in ResidentRequestFlow.SETTINGS.requests + ResidentStoryFlow.SETTINGS.settlement_requests:
		var id := str(entry["id"])
		if ResidentRequestFlow.accepted(id) and not ResidentRequestFlow.done(id):
			_add(result,str(entry.get("item","")),"맡은 부탁 · " + RequestTextData.text("resident_request",id,"title","주민 부탁") + " · 필요 " + str(entry.get("amount",1)) + "개")
	for entry in CommunityRequestFlow.SETTINGS.requests:
		var id := str(entry["id"])
		if CommunityRequestFlow.accepted(id) and not CommunityRequestFlow.done(id):
			_requirements(result,entry,"맡은 부탁 · " + RequestTextData.text("community_request",id,"title","마을 부탁"))
	for entry in PersonalRequestFlow.entries():
		var id := str(entry["id"])
		if PersonalRequestFlow.accepted(id) and not PersonalRequestFlow.done(id): _requirements(result,entry,"맡은 부탁 · " + str(entry["title"]))
	for entry in CraftingPathFlow.SETTINGS.stages:
		var id := str(entry["id"])
		if CraftingPathFlow.accepted(id) and not CraftingPathFlow.done(id): _requirements(result,entry,"시제품 준비 · " + CraftingPathFlow.title(id))
	for kind in ["requests", "events"]:
		for entry in FishingData.entries(kind):
			var id := str(entry["id"])
			if not FishingRecords.accepted(id) or FishingRecords.done(id): continue
			var title := "물가에서 맡은 이야기 · " + str(entry["title"])
			for item in entry.get("items",[]):
				if item.has("group_id"):
					for member in FishingData.group(str(item["group_id"])): _add(result,str(member),title)
				else: _add(result,str(item.get("item_id","")),title)
	for event in StoreEventData.get_all_events():
		var id := str(event["event_id"])
		if not StoreEventData.is_discovered_for_occurrence(id,GameState.total_day): continue
		var occurrence := StoreEventSchedule.occurrence(event,GameState.total_day)
		if GameState.total_day < int(occurrence["discovery_start_day"]) or GameState.total_day > int(occurrence["end_day"]): continue
		if id.begins_with("fish_store_") and not FishingContent.store_available(id): continue
		var moment := StoreEventStory.moment(id,StoreEventStory.phase(event,GameState.total_day))
		if moment.get("cue_items",[]).is_empty(): moment = StoreEventStory.moment(id,"rumor")
		for item in moment.get("cue_items",[]):
			_add(result,str(item),"들은 소문 · " + StoreEventStory.title(event,GameState.total_day) + " · " + StoreEventStory.timing(event,GameState.total_day))
	return result
static func _requirements(result: Dictionary, entry: Dictionary, title: String) -> void:
	for item in entry.get("requirements",[]): _add(result,str(item.get("item","")),title + " · 필요 " + str(item.get("amount",1)) + "개")
static func _add(result: Dictionary, item: String, note: String) -> void:
	if item.is_empty() or not ItemData.has_item(item): return
	if not result.has(item): result[item] = []
	if note not in result[item]: result[item].append(note)
static func source(recipe: Dictionary) -> String:
	var id := str(recipe["recipe_id"])
	for entry in CraftingPathFlow.SETTINGS.stages:
		if entry["recipes"].has(id) and (CraftingPathFlow.accepted(str(entry["id"])) or CraftingPathFlow.done(str(entry["id"]))):
			return str(VillageLifeFlow.resident(str(entry["giver"])).get("name","이웃")) + "에게 배움 · " + CraftingPathFlow.title(str(entry["id"]))
	if id == "camp_bread" and PlayerProgress.story_beat_days.has("tutorial_step:production:intro"): return "타블렌의 첫 제작 안내에서 배움"
	var variant := FishingData.variant(id)
	if not variant.is_empty() and FishingRecords.done(str(variant["base"])):
		return "물가에서 배움 · " + str(FishingData.entry(str(variant["base"])).get("title","제조법"))
	if PlayerProgress.is_recipe_learned(id):
		RecipeUnlockData.ensure_loaded()
		if RecipeUnlockData.by_recipe.has(id): return "배운 제조법 · 관련 두루마리: " + ItemData.get_item_name(str(RecipeUnlockData.by_recipe[id]["scroll_item_id"]))
		return "배운 제조법"
	return "기본으로 사용할 수 있는 제조법"
