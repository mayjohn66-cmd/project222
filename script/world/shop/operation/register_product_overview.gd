class_name RegisterProductOverview
extends RefCounted
## Read the current shop's actual shelf assignments, including sold-out products.

static func entries(world: Node) -> Array[Dictionary]:
	FoodShelfLife.settle()
	var products: Dictionary = {}
	var objects := world.get_node_or_null("Objects")
	for shelf in world.get_tree().get_nodes_in_group("shelf"):
		if shelf.is_queued_for_deletion() or shelf.get_parent() != objects or shelf.get_meta("is_build_preview", false): continue
		for slot in shelf.slots:
			var item := str(slot.get("item_id", ""))
			if item.is_empty() or not ItemData.has_item(item): continue
			if not products.has(item):
				products[item] = {"item_id":item, "name":ItemData.get_item_name(item), "stock":0, "capacity":0, "batches":[]}
			var product: Dictionary = products[item]
			product["stock"] += int(slot.get("stock", 0))
			product["capacity"] += int(slot.get("capacity", 0))
			if FoodShelfLife.tracked(item): product["batches"].append_array(FoodShelfLife.slot_batches(slot).duplicate(true))
	var result: Array[Dictionary] = []
	for item in products:
		var product: Dictionary = products[item]
		var prices: Array[int] = []
		var remaining := -1
		var discounted := 0
		var base: int = ShopPricing.sale_price(item)
		for batch in product["batches"]:
			var days: int = FoodShelfLife.days_left(item, batch)
			remaining = days if remaining < 0 else mini(remaining, days)
			var price: int = FoodShelfLife.unit_price(item, batch)
			prices.append(price)
			if price < base: discounted += int(batch["amount"])
		if prices.is_empty(): prices.append(base)
		product["min_price"] = prices.min()
		product["max_price"] = prices.max()
		product["days_left"] = remaining
		product["discounted"] = discounted
		product["description"] = str(ItemData.get_item(item).get("description", ""))
		product.erase("batches")
		result.append(product)
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a["name"]).naturalnocasecmp_to(str(b["name"])) < 0)
	return result

static func price_text(product: Dictionary) -> String:
	var text: String = "%dG" % product["min_price"] if product["min_price"] == product["max_price"] else "%d~%dG" % [product["min_price"], product["max_price"]]
	var step: int = ShopPricing.step_of(str(product.get("item_id", "")))
	return text if step == 0 else "%s (%s)" % [text, ShopPricing.label(step)]

static func status_text(product: Dictionary) -> String:
	if int(product["stock"]) == 0: return "품절 · 진열 필요"
	if int(product["days_left"]) < 0: return "판매 가능"
	var text := "기한 %d일" % product["days_left"]
	if int(product["discounted"]) > 0: text += " · 할인 %d개" % product["discounted"]
	return text
