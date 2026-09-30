extends Node

var failures: int = 0
var world

func check(value: bool, message: String) -> void:
	if value: print("PASS: ", message)
	else:
		failures += 1
		push_error("FAIL: " + message)

func drain(panel: StoryDialoguePanel) -> void:
	for i in range(20):
		if not panel.open: break
		panel._advance()

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("run")

func run() -> void:
	world = load("res://scenes/shop/main.tscn").instantiate()
	add_child(world)
	for i in range(4): await get_tree().process_frame
	for worker in get_tree().get_nodes_in_group("worker"): worker.queue_free()
	await get_tree().process_frame
	var layout: Array[Dictionary] = [
		{"build_id": "door", "anchor": Vector2i(0, 4), "rotation_index": 3},
		{"build_id": "register", "anchor": Vector2i(4, 3), "rotation_index": 0},
		{"build_id": "shelf_1x1", "anchor": Vector2i(2, 2), "rotation_index": 0,
		 "shelf_slots": [{"item_id": "water", "stock": 3, "capacity": 5}]}
	]
	world.get_node("BuildManager")._restore_current_area_layout(layout)
	await get_tree().process_frame
	var manager = world.get_node("DayManager")
	var tutorial = world.get_node("CheckoutTutorial")
	var cashier = world.get_node("ManualCheckoutController")
	var player = world.get_node("Actors/Player")
	manager.open_shop()
	check(is_instance_valid(tutorial.guide), "first customer tutorial starts with real furniture")
	if not is_instance_valid(tutorial.guide):
		get_tree().quit(1)
		return
	var guide = tutorial.guide
	var register = tutorial.guide_register
	var cell: Vector2i = tutorial.guide_cell
	guide.speed = 800.0
	check(manager.hour_timer.paused, "only tutorial dialogue pauses clock")
	drain(tutorial.dialogue)
	check(not manager.hour_timer.paused, "dialogue restores clock")
	var deadline: int = Time.get_ticks_msec() + 20000
	while tutorial.stage == "shopping" and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	check(tutorial.stage == "checkout", "guide walks to shelf and queues at register")
	if tutorial.stage != "checkout":
		get_tree().quit(1)
		return
	check(guide.carried_amount == 1, "guide picks real stock")
	var worker := Node.new()
	add_child(worker)
	check(not register.try_reserve_worker(worker), "employee cannot take tutorial payment")
	drain(tutorial.dialogue)
	player.set_physics_process(false)
	player.global_position = world.get_node("BuildManager").get_cell_world_position(cell)
	var money_before: int = player.money
	var sales_before: int = player.successful_sales
	check(world.get_node("WorldInteractions").try_interact(), "E path reaches manual register")
	check(cashier.is_busy(), "payment starts on cashier side")
	player.global_position += Vector2(200, 0)
	cashier._process(0.1)
	check(not cashier.is_busy() and player.money == money_before, "leaving cancels without charging")
	check(not register.try_reserve_worker(worker), "tutorial remains protected after cancellation")
	check(not register.is_worker_cell_available(cell, worker), "tutorial cashier position stays reserved after cancellation")
	player.global_position = world.get_node("BuildManager").get_cell_world_position(cell)
	cashier.try_interact()
	cashier._process(2.0)
	check(guide.purchase_completed and player.money == money_before + ItemData.get_item_price("water"), "manual payment gives actual sale amount")
	check(player.successful_sales == sales_before + 1, "sale recorded once")
	check(tutorial.completed() and tutorial.stage == "finished", "completion stored in existing progress")
	drain(tutorial.dialogue)
	cashier.try_interact()
	cashier._process(2.0)
	check(player.successful_sales == sales_before + 1, "repeated interaction does not duplicate sale")
	check(not is_instance_valid(tutorial.guide), "completed guide exits and normal customers resume")
	# 일반 손님도 같은 결제 경로를 사용하고 직원 예약과 충돌하지 않는다.
	var customer = load("res://scenes/shop/actors/customer.tscn").instantiate()
	world.get_node("Actors").add_child(customer)
	customer.global_position = world.get_node("BuildManager").get_cell_world_position(register.get_checkout_cells()[0])
	customer.set_physics_process(false)
	var shelf = get_tree().get_nodes_in_group("shelf")[0]
	check(shelf.take_items_by_id("water", 1) == 1, "ordinary checkout uses real picked inventory")
	customer.carried_item_id = "water"
	customer.carried_amount = 1
	customer.target_register = register
	register.request_checkout(customer)
	register.try_reserve_worker(worker)
	cashier.try_interact()
	check(not cashier.is_busy(), "manual checkout respects employee reservation")
	register.release_worker_reservation(worker)
	player.global_position = world.get_node("BuildManager").get_cell_world_position(register.get_checkout_cells()[0])
	check(not cashier.try_interact(), "customer side cannot operate register")
	player.global_position = world.get_node("BuildManager").get_cell_world_position(cell)
	cashier.try_interact()
	cashier._process(2.0)
	check(customer.purchase_completed and player.successful_sales == sales_before + 2, "ordinary customer completes through existing checkout path")
	manager.hour_timer.start(0.3)
	manager.close_shop_manually()
	var hour: int = manager.current_hour
	await get_tree().create_timer(0.4).timeout
	check(manager.current_hour != hour and not manager.hour_timer.is_stopped(), "closed door keeps clock running")
	var remaining: float = manager.hour_timer.time_left
	manager.open_shop()
	check(manager.hour_timer.time_left <= remaining + 0.01, "reopening preserves elapsed hour")
	check(not is_instance_valid(tutorial.guide), "tutorial does not repeat on reopening")
	var progress: Dictionary = PlayerProgress.to_save_data()
	PlayerProgress.reset()
	PlayerProgress.load_save_data(progress)
	check(tutorial.completed(), "tutorial completion survives save round trip")
	# 하루 경계의 정산과 다음 날 정비 정지는 유지한다.
	for npc in get_tree().get_nodes_in_group("customer"): npc.queue_free()
	await get_tree().process_frame
	manager.close_shop_manually()
	manager.current_hour = 5
	manager._on_hour_timer_timeout()
	deadline = Time.get_ticks_msec() + 5000
	while not manager.summary_open and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	check(manager.summary_open and manager.hour_timer.is_stopped(), "closed shop still settles at 06:00")
	manager.confirm_next_day()
	check(not manager.shop_open and manager.hour_timer.is_stopped(), "next day preparation remains stopped")
	world.queue_free()
	await get_tree().process_frame
	print("CHECK_MANUAL_CHECKOUT failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)
