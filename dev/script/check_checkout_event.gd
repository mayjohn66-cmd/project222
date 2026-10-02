extends Node
var failures: int = 0
func check(ok: bool, caption: String) -> void:
	if ok: print("PASS: ", caption)
	else:
		failures += 1
		push_error(caption)
func drain(dialogue: StoryDialoguePanel) -> void:
	for i in range(30):
		if not dialogue.open: break
		dialogue._advance()
func _ready() -> void: call_deferred("run")
func run() -> void:
	var world = load("res://scenes/shop/main.tscn").instantiate()
	add_child(world)
	for i in range(4): await get_tree().process_frame
	var workers := get_tree().get_nodes_in_group("worker")
	for worker in workers:
		worker.set_process(false)
		worker.set_physics_process(false)
	var manager = world.get_node("DayManager")
	var checkout = world.get_node("CheckoutTutorial")
	var tutorial = world.get_node("TutorialDirector")
	var player = world.get_node("Actors/Player")
	var build = world.get_node("BuildManager")
	player.set_physics_process(false)
	var layout: Array[Dictionary] = [
		{"build_id":"door","anchor":Vector2i(0,4),"rotation_index":3},
		{"build_id":"register","anchor":Vector2i(4,3),"rotation_index":0},
		{"build_id":"shelf_1x1","anchor":Vector2i(2,2),"rotation_index":0}]
	build._restore_current_area_layout(layout)
	tutorial.refresh()
	check(tutorial.npc.global_position.distance_to(player.global_position) > 90, "guide spawns away from player")
	var register = get_tree().get_nodes_in_group("register")[0]
	for cell in register.get_worker_cells() + register.get_checkout_cells():
		check(tutorial.npc.global_position.distance_to(build.get_cell_world_position(cell)) > 90, "guide separated from register interaction cells")
	player.global_position = tutorial.npc.global_position + Vector2(60, 0)
	check(not tutorial.try_interact(), "NPC no longer intercepts E from 60 pixels away")
	for i in range(2):
		var worker = workers[i]
		register.try_reserve_worker_cell(register.get_worker_cells()[i], worker)
		worker.standby_register = register
		worker.reserved_worker_cell = register.get_worker_cells()[i]
	register.try_reserve_worker(workers[0])
	workers[0].pending_register = register
	manager.open_shop()
	check(not is_instance_valid(checkout.guide), "no practice before preparation steps")
	# 이미 개점한 저장 상태에서 추가 대화 없이 연습 손님을 만든다.
	tutorial.flow.mark("setup", "done")
	tutorial.flow.mark("stock", "done")
	check(not tutorial.flow.seen("checkout"), "saved checkout stage has no extra dialogue flag")
	tutorial.refresh()
	checkout.try_start()
	check(is_instance_valid(checkout.guide), "already-open shop creates guide despite staff reservations")
	if not is_instance_valid(checkout.guide):
		get_tree().quit(1)
		return
	check(workers[0].pending_register == null, "stale employee task released")
	drain(checkout.dialogue)
	var guide = checkout.guide
	check(register.get_waiting_customer() == guide and guide.carried_amount == 1, "one forced customer waits even with empty shelves")
	check(tutorial.flow.seen("checkout"), "event itself introduces checkout step")
	check(not is_instance_valid(tutorial.npc), "guide and first customer are not duplicated")
	guide.complete_checkout_by_worker()
	check(not guide.purchase_completed, "employee cannot steal tutorial payment")
	var stock_before: int = GameState.get_item_count("water")
	manager.close_shop_manually()
	checkout._process(0)
	check(GameState.get_item_count("water") == stock_before, "unpaid practice item creates no free stock on abort")
	manager.open_shop()
	check(is_instance_valid(checkout.guide), "closing and reopening retries practice")
	drain(checkout.dialogue)
	player.global_position = build.get_cell_world_position(checkout.guide_cell)
	var sales: int = player.successful_sales
	world.get_node("ManualCheckoutController").try_interact()
	world.get_node("ManualCheckoutController")._process(2)
	check(checkout.completed() and player.successful_sales == sales + 1, "forced customer can be paid by player")
	drain(checkout.dialogue)
	tutorial.refresh()
	check(is_instance_valid(tutorial.npc), "guide returns away from cashier for completion reward")
	world.queue_free()
	await get_tree().process_frame
	print("CHECK_CHECKOUT_EVENT failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)
