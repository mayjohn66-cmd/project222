class_name ActFourFlow
extends RefCounted

const SETTINGS = preload("res://scenes/shop/requests/default_act_four.tres")
const PREFIX := "act4:"
const JOURNAL_PREFIX := "act4:"

static func started() -> bool:
	return VillageExpansionFlow.done("chapter_winter_lights") or VillageExpansionFlow.done("chapter_home_again")
static func event(id: String) -> Dictionary:
	for entry in SETTINGS.events:
		if str(entry["id"]) == id: return entry
	return {}
static func key(id: String, suffix: String, cycle: int = -1) -> String:
	return PREFIX + id + ":" + (str(cycle) + ":" if cycle >= 0 else "") + suffix
static func done(id: String) -> bool: return PlayerProgress.story_beat_days.has(key(id,"last_done"))
static func accepted(id: String) -> bool: return PlayerProgress.story_beat_days.has(key(id,"active"))
static func season_cycle() -> int: return floori(float(maxi(1,GameState.total_day) - 1) / CalendarData.DAYS_PER_SEASON)
static func next_cycle(id: String) -> int:
	if event(id).get("repeat","") == "seasonal": return season_cycle()
	return int(PlayerProgress.story_beat_days.get(key(id,"count"),0)) + 1
static func cycle(id: String) -> int: return int(PlayerProgress.story_beat_days.get(key(id,"active"),next_cycle(id)))
static func title(id: String) -> String:
	return RequestTextData.text("service_text",str(event(id).get("title_id",id)),"title",id)
static func step(id: String) -> Dictionary:
	var entry := event(id)
	if entry.is_empty() or not accepted(id): return {}
	var index := int(PlayerProgress.story_beat_days.get(key(id,"step",cycle(id)),0))
	if index < 0 or index >= entry["steps"].size(): return {}
	var result: Dictionary = entry["steps"][index].duplicate(true)
	result.merge({"event":id,"cycle":cycle(id),"index":index})
	return result

## 시작 전에 전체 단계와 경제 수치를 검사한다. 미확정 수치는 무료 조건으로 바꾸지 않는다.
static func configuration_issues(id: String) -> Array[String]:
	var entry := event(id)
	var issues: Array[String] = []
	if entry.is_empty(): return ["event"]
	if entry.get("steps",[]).is_empty(): issues.append("steps")
	for field in ["money","reputation","minimum_reputation","minimum_ruins"]:
		if entry.has(field) and (entry[field] == null or not (entry[field] is int) or int(entry[field]) < 0): issues.append(field)
	for current in entry.get("steps",[]):
		if RequestTextData.entry("service_text",str(current.get("id",""))).is_empty(): issues.append(str(current.get("id","")) + ":text")
		for field in ["requirements","furniture","sales"]:
			for requirement in current.get(field,[]):
				var item := str(requirement.get("item",""))
				var known := FurnitureData.has_furniture(item) if field == "furniture" else ItemData.has_item(item)
				if not known or requirement.get("amount") == null or not (requirement["amount"] is int) or int(requirement["amount"]) <= 0:
					issues.append(str(current["id"]) + ":" + field + ":" + item)
	return issues

