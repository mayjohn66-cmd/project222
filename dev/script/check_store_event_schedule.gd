extends Node
var checks := 0
var failures := 0
func check(ok: bool, caption: String) -> void:
	checks += 1
	if ok: print("PASS: ", caption)
	else:
		failures += 1
		push_error(caption)
func _ready() -> void: call_deferred("run")
func has_rumor(id: String, day: int, customer_type: String) -> bool:
	return StoreEventData.get_discoverable_events(day, customer_type).any(func(e: Dictionary) -> bool: return str(e["event_id"]) == id)
func has_demand(id: String, day: int, group: String) -> bool:
	return StoreEventDemandData.get_active_demand_entries(group, day).any(func(e: Dictionary) -> bool: return str(e["event_id"]) == id)
func label_text(node: Node) -> String:
	var value: String = node.text if node is Label else ""
	for child in node.get_children(): value += "\n" + label_text(child)
	return value
func run() -> void:
	StoreEventData.ensure_loaded()
	var common := 0
	var seasonal := 0
	var expected: Dictionary = {"spring_market":["bread","berry_juice"],"summer_cool_break":["water","berry_juice"],"autumn_shared_table":["bread","mushroom_stew"],"winter_evening_warmth":["herb_drink","hand_warmer"],"spring_packed_lunch":["herbal_bread","dried_fruit"],"summer_waterside_tea":["mineral_water","reed_tea"],"autumn_lantern_preparation":["glow_lamp","reed_tea"],"winter_morning_table":["herbal_bread","traveler_stew"]}
	for event in StoreEventData.events.values():
		var id := str(event["event_id"])
		var is_seasonal := str(event["event_kind"]) == "seasonal"
		if is_seasonal: seasonal += 1
		else: common += 1
		check(StoreEventSchedule.valid(event), "CSV schedule accepted: " + id)
		var group: String = "normal" if is_seasonal else "traveler"
		for reference in [1, 113, 225]:
			var occurrence := StoreEventData.get_event_occurrence(id, reference)
			var start := int(occurrence["start_day"])
			var end := int(occurrence["end_day"])
			for day in [start - 1, start, end, end + 1]:
				var active: bool = day >= start and day <= end
				check(StoreEventData.is_event_active(id, day) == active and has_demand(id, day, group) == active, "activation and real demand date boundary: " + id + ":" + str(day))
			if is_seasonal:
				check(CalendarData.get_season_id(start) == event["season_id"] and CalendarData.get_year(start) == CalendarData.get_year(reference), "annual event stays in correct year/season: " + id)
				for other in [1,29,57,85]:
					var day: int = (CalendarData.get_year(reference) - 1) * 112 + other + int(event["start_day"]) - 1
					if CalendarData.get_season_id(day) != str(event["season_id"]): check(not StoreEventData.is_event_active(id, day), "not active in another season: " + id + ":" + str(day))
		if is_seasonal:
			for demand in StoreEventDemandData.get_event_demand_entries(id, "normal"):
				check(str(demand["target_type"]) == "item" and str(demand["target_id"]) in expected[id], "seasonal event targets actual specific goods: " + id)
		else:
			for reference in [1,29,57,85]:
				var occurrence := StoreEventData.get_event_occurrence(id, reference)
				check(StoreEventData.is_event_active(id, int(occurrence["start_day"])), "common event works regardless of season: " + id + ":" + str(reference))
	check(common == 3 and seasonal == 8, "three common and eight seasonal sale events")
	var invalid := StoreEventData.get_event("spring_market")
	invalid["season_id"] = "rain"
	check(not StoreEventSchedule.valid(invalid), "unknown season rejected")
	invalid = StoreEventData.get_event("spring_market")
	invalid["end_day"] = 29
	check(not StoreEventSchedule.valid(invalid), "seasonal date cannot spill into next season")
	invalid = StoreEventData.get_event("dungeon_raid")
	invalid["repeat_days"] = 3
	check(not StoreEventSchedule.valid(invalid), "common duration cannot exceed repetition cycle")
	invalid = StoreEventData.get_event("dungeon_raid")
	invalid["event_kind"] = "weather"
	check(not StoreEventSchedule.valid(invalid), "third category rejected")
	var legacy := StoreEventData.get_event("dungeon_raid")
	legacy.erase("event_kind")
	legacy.erase("season_id")
	legacy.erase("repeat_days")
	check(StoreEventSchedule.valid(legacy) and StoreEventSchedule.active(legacy, 4) and not StoreEventSchedule.active(legacy, 32), "legacy absolute schedule remains supported")
	var original_raid := StoreEventData.get_event("dungeon_raid")
	var overlapping := original_raid.duplicate(true)
	overlapping["start_day"] = 15
	overlapping["end_day"] = 17
	StoreEventData.events["dungeon_raid"] = overlapping
	var concurrent := StoreEventData.get_active_events(15)
	check(concurrent.any(func(e: Dictionary) -> bool: return str(e["event_id"]) == "dungeon_raid") and concurrent.any(func(e: Dictionary) -> bool: return str(e["event_id"]) == "spring_market"), "configured common and seasonal events can overlap")
	check(has_demand("dungeon_raid",15,"normal") and has_demand("spring_market",15,"normal"), "overlap keeps both sets of actual item demand")
	StoreEventData.events["dungeon_raid"] = original_raid
	check(not StoreEventData.is_event_active("dungeon_raid",15), "temporary overlap fixture restores actual schedule")

	var world = load("res://scenes/shop/main.tscn").instantiate()
	add_child(world)
	for i in range(6): await get_tree().process_frame
	world.get_node("DayManager").set_process(false)
	var customer = load("res://scenes/shop/actors/customer.tscn").instantiate()
	world.get_node("Actors").add_child(customer)
	customer.set_physics_process(false)
	var notifications: Array[String] = []
	var observer := func(id: String, day: int) -> void: notifications.append(id + ":" + str(day))
	GameState.store_event_discovered.connect(observer)
	for event in StoreEventData.events.values():
		var id := str(event["event_id"])
		var type_id: String = "backpacker" if id == "dungeon_raid" else "villager"
		var next_cycle: int = 113 if str(event["event_kind"]) == "seasonal" else 29
		var first := StoreEventData.get_event_occurrence(id, 1)
		var next := StoreEventData.get_event_occurrence(id, next_cycle)
		GameState.discovered_store_events.clear()
		GameState.total_day = int(first["discovery_start_day"])
		check(has_rumor(id, GameState.total_day, type_id), "real customer subtype can hear first rumor: " + id)
		customer.rumor_event_id = id
		var heard: Dictionary = customer.share_rumor_event()
		check(heard.get("occurrence_id", "") == first["occurrence_id"] and customer.rumor_event_id.is_empty(), "customer shares correct first occurrence and clears marker: " + id)
		check(not has_rumor(id, GameState.total_day, type_id) and not StoreEventData.discover_event(id, GameState.total_day), "same occurrence cannot be rediscovered: " + id)
		GameState.total_day = int(next["discovery_start_day"])
		check(has_rumor(id, GameState.total_day, type_id), "next month/year rumor reappears: " + id)
		customer.rumor_event_id = id
		check(customer.can_share_rumor(), "old saved event id does not block repeat rumor: " + id)
		heard = customer.share_rumor_event()
		check(heard.get("occurrence_id", "") == next["occurrence_id"] and GameState.get_store_event_discovery_day(id) == GameState.total_day, "latest discovery day stores new occurrence: " + id)
		GameState.total_day = int(next["end_day"]) + 1
		customer.rumor_event_id = id
		check(not customer.can_share_rumor() and customer.share_rumor_event().is_empty(), "stale customer cannot announce expired occurrence: " + id)
	check(notifications.size() == StoreEventData.events.size() * 2, "discovery notification once per occurrence")
	GameState.store_event_discovered.disconnect(observer)
	var saved := GameState.create_save_data().duplicate(true)
	var saved_discoveries: Dictionary = GameState.discovered_store_events.duplicate(true)
	check(GameState.is_save_data_valid(saved), "recurring discovery uses valid existing save format")
	GameState.discovered_store_events.clear()
	check(GameState.apply_save_data(saved) and GameState.discovered_store_events == saved_discoveries and not saved_discoveries.is_empty(), "save roundtrip preserves latest annual discovery")
	GameState.total_day = 120
	GameState.discovered_store_events = {"spring_market":8,"dungeon_raid":2}
	check(has_rumor("spring_market",120,"villager") and has_rumor("dungeon_raid",114,"backpacker"), "legacy first-year discoveries do not block later-year rumors")
	var menu = world.get_node("UI/ManagementMenu")
	menu.refresh_schedule()
	await get_tree().process_frame
	var memo := label_text(menu.schedule_list)
	check(memo.contains("공용 이벤트") and memo.contains("계절 이벤트") and memo.contains("지나간 마을 이야기"), "menu separates categories and retains last-heard memory")
	check(StoreEventData.discover_event("spring_market",120), "second spring rumor updates memory")
	menu.refresh_schedule()
	await get_tree().process_frame
	check(label_text(menu.schedule_list).contains("머지않아 있을 일"), "menu switches from old memory to current spring preparation")
	check(StoreEventSchedule.category_label(StoreEventData.get_event("spring_market")) == "계절 이벤트 · 봄", "season label has correct calendar season")
	world.queue_free()
	await get_tree().process_frame
	print("CHECK_STORE_EVENT_SCHEDULE checks=", checks, " failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)
