extends Node
var checks := 0
var failures := 0
var world
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)
func frames() -> void:
	for i in range(12): await get_tree().process_frame
func click(button: Button) -> void:
	var parent := button.get_parent()
	while parent != null and not parent is ScrollContainer: parent = parent.get_parent()
	if parent is ScrollContainer: parent.ensure_control_visible(button)
	await frames()
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = button.get_global_rect().get_center()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		get_viewport().push_input(event, true)
	await frames()
func drain(dialogue: StoryDialoguePanel) -> void:
	for i in range(80):
		if not dialogue.open: break
		dialogue._advance()
func snap(label: String) -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty() or DisplayServer.get_name() == "headless": return
	await get_tree().create_timer(0.5).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(args[0] + "-" + label + ".png")
func complete_current() -> void:
	var request := ResidentRequestFlow.current()
	check(not request.is_empty() and ResidentRequestFlow.accept(request), "early request can be accepted")
	if request.is_empty(): return
	GameState.add_item(str(request["item"]), int(request["amount"]))
	check(not ResidentRequestFlow.deliver(request).is_empty(), "tool-free request can complete")
func _ready() -> void:
	RequestOfferPanel.auto_accept_for_test = true  # 주민 제안 확인창은 이 시험의 대상이 아니므로 바로 수락한다(check_request_proposals 가 확인창 자체를 시험한다)
	call_deferred("run")
