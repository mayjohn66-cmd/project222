class_name ExpeditionLoadoutGuideData
extends RefCounted
## 조회만 한다. 실제 출발 가방과 같은 장착 판정·공격 프로필을 사용한다.
const SETTINGS = preload("res://scenes/expedition/rooms/default_room_settings.tres")

static func snapshot(bag, owned) -> Dictionary:
	var validation := ExpeditionLoadoutService.validate_loadout(bag)
	var result := {"valid":bool(validation.get("success",false)), "message":str(validation.get("message","")), "weapons":[], "armor":[], "tools":[], "unpacked":[]}
	if bag == null: return result
	var loadout := ExpeditionWeaponLoadout.new()
	loadout.build(SETTINGS,bag)
	result["attack_name"] = loadout.active_name()
	result["attack_style"] = ExpeditionWeaponLoadout.get_style_text(str(loadout.slots[0]["item_id"]) if not loadout.slots.is_empty() else "")
	result["can_swap"] = loadout.has_choice()
	for placement in bag.placements:
		var id := str(placement.get("item_id",""))
		if not ExpeditionEquipmentData.has_equipment(id): continue
		var entry := _entry(placement)
		match ExpeditionEquipmentData.get_equipment_type(id):
			ExpeditionEquipmentData.TYPE_WEAPON: result["weapons"].append(entry)
			ExpeditionEquipmentData.TYPE_ARMOR: result["armor"].append(entry)
			ExpeditionEquipmentData.TYPE_TOOL: result["tools"].append(entry)
	if owned != null:
		for placement in owned.placements:
			var id := str(placement.get("item_id",""))
			if not ExpeditionEquipmentData.has_equipment(id): continue
			result["unpacked"].append(_entry(placement))
	return result

static func _entry(placement: Dictionary) -> Dictionary:
	var id := str(placement.get("item_id",""))
	var entry := {"item_id":id, "name":ItemData.get_item_name(id), "instance_id":int(placement.get("instance_id",-1)), "level":int(placement.get("enhancement_level",0)), "type":ExpeditionEquipmentData.get_equipment_type(id)}
	entry["use"] = ExpeditionWeaponLoadout.get_style_text(id) if entry["type"] == ExpeditionEquipmentData.TYPE_WEAPON else str(ItemData.get_item(id).get("description",""))
	if entry["type"] == ExpeditionEquipmentData.TYPE_TOOL:
		ExpeditionGatheringData.ensure_loaded()
		var descriptions: Array[String] = []
		var effect := ExpeditionEquipmentData.get_effect_id(id)
		for table in ExpeditionGatheringData.rules:
			var rule: Dictionary = ExpeditionGatheringData.rules[table]
			if str(rule.get("tool_effect_id","")) != effect: continue
			var target := str(table).trim_prefix("gather_")
			# 기존 채집 대상만 설명하며 새 효과나 성공 보장을 만들지 않는다.
			var name: String = {"water":"물을 뜨기", "wheat":"밀을 거두기"}.get(target,"이 용도의 채집")
			descriptions.append(str(name) + (" · 가방에 도구가 있어야 시도할 수 있습니다." if rule.get("tool_required",false) else " · 도구 없이도 시도할 수 있고, 도구를 넣으면 채집에 도움이 됩니다."))
		entry["use"] = "\n".join(descriptions) if not descriptions.is_empty() else str(entry["use"])
	return entry

static func title(entry: Dictionary) -> String:
	return "%s +%d · 장비 #%d" % [str(entry["name"]),int(entry["level"]),int(entry["instance_id"])]
