class_name RoomPreparationGuide
extends RefCounted
# Guidance only reads real room objects. Navigation never constructs or completes a step.
const ENABLED := true
const FIRST_RECIPE := "camp_bread"
const FIRST_FACILITY := "magic_oven"

static func world_for(host: Node) -> Node:
	var node := host
	while node != null and node.get_node_or_null("DayManager") == null: node = node.get_parent()
	return node

static func next_action(host: Node) -> Dictionary:
	if not ENABLED or not ShopSpaceProgression.active(): return {}
	var world := world_for(host)
	if world == null: return {}
	match ShopSpaceProgression.phase():
		"produce": return production(world)
		"store_materials": return warehouse(world)
	return {}

static func info(current: String, next: String, note: String, action := "", id := "") -> Dictionary:
	return {"current":current,"next":next,"note":note,"action":action,"id":id}

static func production(world: Node) -> Dictionary:
	var ovens: Array[ProductionFacility] = []
	var room := world.get_node("ProductionRoom")
	for node in ProductPreparationData.facilities(world,FIRST_FACILITY):
		if room.is_ancestor_of(node): ovens.append(node)
	var current := "생산실을 마련했습니다.\n화덕 설치: %d대" % ovens.size()
	if not ShopSpaceProgression.marked("production_entered"):
		return info(current,"지금 할 일 · 생산실에 들어가기\n가게 벽의 생산실 문에서 [E]를 누르세요.","문을 설치한 뒤에도 직접 들어가 설비를 준비해야 합니다.")
	if ovens.is_empty():
		return installation(current,FIRST_FACILITY,"생산실","첫 화덕을 준비하면 배운 상품을 만들 수 있습니다.")
	# A finished batch comes before starting another one, including a different product.
	for oven in ovens:
		if oven.has_collectable_output():
			var name := ItemData.get_item_name(oven.pending_item_id)
			return info(current,"지금 할 일 · 완성품 수령\n생산실 화덕에서 [E]로 %s %d개를 받으세요." % [name,oven.pending_amount],"현지식 빵을 실제 수령하면 다음 공간을 준비할 수 있습니다.","facilities")
	var available: Dictionary = {}
	for recipe in ProductRecipeData.get_learned_recipes():
		if str(recipe["recipe_id"]) == FIRST_RECIPE: available = recipe; break
	if available.is_empty():
		if ProductNextStepGuidance.ENABLED and ProductNextStepGuidance.owned_first_scroll():
			return info(current,"지금 할 일 · 받은 제조법 배우기\n인벤토리에서 현지식 빵 제조법 두루마리를 선택하고 ‘배우기’를 누르세요.","안내를 다시 받거나 두루마리를 새로 구할 필요가 없습니다. 배운 뒤 화덕에서 만듭니다.","scroll",ProductNextStepGuidance.first_scroll())
		return info(current,"지금 할 일 · 첫 제조법 확인\n타블렌의 제작 안내와 배운 상품을 확인하세요.","제조법을 배운 뒤 실제 설비에서 만들 수 있습니다.","learned")
	var required := ProductionRecipeService.collect_required_ingredients(available,1)
	var missing: Array[String] = []
	for item in required:
		var deficit := int(required[item]) - int(GameState.inventory.get(item,0))
		if deficit > 0: missing.append("%s %d개 부족" % [ItemData.get_item_name(item),deficit])
	var idle := ovens.any(func(node): return node.production_state == ProductionFacility.ProductionState.IDLE)
	if idle and not required.is_empty() and missing.is_empty() and CraftingPathFlow.recipe_ready(FIRST_RECIPE) and FishingRecords.recipe_available(FIRST_RECIPE):
		return info(current,"지금 할 일 · 첫 상품 만들기\n생산실 화덕에서 [E]로 %s을 선택하세요." % ItemData.get_item_name(str(available["result_item_id"])),"가공을 시작한 뒤 완성품을 직접 수령하세요.","today")
	if not idle:
		return info(current,"지금 할 일 · 가공 마치기\n화덕이 가공 중입니다. 책을 닫고 완료를 기다리세요.","완료 후 같은 화덕에서 [E]로 수령합니다. 책을 연 동안에는 가공도 멈춥니다.","facilities")
	return info(current,"지금 할 일 · 재료 준비\n" + (" · ".join(missing) if not missing.is_empty() else "배운 상품에서 현재 제작 조건을 확인하세요."),"보관 중인 재료는 먼저 꺼내 소지해야 합니다. 준비 후 생산실 화덕에서 [E]로 만듭니다.","today")