static func locked_reason(id: String) -> String:
	var entry := event(id)
	if entry.is_empty(): return "이야기를 찾을 수 없습니다."
	if not started(): return "마을의 첫 겨울 이야기를 마치면 이어집니다."
	if not CommunityRequestFlow.board_available(): return "마을 게시판이 필요합니다."
	if not configuration_issues(id).is_empty(): return "이 이야기의 다음 소식을 기다리고 있어요."
	if accepted(id): return ""
	if done(id) and str(entry.get("repeat","")).is_empty(): return "함께 마친 이야기입니다."
	var last_day := -1
	for previous in entry.get("after",[]):
		if not done(str(previous)): return "앞선 이야기 '%s'을 먼저 마쳐 주세요." % title(str(previous))
		last_day = maxi(last_day,int(PlayerProgress.story_beat_days[key(str(previous),"last_done")]))
	if last_day >= 0 and GameState.total_day < last_day + int(entry.get("days_after",0)): return "앞선 이야기 다음 날 다시 살펴보세요."
	if entry.get("need_rest",false) and not VillageRestFlow.completed(): return "길목 쉼터의 첫 모임을 먼저 마쳐 주세요."
	if entry.get("need_lantern",false) and not LanternWayfarerFlow.completed(): return "등불을 따라온 길손의 이야기를 먼저 마쳐 주세요."
	if ResidentRequestFlow.reputation() < int(entry.get("minimum_reputation",0)): return "이웃들과 부탁을 더 나누며 평판을 쌓아 주세요."
	if GameState.total_day < int(entry.get("minimum_day",1)): return "첫 해가 지나며 이야기가 이어집니다."
	if entry.get("discovery","") != "" and not ActFourRecords.found(str(entry["discovery"])): return "유적에서 낡은 물건을 직접 찾아 돌아와 주세요."
	if entry.get("need_power",false) and not PowerRepairFlow.powered(): return "계산대의 마석 개조를 먼저 마쳐 주세요."
	if entry.get("need_merchant",false) and ActFourRecords.merchant_visits() < 2: return "심야 상인이 다시 찾아오면 이야기가 이어집니다."
	if ActFourRecords.ruins_runs() < int(entry.get("minimum_ruins",0)): return "유적의 흔적을 조금 더 살펴보고 돌아와 주세요."
	if entry.get("season_change",false) and not done(id) and last_day >= 0 and floori(float(last_day - 1) / CalendarData.DAYS_PER_SEASON) >= season_cycle(): return "계절이 바뀌면 길이 모이는 날을 준비할 수 있어요."
	if done(id) and entry.get("repeat","") == "cooldown" and GameState.total_day < int(PlayerProgress.story_beat_days[key(id,"last_done")]) + CalendarData.DAYS_PER_WEEK: return "지난 주문을 전한 뒤 한 주 쉬었다가 다시 찾아오세요."
	if entry.get("repeat","") == "seasonal":
		if PlayerProgress.story_beat_days.has(key(id,"done",next_cycle(id))): return "이번 계절의 장터를 마쳤습니다. 다음 계절에 만나요."
		if not market_window(): return "장터 준비 철이 되면 다시 살펴보세요."
	return ""

static func accept(id: String) -> bool:
	if accepted(id) or not locked_reason(id).is_empty(): return false
	var c := next_cycle(id)
	PlayerProgress.story_beat_days[key(id,"active")] = c
	PlayerProgress.record_story_beat(key(id,"advanced",c),GameState.total_day)
	return true
static func step_reason(id: String) -> String:
	var current := step(id)
	if current.is_empty(): return "게시판에서 이야기를 맡아 주세요."
	if not started() or not configuration_issues(id).is_empty(): return "이 이야기의 다음 소식을 기다리고 있어요."
	var previous := int(PlayerProgress.story_beat_days.get(key(id,"advanced",cycle(id)),GameState.total_day))
	if GameState.total_day < previous + int(current.get("wait_days",0)): return "다음 날 이어지는 이야기를 들어 주세요."
	if current.get("market",false) and not market_window(): return "장터 준비는 남아 있습니다. 다음 장터 철에 이어갈 수 있어요."
	for requirement in current.get("requirements",[]):
		if GameState.get_item_count(str(requirement["item"])) < int(requirement["amount"]): return "보통 창고에 전달할 물품을 준비해 주세요."
	for requirement in current.get("furniture",[]):
		var item := str(requirement["item"])
		if GameState.get_furniture_count(item) < int(requirement["amount"]): return "가구 창고에 전달할 집기를 준비해 주세요."
		if int(PlayerProgress.story_beat_days.get(key(id,"made:" + item,cycle(id)),0)) < int(requirement["amount"]): return "소개를 들은 뒤 집기를 직접 제작해 주세요."
	for item in current.get("show",[]):
		if GameState.get_item_count(str(item)) <= 0: return "살펴볼 물건을 보통 창고에 가져와 주세요. 물건은 소비하지 않습니다."
	for requirement in current.get("sales",[]):
		if int(PlayerProgress.story_beat_days.get(key(id,"sold:" + str(requirement["item"]),cycle(id)),0)) < int(requirement["amount"]): return "안내 뒤 해당 물품을 진열하고 손님의 실제 결제를 받아 주세요."
	if current.get("map_purchase",false) and not PlayerProgress.story_beat_days.has(key(id,"bought_map",cycle(id))): return "안내 뒤 심야 상인이 두 번째 이상 찾아온 밤에 보물 지도를 직접 구매해 주세요."
	if current.get("ruins_run",false) and not PlayerProgress.story_beat_days.has(key(id,"returned",cycle(id))): return "안내 뒤 보물 지도로 유적을 탐험하고 정산을 마쳐 주세요."
	return ""

