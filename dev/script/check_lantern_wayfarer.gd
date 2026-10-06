extends Node
const Tools = preload("res://dev/gemini/request_text_tools.gd")
const Writer = preload("res://dev/gemini/request_text_runner.gd")
var failures := 0
var checks := 0

func check(ok: bool, label_text: String) -> void:
	checks += 1
	if ok: print("PASS: ", label_text)
	else:
		failures += 1
		push_error(label_text)

func settle() -> void:
	for i in range(8): await get_tree().process_frame

func read_all(dialogue: StoryDialoguePanel) -> void:
	for i in range(50):
		if not dialogue.open: return
		dialogue._advance()
	check(false, "dialogue must end")

func unlock() -> void:
	for step in TutorialDirector.SETTINGS.steps:
		PlayerProgress.record_story_beat("tutorial_step:" + str(step["id"]) + ":done", GameState.total_day)
	PlayerProgress.record_story_beat(CheckoutTutorial.BEAT_ID, GameState.total_day)
	PlayerProgress.record_story_beat(ResidentRequestFlow.PREFIX + "settle_naru:done", GameState.total_day)
	PlayerProgress.record_story_beat(CommunityRequestFlow.PREFIX + "path_light:done", GameState.total_day)

func _ready() -> void: call_deferred("run")

