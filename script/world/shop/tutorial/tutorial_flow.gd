class_name TutorialFlow
extends RefCounted
var settings: TutorialSettings
const PREFIX := "tutorial_step:"

func seen(id: String) -> bool:
	return PlayerProgress.story_beat_days.has(PREFIX + id + ":intro")

func done(id: String) -> bool:
	return PlayerProgress.story_beat_days.has(PREFIX + id + ":done")

func current() -> Dictionary:
	for step in settings.steps:
		if not done(str(step["id"])): return RequestTextData.enrich(step, "tutorial_step")
	return {}

func mark(id: String, suffix: String) -> void:
	PlayerProgress.record_story_beat(PREFIX + id + ":" + suffix, GameState.total_day)

func goal_met(step: Dictionary, world: Node) -> bool:
	match str(step["goal"]):
		"fixtures":
			var found: Dictionary = {}
			for object in world.get_node("Objects").get_children():
				if object.is_queued_for_deletion() or object.get_meta("is_build_preview", false): continue
				found[str(object.get_meta("build_id", ""))] = true
			return found.has("door") and found.has("register") and (found.has("shelf_1x1") or found.has("shelf_2x1") or found.has("shelf_3x1"))
		"stock":
			for object in world.get_node("Objects").get_children():
				if not object.is_in_group("shelf") or object.is_queued_for_deletion() or object.get_meta("is_build_preview", false): continue
				for slot in object.slots:
					if int(slot.get("stock", 0)) > 0 and ItemData.get_sellable_items().has(str(slot.get("item_id", ""))): return true
			return false
		"checkout": return PlayerProgress.story_beat_days.has(CheckoutTutorial.BEAT_ID)
		"expedition": return PlayerProgress.has_completed_expedition()
		"production": return PlayerProgress.story_beat_days.has("tutorial_event:produced_bread")
	return false

func validate_gifts(gifts: Array) -> bool:
	for gift in gifts:
		if int(gift.get("amount", 0)) <= 0: return false
		var id: String = str(gift.get("id", ""))
		if gift.get("kind") == "item":
			if not ItemData.has_item(id): return false
		elif gift.get("kind") == "furniture":
			if FurnitureData.get_furniture(id).is_empty(): return false
		else: return false
	return true

func grant(gifts: Array) -> Array[String]:
	var received: Array[String] = []
	for gift in gifts:
		var id: String = str(gift["id"])
		var amount: int = int(gift["amount"])
		var furniture: bool = gift["kind"] == "furniture"
		if bool(gift.get("missing_only", false)):
			amount = maxi(0, amount - (GameState.get_furniture_count(id) if furniture else GameState.get_item_count(id)))
		if gift.get("recipe", "") != "" and PlayerProgress.is_recipe_learned(str(gift["recipe"])): amount = 0
		if amount == 0: continue
		if furniture: GameState.add_furniture(id, amount)
		else: GameState.add_item(id, amount)
		received.append("%s ×%d" % [FurnitureData.get_furniture_name(id) if furniture else ItemData.get_item_name(id), amount])
	return received

func introduce(step: Dictionary) -> Array[String]:
	if seen(str(step["id"])): return []
	var gifts: Array = step.get("starter", [])
	if not validate_gifts(gifts): return []
	mark(str(step["id"]), "intro")
	return grant(gifts)

func claim(step: Dictionary, world: Node) -> Array[String]:
	if done(str(step["id"])) or not seen(str(step["id"])) or not goal_met(step, world): return []
	var gifts: Array = step.get("rewards", [])
	if not validate_gifts(gifts): return []
	mark(str(step["id"]), "done")
	return grant(gifts)
