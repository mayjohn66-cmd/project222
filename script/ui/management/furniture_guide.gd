class_name FurnitureGuide
extends RefCounted
# Usage text reads current catalogs. Opening it never creates or upgrades furniture.
const ENABLED := true
const MAX_COMPARISONS := 3
const MAX_PRODUCTS := 4
static var storage_specs := {}
static func description(id: String, crafting := false) -> String:
	var data := FurnitureData.get_furniture(id)
	var build := BuildObjectData.get_build_object(id)
	if data.is_empty() or build.is_empty(): return ""
	if not ShopSpaceProgression.furniture_visible(id): return "현재 공간에서 사용할 집기를 먼저 준비하세요."
	var family := str(build["build_type"])
	var intro := str(data.get("description",""))
	# Shelf flavor is kept; numerical/stacking sentences are replaced by current specs.
	if family == "shelf": intro = intro.split(".")[0] + "."
	var size: Vector2i = build["grid_size"]
	var lines: Array[String] = [intro,"","[쓰임과 배치]",usage(id,family)]
	lines.append("설치 크기 %d×%d칸 · %s" % [size.x,size.y,"벽에 설치" if build["placement_rule"] == "wall" else "바닥에 설치"])
	if bool(build["blocks_movement"]): lines.append("가구가 차지하는 칸을 피해 통로를 남겨 두세요.")
	var row := FurnitureObjectCatalog.get_object(id)
	if not row.is_empty(): lines.append("재질 · " + str(row["material"]))
	var spec := specs(id)
	if not spec.is_empty(): lines.append(""); lines.append("[현재 규격]"); lines.append(spec_text(spec))
	if family == "shelf":
		if int(spec["levels"]) > 1: lines.append("한 층을 올릴 때 같은 종류의 진열대 1개가 더 필요합니다. 건축 모드에서 같은 진열대 위에 놓으세요.")
		else: lines.append("한 층만 사용합니다. 다양한 상품은 옆에 진열대를 더 놓아 나누어 진열하세요.")
	elif family == "warehouse_storage": lines.append("보관한 재료는 꺼내야 제작·진열에 쓸 수 있습니다. 일반 선반에는 냉장·냉동 기능이 없습니다.")
	elif family == "production_facility":
		var products: Array[String] = []
		for recipe in ProductRecipeData.get_learned_recipes():
			var name := ItemData.get_item_name(str(recipe["result_item_id"]))
			if str(recipe["facility_id"]) == id and name not in products: products.append(name)
		lines.append("배운 상품 · " + " · ".join(products.slice(0,MAX_PRODUCTS)) if not products.is_empty() else "이 설비에서 사용할 배운 제조법이 아직 없습니다.")
		if products.size() > MAX_PRODUCTS: lines.append("나머지 배운 상품은 생산 탭에서 확인하세요.")
	var unit := preservation_unit(id)
	if not unit.is_empty():
		lines.append(str(unit["description"]))
		lines.append("같은 종류를 여러 대 놓아도 보관 재고와 총용량은 함께 사용합니다.")
	var effect := effect_text(id)
	if not effect.is_empty(): lines.append(""); lines.append("[배치 효과]"); lines.append(effect)
	var comparisons := alternatives(id)
	if not comparisons.is_empty():
		lines.append(""); lines.append("[함께 살펴볼 집기]")
		for other in comparisons:
			var other_size: Vector2i = BuildObjectData.get_build_object(other)["grid_size"]
			lines.append("%s · %d×%d칸 · %s" % [FurnitureData.get_furniture_name(other),other_size.x,other_size.y,spec_text(specs(other))])
	if crafting:
		lines.append(""); lines.append("[제작 조건]")
		var reason := FurnitureObjectCatalog.locked_reason(id)
		lines.append("제조법 조건 충족 · 아래 재료를 준비하면 만들 수 있습니다." if reason.is_empty() else "해금 조건: " + reason)
		lines.append("제작한 집기는 보관함에서 골라 건축 모드 [B]로 설치합니다.")
	else: lines.append("\n보유한 집기는 건축 모드 [B]에서 골라 설치합니다.")
	return "\n".join(lines)
static func usage(id: String, family: String) -> String:
	if not preservation_unit(id).is_empty(): return "편의점에 배치하고 가까이에서 [E]로 보관할 물품을 넣고 꺼냅니다."
	match family:
		"shelf": return "편의점에서 [E]로 상품을 넣으면 손님이 고를 수 있습니다. 원정 재료도 그대로 진열할 수 있습니다."
		"register": return "편의점의 계산 자리입니다. 손님이 기다릴 공간을 남겨 두세요. 플레이어 직접 계산과 직원 계산을 같은 방식으로 이용합니다."
		"warehouse_storage": return "창고에 배치하고 [E]로 남은 재료와 상품을 넣고 꺼냅니다."
		"production_facility": return "생산실에 배치하고 [E]로 배운 제조법을 선택합니다. 가공 후 같은 설비에서 완성품을 수령하세요."
		"production_door": return "편의점 벽에 설치하여 생산실을 연결합니다. 문에서 [E]로 들어가 첫 설비를 준비하세요."
		"warehouse_door": return "편의점 벽에 설치하여 창고를 연결합니다. 문에서 [E]로 들어가 보관 선반을 준비하세요."
		"door": return "편의점 벽의 출입구입니다. 손님이 문에서 계산대와 진열대까지 걸어갈 길을 남겨 두세요."
		"decoration": return "편의점에 놓아 가게를 꾸밉니다. 벽 집기는 벽에 붙여 배치하세요."
	return "건축 모드에서 설치할 위치를 고릅니다."
