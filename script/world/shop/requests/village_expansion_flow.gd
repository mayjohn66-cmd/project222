class_name VillageExpansionFlow
extends RefCounted

const SETTINGS = preload("res://scenes/shop/requests/default_village_expansion.tres")
const PREFIX := "village_expansion:"
const JOURNAL_PREFIX := "expansion:"

static func event(id: String) -> Dictionary:
	for entry in SETTINGS.events:
		if str(entry["id"]) == id: return entry
	return {}
static func key(id: String, suffix: String, cycle: int = -1) -> String:
	return PREFIX + id + ":" + (str(cycle) + ":" if cycle >= 0 else "") + suffix
static func done(id: String) -> bool: return PlayerProgress.story_beat_days.has(key(id,"last_done"))
static func accepted(id: String) -> bool: return PlayerProgress.story_beat_days.has(key(id,"active"))
static func cycle(id: String) -> int:
	return int(PlayerProgress.story_beat_days.get(key(id,"active"),next_cycle(id)))
static func next_cycle(id: String) -> int:
	var entry := event(id)
	if entry.get("repeat", "") == "annual": return CalendarData.get_year(GameState.total_day)
	return int(PlayerProgress.story_beat_days.get(key(id,"count"),0)) + 1
static func title(id: String) -> String:
	return RequestTextData.text("service_text",str(event(id).get("title_id",id)),"title",id)
static func completed_cycle(id: String) -> bool:
	return PlayerProgress.story_beat_days.has(key(id,"done",next_cycle(id)))
static func step(id: String) -> Dictionary:
	var entry := event(id)
	if entry.is_empty() or not accepted(id): return {}
	var index := int(PlayerProgress.story_beat_days.get(key(id,"step",cycle(id)),0))
	if index < 0 or index >= entry["steps"].size(): return {}
	var result: Dictionary = entry["steps"][index].duplicate(true)
	result.merge({"event":id,"cycle":cycle(id),"index":index})
	return result
static func resident_entry(id: String) -> Dictionary:
	for entry in SETTINGS.residents:
		if str(entry["id"]) == id: return entry
	return {}
static func locked_reason(id: String) -> String:
	var entry := event(id)
	if entry.is_empty(): return "이야기를 찾을 수 없습니다."
	if not CommunityRequestFlow.board_available(): return "첫 거래와 주민 정착 뒤 게시판에서 이어집니다."
	if accepted(id): return ""
	if str(entry.get("repeat", "")).is_empty() and done(id): return "이미 함께 마친 이야기입니다."
	if entry.get("repeat", "") == "annual" and completed_cycle(id): return "올해의 이야기를 마쳤습니다. 내년에 다시 만나요."
	var last_day := -1
	for previous in entry.get("after_regular", []):
		if not RegularCustomerRecords.has(str(previous),"after"): return "가게를 찾은 단골과 구매 뒤 이야기를 먼저 나눠 주세요."
		last_day = maxi(last_day,RegularCustomerRecords.day(str(previous),"after"))
	for previous in entry.get("after_contact", []):
		if not ExpeditionContactFlow.has(str(previous),"after"): return "원정에서 만난 손님의 가게 구매와 후일담을 먼저 마쳐 주세요."
		last_day = maxi(last_day,ExpeditionContactFlow.day(str(previous),"after"))
	for previous in entry.get("after", []):
		if not done(str(previous)): return "앞선 이야기 '%s'을 먼저 마쳐 주세요." % title(str(previous))
		last_day = maxi(last_day,int(PlayerProgress.story_beat_days[key(str(previous),"last_done")]))
	for previous in entry.get("after_personal", []):
		if not PersonalRequestFlow.done(str(previous)): return "앞선 개인 부탁을 먼저 마쳐 주세요."
		last_day = maxi(last_day,int(PlayerProgress.story_beat_days[PersonalRequestFlow.PREFIX + str(previous) + ":done"]))
	for previous in entry.get("after_craft", []):
		if not CraftingPathFlow.done(str(previous)): return "이웃과 제품 만들기의 시제품을 먼저 나눠 주세요."
		last_day = maxi(last_day,int(PlayerProgress.story_beat_days[CraftingPathFlow.key(str(previous),"done")]))
	for resident in entry.get("neighbors", ["naru","doyun","sora"]):
		if not VillageLifeFlow.available(VillageLifeFlow.resident(str(resident))): return "함께할 이웃의 정착을 기다립니다."
	for resident in entry.get("friendship", {}):
		if VillageLifeFlow.friendship(str(resident)) < int(entry["friendship"][resident]): return "%s와 안부를 더 나눠 주세요." % VillageLifeFlow.resident(str(resident))["name"]
	for recipe in entry.get("recipes", []):
		if not RecipeUnlockData.is_recipe_available(str(recipe)): return "%s 제조법을 먼저 배워 주세요." % ItemData.get_item_name(str(recipe))
	if last_day >= 0 and GameState.total_day < last_day + int(entry.get("days_after",1)): return "앞선 이야기를 마친 다음 날 다시 살펴보세요."
	if GameState.total_day < int(entry.get("minimum_day",1)): return "가게에서 계절을 조금 더 보내면 이야기가 이어집니다."
	if entry.has("anniversary"):
		var opened := int(PlayerProgress.story_beat_days.get(CheckoutTutorial.BEAT_ID,GameState.total_day))
		if GameState.total_day < opened + int(entry["anniversary"]) * next_cycle(id): return "첫 거래를 기념하는 날을 기다립니다."
	if done(id) and entry.get("repeat", "") == "cooldown":
		if GameState.total_day < int(PlayerProgress.story_beat_days[key(id,"last_done")]) + int(entry["cooldown"]): return "지난 주문을 전한 뒤 조금 쉬었다가 다시 찾아오세요."
	var season := str(entry.get("season", ""))
	if not season.is_empty() and CalendarData.get_season_id(GameState.total_day) != season: return "이 이야기는 %s에 시작할 수 있어요." % {"spring":"봄","summer":"여름","autumn":"가을","winter":"겨울"}.get(season,season)
	if entry.has("start_day"):
		var day := CalendarData.get_day_of_season(GameState.total_day)
		if day < int(entry["start_day"]) or day > int(entry["end_day"]): return "기념일이 가까워지면 게시판에 다시 소식이 올라옵니다."
	return ""