static func installation(current: String, id: String, room: String, note: String) -> Dictionary:
	var name := FurnitureData.get_furniture_name(id)
	if GameState.get_furniture_count(id) > 0:
		return info(current,"지금 할 일 · %s 설치\n%s 안에서 건축 모드 [B]를 열고 보유 집기를 골라 놓으세요." % [name,room],note,"inventory",id)
	return info(current,"지금 할 일 · %s 준비\n설계도에서 필요한 재료와 제작 조건을 확인하세요." % name,note,"blueprint",id)

static func warehouse(world: Node) -> Dictionary:
	var room := world.get_node("WarehouseRoom")
	var racks: Array[Node] = []
	var stored := 0
	var capacity := 0
	for node in world.get_tree().get_nodes_in_group("warehouse_storage"):
		if not is_instance_valid(node) or node.is_queued_for_deletion() or node.get_meta("is_build_preview",false) or not room.is_ancestor_of(node): continue
		racks.append(node)
		capacity += int(node.storage_capacity)
		# Raw slots avoid triggering food expiry or changing stock merely by reading guidance.
		for slot in node.storage_slots: stored += maxi(int(slot.get("amount",0)),0)
	var current := "창고를 마련했습니다.\n설치 선반: %d개 · 보관 %d / %d개" % [racks.size(),stored,capacity]
	if not ShopSpaceProgression.marked("warehouse_entered"):
		return info(current,"지금 할 일 · 창고에 들어가기\n가게 벽의 창고 문에서 [E]를 누르세요.","직접 들어가 남은 물품을 정리해 보세요.")
	if racks.is_empty():
		var id := "wood_warehouse_rack"
		for candidate in ["warehouse_rack","wood_warehouse_rack","steel_warehouse_rack"]:
			if GameState.get_furniture_count(candidate) > 0: id = candidate; break
		return installation(current,id,"창고","일반 창고 선반은 재고 정리용입니다. 냉장·냉동 보존은 별도 설비에서 합니다.")
	if stored >= capacity:
		return info(current,"지금 할 일 · 입고할 자리 마련\n창고 선반에서 [E]로 물품을 꺼내 자리를 비운 뒤 남은 물품을 넣어 보세요.","선반을 설치하거나 물품을 꺼내는 것만으로 첫 입고가 완료되지 않습니다.")
	var has_stock := GameState.inventory.values().any(func(amount): return int(amount) > 0)
	if not has_stock:
		return info(current,"지금 할 일 · 보관할 물품 준비\n원정이나 거래로 얻은 물품을 소지한 뒤 창고 선반에서 [E]를 누르세요.","창고에 있던 물품을 꺼내 다시 입고해도 됩니다. 돈이나 집기는 이 선반에 보관하지 않습니다.")
	return info(current,"지금 할 일 · 남은 물품 입고\n창고 선반에서 [E]로 소지한 물품을 하나 이상 넣어 보세요.","빈 슬롯이 없으면 기존 물품을 꺼내거나 같은 물품을 더 넣으세요. 실제 입고 후 확장 안내가 열립니다.")

static func button_text(data: Dictionary) -> String:
	match str(data.get("action","")):
		"blueprint": return "집기 제작 정보 보기"
		"inventory": return "가구 보관함 보기"
		"scroll": return "제조법 두루마리 보기"
		"today": return "상품 준비 보기"
		"learned": return "배운 상품 보기"
		"facilities": return "설비 현황 보기"
	return ""

static func open_action(host: Node) -> bool:
	var data := next_action(host) # Recheck current state when the button is pressed.
	var action := str(data.get("action",""))
	if action.is_empty(): return false
	var menu := host.get_parent()
	while menu != null and not menu.has_method("select_tab"): menu = menu.get_parent()
	if menu == null: return false
	match action:
		"blueprint":
			var id := str(data["id"])
			menu.select_tab(ManagementTabs.MenuTab.BLUEPRINT)
			menu.blueprint_content._on_category_pressed(str(FurnitureData.get_furniture(id)["craft_category"]))
			menu.blueprint_content._select_furniture(id)
		"inventory":
			menu.select_tab(ManagementTabs.MenuTab.INVENTORY)
			menu.management_inventory.select_inventory_group(ItemData.INVENTORY_GROUP_FURNITURE)
		"scroll":
			menu.select_tab(ManagementTabs.MenuTab.INVENTORY)
			menu.management_inventory.select_inventory_group(ItemData.get_inventory_group(str(data["id"])))
		"today","learned","facilities":
			menu.select_tab(ManagementTabs.MenuTab.PRODUCTION)
			if is_instance_valid(menu.management_production.preparation_book): menu.management_production.preparation_book.select_tab(action)
	return true