static func preservation_unit(id: String) -> Dictionary:
	if id == "fridge_unit": return PreservationService.unit("fridge")
	if id == "freezer_unit": return PreservationService.unit("freezer")
	return {}
static func specs(id: String) -> Dictionary:
	var shelf := ShelfData.get_shelf_data(id)
	if not shelf.is_empty(): return {"kind":"shelf","slots":int(shelf["slots_per_level"]),"per_slot":int(shelf["slot_capacity"]),"levels":int(shelf["max_stack_level"])}
	var unit := preservation_unit(id)
	if not unit.is_empty(): return {"kind":"cold","capacity":int(unit["capacity"])}
	if BuildObjectData.get_build_type(id) != "warehouse_storage": return {}
	if not storage_specs.has(id):
		var scene := BuildObjectData.get_build_scene(id)
		if scene == null: return {}
		var node := scene.instantiate()
		FurnitureObjectCatalog.configure_storage(node,id)
		storage_specs[id] = {"kind":"storage","capacity":int(node.get("storage_capacity")),"slots":int(node.get("storage_slot_count"))}
		node.free()
	return storage_specs[id].duplicate()
static func spec_text(spec: Dictionary) -> String:
	match str(spec.get("kind","")):
		"shelf": return "한 층 %d칸 · 칸마다 %d개 · 합계 %d개 · 최대 %d층" % [spec["slots"],spec["per_slot"],int(spec["slots"])*int(spec["per_slot"]),spec["levels"]]
		"storage": return "보관 슬롯 %d칸 · 총 보관량 %d개" % [spec["slots"],spec["capacity"]]
		"cold": return "공유 보관함 총용량 %d개" % int(spec["capacity"])
	return ""
static func alternatives(id: String) -> Array[String]:
	var result: Array[String] = []
	var family := BuildObjectData.get_build_type(id)
	if family not in ["shelf","warehouse_storage"]: return result
	var size: Vector2i = BuildObjectData.get_build_object(id)["grid_size"]
	for other in BuildObjectData.get_all_build_ids():
		if other == id or BuildObjectData.get_build_type(other) != family or not ShopSpaceProgression.furniture_visible(other): continue
		var owned := GameState.get_furniture_count(other) > 0
		if not owned:
			for placed in GameState.get_store_layout():
				if str(placed.get("build_id","")) == other: owned = true; break
		if owned or (not FurnitureRecipeData.get_recipe(other).is_empty() and FurnitureObjectCatalog.locked_reason(other).is_empty()): result.append(other)
	result.sort_custom(func(a,b):
		var same_a: bool = BuildObjectData.get_build_object(a)["grid_size"] == size
		var same_b: bool = BuildObjectData.get_build_object(b)["grid_size"] == size
		return same_a if same_a != same_b else FurnitureData.get_furniture_name(a) < FurnitureData.get_furniture_name(b))
	return result.slice(0,MAX_COMPARISONS)
static func effect_text(id: String) -> String:
	if not preservation_unit(id).is_empty(): return ""
	var effect := FurnitureData.get_effect_data(id)
	if effect.is_empty(): return "외형과 용도를 위한 집기입니다. 별도 손님·평판 보너스는 없습니다." if BuildObjectData.get_build_type(id) == "decoration" else ""
	var value := float(effect.get("effect_value",0))
	var line := ""
	match str(effect.get("effect_type","")):
		"reputation": line = "매장 평판 기여 +%.1f · 손님의 방문 빈도에 영향을 줍니다." % value
		"customer_weight": line = "%s 손님이 찾아올 비중을 높입니다." % CustomerTypeData.get_display_name(str(effect["effect_target"]))
		"purchase_desire": line = "손님이 상품을 추가로 고를 가능성을 높입니다."
	if line.is_empty(): return ""
	return line + "\n같은 효과가 겹칠수록 추가 효율은 줄어듭니다. 매장에 실제 배치해야 적용됩니다."
static func overview(id: String) -> String:
	if not FurnitureData.has_furniture(id) or not ShopSpaceProgression.furniture_visible(id): return ""
	var spec := specs(id)
	match str(spec.get("kind","")):
		"shelf": return "한 층 총 %d개 · %d칸 · 최대 %d층" % [int(spec["slots"])*int(spec["per_slot"]),spec["slots"],spec["levels"]]
		"storage": return "총 보관량 %d개 · 보관 슬롯 %d칸" % [spec["capacity"],spec["slots"]]
		"cold": return "동종 설비 공유 보관 · 총 %d개" % int(spec["capacity"])
	match BuildObjectData.get_build_type(id):
		"production_facility": return "현장 설비에서 [E]로 가공·수령"
		"register": return "플레이어 직접 계산 · 직원 계산"
		"decoration": return effect_text(id).split("\n")[0]
	return ""
