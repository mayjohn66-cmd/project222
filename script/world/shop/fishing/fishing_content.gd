class_name FishingContent
extends RefCounted
static func known_npc(id: String) -> bool:
	if id == "player": return true
	if id in ["neighbor_bread", "gatherer_herbs", "child_berries", "healer_moss", "miner_ore"]:
		return PlayerProgress.story_beat_days.has("resident_request:" + id + ":accepted") or PlayerProgress.story_beat_days.has("resident_request:" + id + ":done")
	if id == "naru" and OpeningJourneyFlow.traded(): return true
	var kind := str(FishingData.data().get("npc_types", {}).get(id, ""))
	return not kind.is_empty() and (PlayerProgress.story_beat_days.has("resident_story:met:" + kind) or int(PlayerProgress.story_beat_days.get("village_life:friendship:" + id, 0)) > 0)
static func conditions(entry: Dictionary, hour: float, weather: String) -> bool:
	if not bool(FishingData.data()["settings"].get("enabled",true)): return false
	for c in entry.get("requires", {}).get("all", []):
		var ok := false
		var id := str(c.get("id", ""))
		match str(c.get("kind", "")):
			"core_tutorial_complete": ok = OpeningJourneyFlow.core_finished()
			"raw_material_sale_recorded": ok = PlayerProgress.story_beat_days.has(OpeningJourneyFlow.RAW_SALE) or OpeningJourneyFlow.legacy_finished()
			"known_npc": ok = known_npc(id)
			"content_completed": ok = FishingRecords.done(id)
			"known_recipe": ok = PlayerProgress.is_recipe_learned(id) if id.begins_with("recipe_fish_") else RecipeUnlockData.is_recipe_available(id)
			"product_collected": ok = FishingRecords.has("collected:" + id)
			"production_room_ready": ok = ShopSpaceProgression.room_ready("production")
			"season": ok = CalendarData.get_season_id(GameState.total_day) == str(c["value"])
			"time": ok = EmployeeData.get_period_at_hour(int(hour)) == str(c["value"])
			"weather": ok = weather == str(c["value"])
			"distinct_fish_caught": ok = FishingRecords.discovered() >= int(c["amount"])
			"seasonal_fish_discovered": ok = FishingRecords.discovered(true) >= int(c["amount"])
			"fish_discovered": ok = FishingRecords.has("caught:" + id)
			"winter_fish_caught_before":
				for fish in FishingData.group("fish_winter_kept"):
					if FishingRecords.has("caught:" + str(fish)) and int(PlayerProgress.story_beat_days[FishingRecords.PREFIX + "caught:" + str(fish)]) < GameState.total_day: ok = true
		if not ok: return false
	return true
static func location_available(id: String, hour: float, weather: String) -> bool:
	var entry := FishingData.entry(id)
	return not entry.is_empty() and conditions(entry, hour, weather)
static func collection() -> Array:
	var result := []
	for kind in ["progression", "recipes", "requests", "events"]:
		for entry in FishingData.entries(kind):
			var e: Dictionary = entry.duplicate(true)
			e["kind"] = kind
			result.append(e)
	return result
static func available(entry: Dictionary, hour: float, weather: String) -> bool:
	if not bool(FishingData.data()["settings"].get("enabled",true)): return false
	var id := str(entry["id"])
	if FishingRecords.done(id) or (entry["kind"] == "recipes" and PlayerProgress.is_recipe_learned(id)): return false
	if not OpeningJourneyFlow.core_finished() or not known_npc(str(entry.get("npc_id", entry.get("teacher", "player")))): return false
	return FishingRecords.accepted(id) or conditions(entry, hour, weather)
static func action_ready(id: String) -> bool:
	match id:
		"fishing_intro": return FishingRecords.has("observed:fish_bank")
		"fishing_rod": return FishingRecords.has("tool:fishing_rod_wood")
		"fishing_first_catch": return FishingRecords.has("catch")
		"fishing_first_sale": return FishingRecords.has("sale")
		"fishing_keep": return FishingRecords.has("kept")
	if id.begins_with("fish_event_") and id not in ["fish_event_moon", "fish_event_table"]: return FishingRecords.has("observed:" + id)
	return true
static func accept(id: String, hour: float, weather: String) -> bool:
	for e in collection():
		if str(e["id"]) != id or not available(e, hour, weather) or FishingRecords.accepted(id): continue
		FishingRecords.mark(id + ":accepted")
		return true
	return false
static func complete(id: String, choices: Dictionary = {}, moon_choice: String = "keep", meeting_ready: bool = false) -> bool:
	if not FishingRecords.accepted(id) or FishingRecords.done(id) or not action_ready(id): return false
	var entry := FishingData.entry(id)
	if entry.is_empty() or (id == "fish_event_table" and not meeting_ready): return false
	if id == "fish_event_moon":
		if GameState.get_item_count("fish_moon_carp") < 1 or moon_choice not in ["keep", "release"]: return false
		if moon_choice == "release": GameState.remove_item("fish_moon_carp", 1)
		FishingRecords.mark("moon:" + moon_choice)
	else:
		if not FishingService.consume(entry.get("items", []), choices): return false
	if id.begins_with("recipe_fish_"): PlayerProgress.learn_recipe(id)
	FishingRecords.mark(id + ":done")
	# Paid requests pay only after actual delivery, never on introduction or reread.
	if id.begins_with("fish_request_"):
		GameState.add_money(int(entry["reward"]["money"]))
		PlayerProgress.story_beat_days[ResidentRequestFlow.PREFIX + "reputation:" + id] = int(entry["reward"]["reputation"])
	GameState.rebuild_inventory_slots_from_counts()
	return true
static func store_available(id: String, hour: float = 12.0, weather: String = "clear") -> bool:
	if not id.begins_with("fish_store_"): return true
	var entry := FishingData.entry(id)
	if entry.is_empty() or not conditions(entry, hour, weather): return false
	for recipe in entry["known_recipe_gate"]:
		if PlayerProgress.is_recipe_learned(str(recipe)): return true
	return false
static func product_known(item: String) -> bool:
	for recipe in FishingData.entries("recipes"):
		if str(recipe.get("result_item_id", "")) == item: return PlayerProgress.is_recipe_learned(str(recipe["id"]))
	return true
static func instructions(id: String) -> String:
	match id:
		"fishing_intro": return "개울에서 ‘물가 살펴보기’를 눌러 보세요."
		"fishing_rod": return "타블렌에게 가지 2개와 수액 1개를 가져가 낚싯대를 엮으세요."
		"fishing_first_catch": return "물가에서 찌를 던지고 입질이 오면 [E]로 건져 보세요."
		"fishing_first_sale": return "잡은 생선을 진열하여 손님에게 실제로 판매하세요."
		"fishing_keep": return "안내를 들은 뒤 생선을 냉장·냉동함에 넣거나, 생산실에서 말린 생선을 만들어 수령하세요."
	return "받은 부탁은 계절과 날씨가 바뀌어도 계속할 수 있습니다. 날짜가 남은 식품을 준비하세요."
