class_name PreservationGuide
extends RefCounted
const ENABLED := true

static func material(item: String) -> Dictionary:
	for rule in PreservationService.SETTINGS.materials:
		if str(rule["item"]) == item: return rule
	return {}

static func known(item: String) -> bool:
	if GameState.get_item_count(item) > 0: return true
	for unit in PreservationService.SETTINGS.units:
		if int(GameState.preservation_state.get(str(unit["id"]),{}).get(item,0)) > 0: return true
	for recipe in ProductRecipeData.get_learned_recipes():
		if str(recipe["result_item_id"]) == item: return true
	if FishingRecords.has("caught:" + item): return true
	for entry in PreservationLessonFlow.SETTINGS.events:
		if str(entry["raw"]) == item and PreservationLessonFlow.discovered(entry): return true
	return false

static func visible_item(item: String) -> bool:
	return not ENABLED or known(item)

static func intro(unit_filter: String) -> String:
	var lines: Array[String] = ["가진 재료와 배운 상품부터 살펴보세요. 보관 상품은 필요한 날 꺼내서 사용하거나 진열합니다."]
	if unit_filter.is_empty() or PreservationService.unit(unit_filter).is_empty(): return "\n".join(lines)
	for rule in PreservationService.SETTINGS.materials:
		var item := str(rule["item"])
		if not known(item) or PreservationService.unit(unit_filter)["accepts"].has(item): continue
		var names: Array[String] = []
		for unit in PreservationService.SETTINGS.units:
			if unit["accepts"].has(item): names.append(str(unit["name"]))
		if not names.is_empty(): lines.append("%s은 이 설비에 넣을 수 없어요. %s이 필요합니다." % [ItemData.get_item_name(item),"·".join(names)])
	return "\n".join(lines)

static func unit_description(unit: Dictionary) -> String:
	var id := str(unit["id"])
	var rate := FoodShelfLife.SETTINGS.fridge_age if id == "fridge" else FoodShelfLife.SETTINGS.freezer_age
	var food := "식품의 기한 진행을 멈춥니다." if rate == 0 else ("식품의 기한이 상온보다 천천히 줄어듭니다." if rate < FoodShelfLife.SETTINGS.ambient_age else "식품의 남은 기한을 살피며 보관하세요.")
	return "맞는 계절 재료는 계절이 바뀌어도 보존합니다. " + food + "\n입고는 기한을 새로 채우지 않습니다."

static func ambient_hint(item: String) -> String:
	var rule := material(item)
	if rule.is_empty(): return ""
	var season := str(rule["season"])
	if season.is_empty() or CalendarData.get_season_id(GameState.total_day + 1) != season:
		return "상온에서는 다음 아침에 %s로 변합니다. 필요한 날 꺼내고 남은 재료는 다시 보관하세요." % ItemData.get_item_name(str(rule["result"]))
	return "%s이 지나 상온에서 아침을 맞으면 %s로 변합니다." % [ExpeditionEnvironment.SEASONS.get(season,season),ItemData.get_item_name(str(rule["result"]))]

static func dry_hint(item: String) -> String:
	for entry in PreservationLessonFlow.SETTINGS.events:
		if str(entry["raw"]) != item: continue
		for path in entry["paths"]:
			if str(path["id"]) != "dry": continue
			for recipe in ProductRecipeData.get_learned_recipes():
				if str(recipe["result_item_id"]) != str(path["item"]): continue
				if not recipe["ingredients"].any(func(ingredient): return str(ingredient["item_id"]) == item): continue
				var facility := FurnitureData.get_furniture_name(str(recipe["facility_id"]))
				return "배운 보존 가공 · %s에서 %s을 만들어 수령할 수도 있어요." % [facility,ItemData.get_item_name(str(path["item"]))]
	return ""

static func lesson_note(unit: String, item: String) -> String:
	for entry in PreservationLessonFlow.SETTINGS.events:
		var id := str(entry["id"])
		if str(entry["raw"]) != item or not PreservationLessonFlow.accepted(id) or PreservationLessonFlow.completed(id): continue
		var name := str(VillageLifeFlow.resident(str(entry["giver"])).get("name","이웃"))
		if not PreservationLessonFlow.ready_path(id).is_empty(): return "보존 체험의 시료가 준비됐어요. %s에게 직접 전달하세요. [E]" % name
		var stored := PreservationLessonFlow.key(id,"stored:" + unit)
		var count := int(GameState.preservation_state.get(unit,{}).get(item,0))
		if count > 0 and PlayerProgress.story_beat_days.has(stored):
			return "%s에게 가져갈 날 필요한 만큼 꺼내세요. 하룻밤 보관했어요." % name if GameState.total_day > int(PlayerProgress.story_beat_days[stored]) else "오늘 넣었어요. 다음 날 이후 꺼내야 하룻밤 보관 체험이 됩니다."
		if PlayerProgress.story_beat_days.has(PreservationLessonFlow.key(id,"practiced:cold")): return "하룻밤 보관 체험은 남아 있어요. %s에게 전달할 시료를 소지품에 준비하세요." % name
		return "맡은 보존 체험 · 소개 뒤 넣고 다음 날 이후 꺼낸 시료를 %s에게 직접 전달합니다." % name
	return ""

static func item_note(unit: String, item: String) -> String:
	var lines: Array[String] = []
	var rule := material(item)
	if not rule.is_empty():
		lines.append(ambient_hint(item))
		var count := int(GameState.preservation_state.get(unit,{}).get(item,0))
		if count > 0: lines.append("이 설비에 넣어 둔 재료는 보존 중입니다.")
	if FoodShelfLife.tracked(item):
		var food := FoodShelfLife.state()
		for zone in ["inventory",unit]:
			var amount := GameState.get_item_count(item) if zone == "inventory" else int(GameState.preservation_state.get(unit,{}).get(item,0))
			if amount <= 0: continue
			var batches: Array = food.get(zone,{}).get(item,[])
			if batches.is_empty(): continue
			var days := int(FoodShelfLife.rules()[item]["days"])
			for batch in batches: days = mini(days,FoodShelfLife.days_left(item,batch))
			lines.append("소지 가장 빠른 재고 · 상온 기준 %d일" % days if zone == "inventory" else "보관 가장 빠른 재고 · 출고 뒤 상온 기준 %d일" % days)
		if bool(FoodShelfLife.rules()[item]["freezable"]) == false: lines.append("냉동할 수 없는 식품입니다. 냉장하며 기한을 살펴보세요.")
	var dry := dry_hint(item)
	if not dry.is_empty(): lines.append(dry)
	var lesson := lesson_note(unit,item)
	if not lesson.is_empty(): lines.append(lesson)
	return "\n".join(lines)

static func add_note(panel: PreservationPanel, unit: String, item: String) -> void:
	if not ENABLED: return
	var text := item_note(unit,item)
	if text.is_empty(): return
	var note := panel._label()
	note.text = text
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel.rows.add_child(note)

static func move_note(_unit: String, item: String, putting: bool) -> String:
	if FoodShelfLife.tracked(item): return "남은 기한은 그대로 이어집니다. " + ("냉동할 수 없는 식품입니다." if not bool(FoodShelfLife.rules()[item]["freezable"]) else "")
	if not material(item).is_empty(): return "넣어 둔 재료는 보존 중입니다." if putting else ambient_hint(item)
	return ""
