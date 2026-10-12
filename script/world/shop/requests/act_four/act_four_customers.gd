class_name ActFourCustomers
extends RefCounted
## 기존 여행자와 동일한 수요/방문 가중치에서 시작한다. 별도 가격·무료 주문은 없다.
const TYPES := {"road_wayfarer":{"source":"backpacker","name":"길목의 길손","after":"a1_road_sign"},"road_caravan":{"source":"peddler","name":"먼 곳의 상단","after":"a2_far_caravan"}}
static func install(types: Dictionary) -> void:
	for id in TYPES:
		var source := str(TYPES[id]["source"])
		if not types.has(source): continue
		var entry: Dictionary = types[source].duplicate(true)
		entry["customer_type_id"] = id
		entry["display_name"] = TYPES[id]["name"]
		entry["description"] = "길목의 이정표를 따라 가게에 들르는 손님"
		types[id] = entry
static func available(id: String) -> bool:
	if not TYPES.has(id): return true
	# 손님 데이터 로더와 이야기 흐름 사이의 순환 호출을 피한다.
	return PlayerProgress.story_beat_days.has("act4:" + str(TYPES[id]["after"]) + ":last_done")
