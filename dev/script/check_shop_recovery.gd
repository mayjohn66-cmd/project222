extends Node
# Fixed layout/stock/history and lethal HP are fixtures; source transfers,
# row selection, enemy damage, result confirmation and scene return are real.
var checks := 0
var failures := 0
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(message)
func frames(n: int = 12) -> void:
	for i in range(n): await get_tree().process_frame
func point(control: Control, position: Vector2) -> void:
	if control.get_window() != get_window(): position += Vector2(control.get_window().position)
	for down in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = position; event.button_index = MOUSE_BUTTON_LEFT; event.pressed = down
		get_viewport().push_input(event, true)
	await frames()
func click(button: Button) -> void: await point(button, button.get_global_rect().get_center())
func key(code: Key) -> void:
	for down in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code; event.physical_keycode = code; event.pressed = down
		get_viewport().push_input(event, true)
	await frames()
func product(world: Node, item: String) -> Dictionary:
	for entry in RegisterProductOverview.entries(world):
		if entry["item_id"] == item: return entry
	return {}
func note(world: Node, item: String) -> String: return RegisterRestockGuide.note(world, product(world,item))
func storage(parent: Node, amount: int, preview: bool = false) -> Node:
	var node = load("res://scenes/shop/warehouse/warehouse_storage.tscn").instantiate()
	node.set_meta("is_build_preview", preview)
	parent.add_child(node)
	node.apply_stored_items({"camp_bread":amount})
	return node
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
	GameState.initialize_new_game(); PlayerProgress.reset()
	PlayerProgress.record_story_beat(OpeningJourneyFlow.VERSION, 1)
	PlayerProgress.record_story_beat(CheckoutTutorial.BEAT_ID, 1)
	for id in FoodShelfLife.SETTINGS.grace_steps: PlayerProgress.record_story_beat("tutorial_step:"+id+":done",1)
	GameState.inventory.clear(); GameState.rebuild_inventory_slots_from_counts()
	GameState.save_store_layout([
		{"build_id":"door","anchor":Vector2i(0,4),"rotation_index":3},
		{"build_id":"register","anchor":Vector2i(4,3),"rotation_index":0},
		{"build_id":"shelf_1x1","anchor":Vector2i(2,2),"rotation_index":0,"shelf_slots":[{"item_id":"camp_bread","stock":0,"capacity":5}]}])
	var world = load(GameConfig.MAIN_SCENE_PATH).instantiate()
	world.get_node("TutorialDirector").enabled = false
	get_tree().root.add_child(world); get_tree().current_scene = world
	await frames()
	world.get_node("CustomerSpawner").set_process(false)
	for worker in get_tree().get_nodes_in_group("worker"): worker.queue_free()
	await frames()
	var empty := note(world,"camp_bread")
	check(empty.contains("보충할 재고가 없습니다"),"sold out with no sources has truthful fallback")
	check(not empty.contains("제조법") and not empty.contains("생산실"),"unlearned future crafting is not exposed")
	var shelf = get_tree().get_nodes_in_group("shelf")[0]
	var store := storage(world.get_node("Objects"),4)
	var preview := storage(world.get_node("Objects"),50,true)
	var outside := storage(self,60)
	var removed := storage(world.get_node("Objects"),70); removed.queue_free()
	check(note(world,"camp_bread").contains("창고 선반 4개") and not note(world,"camp_bread").contains("소지"),"warehouse count excludes preview, other world and queued deletion")
	GameState.add_item("camp_bread",9)
	check(PreservationService.install("fridge",true) and PreservationService.install("freezer",true),"fixture cold storage installation")
	check(PreservationService.deposit("fridge","camp_bread",2) == 2 and PreservationService.deposit("freezer","camp_bread",3) == 3,"actual cold deposits")
	check(note(world,"camp_bread").contains("소지 4개") and note(world,"camp_bread").contains("냉장 보관 2개") and note(world,"camp_bread").contains("냉동 보관 3개"),"four stock locations are distinct")
	var before := GameState.create_save_data().duplicate(true)
	for i in range(3): note(world,"camp_bread")
	check(before == GameState.create_save_data() and shelf.get_item_stock("camp_bread") == 0,"reading guide does not transfer, purchase or learn")
	var register = get_tree().get_nodes_in_group("register")[0]
	var player = world.get_node("Actors/Player")
	player.set_physics_process(false)
	player.global_position = world.get_node("BuildManager").get_cell_world_position(register.get_worker_cells()[0])
	await key(KEY_E)
	var panel: RegisterDashboardPanel = world.get_node("ManualCheckoutController").food_cleanup
	check(panel.visible and get_tree().paused and not panel.cleanup_seen,"actual E opens idle register without employee")
	var row := panel.product_table.get_root().get_first_child()
	await point(panel.product_table, panel.product_table.global_position + panel.product_table.get_item_area_rect(row,0).get_center())
	check(panel.product_table.get_selected() == row and panel.detail.text.contains("냉동 보관 3개"),"actual row pointer displays restocking actions")
	panel.scroll.scroll_vertical = 100000; await frames()
	check(panel.get_ok_button().get_global_rect().end.y < panel.size.y and panel.scroll.scroll_vertical > 0,"long selected detail scrolls and keeps return button")
	await snap("sold-out")
	await click(panel.get_ok_button())
	check(not panel.visible and not get_tree().paused and not FoodShelfLife.state()["learned"],"actual return restores play without completing optional cleanup")
	check(FoodShelfLife.restock_slot(shelf,0,4) == 4 and GameState.get_item_count("camp_bread") == 0,"actual shelf restock consumes carried goods")
	check(note(world,"camp_bread").is_empty(),"stocked assignment stops displaying sold-out guidance")
	shelf.take_items_by_id("camp_bread",4)
	check(store.withdraw_slot_to_inventory(store.find_item_slot("camp_bread"),2) == 2,"actual warehouse withdrawal")
	check(note(world,"camp_bread").contains("소지 2개") and note(world,"camp_bread").contains("창고 선반 2개"),"source counts follow withdrawal without phantom restock")
	check(PreservationService.withdraw("freezer","camp_bread",3) == 3 and not note(world,"camp_bread").contains("냉동 보관"),"actual freezer withdrawal removes cold source")
	GameState.remove_item("camp_bread",5)
	store.withdraw_slot_to_inventory(store.find_item_slot("camp_bread"),2); GameState.remove_item("camp_bread",2)
	PreservationService.withdraw("fridge","camp_bread",2); GameState.remove_item("camp_bread",2)
	check(note(world,"camp_bread").contains("보충할 재고가 없습니다"),"all sources depleted returns to safe fallback")
	preview.queue_free(); outside.queue_free()
	world.queue_free(); get_tree().current_scene = self; await frames()
	# A packed item survives defeat; an unorganized room reward is not deposited.
	GameState.save_expedition_bag([])
	var expedition = load("res://scenes/expedition/expedition.tscn").instantiate()
	get_tree().root.add_child(expedition); get_tree().current_scene = expedition
	await frames()
	expedition.expedition_map = ExpeditionMap.new()
	expedition.set_expedition_phase(expedition.ExpeditionPhase.RUN)
	check(expedition.expedition_bag.add_item("wild_berry",Vector2i.ZERO,2) >= 0 and expedition.expedition_bag.add_item("rusty_sword",Vector2i(1,0)) >= 0,"packed loot and gear fixture")
	var controller: ExpeditionRoomController = expedition.expedition_room_controller
	controller.enter({"result_type":"battle","target_id":"field_slime"},"battle")
	controller.view.set_physics_process(false)
	controller.pending_loot.assign([{"item_id":"raw_water","amount":3}])
	controller.model.player_hp = 1
	controller.model.player_position = controller.model.enemies[0]["position"]
	controller.model.step(0.01,Vector2.ZERO,false); controller.model.step(1.0,Vector2.ZERO,false)
	await frames()
	check(expedition.current_expedition_phase == expedition.ExpeditionPhase.RESULT and expedition.current_end_reason == expedition.ExpeditionEndReason.DEFEAT,"real enemy damage opens defeat result")
	check(not controller.view.visible and expedition.temporary_loot.is_empty(),"defeat closes room and unorganized reward panel")
	check(GameState.get_item_count("wild_berry") == 0 and expedition.expedition_bag.placements.size() == 2,"before confirmation packed loot is not yet deposited")
	check(expedition.result_info_label.text.contains(ItemData.get_item_name("wild_berry")) and expedition.result_info_label.text.contains(ItemData.get_item_name("rusty_sword")),"failure result still lists retained loot and gear")
	var money: int = GameState.money
	await snap("defeat")
	await click(expedition.result_confirm_button)
	await frames(30)
	check(get_tree().current_scene.scene_file_path == GameConfig.MAIN_SCENE_PATH,"actual failure confirmation returns to shop scene")
	check(GameState.get_item_count("wild_berry") == 2 and GameState.get_item_count("raw_water") == 0,"return deposits packed material once, not unorganized reward")
	check(GameState.money == money and GameState.saved_expedition_bag.size() == 1 and GameState.saved_expedition_bag[0]["item_id"] == "rusty_sword","no automatic sale and gear remains in bag")
	print("CHECK_SHOP_RECOVERY checks=",checks," failures=",failures)
	get_tree().quit(0 if failures == 0 else 1)
