extends Node
var failures: int = 0
var world
var director: TutorialDirector
var player
func check(ok: bool, text: String) -> void:
	if ok: print("PASS: ", text)
	else:
		failures += 1
		push_error(text)
func drain(panel: StoryDialoguePanel) -> void:
	for i in range(30):
		if not panel.open: break
		panel._advance()
func talk() -> void:
	director.refresh()
	player.global_position = director.npc.global_position
	check(world.get_node("WorldInteractions").try_interact(), "NPC E interaction")
	check(director.dialogue.name_label.text == director.SETTINGS.guide_name,"guide name is consistent in actual tutorial dialogue")
	drain(director.dialogue)
	director.refresh()
func _ready() -> void: call_deferred("run")
func run() -> void:
	world = load("res://scenes/shop/main.tscn").instantiate()
	add_child(world)
	for i in range(4): await get_tree().process_frame
	for worker in get_tree().get_nodes_in_group("worker"): worker.queue_free()
	await get_tree().process_frame
	player = world.get_node("Actors/Player")
	player.set_physics_process(false)
	director = world.get_node("TutorialDirector")
	var manager = world.get_node("DayManager")
	check(director.flow.current()["id"] == "setup", "starts at preparation")
	check(world.get_node("StoryDirector")._is_blocked(), "ordinary story does not compete")
	var water_before: int = GameState.get_item_count("water")
	talk()
	check(GameState.get_item_count("water") == water_before + 4, "intro provides initial stock")
	talk()
	check(GameState.get_item_count("water") == water_before + 4, "intro reward cannot repeat")
	check(not director.flow.goal_met(director.flow.current(), world), "unbuilt shop does not complete")
	check(not director.flow.validate_gifts([{"kind":"item","id":"missing_tutorial_item","amount":1}]), "invalid rewards are rejected before payment")
	var inventory_before: int = GameState.get_item_count("bread")
	director.flow.claim(director.flow.current(), world)
	check(GameState.get_item_count("bread") == inventory_before, "unfinished task cannot receive reward")
	var layout: Array[Dictionary] = [
		{"build_id":"door", "anchor":Vector2i(0,4), "rotation_index":3},
		{"build_id":"register", "anchor":Vector2i(4,3), "rotation_index":0},
		{"build_id":"shelf_1x1", "anchor":Vector2i(2,2), "rotation_index":0,
		 "shelf_slots":[{"item_id":"water", "stock":3,"capacity":5}]}]
	world.get_node("BuildManager")._restore_current_area_layout(layout)
	var step := director.flow.current()
	var bread_before: int = GameState.get_item_count("bread")
	talk()
	check(GameState.get_item_count("bread") == bread_before + 4 and director.flow.current()["id"] == "stock", "build completion gives next stock")
	director.flow.claim(step,world)
	check(GameState.get_item_count("bread") == bread_before + 4, "same completed step cannot pay twice")
	talk()
	talk()
	check(director.flow.current()["id"] == "checkout", "stock advances to manual checkout")
	check(not director.flow.seen("checkout"), "no extra NPC dialogue required before checkout event")
	manager.open_shop()
	var checkout = world.get_node("CheckoutTutorial")
	check(is_instance_valid(checkout.guide), "stage opens first customer exercise")
	check(checkout.dialogue.name_label.text == director.SETTINGS.guide_name,"first customer uses same named guide")
	if not is_instance_valid(checkout.guide):
		get_tree().quit(1)
		return
	checkout.guide.speed = 800.0
	drain(checkout.dialogue)
	var deadline: int = Time.get_ticks_msec() + 20000
	while checkout.stage == "shopping" and Time.get_ticks_msec() < deadline: await get_tree().process_frame
	check(checkout.stage == "checkout", "guide event reliably prepares a waiting customer")
	if checkout.stage != "checkout":
		get_tree().quit(1)
		return
	drain(checkout.dialogue)
	player.global_position = world.get_node("BuildManager").get_cell_world_position(checkout.guide_cell)
	var cashier = world.get_node("ManualCheckoutController")
	cashier.try_interact()
	cashier._process(2.0)
	drain(checkout.dialogue)
	check(director.flow.goal_met(director.flow.current(),world), "actual player payment completes checkout goal")
	talk()
	check(director.flow.current()["id"] == "expedition", "payment reward unlocks expedition guidance")
	talk()
	check(not director.flow.goal_met(director.flow.current(),world), "unvisited expedition cannot complete")
	PlayerProgress.record_expedition_completed()
	talk()
	check(director.flow.current()["id"] == "production", "expedition return grants production supplies")
	talk()
	var progress: Dictionary = PlayerProgress.to_save_data()
	PlayerProgress.reset()
	PlayerProgress.load_save_data(progress)
	check(director.flow.current()["id"] == "production" and director.flow.seen("production"), "saved tutorial resumes exact pending stage")
	check(not director.flow.goal_met(director.flow.current(),world), "existing bread is not proof of production")
	var facility = load("res://scenes/shop/production/production_facility.tscn").instantiate()
	world.get_node("Objects").add_child(facility)
	director.refresh()
	facility.configure_facility("magic_oven")
	facility.pending_item_id = "bread"
	facility.pending_amount = 1
	facility.production_state = ProductionFacility.ProductionState.READY
	check(facility.collect_production(), "real production collection succeeds")
	check(director.flow.goal_met(director.flow.current(),world), "real collection signal completes goal")
	talk()
	check(director.flow.current().is_empty(), "all five steps completed")
	var final_progress: Dictionary = PlayerProgress.to_save_data()
	PlayerProgress.reset()
	PlayerProgress.load_save_data(final_progress)
	check(not director.is_guiding(), "completed tutorial remains completed after load")
	manager.close_shop_manually()
	world.queue_free()
	await get_tree().process_frame
	print("CHECK_PROGRESSIVE_TUTORIAL failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)
