extends Node
const Tools = preload("res://dev/gemini/request_text_tools.gd")
const Runner = preload("res://dev/gemini/request_text_runner.gd")
var checks := 0
var failures := 0
func check(ok: bool, caption: String) -> void:
	checks += 1
	if ok: print("PASS: ", caption)
	else:
		failures += 1
		push_error(caption)
func _ready() -> void: call_deferred("run")
func sample(type_id: String, day: int) -> Dictionary:
	seed(5091)
	var units := 0
	var event_units := 0
	var stocked: Array[String] = ["potion", "bread", "water"]
	for i in range(1000):
		var request := CustomerDemandData.get_random_wanted_request(type_id, day, stocked)
		units += int(request.get("amount", 0))
		if not str(request.get("event_id", "")).is_empty(): event_units += int(request["amount"])
	return {"units":units, "event_units":event_units}
func label_text(node: Node) -> String:
	var result: String = (node.text + "\n") if node is Label else ""
	for child in node.get_children(): result += label_text(child)
	return result
func run() -> void:
	var world = load("res://scenes/shop/main.tscn").instantiate()
	add_child(world)
	for i in range(8): await get_tree().process_frame
	world.get_node("DayManager").set_process(false)
	world.get_node("CustomerSpawner").set_process(false)
	for worker in get_tree().get_nodes_in_group("worker"):
		worker.set_process(false)
		worker.set_physics_process(false)
	var player = world.get_node("Actors/Player")
	player.set_physics_process(false)
	var menu = world.get_node("UI/ManagementMenu")
	var sources := Tools.load_sources()
	var prose := RequestTextData.read_file(RequestTextData.CSV_PATH)
	check(StoreEventStory.SETTINGS.moments.size() == 18, "three existing events have six narrative stages each")
	var token_id := "store_trail_bought"
	var bad_token := PackedStringArray([token_id, "service_text", "길손의 말", "", "준비를 다 했어.", ""])
	check(not Tools.validate_rows(Tools.COLUMNS, [bad_token], sources)["errors"].is_empty(), "Gemini cannot remove actual purchased item token")
	for entry in StoreEventStory.SETTINGS.moments:
		var id := str(entry["id"])
		check(sources["service_text"].has(id) and prose.has("service_text:" + id), "game and Gemini share scene: " + id)
		var prompt := Runner.build_prompt("service_text", {"service_text": {id:sources["service_text"][id]}})
		check(prompt.contains(str(entry["context"])), "Gemini preserves actual demand context: " + id)
	for event in StoreEventData.get_all_events():
		var id := str(event["event_id"])
		var start := int(event["start_day"])
		var end := int(event["end_day"])
		for day in [start - 1, start, end, end + 1]:
			var note := StoreEventStory.note_text(event, day)
			check(not note.contains("기간:") and not note.contains("×") and not note.contains("개 요구") and not note.contains("D-"), "no date/multiplier sales announcement: " + id + ":" + str(day))
		check(StoreEventStory.phase(event, start - 1) == "rumor" and StoreEventStory.phase(event, end + 1) == "finished", "lifecycle follows actual event dates: " + id)
		check(StoreEventStory.timing(event, start - 1).contains("내일") and StoreEventStory.timing(event, end).contains("오늘"), "readable imminent/last-day cues: " + id)
		var rumor := StoreEventStory.moment(id, "rumor")
		for item in rumor.get("cue_items", []):
			check(ItemData.is_sellable(str(item)), "preparation cue is an actual sellable item: " + str(item))
		for material in rumor.get("cue_materials", []):
			check(ItemData.has_item(str(material)), "preparation material exists: " + str(material))
		GameState.total_day = start - 1
		player.show_rumor_dialog(event)
		check(player.rumor_dialog.dialog_text == StoreEventStory.rumor_text(event, start - 1), "actual rumor dialog uses narrative: " + id)
		player.rumor_dialog.hide()
		var type_id: String = "villager" if id == "spring_market" else "backpacker"
		var item_id: String = "potion" if id == "dungeon_raid" else "bread"
		check(not StoreEventStory.reaction(id, type_id, item_id, "bought", start).is_empty(), "genuine event purchase gets reaction: " + id)
		check(not StoreEventStory.reaction(id, type_id, item_id, "missing", start).is_empty(), "genuine event stockout gets reaction: " + id)
		check(StoreEventStory.reaction(id, type_id, "iron_ore", "bought", start).is_empty(), "unrelated item gets no event praise: " + id)
		check(StoreEventStory.reaction(id, type_id, item_id, "bought", end + 1).is_empty(), "expired demand gets no event praise: " + id)
		var normal := sample(type_id, start - 1)
		var active := sample(type_id, start)
		var ended := sample(type_id, end + 1)
		check(normal["event_units"] == 0 and ended["event_units"] == 0, "event demand absent outside dates: " + id)
		check(active["event_units"] > 0 and active["units"] > normal["units"], "actual request generator increases purchased units: " + id)
		print("DEMAND_SAMPLE ", id, " before=", normal["units"], " active=", active["units"], " after=", ended["units"])

	# 실제 손님 쇼핑의 품절 경로와 진열대 -> 결제 -> 기록 경로를 확인한다.
	GameState.total_day = 22
	var build = world.get_node("BuildManager")
	var layout: Array[Dictionary] = [{"build_id":"door","anchor":Vector2i(0,4),"rotation_index":3}, {"build_id":"register","anchor":Vector2i(4,3),"rotation_index":0}, {"build_id":"shelf_1x1","anchor":Vector2i(2,2),"rotation_index":0}]
	build._restore_current_area_layout(layout)
	for i in range(3): await get_tree().process_frame
	var shelf = get_tree().get_nodes_in_group("shelf")[0]
	for slot in shelf.slots:
		slot["stock"] = 0
		slot["item_id"] = ""
	var event_seed := -1
	var wanted: Dictionary
	for i in range(1000):
		seed(i)
		wanted = CustomerDemandData.get_random_wanted_request("backpacker", 22, [])
		if str(wanted.get("event_id", "")) == "trail_supplies":
			event_seed = i
			break
	check(event_seed >= 0, "reachable travel event request without shelf stock")
	var customer = load("res://scenes/shop/actors/customer.tscn").instantiate()
	world.get_node("Actors").add_child(customer)
	customer.global_position = build.get_cell_world_position(Vector2i(1,4))
	customer.set_physics_process(false)
	customer.customer_type_selected = true
	customer.customer_type_id = "backpacker"
	customer.customer_group_id = "traveler"
	seed(event_seed)
	player.reset_shop_stats()
	customer.start_shopping()
	customer.moving = false
	var notice := player.get_node_or_null("StoreEventRemark") as StoreEventRemark
	check(is_instance_valid(notice) and notice.card.visible and notice.caption.text.contains(ItemData.get_item_name(customer.wanted_item_id)), "empty shelf emits real missing item remark")
	check(player.daily_unmet_demand.get(customer.wanted_item_id, 0) == customer.wanted_amount and player.successful_sales == 0, "stockout records demand without fabricated sale")
	notice._process(StoreEventStory.SETTINGS.remark_seconds)
	check(not notice.card.visible, "remark expires without user input")
	shelf.product_id = customer.wanted_item_id
	shelf.stock = 4
	customer.carried_item_id = customer.wanted_item_id
	customer.carried_amount = shelf.take_items_by_id(customer.wanted_item_id, 2)
	var money_before: int = GameState.money
	var price: int = ItemData.get_item_price(customer.wanted_item_id)
	customer.checkout_item()
	check(player.successful_sales == 1 and player.daily_sold_items.get(customer.wanted_item_id, 0) == 2 and shelf.stock == 2, "real multi-unit sale consumes shelf and records sold units")
	check(GameState.money == money_before + price * 2 and notice.card.visible, "remark follows actual payment and correct money change")
	check(not notice.caption.text.contains("{item}") and notice.caption.text.contains(ItemData.get_item_name(customer.wanted_item_id)), "purchase response names actually sold item")
	customer.checkout_item()
	check(player.successful_sales == 1 and GameState.money == money_before + price * 2, "repeated checkout cannot duplicate payment")
	var shown: String = notice.caption.text
	check(not notice.display("crowded second remark") and notice.caption.text == shown, "crowd cannot overwrite remark while being read")
	check(notice.card.mouse_filter == Control.MOUSE_FILTER_IGNORE and notice.caption.mouse_filter == Control.MOUSE_FILTER_IGNORE and not player.rumor_dialog.visible, "reaction is nonblocking with no modal")
	await get_tree().process_frame
	check(get_viewport().get_visible_rect().encloses(notice.card.get_global_rect()), "remark fits viewport")
	var stats: Dictionary = player.get_daily_shop_stats()
	stats["active_event_ids"] = ["trail_supplies"]
	GameState.record_daily_shop_result(22, 1, stats)
	GameState.discover_store_event("trail_supplies")
	GameState.total_day = 25
	menu.refresh_schedule()
	await get_tree().process_frame
	var memo := label_text(menu.schedule_list)
	check(memo.contains("지나간 마을 이야기") and memo.contains("그 무렵의 영업 기록") and memo.contains(ItemData.get_item_name(customer.wanted_item_id)), "finished event remains with real sales history")
	check(not memo.contains("기간:") and not memo.contains("등장 빈도") and not memo.contains("예상 영향"), "schedule has narrative memory rather than sales forecast")
	var save := GameState.get_discovered_store_events()
	check(save.has("trail_supplies"), "existing discovery persistence retained")
	world.queue_free()
	await get_tree().process_frame
	print("CHECK_STORE_EVENT_STORY checks=", checks, " failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)
