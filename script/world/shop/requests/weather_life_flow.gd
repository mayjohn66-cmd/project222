class_name WeatherLifeFlow
extends RefCounted
const SETTINGS = preload("res://scenes/shop/requests/default_weather_life.tres")
const PREFIX := "weather_life:"
const JOURNAL_PREFIX := "weather:"

static func event(id: String) -> Dictionary:
	for entry in SETTINGS.events:
		if str(entry["id"]) == id: return entry
	return {}
static func key(id: String, stage: String) -> String: return PREFIX + id + ":" + stage
static func has(id: String, stage: String) -> bool: return PlayerProgress.story_beat_days.has(key(id,stage))
static func day(id: String, stage: String) -> int: return int(PlayerProgress.story_beat_days.get(key(id,stage),-1))
static func title(id: String) -> String: return RequestTextData.text("service_text",id + "_intro","title",id)

static func environment() -> Dictionary:
	var tree := Engine.get_main_loop() as SceneTree
	var manager: Node = tree.root.find_child("DayManager",true,false) if tree != null else null
	var hour := float(GameConfig.DAY_START_HOUR)
	if manager != null: hour = float(manager.current_hour) + float(manager.get_display_minute()) / 60.0
	return {"season":CalendarData.get_season_id(GameState.total_day),"weather":str(WorldWeatherData.forecast(GameState.total_day,hour)["kind"])}

static func phase(id: String) -> String:
	var entry := event(id)
	if entry.is_empty() or not CommunityRequestFlow.board_available() or not ResidentRequestFlow.customer_available(str(entry["type"])): return "locked"
	if has(id,"after"): return "complete"
	if has(id,"done"): return "after" if GameState.total_day >= day(id,"done") + int(entry["days_after"]) else "rest"
	if has(id,"bought"): return "finish" if GameState.total_day >= day(id,"bought") + int(entry["days_after"]) else "rest"
	# Once heard, the promised shopping visit survives weather/season changes.
	if has(id,"intro"): return "visit"
	var recipe := str(entry.get("recipe",""))
	if not recipe.is_empty() and not RecipeUnlockData.is_recipe_available(recipe): return "recipe_locked"
	return "intro" if ExpeditionEnvironment.matches(entry,environment()) else "weather_wait"

static func complete_action(id: String, stage: String) -> bool:
	if phase(id) != stage: return false
	if stage in ["intro","after"]:
		PlayerProgress.record_story_beat(key(id,stage),GameState.total_day)
		return true
	if stage != "finish": return false
	var entry := event(id)
	for gift in entry["gifts"]:
		if not ItemData.has_item(str(gift["item"])) or int(gift["amount"]) <= 0: return false
	PlayerProgress.record_story_beat(key(id,"done"),GameState.total_day)
	PlayerProgress.story_beat_days[ResidentRequestFlow.PREFIX + "reputation:weather/" + id] = maxi(0,int(entry["reputation"]))
	for gift in entry["gifts"]: GameState.add_item(str(gift["item"]),int(gift["amount"]))
	return true

static func record_sale(customer: Node, item: String, amount: int) -> bool:
	var id := str(customer.get_meta("weather_life_id",""))
	var entry := event(id)
	if entry.is_empty() or not customer.purchase_completed or phase(id) != "visit": return false
	if customer.get_customer_type_id() != str(entry["type"]) or item != str(entry["purchase_item"]) or amount < int(entry["purchase_amount"]): return false
	PlayerProgress.record_story_beat(key(id,"bought"),GameState.total_day)
	return true

static func requirements(_id: String) -> String: return ""
static func reward(id: String) -> String:
	var entry := event(id)
	var parts: Array[String] = []
	for gift in entry.get("gifts",[]): parts.append("%s ×%d" % [ItemData.get_item_name(str(gift["item"])),gift["amount"]])
	return " · ".join(parts) + " · 평판 +%d (최초 1회)" % int(entry.get("reputation",0))
static func information(id: String) -> String:
	var entry := event(id)
	if entry.is_empty(): return ""
	var state := phase(id)
	if state == "locked": return "첫 거래와 원재료 판매를 마치고 첫 주민을 정착시키면 이야기가 열려요."
	if state == "recipe_locked": return "현지식 빵 제조법을 배운 뒤 비 오는 날의 이야기를 만날 수 있어요."
	if state == "weather_wait": return str(entry["condition_hint"]) + " 마을 게시판 근처에 들러 보세요."
	if state == "intro": return "날씨를 보고 가게를 찾은 사람이 마을 게시판 근처에서 기다립니다. 가까이 가서 [E]."
	if state == "visit": return "%s ×%d를 진열하고 가게를 열어 주세요.\n실제 결제를 기다립니다. 이야기를 들었다면 날씨가 바뀌어도 기다릴 수 있어요." % [ItemData.get_item_name(str(entry["purchase_item"])),entry["purchase_amount"]]
	if state == "rest": return "오늘의 만남을 기억하고 있어요. 다음 날 이후 이야기가 이어집니다."
	if state == "finish": return "실제로 물품을 산 사람이 게시판 근처로 돌아왔어요. [E]로 이야기를 끝까지 들으면 답례: " + reward(id)
	if state == "after": return "다음 날의 안부를 게시판 근처에서 [E]로 들어 보세요. 추가 답례는 없습니다."
	return RequestTextData.text("service_text",id + "_after","completion") + "\n가게를 찾은 날: %d일차" % day(id,"bought")
