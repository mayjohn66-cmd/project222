class_name BlacksmithEquipmentAdapter
extends RefCounted
## 서비스에는 실제 저장 원본의 ID를 넘긴다. 화면의 복사본/이전 단계는 다시 검사한다.
static func entries() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var ids: Dictionary = {}
	for source in ["owned", "bag"]:
		var items := GameState.get_owned_equipment_instances() if source == "owned" else GameState.get_saved_expedition_bag()
		for item in items:
			var id := int(item.get("instance_id", -1))
			if id <= 0 or not ExpeditionEquipmentData.is_enhanceable(str(item.get("item_id", ""))): continue
			if ids.has(id):
				# 같은 ID가 두 원본에 있으면 어느 쪽도 임의로 바꾸지 않는다.
				result = result.filter(func(entry): return int(entry["instance_id"]) != id)
				continue
			ids[id] = true
			item["source"] = source
			result.append(item)
	return result
static func find(id: int) -> Dictionary:
	for entry in entries():
		if int(entry["instance_id"]) == id: return entry
	return {}
static func enhance(snapshot: Dictionary) -> Dictionary:
	if not BlacksmithProgressionFlow.service_available(): return _failure("대장장이와 작업장을 먼저 만나세요.")
	var id := int(snapshot.get("instance_id", -1))
	var current := find(id)
	if current.is_empty() or current.get("source") != snapshot.get("source") or current.get("item_id") != snapshot.get("item_id") or int(current.get("enhancement_level", 0)) != int(snapshot.get("enhancement_level", -1)):
		return _failure("장비가 달라졌습니다. 목록에서 다시 선택하세요.")
	var old_owned := GameState.get_owned_equipment_instances()
	var old_bag := GameState.get_saved_expedition_bag()
	var result := EquipmentEnhancementService.enhance_equipment(current)
	if not result.get("success", false): return result
	if current["source"] == "bag":
		for item in GameState.saved_expedition_bag:
			if int(item.get("instance_id", -1)) == id: item["enhancement_level"] = int(result["new_level"])
	var persisted := find(id)
	if persisted.is_empty() or int(persisted.get("enhancement_level", -1)) != int(result["new_level"]):
		GameState.owned_equipment_instances = old_owned
		GameState.save_expedition_bag(old_bag)
		for material in result.get("consumed", {}): GameState.add_item(str(material), int(result["consumed"][material]))
		return _failure("저장 원본을 확인하지 못했습니다. 재료와 장비를 복구했습니다.")
	BlacksmithProgressionRecords.enhanced()
	return result
static func _failure(message: String) -> Dictionary: return {"success":false, "message":message}
