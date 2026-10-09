class_name ResidentMerchantSupply
extends RefCounted
## 타블렌의 기존 노점에서만 판매. 가격과 상품은 기존 원정 상점 CSV를 읽는다.
const ENABLED := true
const ACTION_PREFIX := "supply:"

static func available() -> bool:
	var life = load("res://script/world/shop/requests/village_life_flow.gd")
	return ENABLED and life.available(life.resident("naru")) and life.friendship("naru") >= 1

static func items() -> Array[String]:
	return ExpeditionShopData.get_items_by_category(ExpeditionShopData.CATEGORY_TOOL)

static func owns_effect(effect: String) -> bool:
	if effect.is_empty(): return false
	var equipment: Array = GameState.get_owned_equipment_instances().duplicate(true)
	equipment.append_array(GameState.get_saved_expedition_bag())
	for entry in equipment:
		var id := str(entry.get("item_id", ""))
		if ExpeditionEquipmentData.has_equipment(id) and ExpeditionEquipmentData.get_equipment_type(id) == ExpeditionEquipmentData.TYPE_TOOL and ExpeditionEquipmentData.get_effect_id(id) == effect: return true
	return false

static func blocked_reason(id: String) -> String:
	if not available(): return "타블렌의 노점을 마련한 뒤 먼저 안부를 나눠 주세요."
	if id not in items() or not ItemData.has_item(id) or not ExpeditionEquipmentData.has_equipment(id) or ExpeditionEquipmentData.get_equipment_type(id) != ExpeditionEquipmentData.TYPE_TOOL: return "판매하지 않는 도구입니다."
	if owns_effect(ExpeditionEquipmentData.get_effect_id(id)): return "같은 용도의 도구를 이미 보유하고 있어요."
	var price := ExpeditionShopData.get_price(id)
	if price <= 0: return "판매 준비 중입니다."
	if not GameState.can_afford(price): return "소지금이 부족해요. 모은 재료를 가게에 진열해 판매해 보세요."
	return ""

static func buy(id: String) -> Dictionary:
	if not blocked_reason(id).is_empty(): return {}
	var price := ExpeditionShopData.get_price(id)
	if not GameState.spend_money(price): return {}
	var instance := GameState.create_owned_equipment_instance(id, 0)
	if instance <= 0:
		GameState.add_money(price)
		return {}
	return {"item":id, "instance":instance, "price":price}

static func water_ready(request: Dictionary) -> bool:
	if not ENABLED or ResidentRequestFlow.done("traveler_water"): return true
	# 이전 저장에서 이미 구한 물이나 도구로 진행하던 부탁은 그대로 끝낼 수 있다.
	var prepared := owns_effect("collect_water") or GameState.get_item_count("raw_water") >= int(request.get("amount", 2))
	if ResidentRequestFlow.accepted("traveler_water"): return prepared
	return ResidentRequestFlow.done("settle_naru") and prepared

static func next_step() -> String:
	if not ENABLED or ResidentRequestFlow.done("traveler_water") or not ResidentRequestFlow.done("neighbor_bread") or not ResidentRequestFlow.done("gatherer_herbs"): return ""
	if not ResidentStoryFlow.introduction_read("peddler"): return "가게를 열어 행상인 타블렌을 만나세요. 채집 도구를 구할 길을 먼저 마련합니다."
	if not ResidentRequestFlow.done("settle_naru"): return "타블렌의 부탁으로 노점 자리를 마련하세요."
	var life = load("res://script/world/shop/requests/village_life_flow.gd")
	if life.friendship("naru") < 1: return "노점에 있는 타블렌에게 안부를 나눈 뒤 도구를 살펴보세요. [E]"
	return "타블렌의 노점 [E] → 채집용 물병 구매 → 원정 가방에 넣기. 도구를 준비하면 라슈가 물을 부탁합니다."
