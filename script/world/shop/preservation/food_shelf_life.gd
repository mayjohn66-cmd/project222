class_name FoodShelfLife
extends RefCounted
## Quantities remain in existing containers. Batches only describe those quantities.
## Transfer APIs move the original batches; ordinary acquisition creates a fresh batch.
const SETTINGS = preload("res://scenes/shop/preservation/default_food_shelf_life.tres")
static var _rules: Dictionary = {}
static var _settling: bool = false

static func rules() -> Dictionary:
	if not _rules.is_empty(): return _rules
	var file := FileAccess.open("res://data/shop/catalogs/economy/food_shelf_life.csv", FileAccess.READ)
	file.get_csv_line()
	while not file.eof_reached():
		var row := file.get_csv_line()
		if row.size() == 3 and not row[0].is_empty():
			_rules[row[0]] = {"days":int(row[1]), "freezable":row[2] == "true"}
	return _rules

static func tracked(item: String) -> bool: return rules().has(item)

static func state() -> Dictionary:
	if GameState.preservation_state.is_empty():
		GameState.preservation_state = PreservationService.initial_state(GameState.total_day)
	if not GameState.preservation_state.has("food"):
		GameState.preservation_state["food"] = {"inventory":{}, "fridge":{}, "freezer":{}, "waste":{}, "markdown":true, "notice_day":0, "notice":"", "learned":false}
	return GameState.preservation_state["food"]

static func fresh(amount: int) -> Array:
	return [{"amount":amount, "age":0, "day":GameState.total_day}] if amount > 0 else []

static func quantity(batches: Array) -> int:
	var count := 0
	for batch in batches: count += int(batch["amount"])
	return count

static func normalize(batches: Array, count: int) -> void:
	# Old saves and initial fixtures have no batch field. Adopt their stock once,
	# at the current day, without retroactively expiring an old player's goods.
	var missing := count - quantity(batches)
	if missing > 0: batches.append_array(fresh(missing))
	elif missing < 0: take(batches, -missing)
	compact(batches)

static func compact(batches: Array) -> void:
	var groups: Dictionary = {}
	for batch in batches:
		var key := "%d:%d" % [batch["age"], batch["day"]]
		if groups.has(key): groups[key]["amount"] = int(groups[key]["amount"]) + int(batch["amount"])
		else: groups[key] = batch.duplicate(true)
	batches.clear()
	batches.append_array(groups.values())

static func take(batches: Array, amount: int) -> Array:
	batches.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["age"]) > int(b["age"]))
	var result: Array = []
	while amount > 0 and not batches.is_empty():
		var batch: Dictionary = batches[0]
		var moved := mini(amount, int(batch["amount"]))
		var part: Dictionary = batch.duplicate(true)
		part["amount"] = moved
		result.append(part)
		batch["amount"] = int(batch["amount"]) - moved
		if int(batch["amount"]) == 0: batches.pop_front()
		amount -= moved
	return result

static func slot_batches(slot: Dictionary, key: String = "stock") -> Array:
	if not slot.has("food_batches"): slot["food_batches"] = []
	var batches: Array = slot["food_batches"]
	normalize(batches, int(slot.get(key, 0)))
	return batches

static func zone_batches(zone: String, item: String, count: int) -> Array:
	var contents: Dictionary = state()[zone]
	if not contents.has(item): contents[item] = []
	var batches: Array = contents[item]
	normalize(batches, count)
	return batches

static func inventory_added(item: String, amount: int, batches: Array = []) -> void:
	if not tracked(item): return
	var owned := zone_batches("inventory", item, int(GameState.inventory.get(item, 0)) - amount)
	var incoming := batches.duplicate(true) if not batches.is_empty() else fresh(amount)
	normalize(incoming, amount)
	owned.append_array(incoming)
	compact(owned)

static func inventory_removed(item: String, amount: int) -> void:
	if tracked(item): take(zone_batches("inventory", item, int(GameState.inventory.get(item, 0))), amount)

