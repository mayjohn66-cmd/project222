extends Node
var failures := 0
var world
func check(ok: bool,message: String) -> void:
	if ok: print("PASS: ",message)
	else:
		failures += 1
		push_error(message)
func settle() -> void:
	for i in range(8): await get_tree().process_frame
func _ready() -> void: call_deferred("run")
func run() -> void:
	world = load("res://scenes/shop/main.tscn").instantiate()
	add_child(world)
	await settle()
	var life: VillageLifeDirector = world.get_node("VillageLifeDirector")
	var manager = world.get_node("DayManager")
	var player = world.get_node("Actors/Player")
	for step in TutorialDirector.SETTINGS.steps:
		PlayerProgress.record_story_beat("tutorial_step:" + str(step["id"]) + ":done",GameState.total_day)
	PlayerProgress.record_story_beat(CheckoutTutorial.BEAT_ID,GameState.total_day)
	world.get_node("TutorialDirector").refresh()
	for entry in VillageLifeFlow.SETTINGS.residents:
		PlayerProgress.record_story_beat(ResidentRequestFlow.PREFIX + str(entry["request"]) + ":done",GameState.total_day)
	VillageSettlement.apply_world(world)
	manager.current_hour = 6
	manager.hour_timer.paused = false
	player.set_physics_process(false)
	life.refresh()
	await settle()
	var npc: VillageResident = life.residents["doyun"]
	player.global_position = Vector2(-3000,-3000)
	check(npc is CharacterBody2D and npc.collision_mask == 1 and npc.collision_layer == 0,"resident respects buildings without blocking player")
	check(VillageRoutine.location(VillageLifeFlow.resident("doyun"),6)["path"] == VillageLifeFlow.resident("doyun")["site"],"morning stays near own home")
	var start := npc.global_position
	manager.current_hour = 12
	life.refresh()
	check(npc.global_position == start,"schedule change does not teleport resident")
	check(npc.routine_label == "노점 주변" and not npc.route.is_empty(),"daytime plans walk to unlocked market")
	for i in range(20): await get_tree().physics_frame
	check(npc.global_position.distance_to(start) > 1.0,"engine physics advances resident and walking animation")
	var shape := CircleShape2D.new()
	shape.radius = VillageLifeFlow.SETTINGS.resident_radius
	var previous := npc.global_position
	for point in npc.route:
		check(VillageRoutine.segment_clear(world.get_world_2d().direct_space_state,shape,previous,point),"planned route avoids building collision")
		previous = point
	var saved := PlayerProgress.to_save_data().duplicate(true)
	var destination := npc.destination
	# Drive real physics movement without waiting several minutes of wall time.
	npc.set_physics_process(false)
	for i in range(6000):
		npc._physics_process(1.0/60.0)
		if npc.global_position.distance_to(destination) < 2.1: break
	check(npc.global_position.distance_to(start) > 20,"resident actually walks across exterior ground")
	check(npc.global_position.distance_to(destination) < 2.1,"resident reaches daytime destination: distance=%s, remaining=%s" % [npc.global_position.distance_to(destination),npc.route.size()])
	check(PlayerProgress.to_save_data() == saved,"walking changes no friendship gifts or saved progress")
	manager.current_hour = 18
	life.refresh()
	check(npc.routine_label == "우물 곁","evening chooses shared well")
	var stopped := npc.global_position
	manager.hour_timer.paused = true
	npc._physics_process(0.1)
	check(npc.global_position == stopped,"paused clock stops residents")
	manager.hour_timer.paused = false
	player.global_position = npc.global_position + Vector2(0,20)
	npc._physics_process(0.1)
	check(npc.global_position == stopped,"neighbor waits when player approaches to talk")
	check(life.try_interact() and life.talking,"moving resident still accepts existing daily greeting")
	npc._physics_process(0.1)
	check(npc.global_position == stopped,"dialogue pauses route")
	for i in range(20):
		if not life.dialogue.open: break
		life.dialogue._advance()
	check(VillageLifeFlow.friendship("doyun") == 1,"daily greeting still grants friendship exactly once")
	player.global_position = Vector2(-3000,-3000)
	manager.current_hour = 0
	life.refresh()
	check(npc.routine_label == "머무는 곳","night returns to own home")
	var journal: VillageJournalDirector = world.get_node("VillageJournalDirector")
	check(journal.try_interact(),"journal opens during routine")
	check(journal.panel.cards["resident:doyun"]["info"].text.contains("현재:"),"journal shows current destination")
	check(VillageJournalFlow.destination(world,"resident:doyun") == npc,"journal tracks moving resident rather than original home")
	await settle()
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(args[0])
	journal.panel.close()
	PlayerProgress.reset()
	life.refresh()
	check(life.residents.is_empty(),"new game removes routine residents")
	print("CHECK_VILLAGE_ROUTINE failures=",failures)
	get_tree().quit(0 if failures == 0 else 1)
