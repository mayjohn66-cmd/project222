extends Node
const Tools = preload("res://dev/gemini/request_text_tools.gd")
const Writer = preload("res://dev/gemini/request_text_runner.gd")
var checks := 0
var failures := 0
var world
var life: VillageLifeDirector
var rest: VillageRestDirector
var board: CommunityBoardDirector
var player
var manager
func check(ok: bool, label_text: String) -> void:
	checks += 1
	if ok: print("PASS: ", label_text)
	else:
		failures += 1
		push_error(label_text)
func settle() -> void:
	for i in range(8): await get_tree().process_frame
func drain() -> void:
	for i in range(90):
		if not rest.dialogue.open: return
		rest.dialogue._advance()
	check(false, "rest scene ends")
func save_reload() -> void:
	var saved := PlayerProgress.to_save_data().duplicate(true)
	PlayerProgress.reset()
	PlayerProgress.load_save_data(saved)
func unlock() -> void:
	for step in TutorialDirector.SETTINGS.steps: PlayerProgress.record_story_beat("tutorial_step:" + str(step["id"]) + ":done", GameState.total_day)
	PlayerProgress.record_story_beat(CheckoutTutorial.BEAT_ID, GameState.total_day)
	for resident in VillageLifeFlow.SETTINGS.residents:
		PlayerProgress.record_story_beat(ResidentRequestFlow.PREFIX + str(resident["request"]) + ":done", GameState.total_day)
		PlayerProgress.story_beat_days[VillageLifeFlow.PREFIX + "friendship:" + str(resident["id"])] = 7
	PlayerProgress.record_story_beat(VillageMarketFlow.PREFIX + "done", GameState.total_day - 2)
	PlayerProgress.record_story_beat(CommunityRequestFlow.PREFIX + "flower_corner:done", GameState.total_day - 2)
	for id in VillageRestFlow.SETTINGS.afterglow_requests:
		PlayerProgress.record_story_beat(PersonalRequestFlow.PREFIX + id + ":done", GameState.total_day - 2)
		PlayerProgress.record_story_beat(MarketAfterglowFlow.PREFIX + id + ":heard", GameState.total_day - 2)
func arrive() -> void:
	var site := VillageRestFlow.site(world)
	for i in range(VillageRestFlow.SETTINGS.participants.size()):
		var id := VillageRestFlow.SETTINGS.participants[i]
		life.residents[id].global_position = site.global_position + Vector2(90 + i * 32, 0)
	player.global_position = site.global_position + Vector2(100, 0)
