class_name StoreEventSchedule
extends RefCounted
## 공용은 경과 일자/주기, 계절은 해당 계절 안의 날짜. UI/수요에는 절대 일자로 변환한다.
const SEASONS: PackedStringArray = ["spring", "summer", "autumn", "winter"]

static func valid(event: Dictionary) -> bool:
	var kind := str(event.get("event_kind", "common"))
	var season := str(event.get("season_id", ""))
	var repeat := int(event.get("repeat_days", 0))
	var begin := int(event.get("discovery_start_day", 0))
	var discovery_end := int(event.get("discovery_end_day", 0))
	var start := int(event.get("start_day", 0))
	var end := int(event.get("end_day", 0))
	if begin < 1 or discovery_end < begin or start <= discovery_end or end < start: return false
	if kind == "seasonal": return season in SEASONS and repeat == 0 and end <= CalendarData.DAYS_PER_SEASON
	if kind == "common": return season.is_empty() and repeat >= 0 and (repeat == 0 or end <= repeat)
	return false

static func occurrence(event: Dictionary, day: int) -> Dictionary:
	var result := event.duplicate(true)
	var offset := 0
	var cycle := 0
	if str(event.get("event_kind", "common")) == "seasonal":
		cycle = CalendarData.get_year(day) - 1
		offset = cycle * CalendarData.DAYS_PER_YEAR + SEASONS.find(str(event["season_id"])) * CalendarData.DAYS_PER_SEASON
	elif int(event.get("repeat_days", 0)) > 0:
		cycle = floori(float(maxi(day, 1) - 1) / float(event["repeat_days"]))
		offset = cycle * int(event["repeat_days"])
	for field in ["discovery_start_day", "discovery_end_day", "start_day", "end_day"]:
		result[field] = int(event.get(field, 0)) + offset
	result["occurrence_id"] = "%s:%d" % [event.get("event_id", ""), cycle]
	return result

static func active(event: Dictionary, day: int) -> bool:
	var instance := occurrence(event, day)
	return day >= int(instance["start_day"]) and day <= int(instance["end_day"])

static func heard(event: Dictionary, day: int, discovery_day: int) -> bool:
	if discovery_day < 1: return false
	return occurrence(event, day)["occurrence_id"] == occurrence(event, discovery_day)["occurrence_id"]

static func category_label(event: Dictionary) -> String:
	if str(event.get("event_kind", "common")) == "common": return "공용 이벤트"
	var names: PackedStringArray = ["봄", "여름", "가을", "겨울"]
	var index := SEASONS.find(str(event.get("season_id", "")))
	return "계절 이벤트 · " + (names[index] if index >= 0 else "")