static func accept(id: String) -> bool:
	if accepted(id) or not locked_reason(id).is_empty(): return false
	var entry := event(id)
	if entry.get("steps", []).is_empty(): return false
	var c := next_cycle(id)
	PlayerProgress.story_beat_days[key(id,"active")] = c
	PlayerProgress.record_story_beat(key(id,"accepted",c),GameState.total_day)
	return true
static func step_reason(id: String, hour: int = -1) -> String:
	var current := step(id)
	if current.is_empty(): return "게시판에서 이야기를 맡아 주세요."
	var previous := int(PlayerProgress.story_beat_days.get(key(id,"advanced",cycle(id)),GameState.total_day))
	if GameState.total_day < previous + int(current.get("wait_days",0)): return "다음 날 이웃에게 이어지는 이야기를 들어 주세요."
	if current.get("mode", "talk") == "gather":
		if CalendarData.get_season_id(GameState.total_day) != str(event(id)["season"]): return "준비는 남아 있습니다. 같은 계절이 돌아오면 함께 모여요."
		var day := CalendarData.get_day_of_season(GameState.total_day)
		if day < SETTINGS.festival_start_day: return "계절 모임 날이 가까워지고 있어요. 준비한 물품은 남아 있습니다."
		if day > SETTINGS.festival_end_day: return "이번 모임 철은 지났어요. 준비한 물품은 남아 있으며 다음 같은 계절에 모일 수 있어요."
		if hour >= 0 and (hour < int(current["start_hour"]) or hour >= int(current["end_hour"])): return "모임은 %d~%d시에 열립니다." % [current["start_hour"],current["end_hour"]]
	if current.has("region") and not PlayerProgress.story_beat_days.has(key(id,"discovered",cycle(id))): return "%s 원정에서 %s을 직접 채집한 뒤 돌아와 주세요." % [ExpeditionMapData.get_region_data(str(current["region"])).get("name",current["region"]),ItemData.get_item_name(str(current["discover_item"]))]
	for item in CommunityRequestFlow.required_items(current):
		if not ItemData.has_item(item) or GameState.get_item_count(item) < int(CommunityRequestFlow.required_items(current)[item]): return "보통 창고에 완제품이나 재료를 준비해 주세요."
	if current.get("mode", "") == "produce":
		for item in CommunityRequestFlow.required_items(current):
			if int(PlayerProgress.story_beat_days.get(key(id,"made:" + item,cycle(id)),0)) < int(CommunityRequestFlow.required_items(current)[item]): return "소개 뒤 실제로 제작하고 수령한 상품이 필요합니다."
	return ""
