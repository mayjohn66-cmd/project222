extends Node
## Continuous campaign from the real title screen. No money, items, recipe,
## completion, date or enemy HP fixtures. Shop positioning is automated;
## room combat uses the existing collision-aware movement/attack driver.
var checks := 0
var failures := 0
var runs := 0
var world
var player
var manager
var builder
var ledger: Array[Dictionary] = []
var save_backups := {}

func check(ok: bool, label: String) -> void:
	checks += 1
	print("PASS: " if ok else "BLOCKED: ", label)
	if not ok:
		failures += 1
		push_error(label)

func frames(count: int = 8) -> void:
	for i in range(count): await get_tree().process_frame

func checkpoint(label: String) -> void:
	var row := {"stage":label,"day":GameState.total_day,"money":GameState.get_money(),"inventory":GameState.inventory.duplicate(true),"furniture":GameState.furniture_inventory.duplicate(true),"runs":runs,"phase":ShopSpaceProgression.phase()}
	ledger.append(row)
	print("CAMPAIGN: ", JSON.stringify(row))

func finish() -> void:
	# Restore existing isolated test slots for the ordinary dev-check batch.
	for path in save_backups:
		if save_backups[path] == null:
			if FileAccess.file_exists(path): DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
		else:
			var restored := FileAccess.open(path,FileAccess.WRITE)
			if restored: restored.store_buffer(save_backups[path])
	var args := OS.get_cmdline_user_args()
	for arg in args:
		if arg.begins_with("--report="):
			var file := FileAccess.open(arg.trim_prefix("--report="),FileAccess.WRITE)
			if file: file.store_string(JSON.stringify({"checks":checks,"failures":failures,"ledger":ledger},"  "))
	print("CHECK_NEW_GAME_CONTINUITY checks=%d failures=%d runs=%d" % [checks,failures,runs])
	get_tree().quit(0 if failures == 0 else 1)

func drain(dialogue: StoryDialoguePanel) -> void:
	for i in range(100):
		if not dialogue.open: return
		dialogue._advance()
	check(false,"dialogue terminates")

func settle_dialogues() -> void:
	for i in range(20):
		var found := false
		for node in world.find_children("*","",true,false):
			if node is StoryDialoguePanel and node.open:
				found = true
				drain(node)
		# Read actual arrival/absence/furniture notices before further inputs.
		for node in world.find_children("*","",true,false):
			if node is AcceptDialog and node.visible:
				node.confirmed.emit()
				node.hide()
		world.get_node("TutorialDirector").refresh()
		await frames(2)
		if not found and not world.get_node("TutorialDirector").dialogue.open: break

func bind_shop() -> void:
	world = get_tree().current_scene
	player = world.get_node("Actors/Player")
	manager = world.get_node("DayManager")
	builder = world.get_node("BuildManager")
	# Manual action pacing: clock/spawn callbacks are driven separately.
	# No calendar or balances are assigned here.
	manager.hour_timer.stop()
	manager.customer_spawner.spawn_timer.stop()
	player.set_physics_process(false)

func wait_scene(path: String) -> bool:
	for i in range(180):
		await get_tree().process_frame
		var scene := get_tree().current_scene
		if is_instance_valid(scene) and scene.scene_file_path == path:
			await frames()
			return true
	check(false,"scene transition to " + path)
	return false

func place(id: String, preferred: Vector2i = Vector2i(-1,-1)) -> Node2D:
	if not builder.build_mode: builder.start_build_mode()
	if not builder.build_mode:
		check(false,"build mode available for " + id)
		return null
	builder.build_selection_state.restore_selection(builder.get_catalog_index_from_build_id(id),0)
	builder.create_preview()
	var cells: Array[Vector2i] = []
	if preferred != Vector2i(-1,-1): cells.append(preferred)
	for x in range(builder.floor.columns):
		for y in range(builder.floor.rows): cells.append(Vector2i(x,y))
	for cell in cells:
		if builder.can_place(cell):
			var before: int = GameState.get_furniture_count(id)
			var object = builder.build_placement_service.place_furniture(id,cell)
			check(object != null and GameState.get_furniture_count(id) == before-1,"place owned " + id)
			builder.confirm_build_changes()
			return object
	builder.confirm_build_changes()
	check(false,"valid placement exists for " + id)
	return null