static func take_inventory(item: String, amount: int) -> Array:
	settle()
	var count := mini(maxi(amount, 0), int(GameState.inventory.get(item, 0)))
	var copy := zone_batches("inventory", item, int(GameState.inventory.get(item, 0))).duplicate(true)
	var result := take(copy, count)
	GameState.remove_item(item, count)
	return result

static func peek_inventory(item: String, amount: int) -> Array:
	settle()
	var copy := zone_batches("inventory", item, int(GameState.inventory.get(item, 0))).duplicate(true)
	return take(copy, mini(amount, int(GameState.inventory.get(item, 0))))

static func learning() -> bool:
	if not PlayerProgress.story_beat_days.has("tutorial_event:opening_prologue_v1"): return false
	for step in SETTINGS.grace_steps:
		if not PlayerProgress.story_beat_days.has("tutorial_step:" + step + ":done"): return true
	return false

static func _age(item: String, batches: Array, rate: int, report: bool = true) -> void:
	var limit := int(rules()[item]["days"]) * SETTINGS.ambient_age
	for i in range(batches.size() - 1, -1, -1):
		var batch: Dictionary = batches[i]
		var baseline := maxi(int(batch["day"]), int(state().get("grace_ended_day", 0)))
		var elapsed := maxi(0, GameState.total_day - baseline)
		batch["age"] = int(batch["age"]) + elapsed * (0 if learning() else rate)
		batch["day"] = GameState.total_day
		if int(batch["age"]) >= limit:
			if report:
				var waste: Dictionary = state()["waste"]
				waste[item] = int(waste.get(item, 0)) + int(batch["amount"])
			batches.remove_at(i)

static func settle_slots(slots: Array, key: String = "stock") -> bool:
	var changed := false
	for slot in slots:
		var item := str(slot.get("item_id", ""))
		if not tracked(item): continue
		var batches := slot_batches(slot, key)
		_age(item, batches, SETTINGS.ambient_age)
		if int(slot.get(key, 0)) != quantity(batches): changed = true
		slot[key] = quantity(batches)
		# An empty shelf keeps its assigned product; warehouse empty slots do not.
		if key == "amount" and int(slot[key]) == 0:
			slot["item_id"] = ""
			slot.erase("food_batches")
	return changed

static func settle() -> void:
	if _settling: return
	_settling = true
	var food := state()
	var protected := learning()
	if bool(food.get("grace_active", false)) and not protected:
		food["grace_ended_day"] = GameState.total_day
	food["grace_active"] = protected
	ExpeditionFoodBatches.settle_owned_stock()
	var inventory_changed := false
	for zone in ["inventory", "fridge", "freezer"]:
		var counts: Dictionary = GameState.inventory if zone == "inventory" else GameState.preservation_state[zone]
		var rate: int = SETTINGS.ambient_age if zone == "inventory" else (SETTINGS.fridge_age if zone == "fridge" else SETTINGS.freezer_age)
		for item in rules():
			var batches := zone_batches(zone, item, int(counts.get(item, 0)))
			_age(item, batches, rate)
			if counts.has(item):
				if zone == "inventory" and int(counts[item]) != quantity(batches): inventory_changed = true
				counts[item] = quantity(batches)
				if zone != "inventory" and int(counts[item]) == 0: counts.erase(item)
	var tree := GameState.get_tree()
	var live: Array = []
	if tree != null:
		for group in ["shelf", "warehouse_storage"]:
			for node in tree.get_nodes_in_group(group):
				if node.is_queued_for_deletion() or node.get_meta("is_build_preview", false): continue
				live.append(node)
				if group == "shelf":
					if settle_slots(node.slots): node.update_stock_label()
				else:
					if settle_slots(node.storage_slots, "amount"): node._rebuild_stored_items()
	# Layout is a mirror of live objects, not a second set of owned stock.
	# When the shop scene is absent (expedition), the saved layout owns the stock.
	if live.is_empty():
		for entry in GameState.store_layout:
			settle_slots(entry.get("shelf_slots", []))
			# Warehouse layouts may contain two legacy aliases of the same stock.
			var slots: Array = entry.get("storage_slots", entry.get("warehouse_slots", []))
			settle_slots(slots, "amount")
			if entry.has("storage_slots") and entry.has("warehouse_slots"):
				entry["warehouse_slots"] = slots.duplicate(true)
	if inventory_changed: GameState.rebuild_inventory_slots_from_counts()
	_settling = false

