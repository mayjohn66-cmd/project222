extends Node

const Tools = preload("res://dev/gemini/request_text_tools.gd")
var checks := 0
var failures := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func frames() -> void:
	for i in range(8): await get_tree().process_frame

func drain(panel: StoryDialoguePanel) -> void:
	for i in range(40):
		if not panel.open: break
		panel._advance()

func _ready() -> void: call_deferred("run")

func run() -> void:
	GameState.initialize_new_game()
	var world = load("res://scenes/shop/main.tscn").instantiate()
	world.get_node("TutorialDirector").enabled = false
	add_child(world)
	await frames()
	for step in TutorialDirector.SETTINGS.steps:
		PlayerProgress.record_story_beat("tutorial_step:" + str(step["id"]) + ":done", 1)
	PlayerProgress.record_story_beat(CheckoutTutorial.BEAT_ID, 1)
	PlayerProgress.record_expedition_completed()
	GameState.remove_item("bread", GameState.get_item_count("bread"))
	GameState.remove_item("water", GameState.get_item_count("water"))
	GameState.total_day = 10
	check(not RecipeUnlockData.is_recipe_available("bake_bread") and not RecipeUnlockData.is_recipe_available("bottled_water"), "modern recipes still locked")
	var resident = world.get_node("ResidentRequestDirector")
	var player = world.get_node("Actors/Player")
	for expected in ["wild_berry", "raw_water"]:
		var request := ResidentRequestFlow.current()
		check(str(request["item"]) == expected, "first requests use expedition materials")
		resident.refresh()
		player.global_position = resident.npc.global_position + Vector2(20, 0)
		check(resident.try_interact() and ResidentRequestFlow.accepted(str(request["id"])), "actual resident dialogue accepts request")
		drain(resident.dialogue)
		var accepted_save := PlayerProgress.to_save_data().duplicate(true)
		PlayerProgress.reset()
		PlayerProgress.load_save_data(accepted_save)
		check(ResidentRequestFlow.current()["id"] == request["id"] and ResidentRequestFlow.accepted(str(request["id"])), "existing resident acceptance survives reload")
		check(resident.panel.goal.text.contains("답례"), "resident UI identifies small thanks")
		var money := GameState.money
		check(ResidentRequestFlow.deliver(request).is_empty() and GameState.money == money, "missing materials never pay")
		GameState.add_item(expected, int(request["amount"]))
		resident.refresh()
		check(resident.try_interact(), "actual resident accepts gathered material without modern stock")
		drain(resident.dialogue)
		check(GameState.get_item_count(expected) == 0 and GameState.money == money + int(request["money"]), "exact material consumption and reward")
		check(ResidentRequestFlow.deliver(request).is_empty(), "no duplicate delivery")
	check(ResidentRequestFlow.customer_available("peddler") and ResidentRequestFlow.completed_count() == 2, "first two material requests still unlock merchant")
	check(GameState.get_item_count("bread") == 0 and GameState.get_item_count("water") == 0, "merchant path does not need surviving starting food")

	# Older saves keep their accepted/completed IDs; the revised requirements are read from settings.
	PlayerProgress.record_story_beat(ResidentRequestFlow.PREFIX + "settle_naru:done", 2)
	PlayerProgress.record_story_beat(ResidentRequestFlow.PREFIX + "settle_doyun:done", 2)
	PlayerProgress.story_beat_days[VillageLifeFlow.PREFIX + "friendship:naru"] = 7
	PlayerProgress.story_beat_days[VillageLifeFlow.PREFIX + "friendship:doyun"] = 3
	PlayerProgress.record_story_beat("village_gathering:well_evening:done", 2)
	for id in ["naru_provisions", "doyun_water", "naru_neighbor_basket"]:
		if id == "naru_neighbor_basket": GameState.total_day += 1
		var entry := PersonalRequestFlow.request(id)
		check(PersonalRequestFlow.locked_reason(entry).is_empty(), "early personal request available without production: " + id)
		check(PersonalRequestFlow.information(entry).contains("물품 대금은 별도로 받지 않습니다"), "donation and small thanks are explicit")
		PlayerProgress.record_story_beat(PersonalRequestFlow.PREFIX + id + ":accepted", 2)
		var saved := PlayerProgress.to_save_data().duplicate(true)
		PlayerProgress.reset()
		PlayerProgress.load_save_data(saved)
		check(PersonalRequestFlow.accepted(id), "existing acceptance survives roundtrip")
		var totals := CommunityRequestFlow.required_items(entry)
		for item in totals:
			check(item != "bread" and item != "water", "followup also avoids modern stock")
			GameState.add_item(item, int(totals[item]))
		check(not PersonalRequestFlow.deliver(id).is_empty(), "resumed personal request consumes current material requirements")
		var completed := PlayerProgress.to_save_data().duplicate(true)
		PlayerProgress.reset()
		PlayerProgress.load_save_data(completed)
		check(PersonalRequestFlow.done(id) and PersonalRequestFlow.deliver(id).is_empty(), "completed memory cannot reward twice")

	# Exercise the real legacy StoryDirector with the revised one-time support CSV.
	for entry in ResidentRequestFlow.SETTINGS.requests:
		PlayerProgress.record_story_beat(ResidentRequestFlow.PREFIX + str(entry["id"]) + ":done", 1)
	for entry in ResidentStoryFlow.SETTINGS.settlement_requests:
		PlayerProgress.record_story_beat(ResidentRequestFlow.PREFIX + str(entry["id"]) + ":done", 1)
	var story = world.get_node("StoryDirector")
	story.set_process(false)
	GameState.remove_item("iron_ore", GameState.get_item_count("iron_ore"))
	for item in ItemData.get_sellable_items():
		if ItemData.get_item_type(item) == ItemData.ITEM_TYPE_STORE_PRODUCT:
			GameState.remove_item(item, GameState.get_item_count(item))
	GameState.money = 0
	GameState.remove_furniture("magic_oven", GameState.get_furniture_count("magic_oven"))
	StoryData.reload()
	check(StoryData.get_beats().size() == 4, "support count and IDs stay stable")
	for beat in StoryData.get_beats():
		check(int(beat["repeat_days"]) == 0, "support is once per save")
		for gift in beat["gifts"]:
			check(gift["type"] == "item" and ItemData.get_item_type(str(gift["id"])) == ItemData.ITEM_TYPE_MATERIAL, "support only gives local raw materials")
		check(NpcInterventionSelector.is_available(beat, get_tree()), "support is available for real shortage")
		story._spawn_npc(beat)
		story._start_talk()
		drain(story.dialogue)
		check(GameState.money == 0 and GameState.get_item_count("iron_ore") == 0 and GameState.get_furniture_count("magic_oven") == 0, "support cannot supply repair fee, ore or production facility")
		check(not NpcInterventionSelector.is_available(beat, get_tree()), "same support cannot repeat")
		await frames()
	var support_save := PlayerProgress.to_save_data().duplicate(true)
	PlayerProgress.reset()
	PlayerProgress.load_save_data(support_save)
	GameState.total_day += 100
	for beat in StoryData.get_beats():
		check(not NpcInterventionSelector.is_available(beat, get_tree()), "saved support remains exhausted after 100 days")
	var text := Tools.validate_file(Tools.TEXT_PATH, Tools.load_sources())
	check(text["errors"].is_empty() and text["warns"].is_empty(), "whole prose CSV valid: " + str(text))
	world.queue_free()
	await frames()
	print("CHECK_EARLY_CONTENT_POLISH checks=", checks, " failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)