func stock(id: String, amount: int) -> bool:
	var shelves := get_tree().get_nodes_in_group("shelf")
	for shelf in shelves:
		for index in range(shelf.slots.size()):
			var slot: Dictionary = shelf.slots[index]
			if not str(slot["item_id"]).is_empty(): continue
			player.global_position = shelf.global_position
			player.try_restock_shelf()
			var ui = player.shelf_panel
			check(ui.visible,"actual shelf E route opens")
			ui._on_shelf_slot_pressed(index)
			ui._on_inventory_item_pressed(id)
			ui.open_action_menu(index)
			ui.restock_button.pressed.emit()
			var before: int = GameState.get_item_count(id)
			ui.restock_amount = amount
			ui.restock_confirm_button.pressed.emit()
			var ok: bool = shelf.get_item_stock(id) >= amount and GameState.get_item_count(id) == before-amount
			check(ok,"actual stocking consumes earned " + id)
			ui.close()
			return ok
	check(false,"free shelf slot for " + id)
	return false

func checkout_visit() -> void:
	var checkout = world.get_node("CheckoutTutorial")
	check(is_instance_valid(checkout.guide),"guaranteed customer present")
	if not is_instance_valid(checkout.guide): return
	drain(checkout.dialogue)
	drain(checkout.dialogue)
	var id: String = checkout.guide.guide_item_id
	var before: int = GameState.get_money()
	player.global_position = builder.get_cell_world_position(checkout.guide_cell)
	var cashier = world.get_node("ManualCheckoutController")
	check(cashier.try_interact(),"actual cashier interaction")
	cashier._process(2.0)
	check(checkout.guide.purchase_completed and GameState.get_money() == before+ItemData.get_item_price(id),"actual payment adds only sale price")
	drain(checkout.dialogue)
	manager.close_shop_manually()
	manager.hour_timer.stop()
	await settle_dialogues()

func talk_request(expected: String) -> void:
	var director = world.get_node("ResidentRequestDirector")
	director.refresh()
	check(ResidentRequestFlow.current().get("id","") == expected,"natural current request " + expected)
	if not is_instance_valid(director.npc): check(false,"request NPC present"); return
	player.global_position = director.npc.global_position+Vector2(20,0)
	check(director.try_interact(),"actual request interaction " + expected)
	drain(director.dialogue)
	await frames()

func pack_owned(prep) -> void:
	var ui = prep.bag_content
	for id in ["rusty_sword","leather_armor","gathering_bottle"]:
		var uid := -1
		for entry in ui._get_owned_model().placements:
			if str(entry["item_id"]) == id: uid = int(entry["uid"]); break
		if uid < 0: continue
		var packed := false
		for y in range(ui.bag_model.height):
			for x in range(ui.bag_model.width):
				if ui._transfer_owned_to_bag(uid,Vector2i(x,y)):
					packed = true
					break
			if packed: break
		check(packed,"bag UI packs owned " + id)

func organize_loot(expedition) -> void:
	var controller = expedition.expedition_bag_controller
	for i in range(100):
		if expedition.temporary_loot.is_empty(): break
		var placed := false
		for y in range(expedition.expedition_bag.height):
			for x in range(expedition.expedition_bag.width):
				var data := {"source":"loot","loot_index":0,"grab_offset_cell":Vector2i.ZERO}
				if controller.can_drop_grid_data("bag",data,Vector2i(x,y)):
					controller.drop_grid_data("bag",data,Vector2i(x,y))
					placed = true
					break
			if placed: break
		if not placed: break
	expedition.confirm_loot_organization()
	if not expedition.temporary_loot.is_empty():
		expedition.discard_loot_dialog.confirmed.emit()
		expedition.discard_loot_dialog.hide()

