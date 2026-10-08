class_name RequestPreparationData
extends RefCounted
const ENABLED := true

# Read accepted records only. Multi-step stories expose only their current step.
static func entries() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not VillageJournalFlow.available(): return result
	for entry in ResidentRequestFlow.SETTINGS.requests + ResidentStoryFlow.SETTINGS.settlement_requests:
		var id := str(entry["id"])
		if ResidentRequestFlow.accepted(id) and not ResidentRequestFlow.done(id):
			_add(result,"resident:" + id,RequestTextData.text("resident_request",id,"title","주민 부탁"),
				[{"item":entry["item"],"amount":entry["amount"]}],"부탁한 주민에게 돌아가 [E]로 전달하세요.")
	for entry in CommunityRequestFlow.SETTINGS.requests:
		var id := str(entry["id"])
		if CommunityRequestFlow.accepted(id) and not CommunityRequestFlow.done(id):
			_add(result,"community:" + id,RequestTextData.text("community_request",id,"title","마을 부탁"),entry.get("requirements",[]),"마을 부탁 게시판에서 전달하세요.")
	for entry in PersonalRequestFlow.entries():
		var id := str(entry["id"])
		if PersonalRequestFlow.accepted(id) and not PersonalRequestFlow.done(id):
			_add(result,"personal:" + id,str(entry["title"]),entry.get("requirements",[]),"마을 부탁 게시판에서 전달하세요.")
	if VillageMarketFlow.accepted() and not VillageMarketFlow.prepared() and not VillageMarketFlow.completed():
		_add(result,VillageMarketFlow.JOURNAL_ID,VillageMarketFlow.title(),VillageMarketFlow.SETTINGS.requirements,"장터를 제안한 이웃에게 [E]로 준비 물품을 전하세요.")
	for entry in SeasonalVillageFlow.events():
		var id := str(entry["id"])
		if SeasonalVillageFlow.accepted(id) and not SeasonalVillageFlow.completed(id):
			_add(result,SeasonalVillageFlow.JOURNAL_PREFIX + id,SeasonalVillageFlow.title(id),entry.get("requirements",[]),"계절 이야기의 이웃에게 돌아가 [E]로 전달하세요.")
	for entry in CraftingPathFlow.SETTINGS.stages:
		var id := str(entry["id"])
		if CraftingPathFlow.accepted(id) and not CraftingPathFlow.done(id):
			_add(result,CraftingPathFlow.JOURNAL_PREFIX + id,CraftingPathFlow.title(id),entry.get("requirements",[]),
				"이야기를 들은 뒤 실제로 제작하여 수령한 시제품이 필요합니다. 안내한 이웃에게 돌아가세요.")
	for entry in FishingContent.collection():
		var id := str(entry["id"])
		if not FishingRecords.accepted(id) or FishingRecords.done(id): continue
		var requirements: Array = entry.get("items",[]).duplicate(true)
		if id == "fishing_rod" and not FishingRecords.has("tool:fishing_rod_wood"):
			requirements = FishingData.entry("fishing_rod_wood").get("materials",[]).duplicate(true)
		_add(result,"fishing:" + id,str(entry["title"]),requirements,FishingContent.instructions(id) + "\n물가나 부탁한 사람에게 [E]로 이어서 이야기하세요.")
	for entry in VillageExpansionFlow.SETTINGS.events:
		var id := str(entry["id"])
		var step := VillageExpansionFlow.step(id)
		var note := "현재 이야기의 이웃에게 돌아가 [E]로 전달하세요."
		if step.get("mode","") == "produce": note += "\n소개 뒤 실제로 제작하여 수령한 상품이 필요합니다."
		if step.has("region"): note += "\n지정 원정에서 직접 채집한 경험도 필요합니다."
		_add(result,VillageExpansionFlow.JOURNAL_PREFIX + id,VillageExpansionFlow.title(id),step.get("requirements",[]),note)
	if ActFourFlow.started():
		for entry in ActFourFlow.SETTINGS.events:
			var id := str(entry["id"])
			var step := ActFourFlow.step(id)
			var requirements: Array = step.get("requirements",[]).duplicate(true)
			for furniture in step.get("furniture",[]):
				var item: Dictionary = furniture.duplicate(true)
				item["kind"] = "furniture"
				requirements.append(item)
			_add(result,ActFourFlow.JOURNAL_PREFIX + id,ActFourFlow.title(id),requirements,"현재 이야기의 이웃에게 돌아가 [E]로 전달하세요. 설치된 집기는 전달 재고에 포함되지 않습니다.")
	return result

