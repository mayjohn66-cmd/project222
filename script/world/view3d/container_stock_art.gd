class_name ContainerStockArt
extends RefCounted
## 가구 전체의 빈/수납 두 상태만 읽는다. 물품 이름·개수로 그림을 합성하지 않는다.
const COLD_UNITS := {"fridge_unit":"fridge","freezer_unit":"freezer"}

static func filled(node: Node, build_id: String, preview: bool = false) -> bool:
	if preview: return false
	if COLD_UNITS.has(build_id):
		# count()의 기한 정산을 호출하지 않는다. 표시 층은 현재 저장값을 읽기만 한다.
		for amount in GameState.preservation_state.get(COLD_UNITS[build_id],{}).values():
			if int(amount) > 0: return true
		return false
	var slots: Variant = node.get("storage_slots" if build_id.ends_with("warehouse_rack") else "slots")
	if not slots is Array: return false
	for slot in slots:
		if not str(slot.get("item_id","")).is_empty() and int(slot.get("amount" if build_id.ends_with("warehouse_rack") else "stock",0)) > 0:
			return true
	return false

static func cold_pair(build_id: String, rotation: int) -> Dictionary:
	var root := "res://art/received/furniture/%s/" % build_id
	var empty := root + "empty_rotation_%d.png" % posmod(rotation,4)
	var stocked := root + "filled_rotation_%d.png" % posmod(rotation,4)
	if ResourceLoader.exists(empty) and ResourceLoader.exists(stocked):
		return {"empty":empty,"filled":stocked,"ready":true}
	# 두 장이 함께 준비될 때 연결한다. 없는 그림을 상품 아이콘/모델로 대신 만들지 않는다.
	var closed := ReceivedWorldArt.furniture_path(build_id,rotation)
	return {"empty":closed,"filled":closed,"ready":false}
