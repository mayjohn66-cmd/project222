class_name NpcServiceSupplyGuide
extends RefCounted
## Explain only the missing carried materials; stored goods must be withdrawn.
const ENABLED := true

static func missing(from: Node, costs: Dictionary) -> String:
	if not ENABLED: return ""
	var world := InventoryItemGuide.world(from)
	if world == null: return ""
	var manager := world.get_node_or_null("DayManager")
	if manager == null: return ""
	var hour: float = float(manager.current_hour) + manager.get_display_minute() / 60.0
	var environment := {"hour":hour, "weather":WorldWeatherData.forecast(GameState.total_day,hour)["kind"], "season":CalendarData.get_season_id(GameState.total_day)}
	var lines: Array[String] = []
	for key in costs:
		var item := str(key)
		var required := int(costs[key])
		if not ItemData.has_item(item) or required <= 0: continue
		var carried := GameState.get_item_count(item)
		if carried >= required: continue
		lines.append(UiText.f("service.supply.item", [ItemData.get_item_name(item),carried,required,required-carried]))
		var stored := ProductPreparationData.shelf_count(world,item)
		if stored > 0: lines.append(UiText.f("service.supply.warehouse", [stored]))
		var cold := ProductPreparationData.preservation_note(item)
		if not cold.is_empty(): lines.append(cold)
		var cold_count := 0
		for id in ["fridge","freezer"]:
			if PreservationService.installed(id): cold_count += int(GameState.preservation_state.get(id,{}).get(item,0))
		if stored + cold_count < required-carried:
			var source := RequestItemSources.describe(world,item,required-carried-stored-cold_count,environment)
			if not source.is_empty(): lines.append(source)
	return "\n".join(lines)
