class_name StoreEventStory
extends RefCounted

const SETTINGS = preload("res://scenes/shop/events/default_store_event_story.tres")

static func moment(event_id: String, stage: String) -> Dictionary:
	for entry in SETTINGS.moments:
		if str(entry.get("event_id", "")) == event_id and str(entry.get("stage", "")) == stage:
			var result: Dictionary = entry.duplicate(true)
			if event_id.begins_with("fish_store_") and result.has("cue_items"):
				result["cue_items"] = result["cue_items"].filter(func(item):return FishingRecords.market_item_available(str(item)))
			return result
	return {}

static func phase(event: Dictionary, day: int) -> String:
	if not event.has("occurrence_id"): event = StoreEventSchedule.occurrence(event, day)
	if day < int(event.get("start_day", 0)): return "rumor"
	if day > int(event.get("end_day", 0)): return "finished"
	if day == int(event.get("end_day", 0)): return "closing"
	return "ongoing"

static func prose(event: Dictionary, day: int) -> Dictionary:
	var entry := moment(str(event.get("event_id", "")), phase(event, day))
	return RequestTextData.entry("service_text", str(entry.get("id", "")))

static func timing(event: Dictionary, day: int) -> String:
	if not event.has("occurrence_id"): event = StoreEventSchedule.occurrence(event, day)
	match phase(event, day):
		"rumor":
			return "내일을 앞둔 이야기" if int(event.get("start_day", 0)) - day == 1 else "머지않아 있을 일"
		"ongoing": return "마을에서 한창인 이야기"
		"closing": return "오늘이면 마무리될 이야기"
	return "지나간 마을 이야기"

static func title(event: Dictionary, day: int) -> String:
	return str(prose(event, day).get("title", event.get("title", "마을 이야기")))

static func rumor_text(event: Dictionary, day: int) -> String:
	var text := prose(event, day)
	var lines := str(text.get("lines", event.get("description", ""))).replace("|", "\n")
	return "%s\n%s · %s\n\n%s\n\n들은 이야기는 관리 메뉴의 일정 탭에 적어 두었습니다." % [title(event, day), StoreEventSchedule.category_label(event), timing(event, day), lines]

static func note_text(event: Dictionary, day: int) -> String:
	var text := prose(event, day)
	return "[%s]\n[%s] %s\n\n%s\n\n%s" % [StoreEventSchedule.category_label(event), timing(event, day), title(event, day), str(text.get("lines", event.get("description", ""))).replace("|", "\n"), str(text.get("summary", ""))]

# 배율과 수량의 원본은 기존 수요 CSV. 반응은 그 수요가 실제 선택된 구매에만 붙인다.
static func reaction(event_id: String, customer_type: String, item_id: String, stage: String, day: int) -> String:
	if stage not in ["bought", "missing"] or not StoreEventData.is_event_active(event_id, day): return ""
	var owners: Array[String] = [customer_type]
	var group := CustomerTypeData.get_group_id(customer_type)
	if not group.is_empty() and group not in owners: owners.append(group)
	var matches := false
	for owner in owners:
		for demand in StoreEventDemandData.get_event_demand_entries(event_id, owner):
			if str(demand["target_type"]) == "item" and str(demand["target_id"]) == item_id:
				matches = true
			if str(demand["target_type"]) == "category" and ItemData.get_item_category(item_id) == str(demand["target_id"]):
				matches = true
	if not matches: return ""
	var entry := moment(event_id, stage)
	return RequestTextData.text("service_text", str(entry.get("id", "")), "lines").replace("{item}", ItemData.get_item_name(item_id)).replace("|", "\n")