static func complete(action: Dictionary, hour: int = -1) -> bool:
	var id := str(action.get("event", ""))
	if action.is_empty() or action != step(id) or not step_reason(id,hour).is_empty(): return false
	for recipe in action.get("teach", []):
		if ProductRecipeData.get_recipe(str(recipe)).is_empty(): return false
	for gift in event(id).get("gifts", []):
		if not ItemData.has_item(str(gift["item"])) or int(gift["amount"]) <= 0: return false
	for item in CommunityRequestFlow.required_items(action): GameState.remove_item(item,int(CommunityRequestFlow.required_items(action)[item]))
	for recipe in action.get("teach", []): PlayerProgress.learn_recipe(str(recipe))
	var c := cycle(id)
	PlayerProgress.story_beat_days[key(id,"step",c)] = int(action["index"]) + 1
	PlayerProgress.record_story_beat(key(id,"advanced",c),GameState.total_day)
	if int(action["index"]) + 1 < event(id)["steps"].size(): return true
	var entry := event(id)
	var first := not done(id)
	PlayerProgress.record_story_beat(key(id,"done",c),GameState.total_day)
	PlayerProgress.record_story_beat(key(id,"last_done"),GameState.total_day)
	PlayerProgress.story_beat_days[key(id,"count")] = int(PlayerProgress.story_beat_days.get(key(id,"count"),0)) + 1
	PlayerProgress.story_beat_days.erase(key(id,"active"))
	GameState.add_money(maxi(0,int(entry.get("money",0))))
	for gift in entry.get("gifts", []): GameState.add_item(str(gift["item"]),int(gift["amount"]))
	if first: PlayerProgress.story_beat_days[ResidentRequestFlow.PREFIX + "reputation:expansion/" + id] = int(entry.get("reputation",1))
	return true
static func record_output(item: String, amount: int) -> void:
	if amount <= 0: return
	for entry in SETTINGS.events:
		var id := str(entry["id"])
		var current := step(id)
		if current.get("mode", "") != "produce": continue
		var totals := CommunityRequestFlow.required_items(current)
		if not totals.has(item): continue
		var k := key(id,"made:" + item,cycle(id))
		PlayerProgress.story_beat_days[k] = mini(int(totals[item]),int(PlayerProgress.story_beat_days.get(k,0)) + amount)
static func record_gather(region: String, item: String, amount: int) -> void:
	if region.is_empty() or item.is_empty() or not ItemData.has_item(item) or amount <= 0: return
	for entry in SETTINGS.events:
		var id := str(entry["id"])
		var current := step(id)
		if str(current.get("region", "")) == region and str(current.get("discover_item", "")) == item:
			PlayerProgress.record_story_beat(key(id,"discovered",cycle(id)),GameState.total_day)
static func recipe_ready(recipe: String) -> bool:
	for entry in SETTINGS.events:
		if not entry.get("exclusive_recipes", []).has(recipe): continue
		return PlayerProgress.is_recipe_learned(recipe) and (done(str(entry["id"])) or (accepted(str(entry["id"])) and int(step(str(entry["id"])).get("index",0)) > 0))
	return true
static func unlocked_paths() -> Array[String]:
	var paths: Array[String] = []
	for entry in SETTINGS.events:
		if done(str(entry["id"])):
			for path in entry.get("unlocks", []): paths.append(str(path))
	return paths
static func gathering(hour: int) -> Dictionary:
	for entry in SETTINGS.events:
		var id := str(entry["id"])
		var current := step(id)
		if current.get("mode", "") == "gather" and step_reason(id,hour).is_empty(): return current
	return {}
static func information(id: String) -> String:
	var entry := event(id)
	if entry.is_empty(): return ""
	var text := RequestTextData.text("service_text",str(entry["title_id"]),"summary") + "\n"
	if RequestPaymentText.is_gift(entry): text += RequestPaymentText.notice(entry) + "\n"
	if accepted(id):
		var current := step(id)
		text += "진행 %d/%d · %s\n" % [int(current["index"]) + 1,entry["steps"].size(),RequestTextData.text("service_text",str(current["id"]),"title")]
		for item in CommunityRequestFlow.required_items(current): text += "%s %d/%d · 창고\n" % [ItemData.get_item_name(item),GameState.get_item_count(item),CommunityRequestFlow.required_items(current)[item]]
		if current.has("site"):
			text += "계절 %d~%d일 · %d~%d시\n" % [SETTINGS.festival_start_day,SETTINGS.festival_end_day,current["start_hour"],current["end_hour"]]
			text += "모임 장소에서 이웃들이 도착하면 대화 [E]\n"
		else: text += "%s에게 대화 [E]\n" % VillageLifeFlow.resident(str(current["resident"])).get("name",current["resident"])
		text += step_reason(id)
	else:
		if done(id):
			text += "함께 마친 날: %d일차 · %d회\n" % [PlayerProgress.story_beat_days[key(id,"last_done")],PlayerProgress.story_beat_days.get(key(id,"count"),1)]
			text += RequestTextData.text("service_text",str(entry["steps"].back()["id"]),"completion") + "\n"
		text += locked_reason(id)
		if not done(id) and locked_reason(id).is_empty(): text += "게시판에서 이야기를 맡은 뒤 주민에게 이어서 들으세요."
	text += "\n%s마지막 대화 완독 때: %d G · 첫 완료 평판 +%d" % ["답례 · " if RequestPaymentText.is_gift(entry) else "",entry.get("money",0),entry.get("reputation",1)]
	for gift in entry.get("gifts", []): text += " · %s ×%d" % [ItemData.get_item_name(str(gift["item"])),gift["amount"]]
	return text
