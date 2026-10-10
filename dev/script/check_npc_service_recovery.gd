extends "res://dev/script/check_fishing_runtime.gd"
# History, positions, stock and elapsed wait are fixtures. UI requests, service
# preflight/commit, shelf withdrawal and cancellation use production paths.
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("run")
func click(target: Button) -> void:
	if target == null: check(false,"missing button"); return
	await frames(12)
	var parent := target.get_parent()
	while parent != null and not parent is ScrollContainer: parent = parent.get_parent()
	if parent is ScrollContainer: parent.ensure_control_visible(target)
	await frames(12)
	for down in [true,false]:
		var event := InputEventMouseButton.new()
		event.position = target.get_global_rect().get_center()
		event.button_index = MOUSE_BUTTON_LEFT; event.pressed = down
		get_viewport().push_input(event,true)
	await frames(12)
func key(code: Key) -> void:
	for down in [true,false]:
		var event := InputEventKey.new()
		event.keycode = code; event.physical_keycode = code; event.pressed = down
		get_viewport().push_input(event,true)
	await frames(12)
func fish_button(prefix: String) -> Button:
	for child in director.panel.body.get_children():
		if child is Button and child.text.begins_with(prefix): return child
	return null
func text(node: Node) -> String:
	var parts: Array[String] = []
	if node is Label: parts.append(node.text)
	for child in node.get_children(): parts.append(text(child))
	return "\n".join(parts)
