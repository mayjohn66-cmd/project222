extends Node
var failures := 0
var checks := 0

func check(ok: bool, label_text: String) -> void:
	checks += 1
	if ok: print("PASS: ", label_text)
	else:
		failures += 1
		push_error(label_text)

func _ready() -> void: call_deferred("run")

func make_host():
	var inst = load("res://scenes/expedition/expedition.tscn").instantiate()
	add_child(inst)
	await get_tree().process_frame
	inst.expedition_map = ExpeditionMap.new()
	inst.set_expedition_phase(inst.ExpeditionPhase.RUN)
	inst.expedition_room_controller.view.set_physics_process(false)
	return inst

func run() -> void:
	var world = load("res://scenes/shop/main.tscn").instantiate()
	add_child(world)
	for i in range(8): await get_tree().process_frame
	PlayerProgress.reset()
	check(not CommunityRequestFlow.accept("welcome_garden"), "welcome request locked before tutorial")
	for step in TutorialDirector.SETTINGS.steps: PlayerProgress.record_story_beat("tutorial_step:" + str(step["id"]) + ":done", GameState.total_day)
	PlayerProgress.record_story_beat(CheckoutTutorial.BEAT_ID, GameState.total_day)
	for id in ["settle_naru","settle_doyun","settle_sora"]: PlayerProgress.record_story_beat(ResidentRequestFlow.PREFIX + id + ":done", GameState.total_day)
	PlayerProgress.story_beat_days[VillageLifeFlow.PREFIX + "friendship:sora"] = 3
	check(not CommunityRequestFlow.accept("welcome_garden"), "welcome request needs preceding flower corner")
	PlayerProgress.record_story_beat(CommunityRequestFlow.PREFIX + "flower_corner:done", GameState.total_day)
	check(not CommunityRequestFlow.accept("welcome_garden") and CommunityRequestFlow.locked_reason(CommunityRequestFlow.request("welcome_garden")).contains("저녁 모임"), "preparation alone does not replace actual gathering")
	for visitor in VillageVisitorFlow.SETTINGS.visitors:
		check(CustomerTypeData.has_customer_type(str(visitor["type"])) and not ResidentRequestFlow.customer_available(str(visitor["type"])), "new subtype exists and remains locked: " + str(visitor["type"]))
		check(VillageJournalFlow.information("visitor:" + str(visitor["type"])).contains("방문 조건"), "journal explains unlock: " + str(visitor["type"]))
	PlayerProgress.record_story_beat(VillageGatheringFlow.COMPLETED, GameState.total_day)
	world.get_node("TutorialDirector").refresh()
	VillageSettlement.apply_world(world)
	var flower := CommunityRequestFlow.landmark_site(world, CommunityRequestFlow.request("welcome_garden"))
	check(flower != null and not flower.visible, "welcome landmark exists and is hidden before delivery")
	var layout_before: Dictionary = world.get_node("StoreExterior").get_village_layout_snapshot().duplicate(true)
	var first_flower := VillageSettlement.find_site(world, "VillageGathering/EastFlowerBed")
	check(first_flower != flower and first_flower.visible, "welcome landmark is distinct from completed first flower corner")
	var board = world.get_node("CommunityBoardDirector")
	var player = world.get_node("Actors/Player")
	player.set_physics_process(false)
	player.global_position = VillageSettlement.find_site(world, CommunityRequestFlow.SETTINGS.board_path).global_position
	check(board.try_interact(), "actual board opens for welcome request")
	board.panel.refresh()
	board.panel.cards["welcome_garden"]["action"].pressed.emit()
	check(CommunityRequestFlow.accepted("welcome_garden"), "real board card accepts welcome quest")
	var requirements := CommunityRequestFlow.required_items(CommunityRequestFlow.request("welcome_garden"))
	for item in requirements: GameState.remove_item(item, GameState.get_item_count(item))
	GameState.add_item("dry_branch", 4)
	var money := GameState.money
	check(CommunityRequestFlow.deliver("welcome_garden").is_empty() and GameState.get_item_count("dry_branch") == 4 and GameState.money == money, "incomplete preparation neither consumes nor rewards")
	GameState.add_item("forest_herb", 2)
	var reputation := ResidentRequestFlow.reputation()
	var count := ResidentRequestFlow.completed_count()
	board.panel.refresh()
	board.panel.cards["welcome_garden"]["action"].pressed.emit()
	VillageSettlement.apply_world(world)
	check(CommunityRequestFlow.done("welcome_garden") and flower.visible and flower.collision_layer > 0, "delivery visibly opens existing flower landmark")
	check(board.panel.message.text.contains("과수원지기") and board.panel.message.text.contains("배달부"), "delivery announces newly unlocked visitors")
	check(VillageJournalFlow.destination(world,"community:welcome_garden") == flower and world.get_node("StoreExterior").get_village_layout_snapshot() == layout_before, "journal tracks correct flower without rewriting user map")
	check(GameState.money == money + 40 and ResidentRequestFlow.reputation() == reputation + 1 and GameState.get_item_count("dry_branch") == 0 and GameState.get_item_count("forest_herb") == 0, "exact small reward and resource deduction")
	check(ResidentRequestFlow.completed_count() == count and CommunityRequestFlow.deliver("welcome_garden").is_empty(), "new quest preserves original milestones and never pays twice")
	check(ResidentRequestFlow.customer_available("orchard_keeper") and ResidentRequestFlow.customer_available("trail_courier") and not ResidentRequestFlow.customer_available("field_cook"), "flower quest opens only its two visitors")
	for visitor in VillageVisitorFlow.SETTINGS.visitors:
		if str(visitor["kind"]) == "personal": PlayerProgress.record_story_beat(PersonalRequestFlow.PREFIX + str(visitor["request"]) + ":done", GameState.total_day)
	# Original introductions have priority; mark those visited before checking the new queue.
	for milestone in ResidentRequestFlow.SETTINGS.customer_milestones:
		PlayerProgress.record_story_beat(ResidentRequestFlow.PREFIX + "visited:" + str(milestone["type"]), GameState.total_day)
	CustomerTypeData.ensure_loaded()
	StoreEventCustomerModifierData.ensure_loaded()
	StoreEventDemandData.ensure_loaded()
	CustomerDemandData.ensure_loaded()
	var groups := CustomerTypeData.customer_groups.duplicate(true)
	var types := CustomerTypeData.customer_types.duplicate(true)
	for visitor in VillageVisitorFlow.SETTINGS.visitors:
		var id := str(visitor["type"])
		var group := CustomerTypeData.get_group_id(id)
		check(ResidentRequestFlow.customer_available(id) and ResidentRequestFlow.pending_introduction() == id, "new visitor has first-visit priority: " + id)
		CustomerTypeData.customer_groups = {group: groups[group]}
		CustomerTypeData.customer_types = {id: types[id]}
		check(CustomerTypeData.get_random_customer_type(22).get("customer_type_id", "") == id, "actual customer picker reaches unlocked subtype: " + id)
		var progress := PlayerProgress.story_beat_days.duplicate(true)
		PlayerProgress.story_beat_days.erase((CommunityRequestFlow.PREFIX if str(visitor["kind"]) == "community" else PersonalRequestFlow.PREFIX) + str(visitor["request"]) + ":done")
		check(CustomerTypeData.get_random_customer_type(22).is_empty(), "actual picker excludes locked subtype: " + id)
		PlayerProgress.story_beat_days = progress
		CustomerTypeData.customer_groups = groups.duplicate(true)
		CustomerTypeData.customer_types = types.duplicate(true)
		var demand := CustomerDemandData.get_random_wanted_request(id, 22)
		check(not demand.is_empty() and ItemData.has_item(str(demand.get("item_id", ""))), "new subtype resolves sellable demand: " + id)
		ResidentRequestFlow.record_visit(id)
		check(VillageJournalFlow.information("visitor:" + id).contains("첫 방문"), "journal remembers actual introduction: " + id)
	var saved := PlayerProgress.to_save_data().duplicate(true)
	PlayerProgress.reset()
	PlayerProgress.load_save_data(saved)
	check(ResidentRequestFlow.pending_introduction().is_empty() and CommunityRequestFlow.done("welcome_garden") and ResidentRequestFlow.customer_available("stone_mason"), "save roundtrip preserves visitor gates and visits")
	check(StoreEventData.get_discoverable_events(18, "villager").any(func(e: Dictionary) -> bool: return e["event_id"] == "trail_supplies"), "travel rumor discoverable on first discovery day")
	for day in [21,22,24,25]:
		var active: bool = day >= 22 and day <= 24
		check(StoreEventData.is_event_active("trail_supplies", day) == active, "travel event date boundary: " + str(day))
		check(is_equal_approx(StoreEventCustomerModifierData.get_active_weight_multiplier("traveler", day), 1.4 if active else 1.0), "visit modifier expires: " + str(day))
		check(StoreEventDemandData.get_active_demand_entries("traveler", day).size() == (2 if active else 0), "travel demand expires: " + str(day))
	world.queue_free()
	await get_tree().process_frame
	for profile in ExpeditionRoomModel.CONTENT.enemy_profiles:
		var id := str(profile["id"])
		var region: String = {"forest_thornling":"forest","mine_shardling":"mine","swamp_reedling":"swamp","ruins_wisp":"hidden_ruins"}[id]
		check(EnemyData.has_enemy(id) and not ExpeditionEventData.get_loot_entries(EnemyData.get_loot_table(id)).is_empty(), "new monster has existing region drops: " + id)
		var candidates := ExpeditionEventData.get_events_by_node_type(region, "battle", 1)
		check(candidates.any(func(e: Dictionary) -> bool: return e["target_id"] == id), "new monster reachable through normal map: " + id)
		var inst = await make_host()
		var controller: ExpeditionRoomController = inst.expedition_room_controller
		controller.enter({"result_type":"battle", "target_id":id}, "battle")
		var model := controller.model
		var enemy := model.enemies[0]
		enemy["position"] = Vector2(4,2)
		model.player_position = Vector2(4,6)
		model._step_enemy(enemy, 0.25)
		check(is_equal_approx(enemy["position"].y, 2.0 + model.settings.enemy_speed * float(profile["speed"]) * 0.25), "movement uses new profile: " + id)
		model.player_position = enemy["position"]
		model._step_enemy(enemy, 0.01)
		check(is_equal_approx(enemy["windup"], model.settings.enemy_windup * float(profile["windup"])), "telegraph uses new profile: " + id)
		model.player_position = Vector2(3.5,7)
		await ExpeditionRoomTestDriver.play(controller)
		check(not controller.is_active() and inst.loot_panel.visible and inst.temporary_loot.size() > 0, "basic attacks clear new enemy room and produce one reward batch: " + id)
		inst.queue_free()
		await get_tree().process_frame
	for encounter in ExpeditionRoomModel.CONTENT.gathering_encounters:
		for choice in range(2):
			var inst = await make_host()
			var controller: ExpeditionRoomController = inst.expedition_room_controller
			controller.enter({"event_id":encounter["id"], "result_type":"loot", "target_id":"forest_gather"}, "gather")
			var model := controller.model
			check(model.gathering_sites.size() == 2, "event config produces two sites: " + str(encounter["id"]))
			var site: Dictionary = model.gathering_sites[choice]
			model.player_position = Vector2(float(site["x"]),float(site["y"]))
			controller.view.interact_button.pressed.emit()
			model.step(0.2,Vector2.ZERO,false)
			check(controller.pending_loot.is_empty() and model.interacting, "no instant reward before gathering completes")
			model.step(0.02,Vector2.DOWN,false)
			check(not model.interacting and model.interaction_progress == 0, "walking interrupts gathering")
			model.interact()
			model.step(0.2,Vector2.ZERO,true)
			check(not model.interacting and controller.pending_loot.is_empty(), "basic attack interrupts gathering")
			model.player_position = Vector2(float(site["x"]),float(site["y"]))
			model.interact()
			model.step(model.interaction_seconds(),Vector2.ZERO,false)
			var expected := str(ExpeditionEventData.get_loot_entries(str(site["table"]))[0]["item_id"])
			check(model.object_consumed and controller.pending_loot.size() == 1 and controller.pending_loot[0]["item_id"] == expected, "selected site alone grants its resource: " + expected)
			var other: Dictionary = model.gathering_sites[1-choice]
			model.player_position = Vector2(float(other["x"]),float(other["y"]))
			model.interact()
			model.step(3.0,Vector2.ZERO,false)
			check(controller.pending_loot.size() == 1, "second site cannot duplicate room reward")
			controller._retreat()
			check(inst.loot_panel.visible and inst.temporary_loot.size() == 1 and inst.temporary_loot[0]["item_id"] == expected, "retreat retains chosen reward for bag organization")
			inst.expedition_bag_controller.finish_loot_organization()
			check(inst.current_expedition_phase == inst.ExpeditionPhase.RESULT, "choice reward completes normal retreat flow")
			inst.queue_free()
			await get_tree().process_frame
	print("[콘텐츠 확장 검사] ", checks, "개 / 실패 ", failures)
	get_tree().quit(0 if failures == 0 else 1)
