extends "res://dev/script/check_market_afterglow.gd"
# Prior tutorial/settlement history and interaction approach positions are fixtures.
# Return settlement, actual board/book buttons, E/Esc, dialogue completion and
# exact consumption/rewards run through production code. No user save is touched.
const F = preload("res://script/world/shop/requests/village_expansion_flow.gd")

func key(code: Key) -> void:
	for pressed in [true,false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.pressed = pressed
		get_viewport().push_input(event,true)
	await settle()

func click(button: Button, menu: Control = null) -> void:
	await settle()
	var parent := button.get_parent()
	while parent != null and not parent is ScrollContainer: parent = parent.get_parent()
	if parent is ScrollContainer: parent.ensure_control_visible(button)
	await settle()
	var at := button.get_global_rect().get_center()
	if menu != null and menu.has_meta("book_stage") and is_instance_valid(menu.get_meta("book_stage")):
		at += menu.get_meta("book_stage")._offset
	var motion := InputEventMouseMotion.new()
	motion.position=at
	get_viewport().push_input(motion,true)
	for pressed in [true,false]:
		var event := InputEventMouseButton.new()
		event.position = at
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		get_viewport().push_input(event,true)
	await settle()

func snap(label: String) -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty() or DisplayServer.get_name() == "headless": return
	await get_tree().create_timer(0.3).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(args[0]+"-"+label+".png")

func greet_fixture() -> void:
	for entry in VillageLifeFlow.entries(): PlayerProgress.record_story_beat(VillageLifeFlow.PREFIX+"greeted:"+str(entry["id"]),GameState.total_day)

func approach(id: String) -> void:
	life.refresh()
	for npc in life.residents.values(): npc.set_physics_process(false)
	player.global_position = life.residents[id].global_position + Vector2(20,0)
	await settle()

func finish_talk(panel: StoryDialoguePanel) -> void:
	for i in range(160):
		if not panel.open: return
		await key(KEY_E)
	check(false,"actual E finishes dialogue")

func returned_material(table: String, item: String, needed: int) -> void:
	var loot = load("res://script/expedition/services/expedition_loot_service.gd").new()
	loot.environment = ExpeditionEnvironment.capture()
	var result_service = load("res://script/expedition/services/expedition_result_service.gd").new()
	for attempt in range(100):
		if GameState.get_item_count(item) >= needed: break
		var result: Dictionary = loot.roll_loot_table(table)
		if not result.get("success",false): continue
		var bag := ExpeditionBag.new()
		check(bag.add_item(str(result["item_id"]),Vector2i.ZERO,int(result["amount"])) > 0,"real rolled material fits return bag")
		var receipt: Dictionary = result_service.deposit_items(bag)
		check(receipt.get("success",false),"real return settles material to owned stock")
		check(result_service.deposit_items(bag).get("deposited_amount",-1) == 0,"return cannot deposit twice")
	check(GameState.get_item_count(item) >= needed,"existing loot supplies required material: " + item)

func journal_button(menu, title: String) -> Button:
	for card in menu.schedule_list.get_children():
		var labels: Array[Node] = card.find_children("*","Label",true,false)
		if labels.is_empty() or labels[0].text != title: continue
		for child in card.get_children():
			if child is Button: return child
	return null

func expansion_talk(id: String) -> void:
	var current := F.step(id)
	await approach(str(current["resident"]))
	await key(KEY_E)
	var director = life.get_node("VillageExpansionDirector")
	check(director.talking and director.action.get("event","") == id,"actual E starts current expansion dialogue")

func run() -> void:
	check(OS.get_user_data_dir().contains("foodbag_checks"),"isolated resident follow-through project")
	if not OS.get_user_data_dir().contains("foodbag_checks"): get_tree().quit(1); return
	seed(94521)
	GameState.initialize_new_game()
	PlayerProgress.reset()
	GameState.total_day = 50
	unlock()
	PlayerProgress.record_story_beat(ShopSpaceProgression.VERSION,1)
	for id in ["naru_provisions","naru_neighbor_basket","naru_market_juice"]: PlayerProgress.record_story_beat(PersonalRequestFlow.PREFIX+id+":done",1)
	PlayerProgress.record_story_beat(MarketAfterglowFlow.PREFIX+"naru_market_juice:heard",1)
	PlayerProgress.record_story_beat(VillageMarketFlow.PREFIX+"done",1)
	PlayerProgress.record_story_beat(VillageRestFlow.PREFIX+"done",1)
	PlayerProgress.record_story_beat(CraftingPathFlow.key("craft_trail_food","done"),1)
	PlayerProgress.learn_recipe("dried_fruit")
	greet_fixture()
	GameState.inventory.clear()
	world = load("res://scenes/shop/main.tscn").instantiate()
	world.get_node("TutorialDirector").enabled = false
	add_child(world)
	await settle()
	life=world.get_node("VillageLifeDirector")
	player=world.get_node("Actors/Player")
	manager=world.get_node("DayManager")
	board=world.get_node("CommunityBoardDirector")
	player.set_physics_process(false)
	manager.hour_timer.paused=true
	manager.current_hour=6
	VillageSettlement.apply_world(world)
	life.refresh()
	check(not ShopSpaceProgression.room_ready("warehouse"),"physical warehouse is not required for this raw-material delivery")
	var id := "naru_bundle_mending"
	var entry := PersonalRequestFlow.request(id)
	check(PersonalRequestFlow.locked_reason(entry).is_empty(),"existing personal request prerequisites are ready")
	check(open_board(),"actual board director opens at approach position")
	await click(board.panel.cards["personal:"+id]["action"])
	check(PersonalRequestFlow.accepted(id) and not PersonalRequestFlow.can_deliver(id),"actual accept changes no missing stock into a reward")
	check(board.panel.message.text.contains("맡았습니다"),"accept retains existing status message")
	check(board.panel.introduction().contains("소지품") and board.panel.introduction().contains("꺼낸 뒤"),"board distinguishes inventory from physical stored stock")
	check(board.panel.cards["personal:"+id]["info"].text.contains("소지품"),"actual personal card identifies its inventory count")
	var before: Dictionary = GameState.create_save_data().duplicate(true)
	PersonalRequestFlow.information(entry)
	VillageJournalFlow.information("personal:"+id)
	check(GameState.create_save_data() == before,"guidance reads no new cash, stock or progress")
	await click(board.panel.close_button)
	check(not board.open and manager.hour_timer.paused and not player.is_physics_processing(),"actual close restores original clock and movement state")
	await returned_material("choice_marsh_reed","marsh_reed",2)
	await returned_material("forest_treasure","amber_sap",1)
	check(PersonalRequestFlow.can_deliver(id) and not ShopSpaceProgression.room_ready("warehouse"),"returned stock enables delivery before warehouse construction")
	var totals := CommunityRequestFlow.required_items(entry)
	var stock := GameState.inventory.duplicate(true)
	var money: int = GameState.get_money()
	var reputation := ResidentRequestFlow.reputation()
	check(open_board(),"board reopens after return")
	board.panel.refresh()
	await click(board.panel.cards["personal:"+id]["action"])
	check(PersonalRequestFlow.done(id) and GameState.get_money() == money + int(entry["money"]) and ResidentRequestFlow.reputation() == reputation + int(entry["reputation"]),"actual delivery pays existing reward exactly once")
	for item in totals: check(GameState.get_item_count(item) == int(stock.get(item,0)) - int(totals[item]),"actual delivery consumes exact owned amount: " + str(item))
	check(PersonalRequestFlow.deliver(id).is_empty(),"repeat delivery cannot pay twice")
	check(MarketAfterglowFlow.pending("naru") == id and not MarketAfterglowFlow.heard(id),"delivery leaves actual follow-up pending")
	check(VillageJournalFlow.destination(world,"personal:"+id) == life.residents["naru"],"completed personal request points to actual resident for follow-up")
	await click(board.panel.close_button)
	var journal = world.get_node("VillageJournalDirector")
	var menu = world.get_node("UI/ManagementMenu")
	await key(KEY_N)
	await get_tree().create_timer(1.7,true,false,true).timeout # Let the actual book cover finish opening.
	check(menu.visible,"actual N opens book schedule")
	var button := journal_button(menu,str(entry["title"]))
	check(button != null and not button.disabled,"book offers current follow-up destination")
	if button != null: await click(button,menu)
	check(journal.tracked_id == "personal:"+id,"actual book button tracks pending follow-up")
	await snap("journal")
	await key(KEY_ESCAPE)
	await get_tree().create_timer(1.7,true,false,true).timeout # Closing cover restores world interactions.
	await settle()
	check(not menu.visible and journal.marker.visible,"closing book exposes destination marker")
	stock=GameState.inventory.duplicate(true)
	money=GameState.get_money()
	reputation=ResidentRequestFlow.reputation()
	check(PersonalRequestFlow.locked_reason(PersonalRequestFlow.request("naru_trail_snacks")).is_empty(),"unrelated snack request is genuinely available")
	await approach("naru")
	await key(KEY_E)
	check(life.talking and life.afterglow_action == id,"actual E chooses pending delivered-request follow-up")
	check(life.dialogue.lines.has(MarketAfterglowFlow.lines(id)[0]) and not life.dialogue.lines.has(RequestTextData.lines("personal_request","naru_trail_snacks")[0]),"follow-up contains current story without unrelated request preview")
	await snap("followup")
	await key(KEY_ESCAPE)
	check(not MarketAfterglowFlow.heard(id) and manager.hour_timer.paused and not player.is_physics_processing(),"partial read remains pending and restores clock/movement")
	save_reload()
	check(MarketAfterglowFlow.pending("naru") == id,"save round trip keeps partial follow-up")
	await approach("naru")
	await key(KEY_E)
	await finish_talk(life.dialogue)
	check(MarketAfterglowFlow.heard(id) and MarketAfterglowFlow.pending("naru").is_empty(),"actual final E records follow-up once")
	check(GameState.inventory == stock and GameState.get_money() == money and ResidentRequestFlow.reputation() == reputation,"follow-up grants and consumes no extra goods or rewards")
	check(not MarketAfterglowFlow.listen(id),"repeated completion grants no extra record")
	save_reload()
	check(VillageJournalFlow.information("personal:"+id).contains("후일담을 들은 날"),"saved journal presents heard memory")
	check(ResidentFollowthroughGuide.personal_lines("naru","").has(RequestTextData.lines("personal_request","naru_trail_snacks")[0]),"ordinary conversation retains available personal request introduction")
	# Representative multi-resident story: introduction, own-stock delivery,
	# same-day waiting, next-day continuation and final reward. Prepared product
	# is a fixture; actual facility crafting is covered by check_village_expansion.
	PlayerProgress.record_story_beat(PersonalRequestFlow.PREFIX+"naru_trail_snacks:done",GameState.total_day-1)
	PlayerProgress.record_story_beat(MarketAfterglowFlow.PREFIX+"naru_trail_snacks:heard",GameState.total_day-1)
	var story := "shared_snack"
	check(open_board(),"board opens for next multi-resident story")
	await click(board.panel.cards[F.JOURNAL_PREFIX+story]["action"])
	check(F.accepted(story),"actual button accepts current unlocked story")
	await click(board.panel.close_button)
	await expansion_talk(story)
	var director = life.get_node("VillageExpansionDirector")
	await key(KEY_ESCAPE)
	check(int(F.step(story)["index"]) == 0,"partial introduction does not advance story")
	await expansion_talk(story)
	await finish_talk(director.dialogue)
	check(int(F.step(story)["index"]) == 1 and F.step_reason(story).contains("소지품"),"first completed conversation points to actual missing inventory")
	check(F.information(story).contains("소지품"),"current expansion count uses same inventory basis")
	GameState.add_item("dried_fruit",2)
	money=GameState.get_money()
	reputation=ResidentRequestFlow.reputation()
	await expansion_talk(story)
	await finish_talk(director.dialogue)
	check(GameState.get_item_count("dried_fruit") == 0 and GameState.get_money() == money and int(F.step(story)["index"]) == 2,"middle dialogue consumes exact product before final reward")
	await expansion_talk(story)
	check(not director.can_finish and director.dialogue.lines.has("다음 날 이웃에게 이어지는 이야기를 들어 주세요."),"same-day conversation explains existing next-day pause")
	await finish_talk(director.dialogue)
	check(int(F.step(story)["index"]) == 2 and GameState.get_money() == money,"waiting conversation cannot skip day or give reward")
	GameState.total_day += 1 # Controlled test calendar; no game-side time skip.
	greet_fixture()
	await expansion_talk(story)
	await finish_talk(director.dialogue)
	check(int(F.step(story)["index"]) == 3,"next day completes actual continuation")
	var final_action := F.step(story)
	await expansion_talk(story)
	await finish_talk(director.dialogue)
	check(F.done(story) and not F.accepted(story) and GameState.get_money() == money + int(F.event(story)["money"]) and ResidentRequestFlow.reputation() == reputation + int(F.event(story)["reputation"]),"final dialogue alone grants existing story reward")
	check(not F.complete(final_action),"completed story cannot grant final reward again")
	board.panel.refresh()
	check(board.panel.cards[F.JOURNAL_PREFIX+story]["action"].disabled and board.panel.cards[F.JOURNAL_PREFIX+story]["action"].text == UiText.t("request.followthrough.finished"),"actual completed story card stops promising another chapter")
	check(VillageJournalFlow.destination(world,F.JOURNAL_PREFIX+story) == null,"completed finite story has no invented next destination")
	save_reload()
	check(F.done(story) and F.information(story).contains("함께 마친 날"),"save keeps completed story history")
	# Existing completed-story UI states only. No conditions or data are altered.
	for flow in [F,ActFourFlow]:
		for event in flow.SETTINGS.events:
			var event_id := str(event["id"])
			PlayerProgress.record_story_beat(flow.key(event_id,"last_done"),GameState.total_day)
			PlayerProgress.story_beat_days[flow.key(event_id,"count")] = 1
			board.panel.refresh()
			var card: Dictionary = board.panel.cards[flow.JOURNAL_PREFIX+event_id]
			if str(event.get("repeat","")).is_empty():
				check(card["action"].disabled and card["action"].text == UiText.t("request.followthrough.finished"),"finite completed card is final: " + flow.JOURNAL_PREFIX+event_id)
			elif not flow.locked_reason(event_id).is_empty():
				check(card["action"].disabled and card["action"].text == UiText.t("request.followthrough.repeat_wait"),"repeat card preserves waiting state: " + flow.JOURNAL_PREFIX+event_id)
			else:
				check(not card["action"].disabled and card["action"].text == "이야기 맡기","repeat card preserves actual next acceptance: " + flow.JOURNAL_PREFIX+event_id)
	check(open_board(),"final records board opens")
	var action: Button = board.panel.cards[F.JOURNAL_PREFIX+story]["action"]
	var scroll := action.get_parent().get_parent().get_parent() as ScrollContainer
	await settle()
	scroll.ensure_control_visible(action)
	await settle()
	check(board.panel.close_button.get_global_rect().end.y <= get_viewport().get_visible_rect().end.y,"board close button stays inside viewport")
	await snap("completed")
	await click(board.panel.close_button)
	print("CHECK_RESIDENT_FOLLOWTHROUGH checks=",checks," failures=",failures)
	get_tree().quit(0 if failures == 0 else 1)