func snap(label: String) -> void:
	if DisplayServer.get_name() == "headless": return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--snap="):
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(arg.trim_prefix("--snap=")+"-"+label+".png")
func run() -> void:
	if not OS.get_user_data_dir().contains("foodbag_checks"):
		push_error("Use isolated foodbag_checks project to protect user saves")
		get_tree().quit(2); return
	reset(); core()
	PlayerProgress.record_story_beat(OpeningJourneyFlow.VERSION,1)
	for step in TutorialDirector.SETTINGS.steps: PlayerProgress.record_story_beat("tutorial_step:"+str(step["id"])+":done",1)
	PlayerProgress.record_story_beat(CheckoutTutorial.BEAT_ID,1)
	PlayerProgress.record_story_beat(ResidentRequestFlow.PREFIX+"settle_naru:done",1)
	VillageLifeFlow.greet("naru")
	world = load(GameConfig.MAIN_SCENE_PATH).instantiate()
	world.get_node("TutorialDirector").enabled = false
	add_child(world); await frames(12)
	world.get_node("CustomerSpawner").set_process(false)
	VillageSettlement.apply_world(world); await frames(12)
	var player = world.get_node("Actors/Player")
	var manager = world.get_node("DayManager")
	manager.hour_timer.start(999); manager.hour_timer.paused = false
	var trade: ResidentTradeDirector = world.get_node("ResidentTradeDirector")
	var stall := VillageSettlement.find_site(world,ResidentTradeFlow.SETTINGS.site)
	player.global_position = stall.global_position + Vector2(60,0)
	var price := ExpeditionShopData.get_price("gathering_bottle")
	GameState.money = price-1
	await key(KEY_E)
	check(trade.open and trade.panel.root.visible,"E opens real settled merchant")
	check(trade.panel.message.text.contains("소지품에서 사용") and not trade.panel.message.text.contains("창고의 재료"),"merchant introduction names actual payment source")
	var buy: Button = trade.panel.cards["supply:gathering_bottle"]["action"]
	check(buy.disabled and trade.panel.cards["supply:gathering_bottle"]["info"].text.contains("소지금이 부족"),"insufficient money disables purchase and explains selling materials")
	var before := GameState.create_save_data().duplicate(true)
	await click(buy)
	check(before == GameState.create_save_data(),"disabled purchase spends nothing")
	await key(KEY_ESCAPE)
	check(not trade.open and not manager.hour_timer.paused and player.is_physics_processing() and not world.has_meta("resident_trade_open"),"merchant Escape restores running clock and movement")
	GameState.money = price
	await key(KEY_E)
	buy = trade.panel.cards["supply:gathering_bottle"]["action"]
	check(not buy.disabled,"reopening reevaluates affordable purchase")
	GameState.money = 0 # Balance changed after the enabled UI snapshot.
	before = GameState.create_save_data().duplicate(true)
	await click(buy)
	check(before == GameState.create_save_data() and buy.disabled,"stale affordable button rechecks funds atomically")
	await key(KEY_ESCAPE)
	GameState.money = price
	await key(KEY_E); await click(buy)
	check(GameState.money == 0 and ResidentMerchantSupply.owns_effect("collect_water") and buy.disabled,"actual purchase receives one tool and blocks duplicate payment")
	await key(KEY_ESCAPE)
	# Stored branches are not spendable until withdrawn.
	var store = load("res://scenes/shop/warehouse/warehouse_storage.tscn").instantiate()
	world.get_node("Objects").add_child(store)
	GameState.add_item("dry_branch",2)
	store.apply_stored_items({"dry_branch":1,"iron_ore":2})
	await key(KEY_E)
	var exchange: Button = trade.panel.cards["grain"]["action"]
	check(exchange.disabled and trade.panel.cards["grain"]["info"].text.contains("소지") and trade.panel.cards["grain"]["info"].text.contains("창고 선반 1개"),"partial carried stock points to real warehouse")
	var used := ResidentTradeFlow.used("grain")
	before = GameState.create_save_data().duplicate(true)
	await click(exchange)
	check(before == GameState.create_save_data() and ResidentTradeFlow.used("grain") == used,"partial exchange cannot consume goods or daily quota")
	await snap("trade-shortage")
	await key(KEY_ESCAPE)
	check(store.withdraw_slot_to_inventory(store.find_item_slot("dry_branch"),1) == 1,"actual withdrawal resolves one missing branch")
	await key(KEY_E); await click(exchange)
	check(GameState.get_item_count("dry_branch") == 0 and GameState.get_item_count("wheat") == 2 and ResidentTradeFlow.used("grain") == used+1,"reopened exchange commits exact amounts once")
	check(trade.panel.message.text.contains("소지품"),"exchange receipt names actual destination")
	await key(KEY_ESCAPE)
	manager.hour_timer.paused = true; player.set_physics_process(false)
	check(trade.try_interact(),"merchant can be opened from preexisting paused state")
	await click(trade.panel.close_button)
	check(manager.hour_timer.paused and not player.is_physics_processing(),"merchant close preserves prior pause and movement state")
	manager.hour_timer.paused = false; player.set_physics_process(true)
	# Craft/enhance services are unlocked history fixtures, not a free workshop.
	PlayerProgress.record_story_beat(CommunityRequestFlow.PREFIX+"open_smithy:done",1)
	for record in ["heard","met","service_intro"]: BlacksmithProgressionRecords.mark(record)
	VillageSettlement.apply_world(world)
	var smith: BlacksmithDirector = world.get_node("BlacksmithDirector")
	smith.refresh(); await frames(12)
	var sword: int = GameState.create_owned_equipment_instance("rusty_sword")
	player.global_position = smith.npc.global_position + Vector2(24,0)
	await key(KEY_E)
	check(smith.open and smith.panel.root.visible,"E opens blacksmith service at real NPC")
	await click(smith.panel.tabs["enhance"])
	await click(smith.panel.cards[str(sword)]["action"])
	check(smith.panel.confirm_button.disabled and smith.panel.detail.text.contains("창고 선반 2개") and smith.panel.message.text.contains("소지품"),"missing enhancement material explains withdrawal instead of remote stock consumption")
	before = GameState.create_save_data().duplicate(true)
	await click(smith.panel.confirm_button)
	check(before == GameState.create_save_data() and BlacksmithEquipmentAdapter.find(sword)["enhancement_level"] == 0,"blocked enhancement preserves equipment and materials")
	await snap("smith-shortage")
	await key(KEY_ESCAPE)
	check(not smith.open and smith.panel.selected.is_empty() and not manager.hour_timer.paused and player.is_physics_processing(),"Escape cancels selection and restores movement")
	check(store.withdraw_slot_to_inventory(store.find_item_slot("iron_ore"),2) == 2,"withdraw actual enhancement material")
	player.global_position = smith.npc.global_position + Vector2(24,0)
	await key(KEY_E)
	check(smith.open,"returning to current NPC position reopens service")
	if not smith.open: get_tree().quit(1); return
	await click(smith.panel.tabs["enhance"]); await click(smith.panel.cards[str(sword)]["action"])
	check(not smith.panel.confirm_button.disabled,"withdrawn materials enable confirmation")
	GameState.remove_item("iron_ore",1)
	var partial: int = GameState.get_item_count("iron_ore")
	await click(smith.panel.confirm_button)
	check(GameState.get_item_count("iron_ore") == partial and BlacksmithEquipmentAdapter.find(sword)["enhancement_level"] == 0,"stale enabled enhancement rejects changed stock without partial charge")
	GameState.add_item("iron_ore",1)
	await click(smith.panel.cards[str(sword)]["action"])
	await click(smith.panel.confirm_button)
	check(BlacksmithEquipmentAdapter.find(sword)["enhancement_level"] == 1 and GameState.get_item_count("iron_ore") == 0,"retry after resupply enhances selected instance exactly once")
	await click(smith.panel.confirm_button)
	check(BlacksmithEquipmentAdapter.find(sword)["enhancement_level"] == 1,"duplicate confirmation cannot enhance again")
	PlayerProgress.learn_recipe("rusty_sword_recipe")
	await click(smith.panel.tabs["craft"])
	var recipe := RecipeData.get_recipe("rusty_sword_recipe")
	for material in recipe["materials"]:
		var id := str(material["item_id"]); GameState.remove_item(id,GameState.get_item_count(id))
	var one: Dictionary = recipe["materials"][0]
	GameState.add_item(str(one["item_id"]),maxi(0,int(one["amount"])-1))
	smith.panel.refresh(); await frames(12)
	check(smith.panel.cards["rusty_sword_recipe"]["action"].disabled,"craft shortage disables learned recipe")
	before = GameState.create_save_data().duplicate(true)
	check(VillageSmithyFlow.craft("rusty_sword_recipe").is_empty() and before == GameState.create_save_data(),"crafting service rejects partial ingredients without consuming")
	await key(KEY_ESCAPE)
	# No rod, incomplete rod ingredients, waiting cancellation, bite/full cancellation.
	director = world.get_node("FishingDirector")
	manager.current_hour = 12; manager.hour_timer.start(999); manager.hour_timer.paused = false
	player.global_position = director.spots.position_for("fish_bank")
	await key(KEY_E)
	check(director.mode == "menu" and fish_button("낚싯대 드리우기").disabled,"no rod prevents casting in actual bank menu")
	before = GameState.create_save_data().duplicate(true)
	await key(KEY_ESCAPE)
	check(before == GameState.create_save_data() and director.mode == "closed" and player.is_physics_processing() and not manager.hour_timer.paused,"bank Escape grants nothing and restores state")
	FishingRecords.mark("fishing_intro:done")
	check(FishingContent.accept("fishing_rod",12,"clear"),"rod lesson accepted fixture via actual condition")
	GameState.add_item("dry_branch",2); GameState.remove_item("amber_sap",GameState.get_item_count("amber_sap"))
	await key(KEY_E)
	await click(fish_button("타블렌과 소박한 낚싯대 엮기"))
	check(is_instance_valid(director.visitor),"rod crafting locates a real teacher")
	player.global_position = director.visitor.global_position + Vector2(10,0)
	await key(KEY_E)
	check(director.mode == "menu" and text(director.panel.body).contains("부족"),"teacher panel explains incomplete rod ingredients")
	before = GameState.create_save_data().duplicate(true)
	await click(fish_button("준비한 재료로 엮기"))
	check(before == GameState.create_save_data() and not FishingService.has_rod(),"failed rod craft does not consume partial materials or grant progress")
	await key(KEY_ESCAPE)
	check(player.is_physics_processing() and not manager.hour_timer.paused,"failed crafting can be left normally")
	GameState.add_item("amber_sap",1)
	check(FishingService.make_rod("fishing_rod_wood",12,"clear") and FishingContent.complete("fishing_rod"),"resupplied rod production uses existing service and actual receipt")
	player.global_position = director.spots.position_for("fish_bank")
	await key(KEY_E); await click(fish_button("낚싯대 드리우기"))
	check(director.mode == "waiting" and not manager.hour_timer.paused and not player.is_physics_processing(),"casting keeps time running but leases movement")
	before = GameState.create_save_data().duplicate(true)
	await key(KEY_ESCAPE)
	check(before == GameState.create_save_data() and director.mode == "closed" and player.is_physics_processing() and director.pending_fish.is_empty(),"waiting Escape gives no catch and restores player")
	await key(KEY_E); await click(fish_button("낚싯대 드리우기"))
	director.remaining = 0; director._process(0.01); await frames(12)
	check(director.mode == "bite" and not director.pending_fish.is_empty(),"accelerated live wait rolls a real catch")
	before = GameState.create_save_data().duplicate(true)
	await key(KEY_ESCAPE)
	check(before == GameState.create_save_data() and not FishingRecords.has("catch") and director.pending_fish.is_empty(),"bite Escape also gives no catch or discovery")
	await key(KEY_E); await click(fish_button("낚싯대 드리우기"))
	director.remaining = 0; director._process(0.01); await frames(12)
	var pending := director.pending_fish
	GameState.inventory.clear(); GameState.add_item("fishing_rod_wood",1)
	var filled := 1
	for id in ItemData.items:
		if id == "fishing_rod_wood" or FishingData.fish(id): continue
		GameState.add_item(str(id),GameState.PLAYER_INVENTORY_STACK_LIMIT)
		filled += 1
		if filled == GameState.PLAYER_INVENTORY_SLOT_COUNT: break
	GameState.rebuild_inventory_slots_from_counts()
	await key(KEY_E)
	check(director.mode == "full" and GameState.get_item_count(pending) == 0 and not FishingRecords.has("catch"),"actual E at full inventory cannot grant fish or discovery")
	check(text(director.panel.body).contains("소지 공간이 부족"),"full catch explains releasing or returning to arrange stock")
	before = GameState.create_save_data().duplicate(true)
	await snap("fishing-full")
	await click(fish_button("물가로 놓아주기"))
	check(before == GameState.create_save_data() and director.mode == "closed" and player.is_physics_processing(),"actual release closes full catch without granting items")
	GameState.inventory.clear(); GameState.add_item("fishing_rod_wood",1)
	await key(KEY_E); await click(fish_button("낚싯대 드리우기"))
	manager.hour_timer.paused = true
	director._process(30); await frames(12)
	check(director.mode == "closed" and manager.hour_timer.paused and player.is_physics_processing() and director.pending_fish.is_empty(),"external clock pause cancels cast without undoing pause")
	manager.hour_timer.paused = false
	await key(KEY_E); await click(fish_button("낚싯대 드리우기"))
	director.remaining = 0; director._process(0.01); await frames(12)
	pending = director.pending_fish
	await key(KEY_E)
	check(director.mode == "closed" and GameState.get_item_count(pending) == 1 and FishingRecords.has("caught:"+pending),"after capacity recovery actual E receives exactly one live rolled fish")
	director.reel()
	check(GameState.get_item_count(pending) == 1,"closed cast cannot grant a second fish")
	check(not world.has_meta("fishing_open") and not world.has_meta("blacksmith_open") and not world.has_meta("resident_trade_open") and not manager.management_menu.visible,"all cancellations release modal locks")
	print("CHECK_NPC_SERVICE_RECOVERY checks=",checks," failures=",failures)
	get_tree().quit(0 if failures == 0 else 1)
