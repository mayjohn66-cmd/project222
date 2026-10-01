extends Node
var failures := 0
var world

func check(ok: bool, message: String) -> void:
	if ok: print("PASS: ", message)
	else:
		failures += 1
		push_error(message)

func settle() -> void:
	for i in range(6): await get_tree().process_frame

func drain(dialogue: StoryDialoguePanel) -> void:
	for i in range(30):
		if not dialogue.open: return
		dialogue._advance()

func _ready() -> void: call_deferred("run")

func run() -> void:
	world = load("res://scenes/shop/main.tscn").instantiate()
	add_child(world)
	await settle()
	var life: VillageLifeDirector = world.get_node("VillageLifeDirector")
	var player = world.get_node("Actors/Player")
	var manager = world.get_node("DayManager")
	var interactions = world.get_node("WorldInteractions")
	life.refresh()
	check(life.residents.is_empty(), "no residents before settlement")
	check(VillageLifeFlow.greet("naru").is_empty() and not VillageLifeFlow.draw_water(), "cannot claim locked gifts or water")
	for step in TutorialDirector.SETTINGS.steps:
		PlayerProgress.record_story_beat("tutorial_step:" + str(step["id"]) + ":done", GameState.total_day)
	PlayerProgress.record_story_beat(CheckoutTutorial.BEAT_ID, GameState.total_day)
	world.get_node("TutorialDirector").refresh()
	player.set_physics_process(false)
	manager.hour_timer.paused = false
	for index in range(3):
		var entry: Dictionary = VillageLifeFlow.SETTINGS.residents[index]
		var id := str(entry["id"])
		PlayerProgress.record_story_beat(ResidentRequestFlow.PREFIX + str(entry["request"]) + ":done", GameState.total_day)
		VillageSettlement.apply_world(world)
		await settle()
		life.refresh()
		check(life.residents.size() == index + 1, "resident appears only after own settlement")
		var npc: VillageResident = life.residents[id]
		check(npc.visible and npc.get_child(0).sprite_frames != null, "resident uses existing pixel sprite")
		var shape := CircleShape2D.new()
		shape.radius = 12
		var query := PhysicsShapeQueryParameters2D.new()
		query.shape = shape
		query.collision_mask = 1
		query.transform = Transform2D(0, npc.global_position)
		check(player.get_world_2d().direct_space_state.intersect_shape(query, 1).is_empty(), "resident stands outside building collision")
		player.global_position = npc.global_position + Vector2(10, 0)
		check(life.interaction_hint().contains(entry["name"]), "nearby E hint identifies resident")
		var before: int = GameState.get_item_count(entry["gift"])
		check(interactions.try_interact(), "existing player interaction starts daily greeting")
		check(life.talking and manager.hour_timer.paused and interactions.blocked(), "dialogue pauses clock and blocks conflicting actions")
		check(GameState.get_item_count(entry["gift"]) == before + entry["amount"] and VillageLifeFlow.friendship(id) == 1, "first daily greeting awards one small gift and friendship")
		drain(life.dialogue)
		check(not manager.hour_timer.paused and not player.is_physics_processing(), "dialogue restores exact clock and movement state")
		life.try_interact()
		drain(life.dialogue)
		check(GameState.get_item_count(entry["gift"]) == before + entry["amount"] and VillageLifeFlow.friendship(id) == 1, "repeat talk does not duplicate gift or friendship")
	var saved := PlayerProgress.to_save_data()
	PlayerProgress.reset()
	PlayerProgress.load_save_data(saved)
	check(VillageLifeFlow.greet("naru")["first"] == false, "save roundtrip prevents repeated daily gift")
	GameState.total_day += 1
	check(VillageLifeFlow.greet("naru")["first"] and VillageLifeFlow.friendship("naru") == 2, "next game day permits another greeting")
	GameState.total_day += 5
	check(VillageLifeFlow.friendship("naru") == 2, "missed days do not decrease friendship")
	VillageLifeFlow.greet("naru")
	check(VillageLifeFlow.friendship_name("naru") == "반가운 이웃", "relationship title changes on third greeting day")
	var well := VillageSettlement.find_site(world, "VillageDecor/VillageWell")
	player.global_position = well.global_position + Vector2(0, -60)
	check(life.nearest().get("id") == "well", "well has its own reachable interaction")
	var water_before: int = GameState.get_item_count("water")
	check(interactions.try_interact(), "E draws water at unlocked well")
	drain(life.dialogue)
	check(GameState.get_item_count("water") == water_before + 1 and VillageLifeFlow.well_used_today(), "well adds water once")
	check(not VillageLifeFlow.draw_water(), "well repeat cannot duplicate water")
	saved = PlayerProgress.to_save_data()
	PlayerProgress.reset()
	PlayerProgress.load_save_data(saved)
	check(not VillageLifeFlow.draw_water(), "well daily use persists")
	GameState.total_day += 1
	check(VillageLifeFlow.draw_water(), "well resets on next game day")
	world.get_node("StoreExterior").refresh_village_layout()
	await settle()
	life.refresh()
	check(life.residents.size() == 3, "exterior rebuild preserves exactly three residents")
	var editor = world.get_node("VillageMapEditor")
	editor.active = true
	life.refresh()
	check(life.residents.is_empty() and life.nearest().is_empty(), "map editing cannot trigger resident interaction")
	editor.active = false
	VillageSettlement.apply_world(world)
	life.refresh()
	var npc: VillageResident = life.residents["naru"]
	player.global_position = npc.global_position
	world.get_node("BuildManager").build_mode = true
	check(not life.try_interact(), "build mode blocks daily dialogue")
	world.get_node("BuildManager").build_mode = false
	PlayerProgress.reset()
	VillageSettlement.apply_world(world)
	life.refresh()
	check(life.residents.is_empty() and VillageLifeFlow.friendship("naru") == 0 and not VillageLifeFlow.well_used_today(), "new game clears daily use and relationships")
	print("CHECK_VILLAGE_LIFE failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)