func run() -> void:
	var world = load("res://scenes/shop/main.tscn").instantiate()
	world.get_node("TutorialDirector").enabled = false # Post-tutorial fixture; opening is tested separately.
	add_child(world)
	await settle()
	var director: LanternWayfarerDirector = world.get_node("LanternWayfarerDirector")
	var player = world.get_node("Actors/Player")
	var manager = world.get_node("DayManager")
	var interactions = world.get_node("WorldInteractions")
	PlayerProgress.reset()
	check(not LanternWayfarerFlow.accept(18) and not LanternWayfarerFlow.help("water") and not LanternWayfarerFlow.finish(), "unstarted game cannot accept consume or reward")
	unlock()
	world.get_node("TutorialDirector").refresh()
	VillageSettlement.apply_world(world)
	check(not LanternWayfarerFlow.accept(17) and LanternWayfarerFlow.evening(18) and LanternWayfarerFlow.evening(0) and LanternWayfarerFlow.evening(5) and not LanternWayfarerFlow.evening(6), "evening and midnight boundaries")
	manager.current_hour = 17
	director.refresh()
	check(not is_instance_valid(director.npc), "first visitor does not appear before evening")
	manager.current_hour = 18
	manager.hour_timer.paused = false
	player.set_physics_process(false)
	var lamp := LanternWayfarerFlow.site(world)
	check(lamp != null and lamp == VillageSettlement.find_site(world,LanternWayfarerFlow.SETTINGS.site_path), "uses actual unlocked lamp")
	var layout: Dictionary = world.get_node("StoreExterior").get_village_layout_snapshot().duplicate(true)
	director.refresh()
	check(is_instance_valid(director.npc) and director.npc.visible, "actual traveler appears beside lamp")
	var terrain = world.get_node("StoreExterior")
	var grid := IsometricGrid.unproject(terrain.to_local(director.npc.global_position), Vector2(terrain.tile_width, terrain.tile_height))
	check(terrain.is_exterior_cell(Vector2i(roundi(grid.x), roundi(grid.y))), "traveler stands on existing exterior tile")
	player.global_position = director.npc.global_position
	world.get_node("BuildManager").build_mode = true
	check(not director.try_interact(), "build mode blocks event")
	world.get_node("BuildManager").build_mode = false
	check(VillageJournalFlow.destination(world,LanternWayfarerFlow.JOURNAL_ID) == director.npc, "journal points to actual visitor")
	check(interactions.try_interact() and director.dialogue.open and director.open, "E starts actual encounter")
	check(manager.hour_timer.paused and interactions.blocked() and not director.npc.title.visible, "event pauses clock and prevents competing interaction")
	director.dialogue.close()
	check(not LanternWayfarerFlow.accepted() and not manager.hour_timer.paused, "interrupted introduction remains retryable")
	check(director.try_interact(), "introduction can be restarted")
	read_all(director.dialogue)
	check(LanternWayfarerFlow.accepted() and director.panel.root.visible and interactions.blocked(), "complete introduction opens explicit choices with same modal pause")
	for item in ["water","bread"]: GameState.remove_item(item,GameState.get_item_count(item))
	GameState.add_item("bread",1)
	director.panel.refresh()
	check(director.panel.cards["water"]["action"].disabled and not director.panel.cards["bread"]["action"].disabled, "choice buttons show actual warehouse stock")
	check(not LanternWayfarerFlow.help("water") and GameState.get_item_count("bread") == 1 and not LanternWayfarerFlow.helped(), "missing choice does not take other supply")
	check(not LanternWayfarerFlow.help("unknown"), "unknown choice is rejected")
	director.panel.close()
	var saved := PlayerProgress.to_save_data().duplicate(true)
	PlayerProgress.reset()
	PlayerProgress.load_save_data(saved)
	GameState.total_day += 30
	GameState.add_item("bread",1) # 식품은 날짜가 지나면 사라지므로(유통기한 기능) 시간이 지난 뒤 다시 채운다
	manager.current_hour = 12
	director.refresh()
	player.global_position = director.npc.global_position
	check(LanternWayfarerFlow.phase(12) == "supplies" and director.try_interact(), "accepted request survives reload has no deadline and remains available by day")
	var reputation := ResidentRequestFlow.reputation()
	var original_count := ResidentRequestFlow.completed_count()
	var money := GameState.money
	var wheat := GameState.get_item_count("wheat")
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		await settle()
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(args[0])
	director.panel.cards["bread"]["action"].pressed.emit()
	check(LanternWayfarerFlow.chosen() == "bread" and LanternWayfarerFlow.helped() and GameState.get_item_count("bread") == 0, "real button consumes only chosen bread")
	check(director.dialogue.open and "빵 냄새" in "|".join(director.dialogue.lines), "help scene follows selected branch")
	check(not LanternWayfarerFlow.help("bread") and not LanternWayfarerFlow.help("water") and not LanternWayfarerFlow.finish(), "help cannot repeat or give same day reward")
	read_all(director.dialogue)
	await settle()
	check(not is_instance_valid(director.npc) and not manager.hour_timer.paused and not player.is_physics_processing(), "visitor leaves after help and original flags restore")
	check(GameState.money == money and GameState.get_item_count("wheat") == wheat and ResidentRequestFlow.reputation() == reputation, "no advance reward before return")
	saved = PlayerProgress.to_save_data().duplicate(true)
	PlayerProgress.reset()
	PlayerProgress.load_save_data(saved)
	check(LanternWayfarerFlow.chosen() == "bread" and not LanternWayfarerFlow.return_ready(), "saved help preserves chosen branch and return delay")
	GameState.total_day += 1
	manager.current_hour = 6
	director.refresh()
	player.global_position = director.npc.global_position
	check(LanternWayfarerFlow.return_ready() and director.try_interact(), "visitor returns next game day and can be met by day")
	check("그때 먹은 빵" in "|".join(director.dialogue.lines), "return dialogue remembers bread")
	director.dialogue.close()
	check(not LanternWayfarerFlow.completed() and GameState.get_item_count("wheat") == wheat, "interrupted return does not grant reward")
	manager.hour_timer.paused = true
	player.set_physics_process(true)
	check(director.try_interact(), "interrupted return can resume")
	read_all(director.dialogue)
	check(LanternWayfarerFlow.completed() and GameState.get_item_count("wheat") == wheat + 2 and ResidentRequestFlow.reputation() == reputation + 1 and GameState.money == money, "completed return gives exact wheat and reputation once")
	check(manager.hour_timer.paused and player.is_physics_processing(), "already paused clock and enabled movement restored exactly")
	check(ResidentRequestFlow.completed_count() == original_count and not LanternWayfarerFlow.finish(), "event does not inflate original customer milestones or duplicate rewards")
	check(VillageJournalFlow.information(LanternWayfarerFlow.JOURNAL_ID).contains("다시 만난 날"), "journal stores completed reunion memory")
	saved = PlayerProgress.to_save_data().duplicate(true)
	PlayerProgress.reset()
	PlayerProgress.load_save_data(saved)
	director.refresh()
	check(LanternWayfarerFlow.completed() and not is_instance_valid(director.npc), "completed event remains complete after reload")
	PlayerProgress.reset()
	unlock()
	GameState.add_item("water",1)
	check(LanternWayfarerFlow.accept(23) and LanternWayfarerFlow.help("water"), "alternative water branch can be played in fresh progress")
	check(not LanternWayfarerFlow.return_ready(), "water branch also waits a day")
	GameState.total_day += 3
	director.refresh()
	player.global_position = director.npc.global_position
	check(director.try_interact() and "지난번 나눠 준 물" in "|".join(director.dialogue.lines), "late return keeps water branch available")
	director.dialogue.close()
	lamp.set_meta("settlement_layout_removed",true)
	lamp.hide()
	director.refresh()
	check(LanternWayfarerFlow.site(world) == VillageSettlement.find_site(world,LanternWayfarerFlow.SETTINGS.fallback_path) and is_instance_valid(director.npc), "removed lamp falls back to existing board without restoring it")
	check(world.get_node("StoreExterior").get_village_layout_snapshot() == layout, "event does not rewrite user map")
	lamp.remove_meta("settlement_layout_removed")
	VillageSettlement.apply_world(world)
	var sources := Tools.load_sources()
	for moment in LanternWayfarerFlow.SETTINGS.moments:
		check(sources[Tools.KIND_SERVICE_TEXT].has(str(moment["id"])), "writer tool registers event moment " + str(moment["id"]))
	var prompt := Writer.build_prompt(Tools.KIND_SERVICE_TEXT,sources,sources)
	check(prompt.contains("물이나 빵 중 하나") and prompt.contains("다음 날 돌아와"), "writer receives event order and choice context")
	check(CustomerTypeData.has_customer_type(LanternWayfarerFlow.SETTINGS.customer_type), "event reuses existing traveler appearance type")
	PlayerProgress.reset()
	director.refresh()
	check(not LanternWayfarerFlow.accepted() and not LanternWayfarerFlow.helped() and not LanternWayfarerFlow.completed(), "new game clears all event stages")
	# Ending the scene during a conversation restores the flags and grants nothing.
	unlock()
	manager.current_hour = 18
	director.refresh()
	player.global_position = director.npc.global_position
	manager.hour_timer.paused = false
	player.set_physics_process(false)
	check(director.try_interact(), "start encounter before unloading")
	director.queue_free()
	await settle()
	check(not interactions.blocked() and not manager.hour_timer.paused and not LanternWayfarerFlow.accepted(), "unloading releases event modal without completing interrupted scene")
	print("CHECK_LANTERN_WAYFARER checks=", checks, " failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)
