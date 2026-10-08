class_name ProductPreparationData
extends RefCounted
const ENABLED := true
const MAX_EXAMPLES := 4
static func facilities(world: Node, id: String = "") -> Array[ProductionFacility]:
	var result: Array[ProductionFacility] = []
	for node in world.get_tree().get_nodes_in_group("production_facility"):
		if not is_instance_valid(node) or node.is_queued_for_deletion() or not node is ProductionFacility: continue
		if not world.is_ancestor_of(node) or node.get_meta("is_build_preview",false): continue
		if id.is_empty() or node.facility_id == id: result.append(node)
	return result
static func location(world: Node, facility: ProductionFacility) -> String:
	for room in ["ProductionRoom", "WarehouseRoom"]:
		var area := world.get_node_or_null(room)
		if area != null and area.is_ancestor_of(facility): return "생산실" if room == "ProductionRoom" else "창고"
	return "편의점"
static func shelf_count(world: Node, item: String) -> int:
	var count := 0
	for shelf in world.get_tree().get_nodes_in_group("warehouse_storage"):
		if is_instance_valid(shelf) and not shelf.is_queued_for_deletion() and world.is_ancestor_of(shelf) and not shelf.get_meta("is_build_preview",false): count += shelf.get_item_count(item)
	return count
static func ready(world: Node, recipe: Dictionary) -> String:
	if ShopSpaceProgression.active() and not ShopSpaceProgression.room_ready("production"): return "생산실 마련"
	var found := facilities(world,str(recipe["facility_id"]))
	if found.is_empty(): return "설비 설치" if ShopSpaceProgression.furniture_visible(str(recipe["facility_id"])) else "첫 상품 수령 먼저"
	for node in found:
		if node.can_start_production(str(recipe["recipe_id"])): return "지금 만들 수 있음"
	var idle := false
	var output := false
	for node in found:
		idle = idle or node.production_state == ProductionFacility.ProductionState.IDLE
		output = output or node.production_state == ProductionFacility.ProductionState.READY
	if not idle: return "완성품 수령 먼저" if output else "설비 사용 중"
	return "재료 준비"
static func entries(world: Node, notes: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for recipe in ProductRecipeData.get_learned_recipes():
		var item := str(recipe["result_item_id"])
		var status := ready(world,recipe)
		var entry := {"recipe":recipe,"id":str(recipe["recipe_id"]),"title":FishingData.recipe_name(recipe),"status":status,"notes":notes.get(item,[]),"priority":0}
		entry["priority"] = (0 if entry["notes"].is_empty() else 2) + (1 if status == "지금 만들 수 있음" else 0)
		result.append(entry)
	result.sort_custom(func(a: Dictionary,b: Dictionary): return str(a["title"]) < str(b["title"]) if a["priority"] == b["priority"] else a["priority"] > b["priority"])
	return result
static func facility_entries(world: Node) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var ids := {}
	for node in facilities(world):
		result.append({"id":str(node.get_instance_id()),"facility_id":node.facility_id,"node":node})
		ids[node.facility_id] = true
	for recipe in ProductRecipeData.get_learned_recipes():
		var id := str(recipe["facility_id"])
		if not ids.has(id) and ShopSpaceProgression.furniture_visible(id):
			result.append({"id":"missing:" + id,"facility_id":id,"node":null})
			ids[id] = true
	return result
static func preservation_note(item: String) -> String:
	var lines: Array[String] = []
	for unit in PreservationService.SETTINGS.units:
		var id := str(unit["id"])
		if not PreservationService.installed(id): continue
		var count := int(GameState.preservation_state.get(id,{}).get(item,0))
		if count > 0: lines.append(("냉장" if id == "fridge" else "냉동") + " 보관 " + str(count) + "개 · 현장에서 꺼내기")
	return "\n".join(lines)
static func storage_state(world: Node) -> Array:
	var state := []
	for node in world.get_tree().get_nodes_in_group("warehouse_storage"):
		if is_instance_valid(node) and not node.is_queued_for_deletion() and world.is_ancestor_of(node) and not node.get_meta("is_build_preview",false): state.append([node.get_instance_id(),node.stored_items])
	return state
static func facility_summary(world: Node, entry: Dictionary) -> String:
	var node = entry["node"]
	if not is_instance_valid(node): return "미설치"
	var status := "재료 준비 대기"
	if node.production_state == ProductionFacility.ProductionState.PROCESSING: status = "가공 중"
	if node.production_state == ProductionFacility.ProductionState.READY: status = "수령 대기"
	return location(world,node) + " · " + status