static func prepare_save() -> void:
	# Save the current containers after settlement, so an older layout mirror
	# cannot bring expired or sold stock back on reload.
	settle()
	_sync_layout(GameState.get_tree().root)

static func _sync_layout(node: Node) -> void:
	if node.is_queued_for_deletion(): return
	if node.scene_file_path == "res://scenes/shop/main.tscn":
		var builder := node.get_node_or_null("BuildManager")
		if builder != null and builder.is_node_ready():
			var current: Array = builder.get_store_layout_data()
			for entry in GameState.store_layout:
				for live in current:
					if entry.get("anchor") != live.get("anchor") or entry.get("room_id", "store") != live.get("room_id", "store") or entry.get("build_id") != live.get("build_id"): continue
					for key in ["shelf_slots", "storage_slots", "warehouse_slots"]:
						if _contains_food(entry.get(key, [])) or _contains_food(live.get(key, [])):
							entry[key] = live.get(key, []).duplicate(true)
		return
	for child in node.get_children(): _sync_layout(child)

static func _contains_food(slots: Array) -> bool:
	for slot in slots:
		if tracked(str(slot.get("item_id", ""))) or not slot.get("food_batches", []).is_empty(): return true
	return false

static func days_left(item: String, batch: Dictionary) -> int:
	return maxi(0, ceili(float(int(rules()[item]["days"]) * SETTINGS.ambient_age - int(batch.get("age", 0))) / SETTINGS.ambient_age))

static func unit_price(item: String, batch: Dictionary) -> int:
	if days_left(item, batch) <= 0: return 0
	var price: int = ItemData.get_item_price(item)
	if state()["markdown"] and days_left(item, batch) <= SETTINGS.markdown_days:
		return maxi(1, price * (100 - SETTINGS.markdown_percent) / 100)
	return price

static func receipt_total(item: String, batches: Array) -> int:
	var total := 0
	for batch in batches: total += unit_price(item, batch) * int(batch["amount"])
	return total

static func describe(item: String, batches: Array = []) -> String:
	if not tracked(item): return ""
	var remaining := int(rules()[item]["days"])
	for batch in batches: remaining = mini(remaining, days_left(item, batch))
	var hint := "마감 할인 %d%%" % SETTINGS.markdown_percent if remaining <= SETTINGS.markdown_days and state()["markdown"] else "신선"
	return "유통기한 · 가장 빠른 재고 %d일 남음 · %s\n상온 %d일 / 냉장에서는 기한이 천천히 줄어듦 / %s" % [remaining, hint, rules()[item]["days"], "냉동 가능" if rules()[item]["freezable"] else "냉동 불가"]

static func restock_slot(shelf: Node, index: int, amount: int) -> int:
	settle()
	var slot: Dictionary = shelf.slots[index]
	var item := str(slot.get("item_id", ""))
	var moved := mini(amount, int(slot.get("capacity", 0)) - int(slot.get("stock", 0)))
	if moved <= 0: return 0
	if not tracked(item):
		return shelf.add_stock_to_slot(index, GameState.remove_item(item, moved))
	var batches := take_inventory(item, moved)
	var added: int = shelf.add_stock_to_slot(index, quantity(batches), batches)
	var remainder := batches.duplicate(true)
	take(remainder, added)
	if not remainder.is_empty(): GameState.add_item(item, quantity(remainder), remainder)
	return added

static func add_slot(slot: Dictionary, amount: int, batches: Array, key: String = "stock") -> void:
	var item := str(slot.get("item_id", ""))
	if not tracked(item): return
	# Called after the container count increases.
	if not slot.has("food_batches"): slot["food_batches"] = []
	var owned: Array = slot["food_batches"]
	normalize(owned, int(slot[key]) - amount)
	var incoming := batches.duplicate(true) if not batches.is_empty() else fresh(amount)
	owned.append_array(take(incoming, amount))
	compact(owned)

