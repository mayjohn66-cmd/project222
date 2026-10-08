class_name RequestItemSources
extends RefCounted
const MAX_ROUTES := 3

static func describe(world: Node, item: String, missing: int, environment: Dictionary) -> String:
	var lines := recipes(world,item,missing)
	if FishingData.fish(item): lines.append_array(fishing(item,environment))
	else: lines.append_array(expedition(item,environment))
	return "\n".join(lines) if not lines.is_empty() else "이 물품을 부탁한 사람의 이야기를 다시 살펴보세요."

static func recipes(world: Node, item: String, missing: int) -> Array[String]:
	var lines: Array[String] = []
	for recipe in ProductRecipeData.get_learned_recipes():
		if recipe["result_item_id"] != item or int(recipe["result_amount"]) <= 0: continue
		var times := ceili(float(missing) / int(recipe["result_amount"]))
		var ingredients := ProductionRecipeService.collect_required_ingredients(recipe,times)
		var parts: Array[String] = []
		for material in ingredients:
			parts.append("%s %d개" % [ItemData.get_item_name(str(material)),ingredients[material]])
		lines.append("배운 제조법 · %s %d회분: %s\n%s · 현장 설비에서 제작하고 완성품을 수령하세요." % [
			FishingData.recipe_name(recipe),times," · ".join(parts),ProductPreparationData.ready(world,recipe)])
		if lines.size() >= MAX_ROUTES: break
	return lines

static func condition_labels(entry: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for field in ["season","weather"]:
		var filter := str(entry.get(field + "_filter","")).strip_edges()
		if filter.is_empty() or filter in ["any","all"]: continue
		var labels: Array[String] = []
		var mapping: Dictionary = ExpeditionEnvironment.SEASONS if field == "season" else ExpeditionEnvironment.WEATHER
		for value in filter.split("|"): labels.append(str(mapping.get(value,value)))
		result.append("/".join(labels))
	return result

static func expedition(item: String, environment: Dictionary) -> Array[String]:
	ExpeditionEventData.ensure_loaded()
	var current: Array[String] = []
	var later: Array[String] = []
	var tool_notes: Array[String] = []
	for event in ExpeditionEventData.events:
		if event.get("result_type","") not in ["loot","battle"] or int(event.get("weight",0)) <= 0: continue
		var region := str(event["region_id"])
		if not ExpeditionMapData.can_enter_region(region): continue
		var table := str(event.get("target_id",""))
		if event.get("result_type","") == "battle":
			if not EnemyData.has_enemy(table): continue
			table = EnemyData.get_loot_table(table)
		for loot in ExpeditionEventData.get_loot_entries(table):
			if str(loot["item_id"]) != item or int(loot.get("weight",0)) <= 0 or int(loot.get("max_amount",0)) <= 0: continue
			var tool_note := ExpeditionGatheringToolGuide.required_tool(table)
			if not tool_note.is_empty() and tool_note not in tool_notes: tool_notes.append(tool_note)
			var labels := condition_labels(event)
			for label in condition_labels(loot):
				if label not in labels: labels.append(label)
			var minimum := int(loot.get("min_difficulty",1))
			var maximum := int(loot.get("max_difficulty",9999))
			if minimum > 1: labels.append("난이도 " + str(minimum) + " 이상")
			if maximum < ExpeditionDifficultyData.get_max_level(): labels.append("난이도 " + str(maximum) + " 이하")
			var type := str(event.get("node_type",""))
			var place := str(ExpeditionMapData.get_region_data(region).get("name",region))
			var route := place + " 원정 · " + ({"gather":"채집","treasure":"보물","unknown":"물음표 방"}.get(type,"탐험") as String)
			if event.get("result_type","") == "battle": route = place + " 원정 · " + ("보스 전투" if type == "boss" else "전투")
			if not labels.is_empty(): route += " · " + " · ".join(labels)
			var day := str(event.get("day_filter","")).strip_edges()
			if not day.is_empty(): route += " · 원정의 요일 조건 확인"
			var active := ExpeditionEnvironment.matches(event,environment) and ExpeditionEnvironment.matches(loot,environment)
			if active:
				if route not in current: current.append(route)
			else:
				route += " · 지금은 계절·날씨 조건을 기다려야 합니다."
				if route not in later: later.append(route)
	var lines: Array[String] = []
	for route in current + later:
		lines.append(route)
		if lines.size() >= MAX_ROUTES: break
	lines.append_array(tool_notes)
	if not lines.is_empty(): lines.append("탐험 중 만나는 채집물과 보물은 달라질 수 있습니다.")
	return lines

static func fishing(item: String, environment: Dictionary) -> Array[String]:
	var entry := FishingData.entry(item)
	var lines: Array[String] = []
	if entry.is_empty() or not FishingRecords.accepted("fishing_intro"): return lines
	var labels: Array[String] = []
	for season in entry.get("seasons",[]): labels.append(str(ExpeditionEnvironment.SEASONS.get(season,season)))
	var conditions := "/".join(labels) if labels.size() < ExpeditionEnvironment.SEASONS.size() else "사계절"
	var period := str(entry.get("time","all"))
	if period != "all": conditions += " · " + str({"morning":"아침","day":"낮","afternoon":"낮","evening":"저녁","night":"밤","dawn":"새벽"}.get(period,period))
	var weather := str(entry.get("weather","all"))
	if weather != "all": conditions += " · " + str(ExpeditionEnvironment.WEATHER.get(weather,weather))
	for location in entry.get("locations",[]):
		if not FishingContent.location_available(str(location),float(environment["hour"]),str(environment["weather"])): continue
		var route := str(FishingData.entry(str(location)).get("name",location)) + " · 낚시 · " + conditions
		var possible := false
		for fish in FishingService.pool(str(location),str(environment["season"]),EmployeeData.get_period_at_hour(int(environment["hour"])),str(environment["weather"])):
			if fish["id"] == item: possible = true
		if not possible: route += " · 지금은 계절·시간·날씨 조건을 기다려야 합니다."
		lines.append(route)
	if not lines.is_empty():
		lines.append("낚싯대를 소지하고 물가에서 찌를 던져 보세요. 입질 때 [E]로 건집니다. 원하는 종류가 항상 잡히는 것은 아닙니다.")
	return lines
