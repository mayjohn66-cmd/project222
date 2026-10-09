class_name ExpeditionReturnGuideData
extends RefCounted
## Result-phase lookup only. The bag includes both carried-in and acquired items.
const ENABLED := true

static func snapshot(bag: ExpeditionBag) -> Dictionary:
	var result := {"valid":false,"rows":[],"text":"가방 정보를 확인할 수 없습니다. 원정 결과의 안내를 확인하세요."}
	if bag == null: return result
	var totals := {}
	var seen := {}
	for placement in bag.placements:
		var item := str(placement.get("item_id",""))
		var uid := int(placement.get("uid",-1))
		var amount := int(placement.get("amount",0))
		if not ItemData.has_item(item) or uid < 0 or amount <= 0 or seen.has(uid): return result
		seen[uid] = true
		totals[item] = int(totals.get(item,0)) + amount
	var requests := RequestPreparationData.entries()
	for item in totals:
		var lines: Array[String] = []
		var deposited := ItemData.should_deposit_after_expedition(item)
		lines.append("확인 후 소지품으로 이동 · 창고 선반이나 보존 설비에 넣는 과정은 별도입니다." if deposited else "가방에 유지 · 다음 원정 준비 때 가방에서 확인하세요.")
		if ItemData.is_sellable(item) and ItemData.is_shelf_allowed(item):
			lines.append("복귀 후 진열대에서 [E]로 보충하면 손님이 고를 수 있습니다. 계산을 마쳐야 판매됩니다.")
		elif ItemData.is_sellable(item):
			lines.append("진열대에 놓을 수 없는 물품입니다.")
		else:
			lines.append("가게에서 판매하는 상품이 아닙니다.")
		var outputs := InventoryItemGuide.learned_outputs(item)
		if not outputs.is_empty():
			var names: Array[String] = []
			for output in outputs.slice(0,2): names.append(ItemData.get_item_name(output))
			lines.append("배운 가공에 사용 · %s%s. 생산실과 설비·나머지 재료를 확인하고 완성품을 수령하세요." % ["·".join(names)," 외" if outputs.size() > 2 else ""])
		for entry in requests:
			for requirement in entry["requirements"]:
				if str(requirement["kind"]) != "item": continue
				var group := str(requirement["group"])
				var matches: bool = str(requirement["item"]) == item if group.is_empty() else FishingData.group(group).has(item)
				if not matches: continue
				lines.append("맡은 부탁 · %s · %s%d개 필요. 복귀 뒤 수첩 [N]에서 전달 장소와 다른 조건도 확인하세요." % [entry["title"],"대체 후보 한 종류 " if not group.is_empty() else "이 물품 ",requirement["amount"]])
		var rule := PreservationGuide.material(item)
		if not rule.is_empty():
			lines.append(PreservationGuide.ambient_hint(item))
			lines.append("상온 변형을 피하려면 이 재료에 맞는 보존 설비에 직접 넣어야 합니다.")
		if FoodShelfLife.tracked(item):
			lines.append("기한이 있는 식품 · 복귀 후 소지품 상세와 보존 설비에서 상태를 살피고, 필요한 만큼 진열하세요.")
		if RecipeUnlockData.is_scroll(item):
			lines.append("이미 배운 제조법의 두루마리입니다." if PlayerProgress.is_recipe_learned(RecipeUnlockData.get_recipe_id_for_scroll(item)) else "제조법은 아직 배우지 않았습니다. 실제 두루마리 사용과 제작 조건을 확인하세요.")
		result["rows"].append({"item":item,"amount":int(totals[item]),"deposited":deposited,"text":"\n".join(lines)})
	result["valid"] = true
	var sections: Array[String] = ["[가방 물품 활용 안내]", "가방에 챙겨 왔던 물품도 함께 표시됩니다. 돌아가서 진열하거나 이웃에게 전할 물품을 골라 보세요.", "확인 버튼으로 재료를 소지품에 옮긴 뒤, 가게에서 진열·전달·보관하세요."]
	if totals.is_empty(): sections.append("가방에 남은 물품이 없습니다. 확인 버튼으로 가게에 돌아갈 수 있습니다.")
	for row in result["rows"]:
		sections.append("%s ×%d\n%s" % [ItemData.get_item_name(row["item"]),row["amount"],row["text"]])
	sections.append("복귀하면서 날짜가 바뀔 수 있으니, 재료의 변형·기한과 맡은 부탁은 가게에서 다시 확인하세요.")
	result["text"] = "\n\n".join(sections)
	return result
