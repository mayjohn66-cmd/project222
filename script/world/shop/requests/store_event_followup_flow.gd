class_name StoreEventFollowupFlow
extends RefCounted

const SETTINGS = preload("res://scenes/shop/requests/default_store_event_followups.tres")

# 영업 기록은 매장 전체의 품목별 결제 수량이다. 행사 가중치로 고른
# 구매인지, 특정 주민이 샀는지까지 구별하는 기록으로 해석하지 않는다.
static func qualifying_sale(entry: Dictionary) -> Dictionary:
	var event_id := str(entry.get("after_store_event", ""))
	var item_id := str(entry.get("sale_item", ""))
	if event_id.is_empty() or item_id.is_empty() or not ItemData.is_sellable(item_id): return {}
	var result: Dictionary = {}
	for record in GameState.daily_shop_history:
		var day := int(record.get("total_day", 0))
		if day < 1 or day > GameState.total_day: continue
		if not record.get("active_event_ids", []).has(event_id): continue
		if int(record.get("sold_items", {}).get(item_id, 0)) <= 0: continue
		var occurrence := StoreEventData.get_event_occurrence(event_id, day)
		if occurrence.is_empty() or day < int(occurrence["start_day"]) or day > int(occurrence["end_day"]): continue
		var available_day := int(occurrence["end_day"]) + maxi(1, int(entry.get("days_after_event", 1)))
		if result.is_empty() or available_day < int(result["available_day"]):
			result = {"sale_day":day, "available_day":available_day, "occurrence_id":str(occurrence["occurrence_id"]), "item_id":item_id}
	return result

static func locked_reason(entry: Dictionary) -> String:
	if str(entry.get("after_store_event", "")).is_empty(): return ""
	var sale := qualifying_sale(entry)
	if sale.is_empty():
		return "'%s' 때 %s을 판매한 영업 기록이 남으면 이야기가 이어져요." % [StoreEventData.get_event(str(entry["after_store_event"])).get("title", "매장 행사"), ItemData.get_item_name(str(entry.get("sale_item", "")))]
	if GameState.total_day < int(sale["available_day"]):
		return "관련 상품을 판매했어요. 행사가 끝난 뒤 이웃의 부탁이 이어져요."
	return ""