func expedition_run(region: String = "forest") -> void:
	await settle_dialogues()
	manager.enter_expedition_scene()
	if not await wait_scene(GameConfig.EXPEDITION_SCENE_PATH): return
	var expedition = get_tree().current_scene
	var prep = expedition.prep_panel
	prep.show_departure_choice()
	prep.map_content.region_buttons[region].pressed.emit()
	await frames()
	pack_owned(prep)
	check(not prep.start_button.disabled,"departure enabled with earned gear")
	prep.start_button.pressed.emit()
	check(expedition.current_expedition_phase == expedition.ExpeditionPhase.RUN,"actual departure")
	runs += 1
	for step in range(40):
		if expedition.current_expedition_phase != expedition.ExpeditionPhase.RUN: break
		var current: Dictionary = expedition.expedition_map.get_node(expedition.current_map_node_id)
		var nexts: Array = current.get("next",[])
		if nexts.is_empty(): check(false,"reachable next map node"); break
		var pick: String = str(nexts[0])
		for candidate in nexts:
			if expedition.expedition_map.get_node(str(candidate)).get("type","") == "gather": pick = str(candidate); break
		expedition.expedition_map_controller.on_node_pressed(pick)
		await frames(2)
		if expedition.expedition_room_controller.is_active():
			check(await ExpeditionRoomTestDriver.play(expedition.expedition_room_controller),"movement/basic attacks/gather/exit complete actual room")
		for drain_index in range(60):
			await frames(1)
			if expedition.message_panel.visible:
				expedition.expedition_message_controller.on_continue_pressed()
			elif expedition.loot_panel.visible: organize_loot(expedition)
			else: break
	check(expedition.current_expedition_phase == expedition.ExpeditionPhase.RESULT,"real expedition reaches result")
	print("RUN_RESULT: ",region," ",expedition.current_end_reason," bag=",expedition.expedition_bag.placements)
	if failures > 0: return
	expedition.result_confirm_button.pressed.emit()
	if not await wait_scene(GameConfig.MAIN_SCENE_PATH): return
	bind_shop()
	if manager.summary_open:
		manager.next_day_button.pressed.emit()
		await frames()
	await settle_dialogues()
	checkpoint("return_" + str(runs))

func tutorial_conversation(expected: String) -> bool:
	var tutorial: TutorialDirector = world.get_node("TutorialDirector")
	tutorial.refresh()
	check(tutorial.flow.current().get("id","") == expected,"natural tutorial step "+expected)
	if not is_instance_valid(tutorial.npc):
		check(false,"tutorial visitor available for "+expected)
		return false
	player.global_position = tutorial.npc.global_position+Vector2(20,0)
	var interacted := tutorial.try_interact()
	check(interacted,"actual NPC conversation for "+expected)
	if not interacted: return false
	drain(tutorial.dialogue)
	await settle_dialogues()
	return true

func ensure_materials(needs: Dictionary) -> void:
	for i in range(12):
		var ready := true
		for id in needs:
			if GameState.get_item_count(str(id)) < int(needs[id]): ready = false
		if ready: return
		await expedition_run("river_valley" if needs.has("raw_water") else "forest")
		if failures > 0: return
	check(false,"obtain requested supplies in bounded natural expeditions " + str(needs))

func snap(label: String) -> void:
	if DisplayServer.get_name() == "headless": return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--snap="):
			await frames(10)
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(arg.trim_prefix("--snap=")+"-"+label+".png")

