class_name ActFourRecords
extends RefCounted
## 새 저장 형식을 만들지 않고 실제 성공한 행동만 기존 진행 기록에 담는다.
const PREFIX := "act4_record:"
static func found(item: String) -> bool: return PlayerProgress.story_beat_days.has(PREFIX + "found:" + item)
static func ruins_runs() -> int: return int(PlayerProgress.story_beat_days.get(PREFIX + "ruins_runs",0))
static func merchant_visits() -> int: return int(PlayerProgress.story_beat_days.get(PREFIX + "merchant_visits",0))
static func record_merchant_visit() -> void:
	if int(PlayerProgress.story_beat_days.get(PREFIX + "merchant_day",-1)) == GameState.total_day: return
	PlayerProgress.record_story_beat(PREFIX + "merchant_day",GameState.total_day)
	PlayerProgress.story_beat_days[PREFIX + "merchant_visits"] = merchant_visits() + 1
static func record_map_purchase(item: String) -> void:
	var current := _step("b3_secret_merchant")
	if item != "treasure_map" or merchant_visits() < 2 or not current.get("map_purchase",false): return
	PlayerProgress.record_story_beat(_key("b3_secret_merchant","bought_map",_cycle("b3_secret_merchant")),GameState.total_day)
static func record_settlement(context: Dictionary, items: Array[Dictionary]) -> void:
	if context.get("region","") != "ruins" or not context.get("explored",false): return
	# 한 번의 원정은 한 영업일을 소비한다. 복귀 재시도·같은 날 체크포인트 재로드는 중복 집계하지 않는다.
	var receipt := PREFIX + "settled:" + str(GameState.total_day)
	if PlayerProgress.story_beat_days.has(receipt): return
	PlayerProgress.record_story_beat(receipt,GameState.total_day)
	PlayerProgress.story_beat_days[PREFIX + "ruins_runs"] = ruins_runs() + 1
	for item in items:
		if str(item["item_id"]) in ["worn_coin","rune_stone"] and int(item["amount"]) > 0:
			PlayerProgress.record_story_beat(PREFIX + "found:" + str(item["item_id"]),GameState.total_day)
	var current := _step("b4_blank_of_map")
	if current.get("ruins_run",false): PlayerProgress.record_story_beat(_key("b4_blank_of_map","returned",_cycle("b4_blank_of_map")),GameState.total_day)
static func record_furniture(item: String, amount: int) -> void:
	if amount <= 0: return
	for entry in _events():
		var id := str(entry["id"])
		var current := _step(id)
		for requirement in current.get("furniture",[]):
			if requirement["item"] != item or requirement.get("amount") == null: continue
			var k := _key(id,"made:" + item,_cycle(id))
			PlayerProgress.story_beat_days[k] = mini(int(requirement["amount"]),int(PlayerProgress.story_beat_days.get(k,0)) + amount)
static func record_sale(customer: Node, item: String, amount: int) -> void:
	if amount <= 0 or not is_instance_valid(customer) or not bool(customer.get("purchase_completed")): return
	for entry in _events():
		var id := str(entry["id"])
		var current := _step(id)
		if current.get("market",false) and not _market_window(): continue
		if current.has("customer_type") and str(customer.get("customer_type_id")) != str(current["customer_type"]): continue
		for requirement in current.get("sales",[]):
			if requirement["item"] != item or requirement.get("amount") == null: continue
			var k := _key(id,"sold:" + item,_cycle(id))
			PlayerProgress.story_beat_days[k] = mini(int(requirement["amount"]),int(PlayerProgress.story_beat_days.get(k,0)) + amount)


static func _events() -> Array:
	var settings: Resource = load("res://scenes/shop/requests/default_act_four.tres")
	return settings.get("events")
static func _key(id: String, suffix: String, cycle: int) -> String:
	return "act4:" + id + ":" + str(cycle) + ":" + suffix
static func _cycle(id: String) -> int:
	return int(PlayerProgress.story_beat_days.get("act4:" + id + ":active",-1))
static func _step(id: String) -> Dictionary:
	var c := _cycle(id)
	if c < 0: return {}
	for entry in _events():
		if entry["id"] != id: continue
		var index := int(PlayerProgress.story_beat_days.get(_key(id,"step",c),0))
		if index >= 0 and index < entry["steps"].size(): return entry["steps"][index]
	return {}
static func _market_window() -> bool:
	var settings: Resource = load("res://scenes/shop/requests/default_village_expansion.tres")
	var day := CalendarData.get_day_of_season(GameState.total_day)
	return day >= int(settings.get("festival_start_day")) and day <= int(settings.get("festival_end_day"))