static func take_shelf(shelf: Node, item: String, amount: int) -> int:
	settle()
	var receipt: Array = []
	# Select the oldest batch across all slots, not merely the first slot.
	while amount > 0:
		var oldest: Dictionary = {}
		var target: Dictionary = {}
		for slot in shelf.slots:
			if slot.get("item_id", "") != item: continue
			for batch in slot_batches(slot):
				if oldest.is_empty() or int(batch["age"]) > int(oldest["age"]):
					oldest = batch
					target = slot
		if oldest.is_empty(): break
		var moved := mini(amount, int(oldest["amount"]))
		receipt.append_array(take(target["food_batches"], moved))
		target["stock"] = int(target["stock"]) - moved
		amount -= moved
	shelf.set_meta("food_receipt", receipt)
	shelf.update_stock_label()
	return quantity(receipt)

static func return_shelf(shelf: Node, item: String, amount: int, batches: Array) -> int:
	settle()
	var incoming := batches.duplicate(true) if not batches.is_empty() else fresh(amount)
	var returned := 0
	for i in range(shelf.slots.size()):
		if shelf.slots[i].get("item_id", "") != item: continue
		var slot: Dictionary = shelf.slots[i]
		var moved := mini(amount - returned, int(slot["capacity"]) - int(slot["stock"]))
		if moved <= 0: continue
		var part := take(incoming, moved)
		returned += shelf.add_stock_to_slot(i, quantity(part), part)
	shelf.update_stock_label()
	return returned

static func capture(customer: Node, shelf: Node, append: bool = false) -> void:
	var batches: Array = customer.get_meta("food_batches", []) if append else []
	if tracked(customer.carried_item_id):
		batches.append_array(shelf.get_meta("food_receipt", []).duplicate(true))
	customer.set_meta("food_batches", batches)

static func customer_batches(customer: Node) -> Array:
	settle()
	var batches: Array = customer.get_meta("food_batches", [])
	if not tracked(customer.carried_item_id): return batches
	normalize(batches, customer.carried_amount)
	_age(customer.carried_item_id, batches, SETTINGS.ambient_age)
	customer.carried_amount = quantity(batches)
	customer.set_meta("food_batches", batches)
	return batches

static func customer_total(customer: Node) -> int:
	if not tracked(customer.carried_item_id): return ItemData.get_item_price(customer.carried_item_id) * customer.carried_amount
	return receipt_total(customer.carried_item_id, customer_batches(customer))

static func recover_customer(customer: Node) -> void:
	var batches := customer_batches(customer)
	var item: String = customer.carried_item_id
	var returned := 0
	if is_instance_valid(customer.target_shelf) and not customer.target_shelf.is_queued_for_deletion():
		returned = customer.target_shelf.return_items_by_id(item, quantity(batches), batches)
	take(batches, returned)
	if not batches.is_empty(): GameState.add_item(item, quantity(batches), batches)
	customer.set_meta("food_batches", [])
	customer.carried_item_id = ""
	customer.carried_amount = 0

static func oldest_age(shelf: Node, item: String) -> int:
	settle()
	var age := -1
	for slot in shelf.slots:
		if slot.get("item_id", "") == item:
			for batch in slot_batches(slot): age = maxi(age, int(batch["age"]))
	return age

static func ordered_shelves(shelves: Array, item: String) -> Array:
	var result := shelves.duplicate()
	if tracked(item): result.sort_custom(func(a: Node, b: Node) -> bool: return oldest_age(a, item) > oldest_age(b, item))
	return result

static func morning_summary() -> String:
	settle()
	var totals: Dictionary = {}
	for item in rules():
		var amount := 0
		for zone in ["inventory", "fridge", "freezer"]:
			for batch in state()[zone].get(item, []):
				if days_left(item, batch) <= SETTINGS.markdown_days: amount += int(batch["amount"])
		var tree := GameState.get_tree()
		for group in ["shelf", "warehouse_storage"]:
			for node in tree.get_nodes_in_group(group):
				if node.is_queued_for_deletion() or node.get_meta("is_build_preview", false): continue
				var slots: Array = node.slots if group == "shelf" else node.storage_slots
				for slot in slots:
					if slot.get("item_id", "") != item: continue
					for batch in slot.get("food_batches", []):
						if days_left(item, batch) <= SETTINGS.markdown_days: amount += int(batch["amount"])
		if amount > 0: totals[item] = amount
	var parts: Array[String] = []
	for item in totals: parts.append("%s %d개" % [ItemData.get_item_name(item), totals[item]])
	var message := "오늘 먼저 살펴볼 식품: " + " · ".join(parts) if not parts.is_empty() else "오늘은 서둘러 내놓을 식품이 없네요."
	if not state()["waste"].is_empty(): message += "\n기한이 지난 식품은 판매 재고에서 분리했습니다. 계산대에서 정리해 주세요."
	return message