static func complete(action: Dictionary) -> bool:
	var id := str(action.get("event",""))
	if action.is_empty() or action != step(id) or not step_reason(id).is_empty(): return false
	# 위에서 수량/보유량을 모두 검증한 뒤 한 번만 소비한다. 'show'는 검사만 한다.
	for requirement in action.get("requirements",[]): GameState.remove_item(str(requirement["item"]),int(requirement["amount"]))
	for requirement in action.get("furniture",[]): GameState.remove_furniture(str(requirement["item"]),int(requirement["amount"]))
	var c := cycle(id)
	PlayerProgress.story_beat_days[key(id,"step",c)] = int(action["index"]) + 1
	PlayerProgress.record_story_beat(key(id,"advanced",c),GameState.total_day)
	if int(action["index"]) + 1 < event(id)["steps"].size(): return true
	var first := not done(id)
	PlayerProgress.record_story_beat(key(id,"done",c),GameState.total_day)
	if event(id).get("repeat","") == "seasonal": PlayerProgress.record_story_beat(key(id,"done",season_cycle()),GameState.total_day)
	PlayerProgress.record_story_beat(key(id,"last_done"),GameState.total_day)
	PlayerProgress.story_beat_days[key(id,"count")] = int(PlayerProgress.story_beat_days.get(key(id,"count"),0)) + 1
	PlayerProgress.story_beat_days.erase(key(id,"active"))
	GameState.add_money(int(event(id).get("money",0)))
	if first: PlayerProgress.story_beat_days[ResidentRequestFlow.PREFIX + "reputation:act4/" + id] = int(event(id).get("reputation",0))
	return true

static func milestone_complete(entry: Dictionary) -> bool:
	for id in entry["events"]:
		if not done(str(id)): return false
	return true
static func milestone_count() -> int:
	var count := 0
	for entry in SETTINGS.milestones:
		if not milestone_complete(entry): break
		count += 1
	return count
static func clues() -> Array[String]:
	var result: Array[String] = []
	for entry in SETTINGS.events:
		if entry.get("clue_id","") != "" and done(str(entry["id"])):
			result.append(RequestTextData.text("service_text",str(entry["clue_id"]),"summary","남겨 둔 질문"))
	return result
static func current_goal() -> String:
	for entry in SETTINGS.events:
		var id := str(entry["id"])
		if entry["branch"] != "A" or done(id): continue
		if accepted(id): return title(id) + " · " + ("이야기 이어 듣기 [E]" if step_reason(id).is_empty() else step_reason(id))
		return title(id) + " · " + ("게시판에서 이야기 맡기" if locked_reason(id).is_empty() else locked_reason(id))
	return "길이 모이는 날을 함께 보냈습니다. 다음 계절의 장터에서 다시 만나요."
static func information(id: String) -> String:
	var entry := event(id)
	if entry.is_empty(): return ""
	var text := RequestTextData.text("service_text",str(entry["title_id"]),"summary","")
	if done(id): text += "\n마무리한 날: %d일차" % int(PlayerProgress.story_beat_days[key(id,"last_done")])
	if not accepted(id): return text + "\n" + ("게시판에서 이야기 맡기" if locked_reason(id).is_empty() else locked_reason(id))
	var current := step(id)
	text += "\n%s · 단계 %d/%d" % [str(current.get("role","이웃")),int(current.get("index",0)) + 1,entry["steps"].size()]
	for field in ["requirements","furniture","sales"]:
		for requirement in current.get(field,[]):
			var item := str(requirement["item"])
			var count := GameState.get_furniture_count(item) if field == "furniture" else GameState.get_item_count(item)
			if field == "sales": count = int(PlayerProgress.story_beat_days.get(key(id,"sold:" + item,cycle(id)),0))
			text += "\n%s %d/%d (%s)" % [FurnitureData.get_furniture_name(item) if field == "furniture" else ItemData.get_item_name(item),count,requirement["amount"],"실제 결제" if field == "sales" else "창고 전달"]
	if not current.get("show",[]).is_empty(): text += "\n물건 확인만 합니다. 소비하지 않습니다."
	text += "\n" + ("완독하면 다음 단계로 이어집니다. [E]" if step_reason(id).is_empty() else step_reason(id))
	if int(entry.get("money",0)) > 0: text += "\n최종 대화 완독 후 대금: %d G" % entry["money"]
	return text
static func market_window() -> bool:
	var day := CalendarData.get_day_of_season(GameState.total_day)
	return day >= VillageExpansionFlow.SETTINGS.festival_start_day and day <= VillageExpansionFlow.SETTINGS.festival_end_day