func _ready() -> void: call_deferred("run")
func run() -> void:
	if not OS.get_user_data_dir().contains("foodbag_checks"):
		check(false,"isolated new-game project required"); finish(); return
	for path in [GameState.SAVE_PATH,GameConfig.SAVE_SLOT_PATHS[0],GameConfig.SAVE_SLOT_PATHS[1]]:
		save_backups[path] = FileAccess.get_file_as_bytes(path) if FileAccess.file_exists(path) else null
	var campaign_seed := 8123
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seed="): campaign_seed = int(arg.trim_prefix("--seed="))
	seed(campaign_seed)
	get_tree().current_scene = null # Keep this runner across real scene transitions.
	get_tree().change_scene_to_file("res://scenes/core/title/title_screen.tscn")
	if not await wait_scene("res://scenes/core/title/title_screen.tscn"): finish(); return
	var title = get_tree().current_scene
	title.new_game_button.pressed.emit()
	if title.new_game_dialog.visible: title.new_game_dialog.hide(); title.new_game_dialog.confirmed.emit()
	title.nickname_edit.text = "연속점검"
	title.nickname_dialog.confirmed.emit()
	title.nickname_dialog.hide()
	if not await wait_scene(GameConfig.MAIN_SCENE_PATH): finish(); return
	bind_shop()
	await settle_dialogues()
	check(GameState.get_money() == 0 and OpeningCleanup.cleaned_count() == 0,"genuine new game starts alone with no earnings")
	checkpoint("new_game")
	# --no-cutscene omits visual debris. For captures only, restore the same
	# dressing fixture without changing cleanup history, items or collisions.
	var cleanup_dressing: OpeningStoreDressing
	if DisplayServer.get_name() != "headless":
		for arg in OS.get_cmdline_user_args():
			if arg.begins_with("--snap="):
				cleanup_dressing = OpeningStoreDressing.new(world.get_node("StoreView3D"))
				cleanup_dressing.smash()
	await snap("cleanup-before")
	var initial_position: Vector2 = player.global_position
	player.global_position = world.get_node("StoreView3D").cell_to_world(Vector2(4.5,7.0))
	await snap("cleanup-near-window")
	player.global_position = initial_position
	if cleanup_dressing != null: cleanup_dressing.clear_all()
	for pile in OpeningCleanup.piles():
		player.global_position = world.get_node("TutorialDirector")._cell_world(pile["stand"])
		check(world.get_node("TutorialDirector").try_interact(),"actual E cleans rubble")
	await settle_dialogues()
	check(OpeningCleanup.all_done(),"all actual rubble cleared")
	place("register",Vector2i(4,3))
	place("shelf_1x1",Vector2i(2,2))
	place("shelf_1x1",Vector2i(2,5))
	await settle_dialogues()
	stock("bread",1) # Preserve barter food; actual player choice, no supply injection.
	await settle_dialogues()
	manager.open_shop()
	manager.customer_spawner.spawn_timer.stop()
	await checkout_visit()
	var tutorial = world.get_node("TutorialDirector")
	tutorial.refresh()
	check(tutorial.flow.current().get("id","") == "barter" and is_instance_valid(tutorial.npc),"first sale naturally brings merchant")
	if failures > 0: finish(); return
	player.global_position = tutorial.npc.global_position+Vector2(20,0)
	check(tutorial.try_interact(),"actual barter NPC E")
	drain(tutorial.dialogue)
	tutorial.barter_panel.action_requested.emit("arrival_barter")
	drain(tutorial.dialogue)
	await settle_dialogues()
	check(OpeningJourneyFlow.traded(),"trade succeeds using salvaged food")
	checkpoint("barter")
	# Read the real merchant's request before leaving, then report the return.
	if not await tutorial_conversation("expedition"): finish(); return
	await expedition_run()
	if failures > 0: finish(); return
	if not await tutorial_conversation("expedition"): finish(); return
	var raw := ""
	for id in GameState.inventory:
		if GameState.get_item_count(str(id)) > 0 and OpeningJourneyFlow.is_raw_material(str(id)):
			if str(id) != "plywood": raw = str(id); break
	check(not raw.is_empty(),"actual first expedition brings sellable material")
	if raw.is_empty(): finish(); return
	stock(raw,1)
	await settle_dialogues()
	manager.open_shop()
	manager.customer_spawner.spawn_timer.stop()
	await checkout_visit()
	check(OpeningJourneyFlow.core_finished(),"core tutorial completes after actual material payment")
	checkpoint("core_tutorial")
	if OS.get_cmdline_user_args().has("--core-only"):
		finish()
		return
	# Optional food-care page must not block residents.
	var cashier = world.get_node("ManualCheckoutController")
	player.global_position = builder.get_cell_world_position(get_tree().get_nodes_in_group("register")[0].get_worker_cells()[0])
	check(cashier.try_interact(),"idle register opens food care")
	cashier.food_cleanup.show_page(true)
	cashier.food_cleanup.confirmed.emit()
	await settle_dialogues()
	for expected in ["neighbor_bread","gatherer_herbs"]:
		talk_request(expected)
		var request := ResidentRequestFlow.current()
		await ensure_materials({str(request["item"]):int(request["amount"])})
		if failures > 0: finish(); return
		talk_request(expected)
		check(ResidentRequestFlow.done(expected),"actual delivery completed " + expected)
	checkpoint("first_two_requests")
	manager.open_shop()
	manager.hour_timer.stop()
	manager.customer_spawner.spawn_timer.stop()
	# Drive the existing arrival callback; it retains rate/identity/path rules.
	var old_scale := Engine.time_scale
	Engine.time_scale = 15.0
	await manager.customer_spawner.spawn_customer()
	Engine.time_scale = old_scale
	await settle_dialogues()
	var requests = world.get_node("ResidentRequestDirector")
	requests.refresh()
	check(ResidentStoryFlow.pending_introduction().get("type","") == "peddler","real pedestrian records merchant reunion")
	if not is_instance_valid(requests.npc): check(false,"merchant reunion NPC present"); finish(); return
	player.global_position = requests.npc.global_position+Vector2(20,0)
	check(requests.try_interact(),"actual merchant reunion E")
	drain(requests.dialogue)
	manager.close_shop_manually()
	await settle_dialogues()
	talk_request("settle_naru")
	await ensure_materials({"dry_branch":4})
	if failures > 0: finish(); return
	talk_request("settle_naru")
	await settle_dialogues()
	checkpoint("merchant_settled")
	tutorial = world.get_node("TutorialDirector")
	tutorial.refresh()
	check(tutorial.flow.current().get("id","") == "production" and is_instance_valid(tutorial.npc),"first settlement naturally offers production")
	if failures > 0: finish(); return
	player.global_position = tutorial.npc.global_position+Vector2(20,0)
	check(tutorial.try_interact(),"merchant explains first production")
	drain(tutorial.dialogue)
	await settle_dialogues()
	check(GameState.get_furniture_count("magic_oven") == 1 and GameState.get_item_count("wheat") >= 4,"actual introduction provides local oven and wheat")
	var life = world.get_node("VillageLifeDirector")
	life.refresh()
	await frames()
	check(life.residents.has("naru"),"settled merchant NPC appears")
	player.global_position = life.residents["naru"].global_position+Vector2(20,0)
	check(life.try_interact(),"merchant first greeting")
	drain(life.dialogue)
	check(ResidentMerchantSupply.available(),"actual greeting enables tool shop")
	var stall := VillageSettlement.find_site(world,ResidentTradeFlow.SETTINGS.site)
	var trade = world.get_node("ResidentTradeDirector")
	player.global_position = stall.global_position+Vector2(60,0)
	check(trade.try_interact(),"actual merchant stall opens")
	var before: int = GameState.get_money()
	trade.panel.cards["supply:gathering_bottle"]["action"].pressed.emit()
	check(GameState.get_money() == before-ExpeditionShopData.get_price("gathering_bottle") and ResidentMerchantSupply.owns_effect("collect_water"),"naturally earned money buys required water tool")
	trade.panel.close()
	talk_request("traveler_water")
	await ensure_materials({"raw_water":2})
	if failures > 0: finish(); return
	talk_request("traveler_water")
	check(ResidentRequestFlow.done("traveler_water"),"actual gathered water delivers")
	checkpoint("water_request")
	var production_door := place("production_door")
	if production_door == null: finish(); return
	player.global_position = production_door.global_position
	check(player.try_use_production_door() and player.in_production_room,"enter actually built production room")
	var oven := place("magic_oven")
	if oven == null: finish(); return
	await settle_dialogues()
	var menu = world.get_node("UI/ManagementMenu")
	var inventory = menu.management_inventory
	inventory._on_recipe_scroll_selected("scroll_camp_bread")
	inventory.recipe_scroll_dialog.confirmed.emit()
	inventory.recipe_scroll_dialog.hide()
	check(PlayerProgress.is_recipe_learned("camp_bread"),"actual received scroll learns local recipe")
	var wheat_before: int = GameState.get_item_count("wheat")
	player.global_position = oven.global_position+Vector2(20,0)
	check(player.try_interact_with_facility() and player.facility_dialog.visible,"actual E opens production workshop")
	var recipe_index: int = player.facility_recipe_ids.find("camp_bread")
	check(recipe_index >= 0,"learned local bread selectable in actual workshop")
	player.facility_recipe_picker.select(recipe_index)
	player.facility_recipe_picker.item_selected.emit(recipe_index)
	await frames()
	check(player.facility_start_button.visible and not player.facility_start_button.disabled,"actual workshop enables first production button")
	check(Rect2(Vector2.ZERO,Vector2(player.facility_dialog.size)).encloses(player.facility_start_button.get_global_rect()),"production button fits actual workshop window")
	await snap("workshop")
	player.facility_start_button.pressed.emit()
	check(oven.production_state == ProductionFacility.ProductionState.PROCESSING and GameState.get_item_count("wheat") == wheat_before-2,"actual production button consumes earned/gifted wheat")
	oven._process(oven.remaining_seconds) # advance only production's elapsed processing time
	await frames()
	check(player.facility_collect_button.visible and not player.facility_collect_button.disabled,"actual finished output enables collection button")
	player.facility_collect_button.pressed.emit()
	check(ShopSpaceProgression.first_product(),"actual collection button opens warehouse stage")
	player.facility_dialog.confirmed.emit()
	player.facility_dialog.hide()
	checkpoint("first_product")
	await snap("production")
	player.global_position = world.get_node("ProductionRoom").get_entry_world_position()
	check(player.try_use_production_door() and not player.in_production_room,"return from production")
	await settle_dialogues()
	# Complete the merchant's actual follow-up after collecting the first bread.
	tutorial = world.get_node("TutorialDirector")
	tutorial.refresh()
	check(tutorial.flow.current().get("id","") == "production" and is_instance_valid(tutorial.npc),"production completion brings merchant follow-up")
	if failures > 0: finish(); return
	player.global_position = tutorial.npc.global_position+Vector2(20,0)
	check(tutorial.try_interact(),"actual E hears first-production follow-up")
	drain(tutorial.dialogue)
	await settle_dialogues()
	check(tutorial.flow.done("production"),"first-production tutorial finishes before warehouse")
	var warehouse_door := place("warehouse_door")
	if warehouse_door == null: finish(); return
	player.global_position = warehouse_door.global_position
	check(player.try_use_warehouse_door() and player.in_warehouse_room,"enter actually built warehouse")
	var rack := place("warehouse_rack")
	if rack == null: finish(); return
	check(rack.deposit_from_inventory("wheat",1) == 1 and ShopSpaceProgression.expansion_ready(),"actual storage transfer opens expansion guidance")
	checkpoint("warehouse_used")
	await snap("warehouse")
	player.global_position = world.get_node("WarehouseRoom").get_entry_world_position()
	check(player.try_use_warehouse_door() and not player.in_warehouse_room,"return from warehouse")
	builder.save_store_layout()
	var saved := GameState.create_save_data().duplicate(true)
	var counts_before := GameState.get_inventory_data()
	check(GameState.apply_save_data(saved) and ShopSpaceProgression.expansion_ready() and GameState.get_inventory_data() == counts_before,"continuous campaign state survives save apply")
	var projected := InventoryCountSlots.build(counts_before,GameState.PLAYER_INVENTORY_SLOT_COUNT,GameState.PLAYER_INVENTORY_STACK_LIMIT)
	var totals := {}
	for slot in projected:
		if not str(slot["item_id"]).is_empty(): totals[slot["item_id"]] = int(totals.get(slot["item_id"],0))+int(slot["amount"])
	var expected_totals := {}
	for id in counts_before:
		if int(counts_before[id]) > 0: expected_totals[id] = counts_before[id]
	check(totals == expected_totals and projected.size() >= maxi(12,expected_totals.size()),"slot compatibility projection preserves every naturally collected item")
	check(InventoryCountSlots.build({},12,99).size() == 12,"empty compatibility projection retains twelve initial slots")
	# Stateless projection case only; never added to the campaign inventory.
	var multi_stack := InventoryCountSlots.build({"bread":205},0,99)
	check(multi_stack.size() == 3 and multi_stack[0]["amount"] == 99 and multi_stack[2]["amount"] == 7,"compatibility projection preserves stacks exceeding one legacy slot")
	# Actual day-end/confirmation prepares a valid save time; no date fixture.
	manager.close_shop_for_day_end_and_settle()
	for i in range(300):
		await frames(1)
		if manager.summary_open: break
	check(manager.summary_open,"actual day-end summary opens")
	manager.next_day_button.pressed.emit()
	await settle_dialogues()
	check(GameState.total_day == 2 and manager.current_hour == GameConfig.DAY_START_HOUR,"actual summary advances next day preparation")
	var save_path := str(GameConfig.SAVE_SLOT_PATHS[0])
	check(manager.save_preparation_checkpoint(save_path),"actual preparation writes verified campaign save")
	var counts := GameState.get_inventory_data()
	var money := GameState.get_money()
	manager._on_game_menu_return_title_requested()
	if not await wait_scene(GameConfig.TITLE_SCENE_PATH): finish(); return
	title = get_tree().current_scene
	title.continue_button.pressed.emit()
	title.load_slot_1_button.pressed.emit()
	if not await wait_scene(GameConfig.MAIN_SCENE_PATH): finish(); return
	bind_shop()
	await settle_dialogues()
	check(GameState.get_inventory_data() == counts and GameState.get_money() == money and ShopSpaceProgression.expansion_ready(),"real title/slot reload preserves earned counts and room milestones")
	await snap("reloaded")
	checkpoint("complete")
	finish()