func _ready() -> void: call_deferred("run")
func run() -> void:
	world = load("res://scenes/shop/main.tscn").instantiate()
	add_child(world)
	await settle()
	life = world.get_node("VillageLifeDirector")
	rest = life.get_node("VillageRestDirector")
	board = world.get_node("CommunityBoardDirector")
	player = world.get_node("Actors/Player")
	manager = world.get_node("DayManager")
	player.set_physics_process(false)
	manager.current_hour = 6
	manager.hour_timer.paused = false
	GameState.total_day = 50
	PlayerProgress.reset()
	var prep := VillageRestFlow.SETTINGS.preparation
	var entry := CommunityRequestFlow.request(prep)
	var bench := VillageSettlement.find_site(world, VillageRestFlow.SETTINGS.site_path)
	check(bench != null and not bench.visible and bench.collision_layer == 0, "new bench hidden and nonblocking before preparation")
	check(not CommunityRequestFlow.accept(prep) and not VillageRestFlow.active(15) and not VillageRestFlow.rest(world), "actions locked before tutorial")
	unlock()
	var last_id: String = VillageRestFlow.SETTINGS.afterglow_requests.back()
	var last_key := MarketAfterglowFlow.PREFIX + last_id + ":heard"
	PlayerProgress.story_beat_days.erase(last_key)
	check(not CommunityRequestFlow.accept(prep) and CommunityRequestFlow.locked_reason(entry).contains("후일담"), "all three actual afterglows required")
	PlayerProgress.record_story_beat(last_key, GameState.total_day)
	check(not CommunityRequestFlow.accept(prep) and VillageRestFlow.locked_reason().contains("다음 날"), "wait from latest heard afterglow")
	GameState.total_day += 1
	PlayerProgress.story_beat_days[VillageLifeFlow.PREFIX + "friendship:doyun"] = 6
	check(not CommunityRequestFlow.accept(prep), "relationship gate retained")
	PlayerProgress.story_beat_days[VillageLifeFlow.PREFIX + "friendship:doyun"] = 7
	world.get_node("TutorialDirector").refresh()
	VillageSettlement.apply_world(world)
	life.refresh()
	check(VillageJournalFlow.destination(world, VillageRestFlow.JOURNAL_ID) == VillageSettlement.find_site(world, CommunityRequestFlow.SETTINGS.board_path), "journal guides to existing board before preparation")
	var layout: Dictionary = world.get_node("StoreExterior").get_village_layout_snapshot().duplicate(true)
	player.global_position = VillageSettlement.find_site(world, CommunityRequestFlow.SETTINGS.board_path).global_position
	check(world.get_node("WorldInteractions").try_interact() and board.open, "real E opens preparation board")
	board.panel.cards[prep]["action"].pressed.emit()
	check(CommunityRequestFlow.accepted(prep) and not CommunityRequestFlow.accept(prep), "actual preparation card accepts once")
	GameState.remove_item("dry_branch", GameState.get_item_count("dry_branch"))
	GameState.remove_item("stone_shard", GameState.get_item_count("stone_shard"))
	GameState.add_item("dry_branch", 5)
	GameState.add_item("stone_shard", 3)
	var money := GameState.money
	var reputation := ResidentRequestFlow.reputation()
	board.panel.refresh()
	check(board.panel.cards[prep]["action"].disabled and CommunityRequestFlow.deliver(prep).is_empty() and GameState.get_item_count("dry_branch") == 5 and GameState.money == money, "partial materials consume nothing and pay nothing")
	GameState.add_item("stone_shard", 1)
	board.panel.refresh()
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		await settle()
		var scroll: ScrollContainer = board.panel.root.get_child(0).get_child(2)
		scroll.ensure_control_visible(board.panel.cards[prep]["action"])
		await settle()
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(args[0] + "-board.png")
	var request_count := ResidentRequestFlow.completed_count()
	var visitors := VillageVisitorFlow.available_types()
	board.panel.cards[prep]["action"].pressed.emit()
	bench = VillageRestFlow.site(world)
	check(VillageRestFlow.prepared() and bench != null and bench.visible and bench.collision_layer > 0, "delivery opens actual reused-art bench")
	check(GameState.get_item_count("dry_branch") == 0 and GameState.get_item_count("stone_shard") == 0 and GameState.money == money + 40 and ResidentRequestFlow.reputation() == reputation + 1, "exact one-time preparation cost and initial reward")
	check(CommunityRequestFlow.deliver(prep).is_empty(), "duplicate preparation cannot pay or consume")
	board.panel.close()
	save_reload()
	check(VillageRestFlow.prepared() and not VillageRestFlow.active(15), "prepared save waits until next afternoon")
	check(VillageJournalFlow.destination(world, VillageRestFlow.JOURNAL_ID) == bench, "journal guides to real new bench")
	world.get_node("StoreExterior").refresh_village_layout()
	await settle()
	bench = VillageRestFlow.site(world)
	check(bench != null and bench.visible, "terrain rebuild preserves unlocked bench")
	GameState.total_day += 1
	check(not VillageRestFlow.active(14) and VillageRestFlow.active(15) and VillageRestFlow.active(17) and not VillageRestFlow.active(18), "afternoon opening window")
	manager.current_hour = 15
	manager.hour_timer.paused = false
	player.global_position = Vector2(-3000, -3000)
	life.refresh()
	for id in VillageRestFlow.SETTINGS.participants:
		check(VillageRoutine.location(VillageLifeFlow.resident(id), 15)["path"] == VillageRestFlow.SETTINGS.site_path, "new routine heads to bench " + id)
		life.residents[id].set_physics_process(false)
	for i in range(6000):
		for id in VillageRestFlow.SETTINGS.participants: life.residents[id]._physics_process(1.0 / 60.0)
		if i % 60 == 0: await get_tree().physics_frame
		if VillageRestFlow.all_present(world): break
	check(VillageRestFlow.all_present(world), "all three actually walk to new rest area on default map")
	if not args.is_empty():
		player.global_position = bench.global_position + Vector2(100, 0)
		await settle()
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(args[0] + "-bench.png")
	player.global_position = bench.global_position + Vector2(100, 0)
	life.residents["sora"].global_position = bench.global_position + Vector2(800, 0)
	check(world.get_node("WorldInteractions").try_interact() and not rest.talking, "first meeting waits for all residents")
	bench.visible = false
	check(VillageRestFlow.site(world) == null and not VillageRestFlow.finish(15, world), "hidden bench cannot award meeting")
	bench.visible = true
	bench.set_meta("settlement_layout_removed", true)
	check(VillageRestFlow.site(world) == null, "user removed bench is respected")
	bench.remove_meta("settlement_layout_removed")
	life.refresh()
	arrive()
	manager.summary_open = true
	check(not rest.try_interact(), "other modal blocks opening")
	manager.summary_open = false
	check(world.get_node("WorldInteractions").try_interact() and rest.stage == "opening" and rest.dialogue.lines.size() >= 10, "actual E begins CSV shared first rest")
	rest.dialogue.close()
	check(not VillageRestFlow.completed() and ResidentRequestFlow.reputation() == reputation + 1 and not manager.hour_timer.paused, "partial opening does not award or complete")
	GameState.total_day += 30
	save_reload()
	check(VillageRestFlow.active(15), "missed opening has no expiry")
	life.refresh()
	arrive()
	manager.hour_timer.paused = true
	player.set_physics_process(true)
	check(world.get_node("WorldInteractions").try_interact(), "opening retries after long absence")
	drain()
	check(VillageRestFlow.completed() and ResidentRequestFlow.reputation() == reputation + 2 and GameState.money == money + 40, "full opening gives one reputation and no second money")
	check(manager.hour_timer.paused and player.is_physics_processing(), "previous clock and physics restored")
	check(not VillageRestFlow.finish(15, world) and not VillageRestFlow.active(15) and VillageRoutine.location(VillageLifeFlow.resident("sora"), 15)["label"] == "노점 주변", "one-time gathering restores normal routine")
	player.global_position = life.residents["naru"].global_position
	check(not rest.try_interact() and not life.nearest().is_empty(), "revisit does not take E from a closer neighbor")
	for id in VillageRestFlow.SETTINGS.participants: life.residents[id].global_position = bench.global_position + Vector2(800, 0)
	player.global_position = bench.global_position + Vector2(100, 0)
	manager.current_hour = 0
	manager.hour_timer.paused = false
	player.set_physics_process(false)
	check(world.get_node("WorldInteractions").try_interact() and rest.stage == "rest", "quiet revisit works outside opening hours")
	rest.dialogue.close()
	check(not PlayerProgress.story_beat_days.has(VillageRestFlow.PREFIX + "rested"), "interrupted revisit records no visit")
	check(world.get_node("WorldInteractions").try_interact(), "quiet revisit resumes")
	drain()
	check(int(PlayerProgress.story_beat_days[VillageRestFlow.PREFIX + "rested"]) == GameState.total_day and not VillageRestFlow.rest(world), "full revisit records once per day")
	GameState.total_day += 1
	check(world.get_node("WorldInteractions").try_interact(), "next day quiet revisit allowed")
	drain()
	save_reload()
	check(VillageJournalFlow.information(VillageRestFlow.JOURNAL_ID).contains("최근 들른 날") and VillageRestFlow.completed(), "save and journal retain opening memory and latest visit")
	check(GameState.money == money + 40 and ResidentRequestFlow.reputation() == reputation + 2 and GameState.get_item_count("dry_branch") == 0, "repeat resting has no currency item or reputation reward")
	check(ResidentRequestFlow.completed_count() == request_count and VillageVisitorFlow.available_types() == visitors, "resting never changes existing customer thresholds")
	check(world.get_node("StoreExterior").get_village_layout_snapshot() == layout and life.residents.size() == 3, "quest does not move user layout or duplicate residents")
	var sources := Tools.load_sources()
	check(sources[Tools.KIND_COMMUNITY_REQUEST].has(prep), "writer registers new community preparation")
	for moment in VillageRestFlow.SETTINGS.moments: check(sources[Tools.KIND_SERVICE_TEXT].has(str(moment["id"])), "writer registers scene " + str(moment["id"]))
	check(Writer.build_prompt(Tools.KIND_COMMUNITY_REQUEST, sources, sources).contains("후일담 세 개"), "writer receives actual community prerequisites")
	check(world.get_node("WorldInteractions").try_interact(), "start quiet revisit before scene exit")
	var last_visit := int(PlayerProgress.story_beat_days[VillageRestFlow.PREFIX + "rested"])
	GameState.total_day += 1
	world.queue_free()
	await settle()
	check(int(PlayerProgress.story_beat_days[VillageRestFlow.PREFIX + "rested"]) == last_visit, "scene exit cannot record unfinished visit")
	PlayerProgress.reset()
	check(not VillageRestFlow.completed() and not VillageRestFlow.prepared() and not PlayerProgress.story_beat_days.has(VillageRestFlow.PREFIX + "rested"), "new game clears preparation opening and visits")
	print("CHECK_VILLAGE_REST checks=", checks, " failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)