static func _add(result: Array[Dictionary], id: String, title: String, values: Array, note: String) -> void:
	var totals := {}
	for value in values:
		var item := str(value.get("item",value.get("item_id","")))
		var group := str(value.get("group_id",""))
		var kind := str(value.get("kind","item"))
		var amount := int(value.get("amount",0))
		if amount <= 0 or (item.is_empty() and group.is_empty()): continue
		var key := kind + ":" + item + ":" + group
		if not totals.has(key): totals[key] = {"item":item,"group":group,"kind":kind,"amount":0}
		totals[key]["amount"] += amount
	if not totals.is_empty(): result.append({"id":id,"title":title,"requirements":totals.values(),"note":note})

static func information(world: Node, entry: Dictionary, environment: Dictionary) -> String:
	var lines: Array[String] = []
	for value in entry["requirements"]:
		var amount := int(value["amount"])
		var group := str(value["group"])
		if not group.is_empty():
			lines.append("대체 가능한 종류 중 한 종류 " + str(amount) + "개 · 모두 준비할 필요는 없습니다.")
			var known := false
			for member in FishingData.group(group):
				var item := str(member)
				if not known_choice(item): continue
				known = true
				lines.append(item_information(world,item,amount,environment))
			if not known: lines.append("물가에서 만난 물고기나 배운 상품을 확인하세요. 아직 기록한 후보가 없습니다.")
		elif value["kind"] == "furniture":
			var item := str(value["item"])
			lines.append("%s · 가구 보관함 %d / 필요 %d" % [FurnitureData.get_furniture_name(item),GameState.get_furniture_count(item),amount])
			if ShopSpaceProgression.furniture_visible(item): lines.append("설계도에서 이 집기의 제작 재료를 확인하세요.")
		else:
			lines.append(item_information(world,str(value["item"]),amount,environment))
	lines.append(str(entry["note"]))
	return "\n\n".join(lines)

static func known_choice(item: String) -> bool:
	if not ItemData.has_item(item): return false
	if GameState.get_item_count(item) > 0: return true
	if FishingData.fish(item): return FishingRecords.has("caught:" + item)
	for recipe in ProductRecipeData.get_learned_recipes():
		if recipe["result_item_id"] == item: return true
	return false

static func item_information(world: Node, item: String, amount: int, environment: Dictionary) -> String:
	if not ItemData.has_item(item): return ""
	var owned := GameState.get_item_count(item)
	var lines: Array[String] = ["%s · 전달 가능 %d / 필요 %d%s" % [ItemData.get_item_name(item),owned,amount,
		" · %d개 부족" % maxi(0,amount-owned) if owned < amount else " · 수량 준비됨"]]
	var stored := ProductPreparationData.shelf_count(world,item)
	if stored > 0: lines.append("창고 선반 %d개 · 현장에서 꺼낸 뒤 전달할 수 있습니다." % stored)
	var preserved := ProductPreparationData.preservation_note(item)
	if not preserved.is_empty(): lines.append(preserved)
	if owned < amount: lines.append(RequestItemSources.describe(world,item,amount-owned,environment))
	if FoodShelfLife.tracked(item): lines.append("날짜가 지난 식품은 전달할 수 없습니다. 보관한 물품도 꺼내기 전에 상태를 확인하세요.")
	return "\n".join(lines)
