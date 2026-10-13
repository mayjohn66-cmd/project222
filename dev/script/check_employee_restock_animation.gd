extends Node
## Real worker timer + real shelf inventory transfer in an isolated test save.
var checks := 0
var failures := 0
var world: Node2D
var view: StoreView3D
var captures := 0


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	run.call_deferred()


func frame_wait(count: int = 8) -> void:
	for i in count: await get_tree().process_frame


func run() -> void:
	check(OS.get_user_data_dir().contains("foodbag_checks"), "isolated test data")
	if failures: get_tree().quit(1); return
	GameState.initialize_new_game()
	PlayerProgress.reset()
	world = load("res://scenes/shop/main.tscn").instantiate()
	world.get_node("TutorialDirector").enabled = false
	add_child(world)
	await frame_wait()
	view = world.get_node("StoreView3D")
	world.get_node("DayManager").hour_timer.stop()
	freeze_simulation(world)
	view.set_process(true)
	var layout: Array[Dictionary] = [{"build_id":"shelf_1x1", "anchor":Vector2i(4,3), "rotation_index":0}]
	world.get_node("BuildManager")._restore_current_area_layout(layout)
	await frame_wait()
	var shelf = get_tree().get_nodes_in_group("shelf")[0]
	shelf.product_id = "water"
	shelf.stock = 0
	var workers := get_tree().get_nodes_in_group("worker")
	check(workers.size() == 3, "three actual employee identities")
	for employee in EmployeeRestockAnimation.EMPLOYEES:
		var base := ActorSpriteFrames.load_set(employee)
		for direction in EmployeeRestockAnimation.DIRECTIONS:
			var poses := EmployeeRestockAnimation.frames(employee,direction)
			check(poses.size() == 4, "four real work poses: " + employee + "/" + direction)
			for pose in poses:
				var image: Image = pose.texture.get_image()
				var idle: Image = base.directions[direction].idle.texture.get_image()
				check(image.get_size() == Vector2i(64,64), "fixed canvas")
				check(same_visible_feet(image,idle), "visible foot pixels and alpha exactly retained")
	var start_money := GameState.money
	for worker in workers:
		worker.visible = true
		worker.on_duty = true
		worker.state = worker.WorkerState.GO_TO_SHELF
		worker.moving = false
		worker.global_position = world.get_node("Floor").to_global(world.get_node("Floor").grid_to_local(Vector2i(3,3)))
		worker.pending_shelf = shelf
		check(shelf.try_reserve_worker(worker), "real shelf reservation")
		view._sync_actors(0.016)
		var figure: PixelActorFigure = view._actors[worker.get_instance_id()].figure
		check(figure.work_pose.is_empty(), "travel to shelf does not show restock")
		shelf.stock = 0
		GameState.add_item("water", 7)
		var before := GameState.get_item_count("water")
		var transferred: int = mini(before, shelf.capacity)
		worker.handle_shelf_arrival() # Starts existing coroutine, not a test replacement.
		var paths := {}
		var elapsed := 0.0
		var paused_once := false
		while worker.state == worker.WorkerState.RESTOCK and elapsed < 3.0:
			await get_tree().process_frame
			elapsed += get_process_delta_time()
			if not figure.work_pose.is_empty():
				var path: String = figure.work_pose.path
				if not paths.has(path):
					paths[path] = true
					check(figure._material.get_shader_parameter("frame_texture") == figure.work_pose.texture, "actual color shader uses work frame")
					check(figure._id_material.get_shader_parameter("frame_texture") == figure.work_pose.texture, "sorting mask uses same work frame")
					if worker.employee_id == "worker_001": await capture(figure)
				if not paused_once:
					paused_once = true
					get_tree().paused = true
					var prior: String = figure.work_pose.path
					var animation: EmployeeRestockAnimation = view._actors[worker.get_instance_id()].restock_animation
					var previous := animation.elapsed
					await get_tree().create_timer(0.10, true).timeout
					view._sync_actors(0.10)
					check(figure.work_pose.path == prior and animation.elapsed == previous, "pause freezes work pose and progress")
					check(GameState.get_item_count("water") == before and shelf.stock == 0, "pause transfers no inventory")
					get_tree().paused = false
		await frame_wait()
		check(paths.size() == 4, "all four poses actually displayed: " + worker.employee_id)
		check(shelf.stock == transferred and GameState.get_item_count("water") == before-transferred, "existing restock transfers once, exact capacity")
		check(figure.work_pose.is_empty(), "completion returns to normal pose")
		check(shelf.reserved_worker == null, "completion releases real reservation")
		worker.visible = false
		worker.on_duty = false
		worker.pending_shelf = null
	# Removing a target mid-job must clear the pose and grant no extra stock.
	var worker = workers[0]
	worker.visible = true
	worker.on_duty = true
	worker.pending_shelf = shelf
	worker.handle_shelf_arrival()
	await frame_wait(2)
	check(not view._actors[worker.get_instance_id()].figure.work_pose.is_empty(), "work started before target removal")
	var remaining_stock := GameState.get_item_count("water")
	shelf.queue_free()
	await frame_wait(2)
	check(view._actors[worker.get_instance_id()].figure.work_pose.is_empty(), "deleted shelf stops visible action")
	await get_tree().create_timer(worker.get_effective_restock_time()+0.1).timeout
	check(GameState.get_item_count("water") == remaining_stock and GameState.money == start_money, "renderer grants/consumes nothing on interrupted job")
	check(view._actors[view.player.get_instance_id()].figure.work_pose.is_empty(), "player gets no work animation")
	print("EMPLOYEE RESTOCK checks=%d failures=%d captures=%d" % [checks,failures,captures])
	get_tree().quit(1 if failures else 0)


func freeze_simulation(node: Node) -> void:
	node.set_process(false)
	node.set_physics_process(false)
	for child in node.get_children(): freeze_simulation(child)


func same_visible_feet(image: Image, original: Image) -> bool:
	# Texture import fixes RGB under alpha=0; compare visible pixels and alpha.
	for y in range(51,64):
		for x in range(64):
			var value := image.get_pixel(x,y)
			var source := original.get_pixel(x,y)
			if value.a != source.a or (source.a > 0.0 and value != source): return false
	return true


func capture(figure: PixelActorFigure) -> void:
	if DisplayServer.get_name() == "headless": return
	var args := OS.get_cmdline_user_args()
	if args.is_empty(): return
	await RenderingServer.frame_post_draw
	var path: String = args[0]+"-"+str(figure.work_pose.path).get_file()
	get_viewport().get_texture().get_image().save_png(path)
	captures += 1
