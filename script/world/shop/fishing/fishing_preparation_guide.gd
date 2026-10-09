class_name FishingPreparationGuide
extends RefCounted
## Read actual carried/physical stock. Guidance never grants tools or consumes fish.
const ENABLED := true

static func materials(world: Node, id: String, environment: Dictionary) -> String:
	var lines: Array[String] = []
	for material in FishingData.entry(id).get("materials", []):
		lines.append(RequestPreparationData.item_information(world, str(material["item_id"]), int(material["amount"]), environment))
	return "\n\n".join(lines)

static func next_step(world: Node, environment: Dictionary) -> String:
	if not ENABLED: return ""
	if not FishingRecords.done("fishing_intro"): return UiText.t("fishing.preparation.intro")
	if not FishingRecords.accepted("fishing_rod") and not FishingRecords.done("fishing_rod"):
		return UiText.t("fishing.preparation.rod_intro")
	if not FishingService.has_rod():
		var stored: Array[String] = []
		for id in ["fishing_rod_wood", "fishing_rod_reinforced"]:
			var count := ProductPreparationData.shelf_count(world, id)
			if count > 0: stored.append(UiText.f("fishing.preparation.stored_rod", [ItemData.get_item_name(id), count]))
		if not stored.is_empty(): return "\n".join(stored)
		if not FishingRecords.has("tool:fishing_rod_wood"):
			return FishingContent.instructions("fishing_rod") + "\n\n" + materials(world, "fishing_rod_wood", environment)
		return UiText.t("fishing.preparation.carry_rod")
	if not FishingRecords.done("fishing_rod"): return UiText.t("fishing.preparation.finish_rod")
	return ""

static func candidates(group: String) -> Array[String]:
	var result: Array[String] = []
	for member in FishingData.group(group):
		var item := str(member)
		if not ENABLED or RequestPreparationData.known_choice(item): result.append(item)
	return result

static func preferred(ids: Array[String], amount: int) -> int:
	var best := 0
	for i in range(ids.size()):
		var count := GameState.get_item_count(ids[i])
		if count >= amount: return i
		if count > GameState.get_item_count(ids[best]): best = i
	return best
