class_name VillageHousing
extends RefCounted
## 주민 집터 배정. 집이 있는 주민이 정착하면 편의점에서 가장 가까운 빈 집터를 받고,
## 정착한 다음 날부터 그 자리에 집이 보인다. 배정은 GameState.village_homes 에 저장된다.
## 집을 켜고 끄는 일은 기존 VillageSettlement 가 하고, 이 클래스는 자리와 시점만 정한다.

# village_homes 필드가 없던 옛 저장을 불러온 직후에만 true: 이미 정착한 주민의 집은 바로 지어진 것으로 본다.
static var adopt_legacy: bool = false


static func homes() -> Dictionary:
	return GameState.village_homes


# 집이 있는 주민이 정착 요청을 마쳤으면 빈 집터를 배정한다. 이미 있으면 그대로 둔다. 빈 문자열이면 집터 없음.
static func assign(resident_id: String) -> String:
	if homes().has(resident_id):
		return str(homes()[resident_id]["slot"])
	VillageHouseSlotsData.ensure_loaded()
	var taken: Dictionary = {}
	for key in homes():
		taken[str(homes()[key]["slot"])] = true
	for slot in VillageHouseSlotsData.slots:
		if not taken.has(slot["id"]):
			homes()[resident_id] = {"slot": slot["id"], "day": 0 if adopt_legacy else GameState.total_day}
			return str(slot["id"])
	push_warning("[VillageHousing] 빈 집터가 없습니다: " + resident_id)
	return ""


static func slot_of(resident_id: String) -> String:
	return str(homes().get(resident_id, {}).get("slot", ""))


static func cell_of(resident_id: String) -> Vector2i:
	var slot := VillageHouseSlotsData.find(slot_of(resident_id))
	return slot.get("cell", Vector2i(-9999, -9999))


# 정착한 다음 날부터 집이 있다(플레이 중에 갑자기 솟지 않게).
static func built(resident_id: String) -> bool:
	return homes().has(resident_id) and GameState.total_day > int(homes()[resident_id].get("day", 0))


# 정착 요청에서 주민 id 를 뽑는다("settle_doyun" -> "doyun").
static func resident_of(request_id: String) -> String:
	return request_id.trim_prefix("settle_")


# 이 정착 시설이 "집"인가(집터 배정 대상).
static func is_house_path(path: String) -> bool:
	return path.begins_with("VillageExtraHouses/")


# 집을 배정하고 집터로 옮긴다(아직 안 지어졌어도 터에는 서 있다). 지어졌으면 true.
static func place(world: Node, request_id: String, path: String) -> bool:
	var resident := resident_of(request_id)
	if assign(resident).is_empty():
		return false
	var house := VillageSettlement.find_site(world, path)
	var terrain := world.get_node_or_null("StoreExterior") as Node2D
	if house == null or terrain == null:
		return false
	var cell := cell_of(resident)
	if house.get_meta("housing_cell", Vector2i(-9999, -9999)) != cell:
		house.global_position = terrain.to_global(terrain.grid_to_local(cell))
		house.set_meta("housing_cell", cell)
	return built(resident)


# 집터는 정해졌지만 아직 짓는 중인 집인가(주민은 그 터에 서 있을 수 있다).
static func under_construction(site: Node) -> bool:
	return site != null and site.has_meta("housing_cell") and not site.visible
