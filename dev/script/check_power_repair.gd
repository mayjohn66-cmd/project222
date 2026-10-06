extends Node
const Tools = preload("res://dev/gemini/request_text_tools.gd")
var checks := 0
var failures := 0
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("FAIL: " + message)
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("run")
func frames() -> void:
	for i in range(6): await get_tree().process_frame
func drain(dialogue: StoryDialoguePanel) -> void:
	for i in range(100):
		if not dialogue.open: return
		dialogue._advance()
	check(false, "dialogue finishes")
func place_basics(shop) -> void:
	# 새 게임은 문만 놓인 채 시작하므로(부서진 가게) 이 검사에 필요한 계산대·진열대를 놓아 둔다.
	var layout: Array[Dictionary] = [
		{"build_id":"door", "anchor":Vector2i(0,4), "rotation_index":3},
		{"build_id":"register", "anchor":Vector2i(4,3), "rotation_index":0},
		{"build_id":"shelf_1x1", "anchor":Vector2i(2,2), "rotation_index":0}]
	shop.get_node("BuildManager")._restore_current_area_layout(layout)
func run() -> void:
	GameState.initialize_new_game()
	var world = load("res://scenes/shop/main.tscn").instantiate()
	add_child(world)
	await frames()
	place_basics(world)
	await frames()
	var tutorial = world.get_node("TutorialDirector")
	tutorial.dialogue.close()
	tutorial.enabled = false
	tutorial.refresh()
	var manager = world.get_node("DayManager")
	manager.hour_timer.stop()
	manager.customer_spawner.set_process(false)
	var life = world.get_node("VillageLifeDirector")
	life.set_process(false)
	var cashier = world.get_node("ManualCheckoutController")
	var repair: PowerRepairDirector = cashier.get_node("PowerRepairDirector")
	repair.set_process(false)
	var player = world.get_node("Actors/Player")
	player.set_physics_process(false)
	check(PowerRepairFlow.opted_in() and not PowerRepairFlow.powered(), "genuine bootstrap starts with broken unpowered register")
	check(PowerRepairFlow.action("naru").is_empty() and not PowerRepairFlow.inspect() and not PowerRepairFlow.order() and not PowerRepairFlow.finish(), "no bypass before introduction inspection contract and workday")
	var register = get_tree().get_nodes_in_group("register")[0]
	player.global_position = world.get_node("BuildManager").get_cell_world_position(register.get_worker_cells()[0])
	cashier._update_panel()
	check(cashier.panel.action.text == "장부 조회 [E]", "initial idle register offers handwritten book")
	check(cashier.try_interact() and cashier.food_cleanup.title.contains("전원 꺼짐"), "broken register preserves real product information as paper ledger")
	cashier.food_cleanup.confirmed.emit()
	check(not get_tree().paused, "ledger close restores processing")
	for step in TutorialDirector.SETTINGS.steps:
		if not step.get("optional", false): PlayerProgress.record_story_beat("tutorial_step:" + str(step["id"]) + ":done", 1)
	PlayerProgress.record_story_beat(CheckoutTutorial.BEAT_ID, 1)
	# A genuine sale remains available while the power story is incomplete.
	var shelf = get_tree().get_nodes_in_group("shelf")[0]
	shelf.slots[0]["item_id"] = "water"
	FoodShelfLife.restock_slot(shelf, 0, 1)
	var buyer = load("res://scenes/shop/actors/customer.tscn").instantiate()
	world.get_node("Actors").add_child(buyer)
	buyer.set_physics_process(false)
	buyer.carried_item_id = "water"
	buyer.carried_amount = shelf.take_items_by_id("water", 1)
	buyer.target_register = register
	buyer.global_position = world.get_node("BuildManager").get_cell_world_position(register.get_checkout_cells()[0])
	register.request_checkout(buyer)
	manager.open_shop()
	manager.hour_timer.stop()
	var money := GameState.get_money()
	check(cashier.try_interact() and cashier.is_busy(), "broken register performs existing manual checkout")
	cashier._update_panel()
	check(cashier.panel.action.text == "손으로 계산 [E]", "customer checkout explicitly remains manual")
	cashier._finish_checkout()
	check(buyer.purchase_completed and GameState.get_money() == money + 100, "manual cash sale works before learning about magic power")
	PlayerProgress.record_story_beat(ResidentRequestFlow.PREFIX + "settle_naru:done", GameState.total_day)
	VillageSettlement.apply_world(world)
	life.refresh()
	check(is_instance_valid(life.residents.get("naru")), "existing merchant returns as actual settled resident")
	player.global_position = life.residents["naru"].global_position
	check(world.get_node("WorldInteractions").try_interact() and life.story_action.get("flow") == "power_repair", "merchant introduces magic source through actual E dialogue")
	life.dialogue.close()
	check(not PowerRepairFlow.introduced(), "partial merchant dialogue does not unlock technician")
	life.try_interact()
	drain(life.dialogue)
	check(PowerRepairFlow.introduced() and PowerRepairFlow.action("naru").is_empty(), "full introduction advances once and releases merchant other stories")
	repair.refresh()
	check(is_instance_valid(repair.npc), "technician physically visits reachable exterior tiles")
	if not is_instance_valid(repair.npc):
		get_tree().quit(1)
		return
	check(repair.npc.global_position.distance_to(life.residents["naru"].global_position) > 64, "technician does not overlap settled merchant")
	player.global_position = repair.npc.global_position
	check(world.get_node("WorldInteractions").try_interact() and repair.dialogue.open and get_tree().paused, "E reaches technician with world paused")
	repair.dialogue.close()
	check(not PowerRepairFlow.marked("inspected") and not get_tree().paused, "partial inspection restores processing without advancing")
	repair.try_interact()
	drain(repair.dialogue)
	check(PowerRepairFlow.phase() == "supplies" and not PowerRepairFlow.powered(), "full inspection offers explicit repair contract")
	GameState.money = 0
	var before := GameState.inventory.duplicate(true)
	repair.try_interact()
	check(repair.panel.visible and repair.panel.submit.disabled, "missing cost and materials disable repair submission")
	repair.panel.repair_requested.emit()
	check(GameState.inventory == before and GameState.money == 0 and not PowerRepairFlow.marked("ordered"), "bypassed disabled button cannot consume partial payment")
	repair.panel.confirmed.emit()
	for requirement in PowerRepairFlow.SETTINGS.requirements: GameState.add_item(str(requirement["item"]), int(requirement["amount"]))
	GameState.money = PowerRepairFlow.SETTINGS.fee - 1
	check(not PowerRepairFlow.order(), "insufficient funds reject complete material delivery")
	GameState.money += 1
	repair.try_interact()
	check(not repair.panel.submit.disabled, "complete quote ready")
	var args := OS.get_cmdline_user_args()
	if args.has("--shot"):
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(args[args.find("--shot") + 1])
	repair.panel.submit.pressed.emit()
	check(PowerRepairFlow.phase() == "working" and repair.dialogue.open, "actual submit button assigns work to technician")
	check(GameState.money == 0 and not PowerRepairFlow.order(), "contract fee spent once")
	for requirement in PowerRepairFlow.SETTINGS.requirements: check(GameState.get_item_count(str(requirement["item"])) == 0, "contract consumes exact warehouse material once")
	repair.dialogue.close()
	check(PowerRepairFlow.marked("ordered") and not get_tree().paused and not PowerRepairFlow.powered(), "submitted work persists if subsequent dialogue interrupted")
	check(not PowerRepairFlow.finish(), "same-day work cannot complete")
	var saved := GameState.create_save_data().duplicate(true)
	check(GameState.is_save_data_valid(saved), "contract pending full save valid")
	GameState.total_day = PowerRepairFlow.ready_day()
	check(not PowerRepairFlow.powered() and PowerRepairFlow.phase() == "finish", "calendar alone does not restore power without final dialogue")
	repair.try_interact()
	repair.dialogue.close()
	check(not PowerRepairFlow.powered(), "partial final visit does not complete repair")
	repair.try_interact()
	drain(repair.dialogue)
	check(PowerRepairFlow.powered() and not PowerRepairFlow.finish(), "full technician completion restores power exactly once")
	player.global_position = world.get_node("BuildManager").get_cell_world_position(register.get_worker_cells()[0])
	cashier.try_interact()
	check(cashier.food_cleanup.title.contains("마석 발전기"), "restored register displays actual generator connection")
	cashier.food_cleanup.confirmed.emit()
	check(VillageJournalFlow.entries().any(func(entry: Dictionary) -> bool: return entry["id"] == PowerRepairFlow.JOURNAL_ID), "side story progress appears in journal")
	player.global_position = repair.npc.global_position
	repair.try_interact()
	check(PowerRepairFlow.phase() == "memory", "repair memory reread available")
	world.queue_free()
	await frames()
	check(not get_tree().paused, "scene exit during technician talk releases modal pause")
	check(GameState.apply_save_data(saved) and PowerRepairFlow.phase() == "working" and not PowerRepairFlow.powered(), "full save restore resumes pending work without recharge")
	PlayerProgress.story_beat_days.erase(PowerRepairFlow.PREFIX + "broken")
	check(PowerRepairFlow.powered() and PowerRepairFlow.action("naru").is_empty(), "old save remains powered without forced new quest")
	var prose := Tools.validate_file(Tools.TEXT_PATH, Tools.load_sources())
	check(prose["errors"].is_empty() and prose["warns"].is_empty(), "new scenes and existing prose all validate")
	print("CHECK_POWER_REPAIR checks=", checks, " failures=", failures, " text=", prose)
	get_tree().quit(0 if failures == 0 else 1)