static func claim_morning_notice() -> String:
	settle()
	if learning() or int(state()["notice_day"]) >= GameState.total_day: return ""
	state()["notice_day"] = GameState.total_day
	state()["notice"] = morning_summary()
	return str(state()["notice"])

static func discard(item: String, amount: int, recycle: bool = false) -> int:
	settle()
	var waste: Dictionary = state()["waste"]
	var moved := mini(maxi(amount, 0), int(waste.get(item, 0)))
	if recycle: moved -= moved % SETTINGS.recycle_input
	if moved <= 0: return 0
	waste[item] = int(waste[item]) - moved
	if int(waste[item]) == 0: waste.erase(item)
	if recycle: GameState.add_item(SETTINGS.recycle_item, moved / SETTINGS.recycle_input * SETTINGS.recycle_output)
	return moved

static func valid_batches(value: Variant, count: int, day: int) -> bool:
	if not value is Array: return false
	var total := 0
	for batch in value:
		if not batch is Dictionary: return false
		for key in ["amount", "age", "day"]:
			if not batch.get(key) is int: return false
		if batch["amount"] <= 0 or batch["age"] < 0 or batch["day"] < 1 or batch["day"] > day: return false
		total += int(batch["amount"])
	return total == count

static func valid_save(data: Dictionary) -> bool:
	if not ExpeditionFoodBatches.valid_save(data): return false
	if not data.get("store_layout", []) is Array: return false
	var preservation: Variant = data.get("preservation", {})
	if not preservation is Dictionary: return false
	var day := int(data.get("total_day", data.get("current_day", 1)))
	if preservation.has("food"):
		var food: Variant = preservation["food"]
		if not food is Dictionary: return false
		if not food.get("markdown") is bool or not food.get("learned") is bool or not food.get("notice") is String: return false
		if not food.get("notice_day") is int or food["notice_day"] < 0 or food["notice_day"] > day: return false
		if food.has("grace_active") and not food["grace_active"] is bool: return false
		if food.has("grace_ended_day") and (not food["grace_ended_day"] is int or food["grace_ended_day"] < 1 or food["grace_ended_day"] > day): return false
		if not food.get("waste") is Dictionary: return false
		for item in food["waste"]:
			if not item is String: return false
			if not tracked(item) or not food["waste"][item] is int or food["waste"][item] <= 0: return false
		for zone in ["inventory", "fridge", "freezer"]:
			if not food.get(zone) is Dictionary: return false
			var counts: Variant = data.get("inventory", {}) if zone == "inventory" else preservation.get(zone, {})
			if not counts is Dictionary: return false
			for item in food[zone]:
				if not item is String: return false
				if not tracked(item) or not valid_batches(food[zone][item], int(counts.get(item, 0)), day): return false
			for item in rules():
				if int(counts.get(item, 0)) > 0 and not food[zone].has(item): return false
	for entry in data.get("store_layout", []):
		if not entry is Dictionary: return false
		for key in ["shelf_slots", "storage_slots", "warehouse_slots"]:
			if not entry.get(key, []) is Array: return false
			for slot in entry.get(key, []):
				if not slot is Dictionary: return false
				if slot.has("food_batches"):
					if not slot["food_batches"] is Array: return false
					if not tracked(str(slot.get("item_id", ""))):
						if not slot["food_batches"].is_empty(): return false
						continue
					if not valid_batches(slot["food_batches"], int(slot.get("stock", slot.get("amount", 0))), day): return false
	return true