func run() -> void:
	GameState.initialize_new_game()
	PlayerProgress.reset()
	check(not ResidentMerchantSupply.available() and ResidentMerchantSupply.buy("gathering_bottle").is_empty(), "no merchant purchase before tutorial/settlement")
	for step in TutorialDirector.SETTINGS.steps:
		PlayerProgress.record_story_beat("tutorial_step:" + str(step["id"]) + ":done", GameState.total_day)
	PlayerProgress.record_story_beat(CheckoutTutorial.BEAT_ID, GameState.total_day)
	world = load("res://scenes/shop/main.tscn").instantiate()
	world.get_node("TutorialDirector").enabled = false
	add_child(world)
	await frames()
	check(ResidentRequestFlow.current().get("id") == "neighbor_bread", "Orel comes first")
	complete_current()
	check(ResidentRequestFlow.current().get("id") == "gatherer_herbs", "Elmi replaces premature water request")
	# Legacy acceptance is preserved, but postponed when no water/tool exists.
	PlayerProgress.record_story_beat(ResidentRequestFlow.PREFIX + "traveler_water:accepted", GameState.total_day)
	check(ResidentRequestFlow.current().get("id") == "gatherer_herbs" and ResidentRequestFlow.accepted("traveler_water"), "old water acceptance survives while tool-free quest comes first")
	GameState.add_item("raw_water", 2)
	check(ResidentRequestFlow.current().get("id") == "traveler_water", "legacy water already prepared remains deliverable")
	GameState.remove_item("raw_water", 2)
	PlayerProgress.story_beat_days.erase(ResidentRequestFlow.PREFIX + "traveler_water:accepted")
	complete_current()
	check(ResidentRequestFlow.current().is_empty() and ResidentRequestFlow.pending_introduction() == "peddler", "two tool-free requests invite merchant before water")
	check(not ResidentMerchantSupply.next_step().is_empty(), "waiting state explains meeting merchant")
	ResidentRequestFlow.record_visit("peddler")
	var director = world.get_node("ResidentRequestDirector")
	var player = world.get_node("Actors/Player")
	var manager = world.get_node("DayManager")
	director.refresh()
	player.global_position = director.npc.global_position + Vector2(25,10)
	check(director.try_interact(), "actual merchant introduction starts with E")
	drain(director.dialogue)
	director.refresh()
	check(ResidentRequestFlow.current().get("id") == "settle_naru", "merchant stall request precedes water")
	player.global_position = director.npc.global_position + Vector2(25,10)
	check(director.try_interact(), "merchant stall request accepted through NPC")
	drain(director.dialogue)
	GameState.add_item("dry_branch", 4)
	check(director.try_interact(), "merchant receives branches through NPC")
	drain(director.dialogue)
	VillageSettlement.apply_world(world)
	world.get_node("VillageLifeDirector").refresh()
	await frames()
	check(ResidentRequestFlow.done("settle_naru") and ResidentRequestFlow.current().is_empty(), "water waits for tool even after stall exists")
	check(world.get_node("VillageLifeDirector").residents.has("naru"), "settled seller actually appears")
	var life = world.get_node("VillageLifeDirector")
	director.refresh()
	player.global_position = life.residents["naru"].global_position + Vector2(25,10)
	check(world.get_node("WorldInteractions").try_interact() and life.talking, "E greets actual settled merchant NPC")
	drain(life.dialogue)
	check(VillageLifeFlow.friendship("naru") == 1, "first NPC greeting opens existing trade service")
	var trade: ResidentTradeDirector = world.get_node("ResidentTradeDirector")
	var stall := VillageSettlement.find_site(world, ResidentTradeFlow.SETTINGS.site)
	player.set_physics_process(false)
	player.global_position = stall.global_position + Vector2(60,0)
	manager.hour_timer.paused = false
	check(world.get_node("WorldInteractions").try_interact() and trade.open, "E at merchant stall opens actual NPC sales panel")
	check(manager.hour_timer.paused and world.get_node("WorldInteractions").blocked(), "shopping pauses clock and blocks other UI")
	GameState.spend_money(GameState.get_money())
	trade.panel.refresh()
	check(trade.panel.cards["supply:gathering_bottle"]["action"].disabled and ResidentMerchantSupply.buy("gathering_bottle").is_empty(), "zero funds cannot buy tool")
	var price := ExpeditionShopData.get_price("gathering_bottle")
	GameState.add_money(price)
	trade.panel.refresh()
	await frames()
	await snap("listing")
	await click(trade.panel.cards["supply:gathering_bottle"]["action"])
	check(GameState.get_money() == 0 and GameState.get_owned_equipment_count("gathering_bottle") == 1, "merchant button charges existing price and creates one equipment instance")
	GameState.add_money(price)
	check(ResidentMerchantSupply.buy("gathering_bottle").is_empty() and GameState.get_money() == price, "duplicate effect never charges twice")
	check(ResidentMerchantSupply.buy("rusty_sword").is_empty() and ResidentMerchantSupply.buy("invalid").is_empty(), "tool seller rejects unrelated/invalid items")
	check(ResidentRequestFlow.current().get("id") == "traveler_water", "Rashu appears after merchant tool purchase")
	for resolution in [Vector2i(1152,648), Vector2i(768,432)]:
		get_window().size = resolution
		await frames()
		check(get_viewport().get_visible_rect().encloses(trade.panel.root.get_global_rect()) and trade.panel.root.get_global_rect().encloses(trade.panel.close_button.get_global_rect()), "merchant panel and close fit screen " + str(resolution))
		await snap("small" if resolution.x == 768 else "purchase")
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	get_viewport().push_input(escape, true)
	await frames()
	check(not trade.open and not manager.hour_timer.paused and not player.is_physics_processing() and not world.has_meta("resident_trade_open"), "Escape restores prior movement/time and clears merchant modal")
	world.queue_free()
	await frames()
	var expedition = load("res://scenes/expedition/expedition.tscn").instantiate()
	add_child(expedition)
	await frames()
	var prep = expedition.prep_panel
	prep.show_departure_choice()
	prep.show()
	check(not prep.has_node("SupplyAccess"), "anonymous expedition shop no longer skips NPC route")
	prep.map_content.region_buttons["forest"].pressed.emit()
	await frames()
	var bag = prep.bag_content
	var gathering := ExpeditionGatheringService.new()
	var loot = load("res://script/expedition/services/expedition_loot_service.gd").new()
	check(not gathering.resolve_gathering("gather_water", bag.bag_model, loot)["gathered"], "owned but unpacked bottle does not collect water")
	var uid := -1
	for placement in bag._get_owned_model().placements:
		if placement["item_id"] == "gathering_bottle": uid = int(placement["uid"])
	check(uid > 0 and bag._transfer_owned_to_bag(uid,Vector2i(3,0)), "merchant tool transfers through actual bag UI flow")
	GameState.save_expedition_bag(bag.bag_model.placements)
	check(ResidentMerchantSupply.owns_effect("collect_water") and GameState.get_owned_equipment_count("gathering_bottle") == 0, "saved packed tool counts as owned")
	check(ResidentMerchantSupply.buy("gathering_bottle").is_empty(), "packed unique tool cannot be repurchased")
	var gathered := 0
	for attempt in range(3):
		var water: Dictionary = gathering.resolve_gathering("gather_water", bag.bag_model, loot)
		check(water["gathered"] and water["item_id"] == "raw_water", "merchant's packed bottle actually gathers water")
		gathered += int(water.get("amount",0))
	check(gathered >= 2, "water sites satisfy request amount")
	GameState.add_item("raw_water", gathered)
	var request := ResidentRequestFlow.current()
	check(ResidentRequestFlow.accept(request), "water request can now be accepted")
	var stock := GameState.get_item_count("raw_water")
	check(not ResidentRequestFlow.deliver(request).is_empty() and GameState.get_item_count("raw_water") == stock - int(request["amount"]), "merchant-gathered water completes request exactly")
	check(ResidentRequestFlow.deliver(request).is_empty(), "water reward cannot repeat")
	var saved := GameState.create_save_data()
	check(GameState.apply_save_data(saved) and ResidentRequestFlow.done("traveler_water") and ResidentMerchantSupply.owns_effect("collect_water"), "save reload preserves quest and packed merchant tool")
	var hint := "\n".join(RequestItemSources.expedition("raw_water", ExpeditionEnvironment.capture()))
	check(hint.contains("준비되어") and hint.contains("가방") and not hint.contains("구매하고"), "preparation recognizes packed tool without duplicate purchase")
	expedition.queue_free()
	await frames()
	print("CHECK_GATHERING_TOOL_ACCESS checks=",checks," failures=",failures)
	get_tree().quit(0 if failures == 0 else 1)
